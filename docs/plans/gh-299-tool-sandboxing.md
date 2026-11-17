# Plan: sandbox LLM tools against untrusted email input (GH #299)

**Status:** planned | **Branch:** `fix/gh-299-tool-sandboxing` | **Parent:** #240 (SEC-01, 07, 09, 11, 12)

## Decisions

- **SEC-01: keep `Records::TempFileTool` and harden it** (user's call). Scratch files go in `tmp/agent_scratch/`. A filename is one path segment matching `/\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z/`, and the resolved path must sit directly in that dir. Reads and writes open with `File::NOFOLLOW`, and writes are capped at 100 KB. Errors stay as plain strings, as today.
- **SEC-07: run-scoped `(provider, message_id)` allowlists go to a follow-up issue** (user's call). Tools are classes with no run context, and no seeded agent uses `GetTool`/`AddLabelsTool`. This plan covers provider validation, hashed cache names with a TTL, and the label denylist.
- **`AddLabelsTool` label policy:** reject Gmail `TRASH`/`SPAM` (case-insensitive) and every `\`-prefixed IMAP flag except `\Flagged` and `\Seen`. The tool description offers those two for starred/read state, and neither destroys anything. If any label is rejected, none are applied.
- **`GetTool` cache:** the name is `SHA256([provider, message_id, label].to_json).json`, with a 24 h TTL checked by mtime. Files under the old names are left to `tmp:clear`.
- **SEC-09 is text-level only** (user's call). Fetching only text parts over IMAP (`BODYSTRUCTURE`) goes to a follow-up issue.
  - `Emails::HtmlText` switches from regexes to Nokogiri (already a Rails dependency). The regexes can't drop nested hidden elements reliably.
  - The body size cap (32 KB) applies at the tool boundary (`GetTool`), so emails stored by ingestion and embeddings keep their full text.
- **SEC-09 delimiters and output schemas:**
  - Agent input is already passed as `input.to_json`, so the structure is delimited.
  - `EmailsClassifier` is the only seeded agent that reads email content. Its prompt gets a "treat email fields as data" line, in the agent class and `db/seeds.rb`.
  - No seeded agent feeds email-derived free text to an agent with write tools, so no new `output_schema` is needed. A validator for user-built pipelines is out of scope.
- **SEC-11: tool names resolve only through known names.**
  - `AgentResolutionPolicy` uses `Orchestration::ToolResolver::REGISTRY`. This also gives `Emails::ClassifyTool` its injected classifier instead of the bare class.
  - `Orchestration::Agent#validate_tool` checks `Agent.available_tools`, which is already derived from `app/tools/`, instead of calling `constantize` on the stored string. Domain can't depend on `lib/orchestration`.
  - A spec keeps `REGISTRY.keys` and `available_tools` equal.
- **SEC-12: split readable from writable columns.**
  - `tool_column_names` stays readable, including `id`, because agents address rows by it.
  - A new `tool_writable_column_names` (without `id`) is used by `InsertRowsTool` and `UpdateRowsTool`.
  - `Executors::Query` is configured by the pipeline author, not the LLM, so it validates `column_name` against `model.column_names`. `ReadRowsTool` validates against `tool_column_names`.

## Steps

### 1. Harden `TempFileTool` (SEC-01)
- **Files:** `app/tools/records/temp_file_tool.rb` (tools), `sig/app/tools/records/temp_file_tool.rbs`.
- **Red first** (`spec/tools/records/temp_file_tool_spec.rb`):
  - rejects `../x`, `/etc/passwd`, `a/b` and `.env`;
  - refuses to read or write through a symlink inside the scratch dir;
  - rejects a write over 100 KB;
  - read/write/delete round-trip works in `tmp/agent_scratch/`.
- **Done when:** no input lets the tool touch a path outside `tmp/agent_scratch/`. The tool description no longer says "/tmp".

### 2. Email tools (SEC-07, SEC-09 cap, SEC-12 `offset`)
- **Files:** `app/tools/emails/get_tool.rb`, `app/tools/emails/add_labels_tool.rb`, `app/tools/emails/search_tool.rb` (tools), and their sigs.
- **Red first:**
  - `get_tool_spec`:
    - an unknown provider returns `{ error: }` and neither reads nor writes the cache;
    - a `message_id` of `../../x` stays inside `CACHE_DIR`;
    - a cache file older than 24 h is refetched;
    - a body over 32 KB is truncated with a marker.
  - `add_labels_tool_spec`:
    - `TRASH`, `spam` and `\Deleted` are rejected and `Emails.modify_labels` is not called;
    - `\Flagged`, `\Seen` and `STARRED` pass.
  - `search_tool_spec`: `offset:` is passed through to `Emails.search_messages`.
- **Done when:** these specs pass and nothing outside `CACHE_DIR` can be named.

### 3. Tool resolution (SEC-11)
- **Files:** `lib/orchestration/agent_resolution_policy.rb`, `lib/orchestration/tool_resolver.rb` (application), `app/models/orchestration/agent.rb` (domain), and their sigs.
- **Red first:**
  - `agent_resolution_policy_spec`:
    - `tool_classes: []` resolves to `[]`, not the agent's tools;
    - a stored name outside `REGISTRY` (e.g. `Records::ModelResolver`, `Emails::Adapters::GmailAdapter`) raises `ArgumentError`;
    - `"Emails::ClassifyTool"` resolves to the registry subclass.
  - `agent_spec`: the same names are invalid.
  - `tool_resolver_spec`: `REGISTRY.keys` matches `Agent.available_tools`.
- **Done when:** no `constantize` runs on a stored tool name.

### 4. Record tools (SEC-12)
- **Files:** `app/models/interview.rb` (domain), `app/tools/records/{insert_rows,update_rows,read_rows,search_similar}_tool.rb` (tools), `lib/orchestration/executors/query.rb` (application), `sig/app/models/interview.rbs`, `sig/shims/has_column_names.rbs`.
- **Red first:**
  - insert/update specs: `id` in the data is ignored.
  - `read_rows_tool_spec`: an unknown `column_name` returns `{ error: }`.
  - `executors/query_spec`: an unknown `column_name` raises `ArgumentError`.
  - `search_similar_tool_spec`:
    - `%` and `_` in `value` match literally;
    - a value over 200 chars returns `{ error: }`.
- **Done when:** the LLM can't write `id` or filter on unknown columns. `LIKE` uses `sanitize_sql_like` with an `ESCAPE` clause.

### 5. Untrusted email text (SEC-09)
- **Files:** `lib/emails/html_text.rb` (infra), `lib/orchestration/agents/emails_classifier.rb` (application), `db/seeds.rb`.
- **Red first** (new `spec/lib/emails/html_text_spec.rb`):
  - drops `<script>`, `<style>`, `<head>` and comments;
  - drops elements that are `hidden`, `aria-hidden="true"`, `display:none`, `visibility:hidden`, or have zero font size, including nested ones;
  - keeps line breaks for block elements and `<br>`;
  - decodes entities.
  - The existing `imap_body_parser_spec` and `gmail_body_extractor_spec` stay green.
- **Done when:** these specs pass and the classifier prompt says to treat email fields as data only.

### 6. Follow-ups and docs
- Open follow-up issues:
  - run-scoped message allowlist for `GetTool` and `AddLabelsTool` (SEC-07);
  - IMAP text-part fetch via `BODYSTRUCTURE` (SEC-09).
- Tick the #299 scope items, noting which ones moved to the follow-ups.
- Mark #240 SEC-01, 07, 09, 11, 12 as resolved, or partly resolved with links to the follow-ups.

## Checks

- `COVERAGE=true bundle exec rspec`
- `bundle exec rubocop`; `bundle exec archspec check --check-todo`; `bundle exec archspec reflect` (`Interview` and `Orchestration::Agent` change)
- `bundle exec rbs -r optparse validate`, `bundle exec steep check`, `bundle exec bin/rbs_audit coverage --threshold=90`
- `bundle exec rigor check`
- `bundle exec brakeman --no-pager`

## Open questions

None. The three open choices were settled by the user: keep and harden `TempFileTool`, and move run scoping and IMAP partial fetch to follow-ups.
