# Research: email sync cursor vs date range for a manual run (GH #248)

Question: the Email Ingestion pipeline (Gmail API + Yahoo IMAP) is run by hand, and its run form takes only `date_from`/`date_to` and a list of providers. Should the incremental cursor (Gmail `historyId`; IMAP UIDVALIDITY + last UID) be dropped (A), kept next to the date range (B), or combined some other way?
Sources: the code at `17050bee`, RFCs 3501/5032/7162, Google's Gmail API reference and help pages, Airbyte connector source, and Fivetran/Make/Zapier/Google Workspace/Thunderbird first-party docs or source. A live `CAPABILITY` call against `imap.mail.yahoo.com:993` was also made. Checked on 2026-11-24.

**Short answer: hybrid. The UI shows only dates, and the cursor becomes an internal shortcut.** `date_from` is optional, and **blank means "since the last sync"**. That one blank field replaces an "only new mail" toggle and a prefill. Per provider, step 1 uses the cursor when the range is open-ended (`date_to` blank or today) and `date_from` is blank or not earlier than the last-sync watermark. In every other case it lists a date window. A closed historical range (`date_to` in the past) **never touches the cursor**. An open window run moves the cursor forward only when the window began at or before the watermark. Duplicates cost nothing because `Email` is unique on `provider` + `provider_message_id`. This is the pattern Make ("Since specific date" for the first run, then "since the previous run"), Google Workspace (start date, then "delta"), and Airbyte/Fivetran (start date + saved state + an explicit re-sync) all use.

Why not plain A: an IMAP message copied or moved into INBOX keeps its old internal date but gets a new UID. A UID cursor catches it, while a date window that starts after that date does not (§3.4). Also, without some saved watermark, the "last synced" hint and the "blank = since last time" default have nothing to read. Why not plain B (two separate inputs): the user would have to understand two notions of position, and `date_to` cannot bound a history/UID listing (§1.5).

| | A: dates only | B: cursor + dates as two inputs | **Hybrid (recommended)** |
|---|---|---|---|
| UI | 2 dates | 2 dates + "incremental" toggle | 2 dates, blank `date_from` = since last sync |
| Steady-state cost | list the window (ids/UIDs only) + 1 dedupe query | 1 history / UID query | same as B |
| Mail moved into INBOX with an old date (IMAP) | missed | caught | caught |
| Gmail run more than ~1 week after the last one | window | 404, then window | 404, then window from the watermark |
| Code | delete ~25 files (§4.5) | as today | today + window bounds + decision rule |

---

## 1. Can a cursor coexist with a date-only UI?

Yes. Each sub-question:

1. **Prefilling `date_from`.** `UI::JsonFieldsComponent` renders `format: "date"` as a bare `<input type="date">`. It reads no `default` and no `description` (`app/components/ui/json_fields_component.html.erb`), and the schema is static per pipeline, so a per-provider value cannot be prefilled without new UI. **Leaving the field blank to mean "since the last sync" avoids the problem** and also covers scheduled runs, which have no `initial_input` (`app/jobs/scheduler_job.rb:27`).
2. **"Last synced at" per provider.** `Email::SyncCursor#last_synced_at` already exists. Showing it needs either a `description` in the schema (static text only) or a small dynamic hint on the pipeline page or in the run dialog. Make and Google Workspace show a start point when the job is set up, not the live position (§2), so the hint is a nice-to-have.
3. **Cursor or window.** Let **W** = `cursor.last_synced_at.to_date - 1 day`. The day of slack covers IMAP's day-granular, server-time `SINCE` (§3.2) and Gmail's PST dates (§3.1). Use the cursor when the range is open-ended and `date_from` is blank or ≥ W. Otherwise list a window. The cursor then returns a superset (everything since W), which is acceptable because the range means "make sure this is ingested", not "only this".
4. **Never moving the cursor backwards.** `advance!`/`reset!` already refuse to rewind within one epoch (`app/models/email/sync_cursor.rb`). The new rule sits one level up: a closed historical range calls neither of them, so `last_synced_at` does not move either.
5. **`date_to` in cursor mode.** `users.history.list` takes only `startHistoryId` ([history.list](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.history/list)), and `UID n:*` has no date. If `date_to` were applied as a filter in cursor mode, the cursor could not advance past the filtered-out mail. So **cursor mode is only for an open end** (`date_to` blank or ≥ today), and a past `date_to` always means a window.

## 2. How established products expose this

