# Plan: email ingestion as an orchestration pipeline (GH #248)

**Status:** planned, architect- and critique-reviewed | **Branch:** `feat/gh-248-email-ingestion-as-an-orchestration-pipeline` | **Follow-up:** #335 (keeps the `force:` seams)

## Decisions

The issue's decisions stand. Choices this plan adds:

- **Executor DSL.** `Orchestration::Executable` gets `output_schema(**props)`, written like `input_schema`: it builds `{"type"=>"object","properties"=>…,"required"=>all keys}` and is not checked against `initialize`. `_AgentCallable` (`sig/shims/types.rbs`) gains `input_schema` and `output_schema`.
- **Output schema lookup.** `Orchestration::PipelineValidator.output_schema_for(action)` returns `action.agent? ? action.agent&.output_schema : ServiceRegistry.lookup(action.agent_class)&.output_schema`. `PipelineValidator#validate` and `StepsListComponent#compute_upstream_schemas_per_step` both use it, so `Action` stays free of the registry.
- **Output buckets hold id lists, not counts.**
  - `tagged`, `untagged`, `embedded`, `skipped` and `document_ids` are unique `Array[Integer]`.
  - `failed` is `[{ "id" => Integer, "error" => String }]`.
  - `duplicates_found` is an integer, the sum of `DetectDuplicates#flagged`.
- **Mappings.** Steps 2, 3 and 4 map `{from: "list_emails", path: "email_ids"}`; steps 5 and 6 map `{from: "ingest_attachments", path: "document_ids"}`. Each step filters by status itself.
- **Step 4 `skipped`** lists the emails that were not processed (not Gmail, or not `tagged`). Unsupported attachment types are still ignored silently. A failed attachment is recorded as `{id: email_id, error: "<filename>: <class>: <msg>"}`.
- **Per-item services:**
  - `Tags::Classify` (`app/services/tags/classify.rb`): `call(item, force: false)` returns `Result(status:, error:)`, where `status` is one of `tagged`, `untagged`, `failed`, `skipped`.
    - It skips the record unless it is `pending`/`failed` or `force:` is set.
    - After a successful run the status is `tagged` if `taggings.exists?`, otherwise `untagged`.
    - A non-transport `RubyLLM::Error` sets `failed` and is returned in the result.
    - `ApplicationJob::TRANSPORT_ERRORS` set `failed` and are re-raised, so `Document::TagJob`'s `retry_on` still applies. The executor loop records any `StandardError` as a `failed` entry.
  - `Document::IngestEmailAttachments` (`app/services/document/ingest_email_attachments.rb`): `call(email)` returns `Result(document_ids:, failed:)`. The logic comes from `ExtractEmailAttachmentsJob`, and a document found by checksum now returns its id.
  - `Email::InboxSync`: `call(provider:, date_from:, date_to:)` returns `Result(mode:, counts:, email_ids:)`. `GmailInbox` and `YahooInbox` are defined inside the same file.
- **Validation.**
  - Step 1's input checks live in `EmailsList` and raise `ArgumentError`: provider enum, `minItems`, ISO dates, `from ≤ to`, no future dates, `date_to` needs `date_from`. `""` and `nil` both mean blank.
  - The cursor-or-window rule is a private method in `Email::InboxSync`.
  - `Email::SyncCursor#usable?` is true when the cursor has both a position and `last_synced_at`.
  - "Today" and the `Time` bounds use `Time.zone` (UTC by default, `config/application.rb:36`).
