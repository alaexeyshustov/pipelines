# Plan: fetch only text parts of IMAP messages (GH #304)

**Status:** planned | **Branch:** `fix/gh-304-imap-text-parts`, cut from `feat/gh-248-email-ingestion-as-an-orchestration-pipeline` (PR #337) | **Follows:** #299 (#240 SEC-09)

## Decisions

Settled with the user:

- **Both fetch paths.** `YahooAdapter#message` (tools) and `ImapInboxReader#mail` (`YahooFullMessage`, the `EmailsList` step) go through one shared text-part fetcher. `RFC822` is no longer fetched anywhere; `YahooAdapter::FULL_FIELDS` is removed. `HEADER_FIELDS` and `ImapSession#fetch_raw_mail` stay for listings.
- **Attachments: adapter + pipeline.** Yahoo implements `attachments` / `attachment`; `AttachmentsIngest` ingests tagged Yahoo emails too; `Document::Download` serves Yahoo documents.
- **Rebuild a reduced `Mail`.** `ImapBodyParser`, `YahooMessageParser` and `YahooFullMessage` keep taking a `Mail`, so `body`, `html_body` and the other fields stay the same for normal mail.
- **Limits (constants).** `MAX_TEXT_PART_BYTES = 1_048_576` (truncate), `MAX_DEPTH = 10`, `MAX_TEXT_PARTS = 20`.
- **Snippet.** For multipart mail today's snippet is the first 200 characters of raw MIME (preamble, boundaries, part headers). It becomes the first 200 characters of the decoded text body. Intended behaviour change for multipart mail; single-part is unchanged.
- **Specs use no test doubles** (`App/NoTestDoubles`). The issue's `instance_double` acceptance criterion is replaced by recorded IMAP responses parsed into real `Net::IMAP::FetchData`.
- **ADR 0013** gets a one-line note that #304 supersedes "Attachments stay Gmail-only (#220)".

Choices this plan adds:

- **Shared fetcher.** New `Emails::Adapters::ImapTextFetcher` (infra) taking an `ImapSession`, next to `ImapInboxReader` and `ImapLabelManager`. `ImapSession` gains one generic `fetch(uid, attrs) -> Net::IMAP::FetchData?`. `ImapSession#with_lock` is a plain `Mutex#synchronize`, so the fetcher takes the lock itself and callers must not hold it.
- **BODYSTRUCTURE walker.** New `Emails::Adapters::ImapBodyStructure` turns `FetchStruct#bodystructure` into ordered leaves (`path`, `mime_type`, `charset`, `encoding`, `size`, `filename`, `inline`). It stops descending at depth 10 and logs the dropped subtree with `Rails.logger.warn`; the message still returns. `message/rfc822` parts are leaves (today's `Mail` does not read text inside them either). Uses the typed net-imap 0.6 readers (`BodyTypeMultipart`, `BodyTypeText`, `BodyTypeBasic`, `BodyTypeMessage`), not `FetchData#attr` (narrowed to `Hash[String, String]` in `sig/shims/external_gems.rbs`).
- **Text part rule.** A leaf of type `text/plain` or `text/html` without a filename (disposition `filename`, content-type `name`, or location; same as `Mail#find_attachment`), so it matches `ImapBodyParser`'s `reject(&:attachment?)`. At most `MAX_TEXT_PARTS` leaves, in tree order.
- **Two round trips per message.**
  1. `UID FETCH uid (UID FLAGS BODYSTRUCTURE BODY.PEEK[HEADER])`
  2. `UID FETCH uid (BODY.PEEK[p1]<0.1048576> BODY.PEEK[p2]<0.1048576> …)` for the text leaves; a single-part message uses path `1`. The server truncates, so no more than 1 MB per part crosses the wire.
- **Reduced `Mail` keeps encoded bytes.** Each text part is rebuilt with `Content-Type: <type>; charset=<charset>` and `Content-Transfer-Encoding: <encoding>` from BODYSTRUCTURE and the fetched (still encoded) body, so Mail decodes base64, quoted-printable and charsets as today. Multipart: `Mail.new(header)` plus the text leaves as parts of a flat multipart under a fresh boundary. Single part: header plus the one body. A truncated base64/QP tail decodes leniently; the existing `encode(..., invalid: :replace)` covers broken bytes.
- **Attachments.** New `Emails::Adapters::ImapAttachmentReader`, the counterpart of `GmailAttachmentReader`:
  - `list(message_id)` → `[{ id: "<part path>", filename:, mime_type:, size: }]`, leaves with a filename, skipping `inline` ones (as Gmail). `size` is the encoded octet count. Filenames go through `Mail::Encodings.value_decode` (RFC 2047); RFC 2231 `filename*=` gets a fixture.
  - `data(message_id, attachment_id)` checks `attachment_id` against `/\A\d+(\.\d+)*\z/` and the listed paths, fetches `BODY.PEEK[<path>]` and decodes it with `Mail::Encodings.get_encoding(encoding).decode`.
  - Ids go through `ImapInboxReader.split_message_id` (`"<uid_validity>:<uid>"` or bare UID); the mailbox is always `ImapInboxReader::MAILBOX`. A validity that differs from the current INBOX UIDVALIDITY raises `"UIDVALIDITY changed"`, so a reset mailbox cannot hand over another message's file. A bare UID skips the check.
- **`YahooAdapter` class length.** It has 110 body lines and `Metrics/ClassLength` is 110. `#message` delegates to `@text_fetcher.mail(uid, mailbox:)` (removing the lock, `ensure_mailbox` and `parse_mail` full-fields code); `#attachments` / `#attachment` are one-line delegates to `@attachment_reader`. No `rubocop:disable`; if still over, move `to_message` into a `YahooMessage` value class.
- **Fixtures.** Raw `* n FETCH (...)` lines in `spec/fixtures/files/imap/*.txt`, parsed by `spec/support/helpers/imap_response_helpers.rb` with `Net::IMAP::ResponseParser.new.parse(line).data`. The existing `Net::IMAP.allocate` + `allow(imap).to receive(:uid_fetch)` pattern stays. The 12-level nesting case is generated in the helper.

## Steps

### 1. Fixtures and `ImapBodyStructure` (infra)

- **Files:** `spec/fixtures/files/imap/` (plain single-part; `multipart/alternative`; `multipart/mixed` with text and a 5 MB PDF; nested `mixed > related > alternative`; ISO-8859-1 quoted-printable; base64 UTF-8; inline image; `message/rfc822`; RFC 2231 filename; 25 text siblings), `spec/support/helpers/imap_response_helpers.rb`, `lib/emails/adapters/imap_body_structure.rb`, `sig/lib/emails/adapters/imap_body_structure.rbs` (`Leaf` `Data`, no `untyped`).
- **Red first:** `spec/lib/emails/adapters/imap_body_structure_spec.rb`: leaf paths (`1`, `1.2`, `2.1.1`) in tree order; text vs attachment leaves by the filename rule; inline flag; `message/rfc822` is a leaf; 12 levels deep returns only parts at depth ≤ 10 without raising.
- **Accept when:** spec green, `steep check` clean for the new file.

### 2. `ImapSession#fetch` and `ImapTextFetcher` (infra)

- **Files:** `lib/emails/adapters/imap_session.rb` (`fetch`), `lib/emails/adapters/imap_text_fetcher.rb` (`MAX_TEXT_PART_BYTES`, `MAX_TEXT_PARTS`, `TEXT_TYPES`, `#mail(uid, mailbox:) -> Mail::Message?`, taking the lock and running `ensure_mailbox`), `sig/lib/emails/adapters/imap_session.rbs`, `sig/lib/emails/adapters/imap_text_fetcher.rbs`.
- **Red first:**
  - `spec/lib/emails/adapters/imap_session_spec.rb`: `#fetch` returns the `FetchData` or nil.
  - `spec/lib/emails/adapters/imap_text_fetcher_spec.rb`:
    - large attachment: `uid_fetch` gets `BODYSTRUCTURE`, then only `BODY.PEEK[1]<0.1048576>`; never `RFC822`, `BODY[]`, `BODY.PEEK[2]` or `BODY.PEEK[TEXT]`;
    - QP ISO-8859-1 and base64 parts decode to the same text as `Mail.new(raw)`;
    - a part over 1 MB is requested with the partial range and the result is ≤ 1 MB;
    - 25 text siblings: only the first 20 are fetched;
    - missing UID returns nil;
    - 12 levels deep yields a `Mail` with only parts within the cap.
- **Accept when:** both specs green; `ImapBodyParser.new(fetched).body/html` equals `ImapBodyParser.new(Mail.new(raw))` for every fixture with a matching full raw message.

### 3. Route both paths through the fetcher; snippet from decoded text (infra)

- **Files:** `lib/emails/adapters/yahoo_adapter.rb` (`@text_fetcher`, `#message`, drop `FULL_FIELDS`), `lib/emails/adapters/imap_inbox_reader.rb` (`#mail(uid)` via `ImapTextFetcher` with `MAILBOX`), `lib/emails/adapters/yahoo_message_parser.rb` (snippet from the decoded text body), `sig/lib/emails/adapters/yahoo_adapter.rbs`, `sig/lib/emails/adapters/imap_inbox_reader.rbs`.
- **Red first:**
  - `spec/lib/emails/adapters/yahoo_adapter_spec.rb`: "never fetches RFC822"; "a message with a large attachment fetches only its text parts"; "normal mail output unchanged" (single-part and multipart give the same `id, subject, from, to, date, body, labels` as the old `Mail.new(raw)` path); "multipart snippet is the first 200 characters of the decoded text".
  - `spec/lib/emails/adapters/yahoo_adapter_inbox_sync_spec.rb`: `#fetch_message` and `#message` examples on fixture responses give identical hashes (including `html_body` and `date`); not-found and no-date cases kept.
- **Accept when:** both specs green; `bundle exec rubocop lib/emails` passes with no new disables; `git grep RFC822 lib/` shows only `RFC822.HEADER`.

### 4. Yahoo attachments (infra)

- **Files:** `lib/emails/adapters/imap_attachment_reader.rb` (`list`, `data`), `lib/emails/adapters/yahoo_adapter.rb` (`#attachments`, `#attachment` delegates), `lib/emails/adapters/base_adapter.rb` (comment: both providers implement attachments), `sig/lib/emails/adapters/imap_attachment_reader.rbs`, `sig/lib/emails/adapters/yahoo_adapter.rbs` (`attachments: (String | Integer) -> Array[attachment]`, `attachment: (String | Integer, String) -> String`, `@attachment_reader`).
- **Red first:** `spec/lib/emails/adapters/yahoo_adapter_attachments_spec.rb`: PDF listed as `{ id: "2", filename: "cv.pdf", mime_type: "application/pdf", size: n }`, inline image left out; RFC 2047/2231 filenames decoded; `#attachment("77:101", "2")` fetches only `BODY.PEEK[2]` and returns decoded bytes; validity mismatch raises; unknown or malformed part id raises without fetching a body; bare UID works.
- **Accept when:** spec green; return shape equals Gmail's (keys and types, as in `spec/lib/emails/adapters/gmail_adapter_attachments_spec.rb`).

### 5. Yahoo attachments in the pipeline and downloads (application)

- **Files:** `lib/orchestration/executors/attachments_ingest.rb` (`eligible` becomes `Email.tagged`; header comment), `app/services/document/ingest_email_attachments.rb` (header comment), `app/services/document/download.rb` (`when Emails::YAHOO` branch), `config/pipelines/email_ingestion.json` (step descriptions: "tagged emails (Gmail and Yahoo)"), `docs/architecture.md`, `docs/orchestration.md` (step 4), `docs/schemas.md` (Yahoo `source_ref`: `message_id` is `"<uid_validity>:<uid>"`, `attachment_id` is the IMAP part path), `docs/adr/0013-email-ingestion-pipeline.md` (superseded-by-#304 note). Sigs only if `Document::Download` gains a method.
- **Red first:**
  - `spec/lib/orchestration/executors/attachments_ingest_spec.rb`: "ingests the attachments of tagged Yahoo emails" replaces "skips Yahoo emails"; add "skips untagged Yahoo emails"; keep "returns the leftover documents of a re-listed Yahoo email".
  - `spec/services/document/ingest_email_attachments_spec.rb`: a Yahoo email via `stub_yahoo_adapter(attachments:, attachment:)` gives a Document with `source_ref` `{ provider: "yahoo", message_id: "77:101", attachment_id: "2" }`.
  - `Document::Download` service spec and request spec: a Yahoo email-attachment document downloads its bytes.
- **Accept when:** these specs green; `spec/config/email_ingestion_pipeline_spec.rb` and `spec/lib/orchestration/email_ingestion_pipeline_spec.rb` stay green.

## Checks

- `COVERAGE=true bundle exec rspec`
- `bundle exec rubocop`; `bundle exec archspec check --check-todo` (new code is infra in `lib/emails`; step 5 is application → domain/infra; nothing added to `archspec_todo.yml`); `bundle exec archspec reflect` after the pipeline JSON change, committing any `archspec_facts/` diff.
- `bundle exec rbs -r optparse validate`, `bundle exec steep check`, `bundle exec bin/rbs_audit coverage --threshold=90` (three new classes with full sigs, private helpers included).
- `bundle exec rigor check`, `bundle exec brakeman --no-pager`, `bundle exec bundle-audit check --update`, `.sandbox/test/*_test.rb`. No JS changes.

## Requirement → step

| Requirement | Step | Verification |
|---|---|---|
| BODYSTRUCTURE first, then only text parts via `BODY.PEEK[n]` | 2, 3 | `imap_text_fetcher_spec`, `yahoo_adapter_spec` (large attachment) |
| 1 MB per text part, at most 20 text parts | 2 | truncation and sibling-cap examples |
| MIME depth cap of 10 | 1, 2 | depth examples |
| One fetcher for `#message` and `ImapInboxReader#mail` | 3 | both adapter specs; `git grep RFC822` |
| Output unchanged for normal mail; multipart snippet from decoded text | 3 | parity and snippet examples |
| Per-part charset and transfer encoding | 2 | QP and base64 examples |
| Attachment metadata kept, bytes on demand | 4 | `yahoo_adapter_attachments_spec` |
| `AttachmentsIngest` processes Yahoo; Yahoo documents download | 5 | executor, service, download specs |
| Definition of done | all | Checks |

## Risks

- **Partial-fetch response key.** Confirm net-imap 0.6.8 stores the `<0.1048576>` answer under a key `FetchStruct#part(1, offset: 0)` finds (`"BODY[1]<0>"`); record a real response line rather than guess.
- **net-imap parses BODYSTRUCTURE uncapped.** Its parser recurses over the whole structure before our depth cap runs; `max_response_size` is the only lever. Out of scope.
- **New attachment failure modes.** A message moved out of INBOX or a UIDVALIDITY reset now fails the attachment fetch; `IngestEmailAttachments` and `PerRecord` report it as a failure, not a crash.
