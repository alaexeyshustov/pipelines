# ADR 0013: Email ingestion pipeline

## Status
Accepted (GH #222, part of #215)

## Context

`Email` (GH #217) stores every INBOX email with its full body, but nothing fills it. After ingest an email must be tagged (`Tags::Classifier`, #219), its attachments extracted when tagged (`Document::ExtractEmailAttachmentsJob`, #220) and, for `job_application` emails, its `Interview` upserted (#228). The Drive pipeline (#221: `Document::SyncDriveJob` run by the `DriveDocumentsSync` step) is the pattern to mirror. Constraints: INBOX only, Gmail and Yahoo (IMAP), full body. The legacy `Applications Workflow` (`EmailsFetcher` -> `ApplicationMail`) stays untouched until #228 removes it.

## Decision

**Backfill.** The first sync of a mailbox (no cursor) fetches the last 90 days (`Setting "email_backfill_days"`, default 90).

**Incremental sync with a stored cursor.** Gmail uses `historyId`, IMAP uses `UIDVALIDITY` + last UID. The cursor lives in a new table `email_sync_cursors`, one row per account and mailbox:

| Column | Type | Notes |
|---|---|---|
| provider | STRING, NOT NULL | `gmail` / `yahoo` |
| account | STRING, NOT NULL | mailbox owner (Gmail address, Yahoo username) |
| mailbox | STRING, NOT NULL | `INBOX` for now |
| history_id | STRING, NULL | Gmail only |
| uid_validity | BIGINT, NULL | IMAP only |
| last_uid | BIGINT, NULL | IMAP only |
| last_synced_at, last_rescan_at | DATETIME | |

Unique index on `[provider, account, mailbox]`. A model (`Email::SyncCursor`), not a `Setting`: it is per mailbox, advanced atomically with the sync, and not user configuration. Gmail: capture the profile `historyId` before listing, then page `users.history.list(startHistoryId, historyTypes: messageAdded, labelId: INBOX)`. IMAP: select INBOX, compare `UIDVALIDITY`, `UID SEARCH UID last_uid+1:*` and drop UIDs `<= last_uid` (`*` always matches the last message). The cursor advances only after the whole batch is stored, so a crash re-reads instead of skipping.

**Stale cursor falls back to a rescan.** Gmail 404 on history, or a changed `UIDVALIDITY`, triggers a 90-day date-window rescan (`after:` / IMAP `SINCE`) deduped on `provider_message_id`, then the cursor is reset to the current position. A rescan is also the path for a missing cursor, so backfill and recovery are one code path.

**Idempotency.** `Email` is unique on `[provider, provider_message_id]` (exists). Insert and rescue `ActiveRecord::RecordNotUnique`; only newly created rows count as stored and enter the chain. Gmail id is the message id. IMAP UIDs are only unique within one `UIDVALIDITY`, so Yahoo's `provider_message_id` becomes `"<uid_validity>:<uid>"` (a reset then creates new rows instead of colliding with old UIDs; the 90-day rescan limits the duplicates this can produce).

**Where orchestration lives.** Services must not call services (`App/ServiceMustNotCallService`) and models must not enqueue, so the flow is jobs, mirroring #221:

- `Orchestration::Executors::EmailsSync` (registered in `ServiceRegistry`) runs `Email::SyncInboxJob.perform_now` inline for each provider, so the `StepRun` records the outcome. Seeded as pipeline "Email Ingestion" with one step.
- `Email::SyncInboxJob(provider)` fetches via the `Emails` seam (new cursor-based methods on the adapters, in `infra`), stores new emails and enqueues `Email::ProcessJob` per new email. `Emails` stays free of models.
- `Email::ProcessJob(email_id)` runs `Tags::Classifier.call(email)`, then enqueues `Document::ExtractEmailAttachmentsJob` when the email has a tagging and the Interview extraction job (#228) when it has the `job_application` tag. Each later stage is its own job so it retries on its own.

**Schedule.** Cron `*/30 * * * *` (the scheduler ticks every minute). Overlap is harmless: stores are idempotent and the cursor is advanced only forward.

**Errors and retries per stage.**
- Sync: a provider failure (auth, network, API) is recorded in the output and does not stop the other provider; the step raises after both were tried so the `StepRun` is `failed`. The cursor does not advance. A single message that cannot be fetched or parsed is logged, counted as `failed`, and skipped, and it holds the cursor: if any message of a run failed the cursor is neither advanced nor reset, so the next run re-reads the same range (already stored messages are cheap duplicates). A permanently failing message therefore keeps the cursor until a history 404 / `UIDVALIDITY` change triggers a rescan.
- Tag: no job retry on `RubyLLM::Error` (RubyLLM retries and falls back itself, see `orchestration.md`); one retry for raw transport errors. `Classifier` writes nothing on failure, so the next attempt is clean. A new nullable `emails.tagged_at` is set after a successful classification; each sync run first re-enqueues emails with `tagged_at IS NULL` older than one hour, so a failed tag stage is never lost and "failed" is distinguishable from "untagged".
- Attachments: failures are per attachment (logged, other attachments continue; #220). Dedup on checksum makes re-runs free.
- Interview: upsert by company and job title; re-runs are idempotent (#228).

**Re-tagging.** Only a newly stored email enters the chain, once. Re-running `Tags::Classifier` replaces `llm` taggings and never touches `manual` ones (#219). Manual or repeated re-tagging does not re-trigger later stages automatically; they are idempotent, so a backfill task can enqueue `Email::ProcessJob` for any set of emails safely.

**Observability.** The step returns per provider `{ "mode" => "backfill|incremental|rescan", "fetched", "stored", "duplicates", "failed", "enqueued" }`, saved as the `StepRun` output, like the Drive summary. Per-email stage outcomes live in Solid Queue and the log; `tagged_at IS NULL` is the backlog gauge.

## Consequences

- Steady-state cost is one cheap history/UID query per provider per run; the 90-day rescan is the rare recovery path.
- Adapters gain real work: Gmail must return `html_body`, `source_url` and a parseable date, and expose history; IMAP must expose `UIDVALIDITY` and fetch by UID range. Today `get_message` returns one `body`, no html, and `date` as a string.
- Yahoo ids change shape; any code reading Yahoo `provider_message_id` as a bare UID (`Emails.get_message`) must split it. Attachments stay Gmail-only (#220).
- Emails older than 90 days are never ingested unless the window setting is raised and a rescan is forced.
- The legacy Applications Workflow and the new pipeline coexist until #228; they share only the `Emails` seam.
- Three small additions to the schema: `email_sync_cursors`, `emails.tagged_at` (and Yahoo id format).

## Alternatives considered

**Date-window only** (rescan the last N days every run, dedupe on id): simplest, no cursor table. Rejected: cost grows with mailbox size on every run (list plus per-message fetch checks), IMAP `SINCE` is day-granular, and a missed window silently loses mail. It is kept as the fallback only.

**One pipeline step per stage** (sync, tag, attachments, interviews as separate steps): visible in the pipeline UI. Rejected: steps run sequentially over the whole run output, so one slow or failing email blocks the batch, the step input would carry email ids through `StepRun` JSON, and retries are per step rather than per email. Per-email jobs isolate failures and retry independently; the cost is that stage outcomes are not in the `StepRun`.

## Follow-ups

- #234 Email sync cursor model
- #235 Gmail incremental INBOX sync
- #236 Yahoo (IMAP) incremental INBOX sync
- #237 Ingestion pipeline step
- #238 Per-email processing chain: tag -> attachments
- #239 Enqueue Interview extraction for job_application emails
