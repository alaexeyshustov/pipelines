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

1.  **Ingestion**: `Email::SyncInboxJob` pulls new Gmail and Yahoo INBOX mail into `Email` rows (ADR 0013).
2.  **Tagging**: `Tags::Classifier` tags each email; tagged attachments are extracted into `Document`s.
3.  **Extraction**: `Interview::ExtractJob` (`Interviews::EmailExtractor`) reads `job_application`-tagged emails and upserts `Interview` rows directly, linking each email through `emails.interview_id`.
4.  **Export**: The tracker can be exported to GitHub Gists as CSV.

## Key Parts

### Core Technologies
- **Rails 8.1 / Ruby 4.0**: Modern Rails stack.
- **SQLite**: Local database (FTS5 for email and document search).
- **RubyLLM**: A unified client for multiple LLM providers.
- **ViewComponent + Tailwind + Turbo**: For the Web UI.

### Directory Structure
- `lib/orchestration/agents/`: specialized AI agent implementations (`lib/orchestration/executors/` holds executable steps).
- `app/models/orchestration/`: models for managing the pipeline workflow.
- `app/models/evaluation/`, `app/services/evaluation/`, `lib/evaluation/`: evaluation logic to ensure agent quality. See [evals.md](evals.md).
- `app/services/tags/`, `app/forms/tags/`, `app/components/tags/`: tagging of emails and documents. `Tags::Classifier` classifies with `RubyLLM::Judge` (decisions API, one multi-label call plus one choice per kept tag; never creates tags; keeps manual taggings). Not yet wired into pipelines (ingestion is GH #222). See the taggings table in [schemas.md](schemas.md).
- Drive ingestion: `Document::SyncDriveJob` (run by the `Orchestration::Executors::DriveDocumentsSync` pipeline step, seeded as "Drive Documents Sync", nightly) scans the folders in `Setting "drive_folder_ids"` (ids or URLs, comma/whitespace separated) via `Emails::Adapters::DriveFileFetcher` (drive.readonly token in `DRIVE_TOKEN_PATH`, default `drive_token.yaml`).
- Email ingestion: `Email::SyncInboxJob` (run for `gmail` and `yahoo` by the `Orchestration::Executors::EmailsSync` pipeline step, seeded as "Email Ingestion", every 30 minutes) stores new INBOX mail as `Email` rows from a per-account `Email::SyncCursor`. Providers run independently; one without credentials is reported as skipped, a failing one fails the step after the other ran. See [adr/0013-email-ingestion-pipeline.md](adr/0013-email-ingestion-pipeline.md).
- `app/tools/`: LLM tools exposed to agents.
- `lib/emails/`: provider-specific email fetching logic. See [connectors.md](docs/connectors.md) for details.

## Dependency rules
Layer order and subsystem boundaries are declared in [Archspec.rb](../Archspec.rb) and enforced by `bundle exec archspec check` (CI and pre-commit). Layers, top to bottom: interface, application, tools, domain, infra; orchestration must not use evaluation. Known violations are baselined in `archspec_todo.yml` (shrink it, never grow it). See [ADR 0011](adr/0011-archspec-layers.md).

## AI Agents
Agents are first-class citizens, defined in `lib/orchestration/agents/`. They utilize `orchestration_prompts` for versioned system instructions and `orchestration_agents` for tool access configuration.