- **Providers run one after another** in step 1, not through `Async`, so SQLite cursor writes stay serial.
- **Embedding is per item:** `Embeddings::Embed.call([record], force:)` once per record. This matches #241 fan-out and the jobs, at one model call per record.
- **"Current embedding"** means an `Embedding` row for `LlmModels.embedding`, whatever its digest. A new `Embeddable` scope `without_embedding(model:)` serves steps 1 and 3.
- **`classification_status`** is declared once in `Taggable`: `enum` with `default: :pending, validate: true` and no prefix. `awaiting_tagging(before:)` keeps its name and now means `pending`/`failed`.
- **Manual tagging sets the status.** `Tags::ManualTaggingForm#save` sets `classification_status: "tagged"` on the taggable, in the same transaction as the tagging, so the next run embeds the record and ingests its attachments. Removing a manual tag doesn't change the status.
- **Stale runs: heartbeat.**
  - New column `orchestration_pipeline_runs.heartbeat_at` (plain `add_column`; this table has no FTS triggers).
  - `PipelineRunner` sets it when the run starts and before and after each step. It also sets `Orchestration::Current.pipeline_run` (`ActiveSupport::CurrentAttributes`, in `lib/orchestration`).
  - Per-item executor loops call `Orchestration::Heartbeat.beat`, which touches the current run at most once a minute and does nothing outside a run.
  - `PipelineRun::STALE_AFTER = 10.minutes`. Scope `blocking`: `in_progress` where `COALESCE(heartbeat_at, started_at, created_at) >= STALE_AFTER.ago`.
  - `Pipeline#run_in_progress?` and `SchedulerJob` both use `blocking`.
- **Run hints.**
  - The optional executor hook is `self.run_hints`, returning `Hash[String, String]` keyed by input field.
  - `EmailsList.run_hints` returns `{"providers" => "Last synced: gmail 2026-11-20 14:03, yahoo never"}` from one query: `Email::SyncCursor.group(:provider).maximum(:last_synced_at)`.
  - `Orchestration::RunHints.call(pipeline)` (in `lib/orchestration`) finds the first enabled step and its first step action, looks it up in the registry, and calls `run_hints` if the executor responds to it.
  - The controller passes the hints through `body_options`. `JsonFieldsComponent` gets a `hints: {}` keyword and renders `description` and the hint under each field.
- **Seeds** remove only the pipeline named "Email Ingestion" that has an `EmailsSync` step. They:
  1. Destroy its runs, then the pipeline, using `destroy!`.
  2. Destroy the `EmailsSync` action if no step uses it any more.
  3. Log a warning naming any other pipeline that still has an `EmailsSync` step. Those pipelines are left as they are and fail at run time once the class is removed.
  4. Import the JSON when no pipeline named "Email Ingestion" exists.
  5. Enable the pipeline only if this seed run imported it, so a user's later disable is respected.
- **The pipeline JSON is produced once:** build the six steps in a console, then `PipelineExporter` → `JSON.pretty_generate`. It is never hand-written; the round-trip spec guards it.
- **New ADR:** `docs/adr/0018-ingestion-steps-in-pipeline.md` (the last existing ADR is 0017).

## Steps

### 1. Adapters: upper bound, epoch bounds, `labelAdded` (infra)

Files:
- `lib/emails.rb` and, under `lib/emails/adapters/`: `base_adapter.rb`, `gmail_adapter.rb`, `gmail_inbox_lister.rb`, `yahoo_inbox_sync.rb`, `imap_inbox_reader.rb`.
- Their sigs under `sig/lib/emails/**`.
- The two `Email::SyncInboxJob` inbox classes: a one-line `Date` → `Time` change each, to stay green until step 5.

Changes:
- `inbox_message_ids_after(from, before: nil)` and `inbox_uids_since(from, before: nil)` take `Time`.
- Gmail sends `q: "after:#{from.to_i}"`, plus `" before:#{before.to_i}"` when `before` is given.
- IMAP builds `ImapSearchCriteria.new(after_date: from.to_date, before_date: before&.to_date)`.
- `GmailInboxLister#since` asks for `history_types: %w[messageAdded labelAdded]` and keeps `labels_added` entries whose `label_ids` include `INBOX`. Returned ids are unique.

