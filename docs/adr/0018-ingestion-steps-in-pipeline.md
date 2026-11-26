# ADR 0018: Ingestion steps in the pipeline

## Status
Accepted (GH #248). Partially supersedes [ADR 0013](0013-email-ingestion-pipeline.md): "Where orchestration lives", "Errors and retries per stage" and the alternative "One pipeline step per stage". Changes the "Sync vs background" decision of [ADR 0014](0014-embedding-model.md) for emails and email attachments.

## Context

ADR 0013 ran ingestion as a chain of background jobs and put only its entry point (`EmailsSync`) in a pipeline step. Each later stage (`Email::ProcessJob`, `Document::ExtractEmailAttachmentsJob`, the embed jobs) was invisible to the pipeline run: no input or output on an `ActionRun`, no failure in the run dashboard. The sync decided between "incremental" and "rescan" by itself, so a user could not ask for a given date range.

## Decision

- **Six steps in one on-demand pipeline, "Email Ingestion", no cron.** `EmailsList`, `EmailsClassify`, `EmailsEmbed`, `AttachmentsIngest`, `DocumentsClassify`, `DocumentsEmbed`. Steps run synchronously inside `PipelineRunJob`. They pass record ids, never records, and every id list is unique. The pipeline is loaded from `config/pipelines/email_ingestion.json` (written by `PipelineExporter`); the seeds import it into a database that has none and remove the old one-step pipeline.
- **Per-item services, loops in the executors.** `Tags::Classify`, `Embeddings::Embed` (per record), `Document::IngestEmailAttachments` and `Email::InboxSync` return an outcome; the executor loops, tallies and reports. A step can later fan out per record (#241) and the jobs that stay (`Document::TagJob`, `Email::EmbedJob`, `Document::EmbedJob`) call the same services.
- **Errors.** A per-item failure is reported in the step output as `failed: [{ "id", "error" }]` and does not fail the step. Step 1 fails only when every requested provider failed or lacked credentials; a failed `ActionRun` keeps no output, so its error carries the per-provider JSON. Pipeline steps have no `retry_on`: running the pipeline again is the retry (one exception: if duplicate detection raises after a document was embedded, `DocumentsEmbed` keeps it embedded, enqueues `Document::DetectDuplicatesJob`, which retries, and lists the id in `failed`). It picks up `pending` and `failed` emails of the requested providers, tagged emails without an embedding for the current model, and, through the documents of the processed emails, `pending` and `failed` documents. `ApplicationJob::TRANSPORT_ERRORS` is shared by the jobs that keep a `retry_on`.
- **Dates replace the mode.** The run form asks for providers and optionally `date_from` and `date_to`. Blank dates continue from the sync cursor (`Email::SyncCursor`). A date window is read by received date. The rules are in the header of `Email::InboxSync`; the research is in `docs/research/email-sync-cursor-vs-date-range.md`. Gmail gets epoch-second bounds (a `YYYY/MM/DD` date is read as Pacific time), IMAP gets `SINCE` and `BEFORE`, and the Gmail history also reads `labelAdded` (INBOX), so mail moved into the inbox is not missed. A historical range never touches the cursor. The sync logic moved from `Email::SyncInboxJob` into `app/services/email/inbox_sync.rb`.
- **`classification_status` replaces `tagged_at`** on `emails` and `documents`: an enum `pending | tagged | untagged | failed` (a plain enum, not AASM: `force:` and a changed Drive file move between any states). `untagged` means analysed with no tags; `failed` means the last classification raised. `Tags::ManualTaggingForm` sets `tagged`, so a manually tagged record is embedded and its attachments ingested by the next run.
- **Embedding policy.** Only `tagged` emails and email attachments are embedded (until now every email and attachment was). Untagged records drop out of semantic search; existing embeddings of untagged records stay. Drive documents are still always embedded. "Current embedding" means an `Embedding` row for `LlmModels.embedding`, whatever its digest. `Embeddings::Embed` takes `force:` to re-embed regardless of the digest (for #335).
- **Interview extraction is dropped from ingestion** on purpose; an extraction pipeline is planned separately. `Interview::ExtractJob` is removed; `Interviews::EmailExtractor` and the Interview model and pages stay.
- **Stale runs: heartbeat.** `orchestration_pipeline_runs.heartbeat_at` is set by `PipelineRunner` when a run starts and around each step, and by the executors' loops, `Email::InboxSync` (per message) and `Document::IngestEmailAttachments` (per attachment) through `Orchestration::Heartbeat.beat` (at most once a minute; the current run is `Orchestration::Current.pipeline_run`, set inside each `Async` task because current attributes are isolated per fiber). An in-progress run whose heartbeat (else `started_at`, else `created_at`) is older than 10 minutes no longer blocks `PipelineRunForm` or `SchedulerJob`. A queued run that never started has no heartbeat, so it falls back to `created_at` and also stops blocking after 10 minutes; this is accepted.
- **Output schemas for services.** `Orchestration::Executable.output_schema` declares an executor's output, so the validator and the steps list check the paths a later step maps from it (`PipelineValidator.output_schema_for`). An executor may define `run_hints`; the pipeline page shows its text under the matching field of the run dialog (the last sync per provider).

## Consequences

- Every stage shows up in the run: its input, its output (id lists) and its failures.
- The migration carries no data over (the app held none); every row starts `pending`. A run is synchronous and serial, so a run classifies every `pending` email in one step. The heartbeat keeps that run from being marked stale; a single message fetch or OCR call slower than 10 minutes could still make a live run look stale.
- A step failing for one email never blocks the others, but a failed email is retried only by running the pipeline again.
- Unsupported attachment types are ignored silently. A failed attachment is not retried: step 4 downloads only listed emails without a document, and step 1 stops listing an email once it is tagged and embedded (which step 3 does before step 4 runs). Documents are not lost the same way: step 4 also passes on every document of a tagged Gmail email that is `pending`, `failed`, or tagged without an embedding, so steps 5 and 6 finish them on a later run.
- Another pipeline that still has an `EmailsSync` step is kept by the seeds and logged; it fails when run because the class is gone.
- The cursor, the research note and the schema changes stay: `email_sync_cursors` (ADR 0013), `classification_status` and `heartbeat_at` (this ADR).

## Alternatives considered

**Keep the job chain and only report from the entry step** (ADR 0013): the stages stay invisible and a date range cannot be requested. Rejected.

**Fan out per record from the start** (#241): the per-item services make it possible later; it is not needed to make the stages visible and would need the pipeline runner to wait for jobs.

**AASM for the classification status:** rejected, any state can move to any other (`force:`, a changed Drive file).