| Product | Initial point | Afterwards | Resync / backfill | Source |
|---|---|---|---|---|
| Airbyte Gmail | optional `start_date` (UTC date-time); "If not set, all historical data will be replicated" | `DatetimeBasedCursor` over 30-day slices, `lookback_window: PT1H`, Gmail query `after:<epoch> before:<epoch+1>`. **It does not use historyId** | "Refresh" erases the cursor for incremental streams (keep or remove records) | [manifest.yaml @6c8c30b](https://github.com/airbytehq/airbyte/blob/6c8c30b33e69de525ff352a553d071d7af8d2a0f/airbyte-integrations/connectors/source-gmail/manifest.yaml), [Refreshes](https://docs.airbyte.com/platform/operator-guides/refreshes) |
| Airbyte (general) | first incremental run behaves like a full refresh | at-least-once; "sources should prefer resending data if the cursor field is ambiguous" | | [Incremental append + deduped](https://docs.airbyte.com/platform/using-airbyte/core-concepts/sync-modes/incremental-append-deduped) |
| Fivetran | "historical sync time frame" on some connectors; the first historical sync is "the initial sync" | incremental: "only data that has been modified or added" | "Updating the time frame to a larger value triggers a connection re-sync"; manual "Resync all data" / per-table "Re-sync" | [Sync overview](https://fivetran.com/docs/core-concepts/syncoverview), [Trigger re-syncs](https://fivetran.com/docs/connectors/troubleshooting/trigger-historical-re-syncs) |
| Make | "Choose where to start": From now on / Since specific date / ID ≥ / All bundles / Select the first bundle | (not stated on that page) | reopen the panel by right-clicking the trigger | [Select the first bundle to process](https://help.make.com/select-the-first-bundle-to-process) |
| Zapier | the trigger dedupes by item ID: "If the Zap sees a new ID, the Zap runs" | same | no backfill described | [Data deduplication in Zaps](https://help.zapier.com/hc/en-us/articles/8496260269965-Data-deduplication-in-Zaps) |
| Google Workspace data migration | start date only: "imports messages from the selected date to the date that you start the import"; default Jan 1 2000 | "delta import" copies "newly added or updated data"; already imported mail is "skipped" | rerun the delta | [Migrate email with the new data migration service](https://knowledge.workspace.google.com/admin/migrate/migrate-email-with-the-new-data-migration-service?hl=en) |
| Thunderbird | "Synchronize all messages locally regardless of age" / "Synchronize the most recent [N] [days]" | an age window for the local copy only | | [am-offline.dtd](https://github.com/mozilla/releases-comm-central/blob/master/mail/locales/en-US/chrome/messenger/am-offline.dtd), [account settings help](https://github.com/mozilla/releases-comm-central/blob/master/suite/locales/en-US/chrome/common/help/mailnews_account_settings.xhtml) |

Common pattern: **one start date picked by the user, a position kept by the system, and an explicit "re-sync/refresh" for going back.** None of these products asks for an end date on incremental runs. The only end date found is in the legacy GWMME command-line tool (search result only, **unverified**). Fastmail and Apple Mail import windows were **not checked**.

## 3. API facts and correctness pitfalls

### 3.1 Gmail
- **Full vs partial sync.** A partial sync uses `history.list`. If `startHistoryId` is out of range the API "returns an HTTP 404" and "your client must perform a full sync". "History records are typically available for at least one week and often longer" ([sync guide](https://developers.google.com/workspace/gmail/api/guides/sync)). **For a manual, unscheduled run, Gmail's cursor will often be stale**, so the window path is the common case. It should start at W, not at `backfill_days`.
- **History IDs** "increase chronologically but are not contiguous" ([history.list](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.history/list)). The response `historyId` is "the mailbox's current history record", which is what `profile` returns today.
- **`after:`/`before:` dates.** "All dates used in the search query are interpreted as midnight on that date in the PST timezone"; for other zones, pass epoch seconds (`after:1388552400`) ([filtering guide](https://developers.google.com/workspace/gmail/api/guides/filtering)). `GmailInboxLister#after` sends `after:YYYY/MM/DD`, which is PST. **Use epoch seconds from the app's time zone**, with `before:` = start of `date_to + 1 day`. Airbyte does the same (`before:{{ end + 1 }}`). Whether an epoch `after:` is inclusive is **unverified**, so the one-day slack makes it irrelevant.
- **Which date.** The help page says `after:`/`before:` "search for emails received during a certain time period" ([Gmail search operators](https://support.google.com/mail/answer/7190?hl=en)). `internalDate` is "the time the message was originally accepted by Google… more reliable than the `Date` header", except for API-migrated mail, where it may be based on `Date` (Gmail discovery doc, `Message.internalDate`). That the search compares `internalDate` exactly is **unverified**.
- **Label moves.** `messageAdded` + `labelId: INBOX` (the current lister) does not report a message that later gets the INBOX label (`labelAdded`), and a date window misses it too if it is old. Both options share this gap (an inference from the [history types](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.history/list), not tested).

### 3.2 IMAP SEARCH dates ([RFC 3501 §6.4.4](https://www.rfc-editor.org/rfc/rfc3501#section-6.4.4))
- `SINCE`/`BEFORE`/`ON` compare the **internal date** "(disregarding time and timezone)". `SENTSINCE`/`SENTBEFORE` compare the `Date:` header in the same way. `BEFORE` is exclusive, so an inclusive `date_to` needs `BEFORE date_to+1`. `ImapSearchCriteria` already builds `BEFORE`.
- The internal date "reflects when the message was received"; for COPY it "SHOULD be the internal date and time of the source message" ([RFC 3501 §2.3.3](https://www.rfc-editor.org/rfc/rfc3501#section-2.3.3)). **Use SINCE/BEFORE, not SENT\***. A forged or old `Date:` header does not hide a newly received message.
- Second-level `OLDER`/`YOUNGER` exist only with the `WITHIN` extension ([RFC 5032 §2](https://www.rfc-editor.org/rfc/rfc5032#section-2)). Yahoo does not advertise it (§3.5).

### 3.3 UIDVALIDITY ([RFC 3501 §2.3.1.1](https://www.rfc-editor.org/rfc/rfc3501#section-2.3.1.1))
UIDs are "assigned in a strictly ascending fashion"; UID + UIDVALIDITY "MUST NOT refer to any other message… forever"; if UIDs do not persist, the new UIDVALIDITY "MUST be greater". UIDNEXT "MUST change whenever new messages are added". The current code is consistent with this: it compares UIDVALIDITY, uses `UIDNEXT - 1` as the position after a window, and builds ids as `"<uid_validity>:<uid>"`.

### 3.4 Late or odd mail
- **Old `Date:` header, received now.** The internal date is now, so both the cursor and a window covering today catch it. The stored `Email.date` is the `Date:` header (`lib/emails/adapters/yahoo_full_message.rb`, `gmail_full_message.rb`), so it can fall outside the range the user asked for. That is cosmetic, but worth one line in the UI hint: the range means "received".
- **Moved or copied into INBOX (IMAP).** It gets a new UID (strictly ascending) but keeps the source's internal date (§3.2). **The cursor catches it; a window that starts after that date does not.** This is the main correctness argument for keeping the IMAP cursor.
- **Overlapping or repeated ranges.** Harmless. Listing returns ids only, existing rows are filtered in one query (`SyncInboxJob#store_all`), and `RecordNotUnique` is rescued. Only new messages are fetched.

### 3.5 CONDSTORE/QRESYNC and Yahoo
- CONDSTORE adds mod-sequences, mainly so that **flag changes** can be resynced with `CHANGEDSINCE`. QRESYNC extends it to discover expunges in one round trip (`VANISHED`) ([RFC 7162 §1, §3.1](https://www.rfc-editor.org/rfc/rfc7162)). This pipeline only ingests new INBOX mail, so **neither one is needed**. UID + UIDVALIDITY is enough.
- **Yahoo, observed 2026-11-24 before login:** `CAPABILITY IMAP4rev1 SASL-IR AUTH=PLAIN AUTH=XOAUTH2 AUTH=OAUTHBEARER ID MOVE NAMESPACE XYMHIGHESTMODSEQ UIDPLUS LITERAL+ CHILDREN UNSELECT X-MSG-EXT OBJECTID IDLE ENABLE UIDONLY X-UIDONLY LIST-EXTENDED LIST-STATUS SPECIAL-USE PARTIAL APPENDLIMIT=41697280`. **There is no CONDSTORE, QRESYNC or WITHIN.** `XYMHIGHESTMODSEQ` is proprietary and undocumented. Capabilities after login were **not checked** (no credentials used). Note `UIDONLY` ([RFC 9586](https://www.rfc-editor.org/rfc/rfc9586)): the current code already uses UID commands only.

## 4. Recommendation for this app

### 4.1 Run form
- **providers**: checkboxes `gmail`, `yahoo`; required (`minItems: 1`). Today `JsonFieldsComponent` cannot pre-check them.
- **date_from**: optional date. Blank means "since the last sync", or the last `Email.backfill_days` days for a provider never synced. This replaces the "only new mail" toggle, so **no toggle**.
- **date_to**: optional date. Blank means "now". Set it only for a historical backfill, which leaves the sync position alone.
- **Hint:** first a static `description` ("Leave dates empty to fetch mail received since the last sync. Dates are received dates."). That needs `JsonFieldsComponent` to render `description`. Later, per-provider "last synced: <date>" from `Email::SyncCursor.last_synced_at`.

### 4.2 `initial_input_schema`
```json
{ "type": "object",
  "properties": {
    "providers": { "type": "array", "items": { "enum": ["gmail", "yahoo"] }, "minItems": 1 },
    "date_from": { "type": "string", "format": "date" },
    "date_to":   { "type": "string", "format": "date" } },
  "required": ["providers"] }
```
The executor checks the cross-field rules: `date_from ≤ date_to`, `date_to` not in the future, and `date_to` requires `date_from`.

### 4.3 Step 1 decision (per provider)
```
open_end = date_to.nil? || date_to >= today
W        = cursor.last_synced_at&.to_date&.-(1)           # nil if never synced
from     = date_from || W || today - backfill_days

if open_end && cursor.usable? && (date_from.nil? || date_from >= W)
  incremental (history since historyId / UID > last_uid)
  on Gmail 404 or UIDVALIDITY change -> window [W, now]    # not backfill_days
elsif open_end
  window [from, now]
else
  window [date_from, date_to]                              # historical
end
```
Windows are listed by received date: Gmail `after:<epoch(from)> before:<epoch(date_to+1)>`; IMAP `SINCE from BEFORE date_to+1`. Report the mode in the output, as `mode` does today (`incremental` / `window` / `historical`).

### 4.4 When the cursor advances
- **Incremental run:** `advance!` to the captured position. This is unchanged and still subject to the `failed_runs` hold.
- **Open window run:** `reset!` to the captured position (profile `historyId` / `UIDNEXT-1`) **only if `from ≤ W` or there is no cursor**. Otherwise the gap between W and `date_from` was never read, so the cursor stays and the next blank run covers it.
- **Historical run** (closed range): no cursor write at all, not even `last_synced_at`.
- Keep forward-only and the `failed_runs` rules as they are.

### 4.5 If the cursor were dropped (option A), delete
`app/models/email/sync_cursor.rb`, `db/migrate/20261103090300_create_email_sync_cursors.rb` (plus a drop-table migration), the cursor and `position` logic in `app/jobs/email/sync_inbox_job.rb` and `sync_inbox_job/{gmail,yahoo}_inbox.rb`, `failed_runs`, `lib/emails/history_expired_error.rb`, `GmailInboxLister#since`, `inbox_message_ids_since`, `inbox_uids_after`, `inbox_status`/`ImapInboxReader#status`/`#uids_after`/`#uid_validity` (`base_adapter.rb`, `gmail_adapter.rb`, `yahoo_inbox_sync.rb`, `lib/emails.rb`), their `sig/` files, and the specs `spec/models/email/sync_cursor_spec.rb`, `spec/factories/email_sync_cursors.rb`, `gmail_adapter_inbox_message_ids_since_spec.rb`, `yahoo_adapter_inbox_sync_spec.rb` and parts of `sync_inbox_job*_spec.rb`, `base_adapter_spec.rb`. ADR 0013 would then need a superseding ADR. **Keep** `"<uid_validity>:<uid>"` ids, because IMAP UIDs are unique only within one UIDVALIDITY. The cost of A is the gap in §3.4, and a "last synced" value would have to come from `Email` or `PipelineRun` data instead.

## 5. Open questions
1. Keep the `*/30` cron in `db/seeds.rb`? The issue says manual only. Either way, blank input must work: scheduled runs have no `initial_input`, and an `input_mapping` path into `_initial` raises `MissingPath` (`lib/orchestration/input_mapping_resolver.rb:47`).
2. In cursor mode, should mail received before `date_from` be dropped (a filter) or kept (a superset)? Keeping it is recommended, since it is simpler and the cursor stays valid.
3. Should `date_to = today` count as open-ended (the proposal does) or as historical? If it is open-ended, a window ending today can move the cursor forward when `from ≤ W`.
4. Should the dynamic "last synced" hint come now or later? It needs a change to `JsonFieldsComponent` or the run dialog.
5. Gmail INBOX label moves (§3.1) are missed by both paths. Should `labelAdded` be added?
