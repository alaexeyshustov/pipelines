# Application Pipeline

A Rails 8.1 multi-agent pipeline management system. Integration with Gmail and Yahoo Mail, classifies them with an LLM, labels them in the provider, and maintains a local SQLite database of job applications and interview progress.

## Stack

- **Ruby 4.0 / Rails 8.1**
- **SQLite** + **sqlite-vec** — persistence and vector embeddings
- **RubyLLM** — multi-provider LLM client (Mistral, OpenAI, Gemini, Anthropic)
- **Async** — concurrent email fetching
- **dry-cli** — CLI interface
- **Falcon** — web server (replaces Puma due to Ruby 4.0 compatibility)
- **AASM** — state management for interviews
- **Tailwind CSS** + **Turbo** + **Stimulus** — frontend stack

---

## Prerequisites

- Ruby 4.0 (`rbenv install 4.0.1`)
- SQLite 3 with dev headers (`brew install sqlite` / `apt-get install libsqlite3-dev`)
- At least one LLM API key (Mistral is the default)

---

## Setup

```bash
bundle install
bundle exec rails db:schema:load
cp .env.example .env   # then fill in your keys
```

### Environment variables

```dotenv
# LLM — at least one required
MISTRAL_API_KEY=
OPENAI_API_KEY=
GEMINI_API_KEY=
ANTHROPIC_API_KEY=

DEFAULT_MODEL=mistral-large-latest   # used by the pipeline when --model is not passed

# Email providers to activate (comma-separated)
MAIL_PROVIDERS=gmail,yahoo

# Yahoo IMAP — required if yahoo is in MAIL_PROVIDERS
YAHOO_USERNAME=you@yahoo.com
YAHOO_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx

# How far back to scan on first run (default: 3 months)
LOOKBACK_MONTHS=3

# Data export
GITHUB_TOKEN=
GIST_ID=              # existing Gist to update; omit to create a new one
```

---

## Gmail OAuth setup

The first time you run against Gmail you need to authorize the app:

1. Create a project in [Google Cloud Console](https://console.cloud.google.com).
2. Enable the **Gmail API**.
3. Create **OAuth 2.0** credentials → download the JSON file → save it as `credentials.json` in the project root.
4. Run the guided setup:

```bash
bin/pipeline setup --providers=gmail
```

A browser window opens for authorization. The token is saved to `token.yaml` (git-ignored).

---

## Yahoo setup

1. Go to your Yahoo Account Security settings.
2. Generate an **app password** for Mail + Other device.
3. Set `YAHOO_USERNAME` and `YAHOO_APP_PASSWORD` in `.env`.
4. Test with `bin/pipeline test --providers=yahoo`.

---

## CLI

The pipeline is driven from `bin/pipeline`.

```
bin/pipeline run     --pipeline=jobs      Run the full production workflow
bin/pipeline run     --pipeline=test      Run the lightweight test workflow
bin/pipeline test    [--providers=...]    Test connectivity to mail providers
bin/pipeline setup   [--providers=...]    Interactive provider setup
bin/pipeline upload_gist                  Export interviews table to a GitHub Gist as CSV
```

### Common options for `run`

| Option | Default | Description |
|---|---|---|
| `--pipeline` | `test` | `jobs` or `test` |
| `--model` | `$DEFAULT_MODEL` | LLM model identifier |
| `--watch` | `false` | Re-run every 6 hours |
| `--log_level` | `info` | `debug`, `info`, `warn`, `error` |
| `--log_file` | `log/pipeline.log` | Path to log file |

### Examples

```bash
# One-shot run with Mistral
bin/pipeline run --pipeline=jobs --model=mistral-large-latest

# Watch mode — re-runs every 6 hours
bin/pipeline run --pipeline=jobs --watch

# Export interview tracker to Gist
bin/pipeline upload_gist --filename=jobs.csv
```

---

## How the pipeline works

```
Step 1  Fetch emails              Fetch emails from Gmail + Yahoo concurrently (Async)
Step 2  Classify emails           Categorize emails as job-related or not
Step 3  Filter emails             Filter to relevant job applications
Step 4  Map emails                Extract structured data from filtered emails
Step 5  Store mapped emails       Save emails to application_mails table
Step 6  Normalize stored emails   Clean up company and job title fields
Step 7  Reconcile to interviews   Update or create entries in the interviews table
Step 8  Upload CSV to Gist        Export the interviews table to GitHub (if GIST_ID set)
```

Rate limiting is handled automatically within the workflow logic.

---

## Web UI

Start the server:

```bash
bin/rails server
# or: bundle exec falcon serve
```

| Route | Description |
|---|---|
| `GET /` | Chat history list |
| `GET /chats/:id` | Chat detail — messages, tool calls, thinking tokens |
| `GET /application_mails` | View all stored application emails |
| `GET /interviews` | Track company/role status and progress |
| `GET /orchestration/pipelines` | Configure and run automated pipelines |
| `GET /orchestration/actions` | Manage atomic pipeline actions |
| `GET /up` | Health check |

---

## Development

```bash
# Setup
bin/setup

# Lint
bundle exec rubocop --parallel

# Type checks
bundle exec steep check

# Tests
bundle exec rspec

# Security scan
bundle exec brakeman --no-pager

# Code quality
bundle exec rubycritic .
```

Tests use VCR cassettes for all external API calls — no live network traffic in CI.

---

## Project structure

```
app/
  models/
    application_mail.rb          Job email record
    interview.rb                 Company/role tracker
    email_vector.rb              Vector embedding wrapper (sqlite-vec)
    orchestration/               Pipeline, Step, Action, and run models
    chat.rb / message.rb         LLM conversation history (RubyLLM)
    tool_call.rb / model.rb
  agents/                        RubyLLM::Agent subclasses
    emails/                      Classify, Filter, Mapping
    records/                     Store, Normalize, Reconcile
  tools/                         RubyLLM::Tool implementations
  controllers/
    chats_controller.rb
    application_mails_controller.rb
    interviews_controller.rb
    orchestration/
      pipelines_controller.rb
      actions_controller.rb

lib/
  emails/                        Gmail + Yahoo adapters, OAuth flow
  pipeline/
    applications_workflow.rb     The main 8-step workflow
    logger.rb                    Stderr + file logger

bin/pipeline                     CLI entry point (dry-cli)
docs/
  schemas.md                     DB schema quick reference
  rbs.md                         RBS signature conventions
sig/                             .rbs type signatures
spec/                            RSpec test suite
```