Red specs:
- `gmail_adapter_inbox_message_ids_after_spec.rb`: epoch `after`/`before`, no `YYYY/MM/DD`.
- `gmail_adapter_inbox_message_ids_since_spec.rb`: a message given the INBOX label is returned; any other added label is ignored.
- `yahoo_adapter_inbox_sync_spec.rb`: `SINCE` + `BEFORE date_to+1`.
- `base_adapter_spec.rb`: the new keywords raise `NotImplementedError`.

Acceptance: adapter specs are green; `rg "strftime\('%Y/%m/%d'\)" lib/emails` returns nothing; `steep check` is clean.

### 2. `classification_status` replaces `tagged_at`; `Tags::Classify` (domain + application)

Files:
- New: `db/migrate/<ts>_replace_tagged_at_with_classification_status.rb` and `app/services/tags/classify.rb`.
- Schema: `db/structure.sql`.
- Model concerns:
  - `app/models/concerns/taggable.rb`: the enum and `awaiting_tagging`.
  - `app/models/concerns/embeddable.rb`: `without_embedding`.
- Models:
  - `app/models/document/drive_entry.rb`: `classification_status: "pending"` when a Drive file changes.
- Forms:
  - `app/forms/tags/manual_tagging_form.rb`: sets `tagged` on save.
- Jobs:
  - `app/jobs/document/sync_drive_job.rb`: header comment and the requeue.
  - `app/jobs/document/tag_job.rb`: `perform(document_id, force: false)` calls `Tags::Classify`; `TRANSPORT_ERRORS` comes from `ApplicationJob`.
  - `app/jobs/application_job.rb`: `TRANSPORT_ERRORS`. `Evaluation::SampleJob` drops its own copy.
  - `app/jobs/email/process_job.rb`: minimal switch to `Tags::Classify` (deleted in step 5).
- Sigs: `email` and `document` models, `Taggable`, `Embeddable`, `Tags::Classify`, `ApplicationJob`, `ManualTaggingForm`.
- `archspec_facts/`, regenerated with `archspec reflect`.

Migration:
- Add the column with `add_column … :string, null: false, default: "pending"`; SQLite applies `ADD COLUMN` without rebuilding the table.
- No data backfill: the app holds no data yet, so every row starts `pending`.
- Add indexes `(provider, classification_status)` on `emails` and `(classification_status)` on `documents`.
- Drop the old column with `execute "ALTER TABLE emails DROP COLUMN tagged_at"`, and likewise for `documents`.
- Use no `remove_column` or `change_column_*`: on SQLite they rebuild the table and drop the FTS triggers.
- `down`:
  - re-add `tagged_at` (nullable, no values restored);
  - drop the new indexes;
  - drop `classification_status` with raw SQL.

Red specs:
- `spec/db/replace_tagged_at_with_classification_status_spec.rb`, in the style of `explicit_prompt_activation_spec.rb`:
  - the new column (string, not null, default `pending`), the indexes, and `tagged_at` gone;
  - all six FTS triggers survive up and down;
  - FTS search still finds a row.
- `spec/db/structure_load_spec.rb`: rename the `tagged_at` wording.
- `spec/services/tags/classify_spec.rb`:
  - `pending`/`failed` records are classified;
  - `tagged`/`untagged` records are skipped unless `force:` is set;
  - `force:` replaces only `llm` taggings;
  - a record with only manual taggings becomes `tagged`;
  - a non-transport error gives `failed`; a transport error gives `failed` and is re-raised.
- `spec/models/{email,document}_spec.rb`: the enum, its default, `awaiting_tagging`, `without_embedding`.
- `spec/forms/tags/manual_tagging_form_spec.rb`:
  - `pending`/`untagged`/`failed` → `tagged` on save;
  - a failed save leaves the status unchanged.
- `spec/jobs/document/tag_job_spec.rb`: uses the service, passes `force:`, retries on transport errors.
- `spec/jobs/document/sync_drive_job_spec.rb`: a changed file resets to `pending`, `TagJob` is enqueued and classifies it.

