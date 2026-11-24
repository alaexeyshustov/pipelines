# Architecture — AI Agent Quick Reference

This project is a Rails 8.1 / Ruby 4.0 application designed as a **multi-agent job-application tracking pipeline**. It automates the process of monitoring job applications by fetching emails, classifying them, and updating a local tracker.

- This project uses Rails with SQLite — be aware of SQLite-specific extension issues when modifying schema or running `db:test:prepare`
- Prefer configurable singleton patterns with class methods for service objects
- Views: ViewComponent, Tailwind CSS, Turbo, Stimulus.
- Testing Framework: RSpec, FactoryBot, VCR.
- Uses Rubocop omakase style.
- Use .rbs type signatures [rbs.md](docs/rbs.md). **After every code change, always update or create the matching `.rbs` file under `sig/` mirroring the source path.**
- Uses rubycritic for refactoring.
- Mutation testing: `bundle exec rake mutant:baseline` for a full-codebase baseline run. CI reports score for changed files only (`--since origin/main`). Target: 50%. Subjects configured in `.mutant.yml`.

## System Overview

The system follows a pipeline-based architecture where data flows through several stages, each handled by specialized agents.

### Data Flow

1.  **Ingestion**: the on-demand "Email Ingestion" pipeline (ADR 0018) lists new Gmail and Yahoo INBOX mail into `Email` rows, classifies and embeds the emails, ingests the attachments of tagged Gmail emails into `Document`s, then classifies and embeds those.
2.  **Extraction**: `Interviews::EmailExtractor` reads `job_application`-tagged emails and upserts `Interview` rows directly, linking each email through `emails.interview_id`. Ingestion no longer runs it; a separate extraction pipeline is planned.
3.  **Export**: The tracker can be exported to GitHub Gists as CSV.

## Key Parts

### Core Technologies
- **Rails 8.1 / Ruby 4.0**: Modern Rails stack.
- **SQLite**: Local database (FTS5 for email and document search).
- **RubyLLM**: A unified client for multiple LLM providers.
- **ViewComponent + Tailwind + Turbo**: For the Web UI.
- **Content Security Policy**: enforced, script nonce only; see [ADR 0016](adr/0016-content-security-policy.md). No inline `<script>` or `on*=` handlers; use Stimulus.
- **State machines**: Rails `enum` for simple states; AASM for complex workflows (currently only `Evaluation::Experiment`).

### Directory Structure
- `lib/orchestration/agents/`: specialized AI agent implementations (`lib/orchestration/executors/` holds executable steps).
- `app/models/orchestration/`: models for managing the pipeline workflow.
- `app/models/evaluation/`, `app/services/evaluation/`, `lib/evaluation/`: evaluation logic to ensure agent quality. See [evals.md](evals.md).
- `app/services/tags/`, `app/forms/tags/`, `app/components/tags/`: tagging of emails and documents. `Tags::Classifier` classifies with `RubyLLM::Judge` (decisions API, one multi-label call plus one choice per kept tag; never creates tags; keeps manual taggings). `Tags::Classify` runs it for one email or document and records the outcome in `classification_status`. See the taggings table in [schemas.md](schemas.md).
- Drive ingestion: `Document::SyncDriveJob` (run by the `Orchestration::Executors::DriveDocumentsSync` pipeline step, seeded as "Drive Documents Sync", nightly) scans the folders in `Setting "drive_folder_ids"` (ids or URLs, comma/whitespace separated) via `Emails::Adapters::DriveFileFetcher` (drive.readonly token in `DRIVE_TOKEN_PATH`, default `drive_token.yaml`).
- Email ingestion (GH #248, ADR 0018): the "Email Ingestion" pipeline, on demand (no cron), loaded by the seeds from `config/pipelines/email_ingestion.json`. Six service steps, each passing record ids to the next: `EmailsList` (`Email::InboxSync`: incremental from the per-account `Email::SyncCursor`, or a date window; providers run one after another, one without credentials is skipped, one failing does not stop the other), `EmailsClassify` (`Tags::Classify`), `EmailsEmbed`, `AttachmentsIngest` (`Document::IngestEmailAttachments`: tagged Gmail emails only), `DocumentsClassify`, `DocumentsEmbed` (then duplicate detection). Per-item failures are reported in the step output and do not fail the step. Only `tagged` emails and attachments are embedded. See [adr/0018-ingestion-steps-in-pipeline.md](adr/0018-ingestion-steps-in-pipeline.md) and [adr/0013-email-ingestion-pipeline.md](adr/0013-email-ingestion-pipeline.md).
- Embeddings (GH #226, ADR 0014): `Embeddings::Embed` is called per record by the Email Ingestion steps and, for Drive documents, by `Document::EmbedJob` (enqueued by `Document::SyncDriveJob`; `Email::EmbedJob` is kept for re-embedding, #335); `Email::SearchQuery` / `Document::SearchQuery` take `mode: :text | :semantic | :hybrid`. See the embeddings table in [schemas.md](schemas.md).
- Document deduplication (GH #227): `Document::EmbedJob` enqueues `Document::DetectDuplicatesJob` (`Document::DetectDuplicates`: KNN over Document vectors of the current model) which records `DocumentDuplicate` candidates. **Decision:** link and flag for review, never merge, hide or delete; the document page lists candidates with Confirm / Dismiss, and a dismissed pair is not flagged again. Threshold: cosine similarity 0.95, Setting `document_dedup_threshold` then ENV `DOCUMENT_DEDUP_THRESHOLD`. See the document_duplicates table in [schemas.md](schemas.md).
- `app/tools/`: LLM tools exposed to agents.
- `lib/emails/`: provider-specific email fetching logic. See [connectors.md](docs/connectors.md) for details.

## Dependency rules
Layer order and subsystem boundaries are declared in [Archspec.rb](../Archspec.rb) and enforced by `bundle exec archspec check` (CI and pre-commit). Layers, top to bottom: interface, application, tools, domain, infra; orchestration must not use evaluation. Known violations are baselined in `archspec_todo.yml` (shrink it, never grow it). See [ADR 0011](adr/0011-archspec-layers.md).

## Authentication
The whole app, including the `/jobs` and `/monitoring` engines, is behind a login (default deny). `ApplicationController` includes the `Authentication` concern; only `sessions#new` and `sessions#create` (and `/up`) are open. One user, created by `bin/rails users:upsert` from `ADMIN_EMAIL` and `ADMIN_PASSWORD`; no sign-up, no password reset. `spec/requests/route_authentication_spec.rb` walks every route to prove it. See [ADR 0017](adr/0017-authentication-default-deny.md).

## AI Agents
Agents are first-class citizens, defined in `lib/orchestration/agents/`. They utilize `orchestration_prompts` for versioned system instructions and `orchestration_agents` for tool access configuration.
