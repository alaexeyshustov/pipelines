# Architecture — AI Agent Quick Reference

This project is a Rails 8.1 / Ruby 4.0 application designed as a **multi-agent job-application tracking pipeline**. It automates the process of monitoring job applications by fetching emails, classifying them, and updating a local tracker.

- This project uses Rails with SQLite — be aware of SQLite-specific extension issues (e.g., vec0, sqlite_vec) when modifying schema or running `db:test:prepare`
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

1.  **Ingestion**: Emails are fetched from Gmail and Yahoo Mail concurrently using `Async`.
2.  **Processing**: A series of AI Agents (Mistral, Anthropic, etc.) process the emails:
    -   **Classify**: Identify if an email is job-related.
    -   **Filter**: Select relevant application-related emails.
    -   **Map**: Extract structured data (Company, Job Title, Action).
3.  **Persistence**: Extracted data is stored in the `application_mails` table.
4.  **Reconciliation**: Data is normalized and matched to the `interviews` table to track the application lifecycle.
5.  **Export**: The tracker can be exported to GitHub Gists as CSV.

## Key Parts

### Core Technologies
- **Rails 8.1 / Ruby 4.0**: Modern Rails stack.
- **SQLite + sqlite-vec**: Local database with vector embedding support for semantic search and retrieval.
- **RubyLLM**: A unified client for multiple LLM providers.
- **ViewComponent + Tailwind + Turbo**: For the Web UI.

### Directory Structure
- `app/agents/`: specialized AI agent implementations.
- `app/models/orchestration/`: models for managing the pipeline workflow.
- `app/evals/`: evaluation logic to ensure agent quality.
- `lib/emails/`: provider-specific email fetching logic. See [connectors.md](docs/connectors.md) for details.

## AI Agents
Agents are first-class citizens, defined in `app/agents/`. They utilize `orchestration_prompts` for versioned system instructions and `orchestration_agents` for tool access configuration.

## Persistence & Vectors
The project uses `sqlite-vec` for vector operations. `EmailVector` provides a wrapper for storing and querying embeddings of email content.