Acceptance:
- `rg tagged_at app lib sig spec db/structure.sql` has no hits outside old migrations.
- The FTS triggers are still in `structure.sql`.
- `archspec check --check-todo` passes.

### 3. Services: `Email::InboxSync`, `Document::IngestEmailAttachments`, `Embeddings::Embed force:` (application)

Files:
- `app/services/email/inbox_sync.rb` (new, with nested `GmailInbox`/`YahooInbox`).
- `app/models/email/sync_cursor.rb` (`#usable?`).
- `app/services/document/ingest_email_attachments.rb` (new).
- `app/services/embeddings/embed.rb` (`force:` skips the digest comparison).
- Sigs for all of these.

`InboxSync` implements the issue's pseudocode:
- `W = last_synced_at.in_time_zone.to_date - 1`.
- Bounds are `from.beginning_of_day` and `(date_to + 1).beginning_of_day` in `Time.zone`.
- On Gmail 404 or a UIDVALIDITY change: mode `rescan_window` over `[W, now]`, then `reset!`.
- An open window calls `reset!` only if `from ≤ W` or the cursor isn't usable.
- A historical run writes nothing to the cursor, not even `failed_runs`.
- The `failed_runs` hold wraps every `advance!` and `reset!`.
- `store_all`, `counts_for` and `attributes_for` move over unchanged.

Red specs:
- `spec/services/email/inbox_sync_spec.rb`, table-driven:
  - blank dates with a usable cursor → incremental, then `advance!`;
  - `date_from ≥ W` → incremental, and earlier mail is kept;
  - `date_from < W` → window, then `reset!`;
  - a cursor without a position → window from `backfill_days`, then `reset!`;
  - no cursor → window;
  - past `date_to` → historical, and the cursor row is unchanged;
  - `date_to = today` counts as open-ended;
  - Gmail 404 or UIDVALIDITY change → `rescan_window`;
  - the hold on window resets, and its release at `MAX_FAILED_RUNS`;
  - the `Time` bounds passed to the adapters.
- `spec/services/document/ingest_email_attachments_spec.rb`, with Mistral OCR stubbed through WebMock:
  - a known checksum skips OCR and still returns the id;
  - a failing attachment lands in `failed` while the others continue;
  - unsupported types are ignored.
- `spec/services/embeddings/embed_spec.rb`: `force:` re-embeds an unchanged digest.
- `spec/models/email/sync_cursor_spec.rb`: `#usable?`.

Acceptance:
- The `App/Service*` cops pass, including the nested inbox classes.
- `archspec check` passes.

### 4. Six executors, `output_schema`, registry, validator, component, heartbeat (application + interface)

Files:
- `app/concerns/orchestration/executable.rb` (+ sig).
- `sig/shims/types.rbs`.
- The six executors in `lib/orchestration/executors/`: `emails_list`, `emails_classify`, `emails_embed`, `attachments_ingest`, `documents_classify`, `documents_embed` (+ sigs).
- `lib/orchestration/service_registry.rb`: the six are added; `EmailsSync` stays until step 5.
- `lib/orchestration/pipeline_validator.rb`: `output_schema_for`.
- `app/components/orchestration/steps_list_component.rb`.
- Heartbeat:
  - `lib/orchestration/current.rb` and `lib/orchestration/heartbeat.rb` (+ sigs);
  - a migration adding `heartbeat_at`;
  - `lib/orchestration/pipeline_runner.rb` sets `Current` and touches the heartbeat per step.
- `spec/support/prosopite.rb`: method-scoped entries for the per-item loops, each with a one-line reason ("per-item service by design, #241").

`EmailsList`:
- Validates its input, then runs `InboxSync` per requested provider.
- A provider raising `NotConfigured` gets `{mode: "skipped"}`; any other error gets `{mode:, failed:, error:}`.
- `email_ids` is the unique union of:
  - the new emails;
  - the requested providers' `pending`/`failed` emails;
  - `tagged.without_embedding`.
