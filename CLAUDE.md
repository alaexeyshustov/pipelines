# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Rails 8.1 / Ruby 4.0 application that runs a **multi-agent job-application tracking pipeline**. It pulls emails from Gmail and Yahoo Mail, classifies them with Mistral AI, labels them in the provider, and maintains an SQLite database of job applications and interview progress.

This is a **backend-only pipeline** with no web interface. Entry point is `bin/pipeline`.

**Language: Ruby 4.0. Do NOT use Python anywhere.**

---

## Commands

| Task                   | Command                                                          |
| ---------------------- | ---------------------------------------------------------------- |
| Install dependencies   | `bundle install`                                                 |
| Run migrations         | `bundle exec rails db:migrate`                                   |
| Run all tests          | `bundle exec rspec`                                              |
| Run a single spec      | `bundle exec rspec spec/tools/list_emails_tool_spec.rb`          |
| Run pipeline once      | `bin/pipeline run`                                               |
| Run pipeline (model)   | `bin/pipeline run --model mistral-large-latest`                  |
| Run pipeline (watch)   | `bin/pipeline run --watch`                                       |
| Run pipeline (debug)   | `bin/pipeline run --log-level debug`                             |
| Upload interviews gist | `bin/pipeline upload_gist`                                       |
| Rails console          | `bundle exec rails console`                                      |
| Format code            | `rubyfmt`                                                        |

---

## Architecture

### Key Difference from `gmail_mcp`

This app has **no MCP**. Tools are plain `RubyLLM::Tool` subclasses instantiated directly in `JobsWorkflow#build_tools` and passed to agents. There is no subprocess or stdio transport.

### Request Flow

```
bin/pipeline run
  → Pipeline::JobsWorkflow
      → ProviderRegistry (GmailAdapter | YahooAdapter)
      → RubyLLM::Agent subclasses
          → Tools::* (RubyLLM::Tool subclasses, direct Ruby calls)
              → GmailService / YahooMailService / EmailClassifier / ApplicationMail / Interview
```

### Tool Name Resolution

`RubyLLM::Tool` derives the tool name from the class name by snake_casing and stripping the `_tool` suffix:
- `ListEmailsTool` → `"list_emails"`
- `ManageDatabaseTool` → `"manage_database"`

Agent `TOOLS` constants list these derived names. `JobsWorkflow#tools_for` filters `@tools` by `t.name`.

### Database (SQLite + sqlite-vec)

- `application_mails` — one row per job email (date, provider, email_id, company, job_title, action)
- `interviews` — one row per company/job_title pair, tracking lifecycle status and interview dates
- `email_vectors` — sqlite-vec virtual table (vec0) storing 1536-dim float embeddings for RAG

`EmailVector.search(embedding)` wraps the `vec0` KNN query. `SqliteVecExtension` in `config/initializers/sqlite_vec.rb` loads the extension on every connection.

Schema format is `:sql` (not `:ruby`) because `vec0` virtual tables cannot be expressed in Ruby schema DSL.

### Provider Adapters

Same pattern as `gmail_mcp`: `ProviderRegistry` → `Adapters::GmailAdapter` / `Adapters::YahooAdapter` → `GmailService` / `YahooMailService`. Adapters live in `app/services/adapters/`.

### ManageDatabaseTool vs manage_csv

`ManageDatabaseTool` replaces the CSV-based `manage_csv` from `gmail_mcp`. It writes to `ApplicationMail` and `Interview` ActiveRecord models. Column names changed to snake_case to match the schema (e.g. `applied_at` instead of "applied at").

---

## Adding a New Tool

1. Create `app/tools/<name>_tool.rb` subclassing `RubyLLM::Tool`.
2. Add it to the array in `JobsWorkflow#build_tools`.
3. Add to the relevant agent's `TOOLS` constant.
4. Write a spec in `spec/tools/`.

## Testing Conventions

- Framework: RSpec
- No real HTTP or IMAP calls — mock at the service/adapter layer
- `ManageDatabaseTool` specs use `Rails.application.config.database_configuration` to hit the test DB in-memory

## Environment Variables

| Variable               | Purpose                                      |
| ---------------------- | -------------------------------------------- |
| `CREDENTIALS_PATH`     | Path to Google OAuth credentials JSON        |
| `TOKEN_PATH`           | Path to persisted OAuth token YAML           |
| `YAHOO_USERNAME`       | Yahoo Mail address                           |
| `YAHOO_APP_PASSWORD`   | Yahoo IMAP app password                      |
| `YAHOO_IMAP_HOST/PORT` | IMAP server (default: imap.mail.yahoo.com/993) |
| `MISTRAL_API_KEY`      | Mistral AI key (primary LLM)                 |
| `OPENAI_API_KEY`       | Optional fallback model                      |
| `LOOKBACK_MONTHS`      | How far back to search on first run (default 3) |
| `DEFAULT_MODEL`        | Override default agent model                 |
| `GITHUB_TOKEN`         | For `upload_gist` command                    |
| `GIST_ID`              | Existing Gist ID to update                   |
