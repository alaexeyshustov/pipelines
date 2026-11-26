# Plan: fetch only text parts of IMAP messages (GH #304)

**Status:** planned, architect-reviewed | **Branch:** `fix/gh-304-imap-text-parts`, cut from `feat/gh-248-email-ingestion-as-an-orchestration-pipeline` (PR #337) | **Follows:** #299 (#240 SEC-09)

## Decisions

Settled with the user:

- **Both fetch paths.** `YahooAdapter#message` (tools) and `ImapInboxReader#mail` (`YahooFullMessage`, the `EmailsList` step) go through one shared text-part fetcher. `RFC822` is no longer fetched anywhere; `YahooAdapter::FULL_FIELDS` is removed. `HEADER_FIELDS` and `ImapSession#fetch_raw_mail` stay for listings.
- **Attachments: adapter + pipeline.** Yahoo implements `attachments` / `attachment`; `AttachmentsIngest` ingests tagged Yahoo emails too; `Document::Download` serves Yahoo documents.
- **Rebuild a reduced `Mail`.** `ImapBodyParser`, `YahooMessageParser` and `YahooFullMessage` keep taking a `Mail`, so `body`, `html_body` and the other fields stay the same for normal mail.
- **Limits (constants).** `MAX_TEXT_PART_BYTES = 1_048_576` (truncate), `MAX_DEPTH = 10`, `MAX_TEXT_PARTS = 20`.
- **Snippet.** For multipart mail today's snippet is the first 200 characters of raw MIME (preamble, boundaries, part headers). It becomes the first 200 characters of the decoded text body. Intended behaviour change for multipart mail; single-part is unchanged.
- **Specs use no test doubles** (`App/NoTestDoubles`). The issue's `instance_double` acceptance criterion is replaced by recorded IMAP responses parsed into real `Net::IMAP::FetchData`.
- **ADR 0013 and ADR 0018** each get a one-line note that #304 supersedes "Gmail-only" attachments. No new ADR: never fetching RFC822 is an implementation constraint.
- **No backfill.** No tagged Yahoo emails exist yet, so no data migration is needed.
- **Forwarded mail.** Attachments inside `message/rfc822` parts are not listed for Yahoo (Gmail expands them). Accepted gap.

Choices this plan adds:

- **Shared fetcher.** New `Emails::Adapters::ImapTextFetcher` (infra) taking an `ImapSession`, next to `ImapInboxReader` and `ImapLabelManager`. `ImapSession` gains lock-free `fetch(uid, attrs) -> Net::IMAP::FetchData?` (`fetch_raw_mail` is rebuilt on it, so there is one `uid_fetch` call site) and lock-free `uid_validity(mailbox) -> Integer` (`ImapInboxReader#uid_validity` wraps it in the lock). `ImapSession#with_lock` is a non-reentrant `Mutex#synchronize`: the fetcher and the attachment reader each take the lock once and do all their IMAP calls inside it (which also keeps the reconnect `retry` correct); callers must not hold it. Parse errors raise (no `$stderr` swallowing); `PerRecord` reports them.
- **BODYSTRUCTURE walker.** New `Emails::Adapters::ImapBodyStructure` (pure, no IO) turns `FetchStruct#bodystructure` into ordered `Leaf`s (`path`, `mime_type`, `charset`, `encoding`, `size`, `filename`, `inline`). It narrows the union with `case … when Net::IMAP::BodyTypeMultipart`, stops descending at depth 10 and logs the dropped subtree with `Rails.logger.warn`; the message still returns. `message/rfc822` parts are leaves (today's `Mail` does not read text inside them either). Uses the typed net-imap 0.6 readers, not `FetchData#attr` (narrowed to `Hash[String, String]` in `sig/shims/external_gems.rbs`).
- **Normalisation on the `Leaf`.** net-imap upcases media types and param keys (`"CHARSET"`, `"NAME"`, `"FILENAME"`), so `mime_type` is downcased (`Document::FileType.supported?` and `TEXT_TYPES` compare lowercase). Filenames: params are downcased into a `Mail::ParameterHash` (decodes RFC 2231 `filename*=` / `filename*0*=`), then `Mail::Encodings.value_decode` (RFC 2047). A nil or unknown transfer encoding is treated as `7bit`.
- **Rules on the `Leaf`.** `Leaf#text?` (type `text/plain` or `text/html` without a filename: disposition `filename`, content-type `name`, or location; same as `Mail#find_attachment`, so it matches `ImapBodyParser`'s `reject(&:attachment?)`), `Leaf#attachment?` (filename present, not inline) and `Leaf#part_numbers` (`[2, 1]` for `"2.1"`). `ImapTextFetcher` and `ImapAttachmentReader` share them, so the rules cannot drift; the two classes stay separate, like `GmailFullMessage` / `GmailAttachmentReader`. At most `MAX_TEXT_PARTS` text leaves, in tree order.
- **Two round trips per message.**
  1. `UID FETCH uid (UID BODYSTRUCTURE BODY.PEEK[HEADER])` (no `FLAGS`: labels come from the mailbox).
  2. `UID FETCH uid (BODY.PEEK[p1]<0.1048576> BODY.PEEK[p2]<0.1048576> …)` for the text leaves; a single-part message uses path `1`. The server truncates, so no more than 1 MB per part crosses the wire. Skipped when there are no text leaves (an empty `UID FETCH uid ()` is a protocol error); the `Mail` then has headers and no body. Read with `part(first, *rest, offset: 0)` (the sig needs a positional first index).
- **Reduced `Mail` keeps encoded bytes.** Each text part is rebuilt with `Content-Type: <type>; charset=<charset>` and `Content-Transfer-Encoding: <encoding>` from BODYSTRUCTURE and the fetched (still encoded) body, so Mail decodes base64, quoted-printable and charsets as today. Multipart: `Mail.new(header)` plus the text leaves as parts of a flat multipart under a fresh boundary that overrides the original `Content-Type`. Single part: header plus the one body. A truncated base64/QP tail decodes leniently; the existing `encode(..., invalid: :replace)` covers broken bytes.
- **Attachments.** New `Emails::Adapters::ImapAttachmentReader`, the counterpart of `GmailAttachmentReader`:
  - `list(message_id)` → `[{ id: "<part path>", filename:, mime_type:, size: }]` for `Leaf#attachment?` leaves (inline ones skipped, as Gmail). `size` is the encoded octet count.
  - `data(message_id, attachment_id)` checks `attachment_id` against `/\A\d+(\.\d+)*\z/` and the listed paths, fetches `BODY.PEEK[<path>]` and decodes it with `Mail::Encodings.get_encoding(encoding).decode` (`# : String`, the Mail sigs return `untyped`).
  - Ids go through `ImapInboxReader.split_message_id` (`"<uid_validity>:<uid>"` or bare UID); the mailbox is always `ImapInboxReader::MAILBOX`. In **both** `list` and `data`, inside the reader's single lock block, `ImapSession#uid_validity` is compared with the id's validity before BODYSTRUCTURE and body fetches; a mismatch raises `"UIDVALIDITY changed"`, so a reset mailbox cannot list or hand over another message's files. A bare UID skips the check.
  - Attachment bytes are fetched whole, with no cap (same as Gmail).
- **`YahooAdapter` class length.** It has 110 body lines and `Metrics/ClassLength` is 110; the delegates alone would put it at about 112. So `to_message` (`yahoo_adapter.rb:115-127`) moves to `YahooMessageParser#to_message` (the parser already holds `uid`, `mail`, `mailbox`), which decodes the body once and takes the snippet from `body[0, 200]` (no second `ImapBodyParser`). `#message` delegates to `@text_fetcher.mail(uid, mailbox:)` (removing the lock, `ensure_mailbox` and `parse_mail` full-fields code); `#attachments` / `#attachment` are one-line delegates to `@attachment_reader`. No `rubocop:disable`; the `YahooInboxSync` mixin is the precedent if more room is needed.
- **Fixtures.** Only BODYSTRUCTURE and header response lines are hand-recorded, in `spec/fixtures/files/imap/*.txt`, next to a stored raw `.eml` per message. `spec/support/helpers/imap_response_helpers.rb` builds the `* 1 FETCH (UID 101 BODY[n]<0> {len}\r\n…)` lines from bytes sliced out of the `.eml` (exact byte counts and CRLF) and parses them with `Net::IMAP::ResponseParser.new.parse(line).data` into real `FetchData`; the step-2 parity check compares against the same `.eml`. A "large" attachment is only a declared size in the BODYSTRUCTURE line; no large file is committed. The 12-level nesting case is generated in the helper. The existing `Net::IMAP.allocate` + `allow(imap).to receive(:uid_fetch)` partial stub stays (`App/NoTestDoubles` bans only receiverless `double`, `instance_double`, `spy`). `stub_yahoo_adapter(attachments:, attachment:)` already exists for step 5.

## Steps

### 1. Fixtures and `ImapBodyStructure` (infra)

- **Files:** `spec/fixtures/files/imap/` (plain single-part; `multipart/alternative`; `multipart/mixed` with text and a PDF declared at 5 MB; nested `mixed > related > alternative`; ISO-8859-1 quoted-printable; base64 UTF-8; inline image; `message/rfc822`; RFC 2231 filename; single-part `application/pdf` with no text; 25 text siblings), `spec/support/helpers/imap_response_helpers.rb`, `lib/emails/adapters/imap_body_structure.rb`, `sig/lib/emails/adapters/imap_body_structure.rbs` (`Leaf` `Data` with `text?`, `attachment?`, `part_numbers`; no `untyped`).
- **Red first:** `spec/lib/emails/adapters/imap_body_structure_spec.rb`: leaf paths (`1`, `1.2`, `2.1.1`) and `part_numbers` in tree order; `text?` / `attachment?` by the filename and inline rules; uppercase types and param keys come back downcased; RFC 2231 and RFC 2047 filenames decoded; nil encoding is `7bit`; `message/rfc822` is a leaf; 12 levels deep returns only parts at depth ≤ 10 without raising.
- **Accept when:** spec green, `steep check` clean for the new file.

### 2. `ImapSession#fetch` and `ImapTextFetcher` (infra)

- **Files:** `lib/emails/adapters/imap_session.rb` (`fetch`, `uid_validity`, `fetch_raw_mail` on `fetch`), `lib/emails/adapters/imap_text_fetcher.rb` (`MAX_TEXT_PART_BYTES`, `MAX_TEXT_PARTS`, `TEXT_TYPES`, `#mail(uid, mailbox:) -> Mail::Message?`, taking the lock and running `ensure_mailbox`), `sig/lib/emails/adapters/imap_session.rbs`, `sig/lib/emails/adapters/imap_text_fetcher.rbs`.
- **Red first:**
  - `spec/lib/emails/adapters/imap_session_spec.rb`: `#fetch` returns the `FetchData` or nil; `#uid_validity` reads STATUS without taking the lock.
  - `spec/lib/emails/adapters/imap_text_fetcher_spec.rb`:
    - large attachment: `uid_fetch` gets `BODYSTRUCTURE`, then only `BODY.PEEK[1]<0.1048576>`; never `RFC822`, `BODY[]`, `BODY.PEEK[2]` or `BODY.PEEK[TEXT]`;
    - QP ISO-8859-1 and base64 parts decode to the same text as `Mail.new(raw)`;
    - a part over 1 MB is requested with the partial range and the result is ≤ 1 MB;
    - 25 text siblings: only the first 20 are fetched;
    - no text leaves (single-part PDF): only round 1 is sent, and a header-only `Mail` comes back;
    - missing UID returns nil;
    - 12 levels deep yields a `Mail` with only parts within the cap.
- **Accept when:** both specs green; `ImapBodyParser.new(fetched).body/html` equals `ImapBodyParser.new(Mail.new(raw))` for every fixture with a matching full raw message.

### 3. Route both paths through the fetcher; `to_message` and snippet in the parser (infra)

- **Files:** `lib/emails/adapters/yahoo_adapter.rb` (`@text_fetcher`, `#message`, drop `FULL_FIELDS`, drop `to_message` and `parse_mail`'s full-fields use), `lib/emails/adapters/imap_inbox_reader.rb` (`#mail(uid)` via `ImapTextFetcher` with `MAILBOX`; `#uid_validity` wraps `ImapSession#uid_validity`), `lib/emails/adapters/yahoo_message_parser.rb` (`#to_message`, body decoded once, snippet from `body[0, 200]`), `sig/lib/emails/adapters/yahoo_adapter.rbs`, `sig/lib/emails/adapters/imap_inbox_reader.rbs`, `sig/lib/emails/adapters/yahoo_message_parser.rbs`.
- **Red first:**
  - `spec/lib/emails/adapters/yahoo_adapter_spec.rb`: "never fetches RFC822"; "a message with a large attachment fetches only its text parts"; "normal mail output unchanged" (single-part and multipart give the same `id, subject, from, to, date, body, labels` as the old `Mail.new(raw)` path); "multipart snippet is the first 200 characters of the decoded text".
  - `spec/lib/emails/adapters/yahoo_adapter_inbox_sync_spec.rb`: `#fetch_message` and `#message` examples on fixture responses give identical hashes (including `html_body` and `date`); not-found and no-date cases kept.
- **Accept when:** both specs green; `bundle exec rubocop lib/emails` passes with no new disables; `git grep RFC822 lib/` shows only `RFC822.HEADER`.

### 4. Yahoo attachments (infra)

- **Files:** `lib/emails/adapters/imap_attachment_reader.rb` (`list`, `data`), `lib/emails/adapters/yahoo_adapter.rb` (`#attachments`, `#attachment` delegates), `lib/emails/adapters/base_adapter.rb` (comment: both providers implement attachments), `sig/lib/emails/adapters/imap_attachment_reader.rbs`, `sig/lib/emails/adapters/yahoo_adapter.rbs` (`attachments: (String | Integer) -> Array[attachment]`, `attachment: (String | Integer, String) -> String`, `@attachment_reader`).
- **Red first:** `spec/lib/emails/adapters/yahoo_adapter_attachments_spec.rb`: PDF listed as `{ id: "2", filename: "cv.pdf", mime_type: "application/pdf", size: n }` (lowercase type), inline image and attachments inside `message/rfc822` left out; RFC 2047/2231 filenames decoded; `#attachment("77:101", "2")` fetches only `BODY.PEEK[2]` and returns decoded bytes; validity mismatch raises in both `#attachments` and `#attachment` before any BODYSTRUCTURE or body fetch, without `ThreadError`; unknown or malformed part id raises without fetching a body; bare UID works.
- **Accept when:** spec green; return shape equals Gmail's (keys and types, as in `spec/lib/emails/adapters/gmail_adapter_attachments_spec.rb`).

### 5. Yahoo attachments in the pipeline and downloads (application)

- **Files:** `lib/orchestration/executors/attachments_ingest.rb` (`eligible` becomes `Email.tagged`; header comment), `app/services/document/ingest_email_attachments.rb` (header comment), `app/services/document/download.rb` (`when Emails::GMAIL, Emails::YAHOO then from_email(ref)`, passing `ref["provider"]` to `Emails.attachment`; header comment; errors already redirect in `documents_controller.rb`), `config/pipelines/email_ingestion.json` (step descriptions: "tagged emails (Gmail and Yahoo)"), `docs/architecture.md` (lines 20, 40), `docs/orchestration.md` (step 4, line 44), `docs/schemas.md` (Yahoo `source_ref`: `message_id` is `"<uid_validity>:<uid>"`, `attachment_id` is the IMAP part path), `docs/adr/0013-email-ingestion-pipeline.md` and `docs/adr/0018-ingestion-steps-in-pipeline.md` (superseded-by-#304 notes). No sig changes expected.
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

- **Partial-fetch response key.** net-imap 0.6.8's `FetchStruct#part(1, offset: 0)` reads `"BODY[1]<0>"` (verified by architect); the fixtures still use real response syntax.
- **net-imap parses BODYSTRUCTURE uncapped.** Its parser recurses over the whole structure before our depth cap runs; `max_response_size` is the only lever. Out of scope.
- **Unparseable BODYSTRUCTURE.** A structure net-imap cannot parse now fails the message, where RFC822 used to work; `PerRecord` reports it.
- **New attachment failure modes.** A message moved out of INBOX or a UIDVALIDITY reset now fails the attachment fetch; `IngestEmailAttachments` and `PerRecord` report it as a failure, not a crash.
- **Forwarded-mail attachments** (inside `message/rfc822`) are not ingested for Yahoo; accepted.