- Raises with `"… Output: #{json}"` only when every requested provider failed or was skipped.
- Its input schema gives `date_from`/`date_to` a `description` and no `type`.

The per-item loops in every executor call `Orchestration::Heartbeat.beat`.

Red specs:
- One spec per executor in `spec/lib/orchestration/executors/`:
  - schema shapes;
  - status filtering;
  - unique ids;
  - per-item `failed`;
  - Yahoo emails skipped in step 4;
  - `duplicates_found`;
  - the all-providers-failed raise and its message.
- The `output_schema` DSL in the executable spec.
- `pipeline_validator_spec.rb`: `invalid_path` against a service output schema.
- `steps_list_component_spec.rb`: records the service schema.
- `service_registry_spec.rb`: the six entries.
- `pipeline_runner_spec.rb`: `heartbeat_at` is set at start and before and after each step, and `Current` is reset afterwards.
- `heartbeat_spec.rb`: throttled to once a minute; a no-op without a current run.

Acceptance:
- `REGISTRY` lists the six executors, and `AgentClassKeyword.encode` gives `agent_emails_list` and so on.
- `steep check` is clean.

### 5. Pipeline JSON, seeds, end-to-end, removals (config + application)

Add or change:
- `config/pipelines/email_ingestion.json`: six steps; step 1 maps `_initial.providers`, plus `date_from`/`date_to` with `optional: true`; `cron_expression: null`; the issue's `initial_input_schema` with descriptions.
- `db/seeds.rb`: remove the legacy pipeline as in Decisions, import, enable, and drop the `*/30` cron block.
- `e2e/pipeline-export-import.spec.ts`: `STEP_COUNT = 6`.

Delete:
- `app/jobs/email/sync_inbox_job.rb` and the `sync_inbox_job/` directory.
- `app/jobs/email/process_job.rb`.
- `app/jobs/document/extract_email_attachments_job.rb`.
- `app/jobs/interview/extract_job.rb`.
- `lib/orchestration/executors/emails_sync.rb`.
- The sigs and specs of all of the above.
- The `EmailsSync` registry entry.
- The `.rigor-baseline.yml` entries for these files.
- The Prosopite allowlist entry for `ExtractEmailAttachmentsJob`.

Red specs:
- `spec/config/email_ingestion_pipeline_spec.rb`:
  - imports with no errors;
  - a separate `PipelineValidator` call returns no warnings;
  - round-trip: import, export, import again.
- `spec/db/seeds_email_ingestion_spec.rb`:
  - the legacy "Email Ingestion" and its runs are removed;
  - an unrelated pipeline with an `EmailsSync` step is kept, along with its action, and a warning is logged;
  - seeding twice leaves one pipeline;
  - the pipeline is enabled with no cron;
  - a pipeline the user disabled stays disabled when seeds run again.
- `spec/lib/orchestration/email_ingestion_pipeline_spec.rb`, end to end through `PipelineRunner`:
  - adapters `instance_double`d behind `Emails`, Mistral via WebMock, `RubyLLM::Judge` and `Embeddings::Client` stubbed;
  - covers every bullet in the issue's end-to-end list.

Acceptance:
- `rg "SyncInboxJob|ProcessJob|ExtractEmailAttachmentsJob|Interview::ExtractJob|EmailsSync" app lib sig spec config` has hits only in the seeds' legacy removal.
- `Interviews::EmailExtractor` and its spec remain.
- A second `bin/rails db:seed` on a fresh database is a no-op.

### 6. Run form, hints, stale runs, docs and ADR (interface + docs)

Files:
- Run form and hints:
  - `app/components/ui/json_fields_component.{rb,html.erb}` (`description`, `hints:`) and its preview.
  - `lib/orchestration/run_hints.rb` (+ sig).
  - `app/controllers/orchestration/pipelines_controller.rb`: `show` sets `@run_hints`.
  - `app/views/orchestration/pipelines/show.html.erb`.
- Stale runs:
  - `app/models/orchestration/pipeline_run.rb`: `STALE_AFTER`, `blocking`.
  - `pipeline.rb`.
  - `app/jobs/scheduler_job.rb`.
- Docs:
  - New `docs/adr/0018-ingestion-steps-in-pipeline.md`. It supersedes ADR 0013's "Where orchestration lives", "Errors and retries" and its "One pipeline step per stage" alternative, and records the embedding policy, the dropped interview extraction and the heartbeat.
  - ADR 0013's status becomes "Partially superseded by 0018".
  - ADR 0014's sync section.
  - `docs/orchestration.md` (heartbeat, `output_schema`, run hints), `docs/architecture.md`, `docs/schemas.md`.
  - `README.md:119`.
  - The header comments of `Email::EmbedJob`, `Document::EmbedJob` and `Document::TagJob`.
- `docs/research/email-sync-cursor-vs-date-range.md` is committed.

Red specs:
- `json_fields_component_spec.rb`: renders the description and the hint; makes no queries.
- `run_hints_spec.rb`: returns the hints when the first executor defines the hook, `{}` otherwise.
- `spec/requests/orchestration/pipelines_spec.rb`:
  - "Last synced" is shown per provider;
  - a run with blank dates is accepted;
  - a run with no providers shows the form error;
  - an invalid date gives a failed run.
- `pipeline_run_form_spec.rb` and `scheduler_job_spec.rb`:
  - a run with a recent heartbeat blocks a new one;
  - a stale heartbeat doesn't;
  - with no heartbeat, the check falls back to `started_at`/`created_at`.

Acceptance: only the "Email Ingestion" run dialog shows the hints; the other dialogs are unchanged.

## Checks

- `COVERAGE=true bundle exec rspec`
- `bundle exec rubocop` and `bundle exec archspec check --check-todo` (no `archspec_todo.yml` additions)
- `bundle exec archspec reflect` (models and schema change), then commit `archspec_facts/`
- `bundle exec rbs -r optparse validate`, `bundle exec steep check`, `bundle exec bin/rbs_audit coverage --threshold=90`
- `bundle exec rigor check`
- `bundle exec brakeman --no-pager`
- `pnpm lint` and `pnpm format:check` (the e2e `.ts` file changes)
- `bin/rails db:migrate && bin/rails db:rollback STEP=2 && bin/rails db:migrate`, then diff `db/structure.sql` to confirm the triggers are unchanged

## Risks

- **SQLite FTS triggers.** Any `remove_column` or `change_column_*` on `emails`/`documents` rebuilds the table and silently drops the `*_fts_*` triggers. Use only `add_column` and raw `DROP COLUMN`.
  - `DROP COLUMN` needs SQLite 3.35 or newer; check `SQLite3::SQLITE_VERSION`.
  - `DROP COLUMN` fails on an indexed column, so `down` drops the new indexes first.
- **Legacy pipeline removal.** `Pipeline has_many :steps` is declared before `:pipeline_runs`, so a plain destroy hits the `StepAction` `restrict_with_error`. Destroy the runs explicitly first.
- **Other pipelines with an `EmailsSync` step** stay after seeding, but they fail at run time and can't be exported once the class is gone; the warning names them.
- **Blank dates.** The form sends `""`; with `optional: true` a missing key resolves to `nil`. A run with no `_initial` at all still fails on `providers`, which is acceptable because there is no cron.
- **Backlog.** Any email still `pending` is classified by the next run in one synchronous step. The heartbeat keeps that run from being marked stale. The migration carries no data over (the app held none).
- **Heartbeat gaps.** A single item that takes longer than `STALE_AFTER` (a slow OCR call, say) could make a live run look stale. 10 minutes is well above the OCR and LLM timeouts.
- **Prosopite.** Allowlist the per-item loops per method, not globally.
