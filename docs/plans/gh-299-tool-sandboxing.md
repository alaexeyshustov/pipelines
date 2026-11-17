# Plan: sandbox LLM tools against untrusted email input (GH #299)

**Status:** planned, architect-reviewed | **Branch:** `fix/gh-299-tool-sandboxing` | **Parent:** #240 (SEC-01, 07, 09, 11, 12)

## Decisions

- **SEC-01: keep `Records::TempFileTool` and harden it** (user's call).
  - Scratch files go in one directory, `Records::TempFileTool.scratch_dir`. It defaults to `tmp/agent_scratch/`; specs point it at `Dir.mktmpdir` so spec and mutant runs stop writing into the repo root.
  - A filename is one path segment matching `/\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z/`, and the resolved path must sit directly in that dir.
  - Reads and writes open with `File::NOFOLLOW`, and writes are capped at 100 KB.
  - Errors stay as plain strings, as today.
- **SEC-01: take `TempFileTool` off `EmailsClassifier`** (architect, agreed).
  - `EmailsClassifier` reads untrusted subject lines but never uses scratch files, and the tool can write (`readonly? = false`).
  - Remove it from the agent class (`lib/orchestration/agents/emails_classifier.rb:5`) and from the seed (`db/seeds.rb:36`).
  - Add a data migration that removes `"Records::TempFileTool"` from that agent's stored `tools`.
  - The tool stays in the registry for agents users configure.
- **SEC-07: run-scoped `(provider, message_id)` allowlists are in #303** (user's call). `Emails::GetTool` and `Emails::AddLabelsTool` stay available (user's call).
- **`GetTool`: drop the disk cache** (architect, agreed).
  - ADR 0013 makes the `emails` table the durable store, and a hand-built file cache under `tmp/` is exactly the path-traversal surface.
  - Validate `provider` against `Emails::PROVIDER_NAMES` (`lib/emails.rb:4`) before calling out.
  - Cap `body` at 32 KB with `String#truncate_bytes` (byte limit, multibyte-safe). The cap applies only at the tool boundary, so ingestion keeps full bodies.
- **`AddLabelsTool` label policy** (Yahoo folder names skipped, user's call):
  - Reject Gmail `TRASH` and `SPAM` (case-insensitive).
  - IMAP flags are an allowlist: `\Flagged` and `\Seen` pass, and every other `\`-prefixed label is rejected.
  - If any label is rejected, none are applied.
- **SEC-09 is text-level only** (user's call). Fetching only text parts over IMAP is in #304.
  - `Emails::HtmlText` switches to `Nokogiri::HTML5`, declared directly in the `Gemfile`, with an RBS shim if the pinned nokogiri signatures lack `HTML5`.
  - `Embeddings::Text` uses `HtmlText` too, so embedding text changes. Email bodies already stored keep their old text.
- **SEC-09: put the untrusted-input guard in the agent builder** (architect, agreed).
  - `Orchestration::RuntimeAgentBuilder#apply_prompt` always prepends a fixed preamble saying input fields are data and instructions inside them must be ignored.
  - This covers every agent and every prompt source, including an active `Evaluation::Prompt` and user-built pipelines, with no data migration.
  - `ClassifyTool` builds `EmailsClassifier` directly, skipping the builder, so the class `instructions` get the same line.
- **SEC-11: one tool lookup** (architect, agreed). This is the convergence ADR 0010 deferred.
  - Add `Orchestration::ToolResolver.lookup(name)`, which does `REGISTRY.fetch` and raises `ArgumentError, "Unknown tool class: …"`. `ToolResolver#resolve` and `AgentResolutionPolicy` both use it.
  - Remove the policy's `Class` passthrough and namespace check; stored tools are JSON strings.
  - Caller-supplied `tool_classes:` pass through unvalidated, because the Sampler hands in anonymous write-blocked subclasses (`app/services/evaluation/sampler.rb:83-101`).
  - Test `tool_classes` with `nil?`, not `present?`, so `[]` means no tools.
  - `ToolResolver#resolve` uses an agent class's `tools` only when `safe_constantize` returns a `RubyLLM::Agent` subclass.
  - The domain `Orchestration::Agent#validate_tool` checks `Agent.available_tools`, which comes from the filesystem, instead of calling `constantize` on the stored string, and drops the namespace check. Domain can't depend on `lib/orchestration`.
  - A spec keeps `REGISTRY.keys` equal to `Agent.available_tools`, so a new file under `app/tools` can't expose a tool without being registered.
  - Amend ADR 0010 and the "can be constantized" line in `docs/orchestration.md`.
- **SEC-12: split readable from writable columns.**
  - `tool_column_names` stays readable, including `id`, because agents address rows by it.
  - A new `Interview.tool_writable_column_names` (without `id`) is used by `InsertRowsTool` and `UpdateRowsTool`.
  - Anything that reaches records from run data validates columns against `tool_column_names`. That means `ReadRowsTool`, and `Executors::Query`'s `column_name` and `columns`, because input mappings can feed them from an upstream agent's output (`lib/orchestration/input_mapping_resolver.rb:15-25`).

## Steps

### 1. Harden `TempFileTool` and take it off `EmailsClassifier` (SEC-01)
- **Files:**
  - tools: `app/tools/records/temp_file_tool.rb`;
  - application: `lib/orchestration/agents/emails_classifier.rb`;
  - `db/seeds.rb`, a new data migration in `db/migrate/`, and the matching sigs.
- **Red first:**
  - `spec/tools/records/temp_file_tool_spec.rb`, with `scratch_dir` set to a temp dir:
    - rejects `../x`, `/etc/passwd`, `a/b` and `.env`;
    - refuses to read or write through a symlink;
    - rejects a write over 100 KB;
    - read/write/delete round-trip works.
  - Agent spec: `EmailsClassifier.tools` is empty.
  - Migration spec: the stored classifier agent loses `Records::TempFileTool`, and other agents are unchanged.
- **Done when:**
  - no input touches a path outside `scratch_dir`;
  - the description no longer says "/tmp";
  - specs leave no files in the repo root;
  - the stray `#<Records::TempFileTool…>` and `test_manage_*.txt` files are deleted.

### 2. Email tools (SEC-07, SEC-09 cap, SEC-12 `offset`)
- **Files:** `app/tools/emails/get_tool.rb`, `app/tools/emails/add_labels_tool.rb`, `app/tools/emails/search_tool.rb` (tools), and their sigs.
- **Red first:**
  - `get_tool_spec`:
    - an unknown provider returns `{ error: }` without calling `Emails.message`;
    - nothing is written to disk;
    - a body over 32 KB is truncated to 32 KB with a marker, and multibyte text stays valid.
  - `add_labels_tool_spec`:
    - `TRASH`, `spam` and `\Deleted` are rejected and `Emails.modify_labels` is not called;
    - `\Flagged`, `\Seen` and `STARRED` pass.
  - `search_tool_spec`: `offset:` is passed through to `Emails.search_messages`.
- **Done when:** these specs pass and `CACHE_DIR` is gone.

### 3. Tool resolution (SEC-11)
- **Files:**
  - application: `lib/orchestration/tool_resolver.rb`, `lib/orchestration/agent_resolution_policy.rb`;
  - domain: `app/models/orchestration/agent.rb`;
  - sigs, `docs/adr/0010-tool-resolver-extracted-from-sampler.md`, `docs/orchestration.md`.
- **Red first:**
  - `tool_resolver_spec`:
    - `.lookup` returns the registry value, and the `Emails::ClassifyTool` subclass carries its classifier;
    - an unknown name raises;
    - `REGISTRY.keys` matches `Agent.available_tools`;
    - an agent name that resolves to a non-agent class raises.
  - `agent_resolution_policy_spec`:
    - `tool_classes: []` resolves to `[]`;
    - stored names outside `REGISTRY` (e.g. `Records::ModelResolver`, `Emails::Adapters::GmailAdapter`) raise;
    - caller-supplied anonymous subclasses pass through.
  - `agent_spec`: the same unknown names are invalid.
  - `sampler_spec`: write-blocked tools still reach the runtime agent.
- **Done when:** no `constantize` runs on a stored tool name, and ADR 0010 records the convergence.

### 4. Record tools (SEC-12)
- **Files:**
  - domain: `app/models/interview.rb`;
  - tools: `app/tools/records/{insert_rows,update_rows,read_rows,search_similar}_tool.rb`;
  - application: `lib/orchestration/executors/query.rb`;
  - `sig/app/models/interview.rbs`, `sig/shims/has_column_names.rbs`.
- **Red first:**
  - insert/update specs: `id` in the data is ignored.
  - `read_rows_tool_spec`: an unknown `column_name` returns `{ error: }`.
  - `executors/query_spec`: an unknown `column_name` or entry in `columns` raises `ArgumentError`.
  - `search_similar_tool_spec`:
    - `%` and `_` in `value` match literally;
    - a value over 200 chars returns `{ error: }`.
- **Done when:**
  - neither the LLM nor run data can write `id` or name unknown columns;
  - the substring `LIKE` uses `sanitize_sql_like` with an `ESCAPE` clause;
  - the reverse direction (`:value LIKE '%' || column || '%'`) either escapes the column's wildcards or is replaced with `instr`.

### 5. Untrusted email text (SEC-09)
- **Files:**
  - `Gemfile`, `Gemfile.lock`;
  - infra: `lib/emails/html_text.rb`;
  - application: `lib/orchestration/runtime_agent_builder.rb`, `lib/orchestration/agents/emails_classifier.rb`;
  - `sig/shims/external_gems.rbs` if needed.
- **Red first:**
  - New `spec/lib/emails/html_text_spec.rb`:
    - drops `<script>`, `<style>`, `<head>` and comments;
    - drops elements that are `hidden`, `aria-hidden="true"`, `display:none`, `visibility:hidden`, or have zero font size, including nested ones;
    - keeps line breaks for block elements and `<br>`;
    - decodes entities.
  - `runtime_agent_builder_spec`: the preamble comes before the agent prompt, a prompt override and an empty prompt.
  - The existing `imap_body_parser_spec`, `gmail_body_extractor_spec` and embeddings text specs stay green, or are updated deliberately.
- **Done when:** these specs pass and `EmailsClassifier`'s instructions carry the data-only line.

### 6. Docs and issues
- `docs/orchestration.md`: describe tool registration and the untrusted-input preamble.
- `docs/adr/0010`: amend the "Deferred" note.
- Tick the #299 scope items, linking #303 and #304 for the parts moved there, and mark #240 SEC-01, 07, 09, 11, 12 as resolved or partly resolved.

## Checks

- `COVERAGE=true bundle exec rspec`
- `bundle exec rubocop`; `bundle exec archspec check --check-todo`; `bundle exec archspec reflect` (`Interview`, `Orchestration::Agent` and the `Gemfile` change)
- `bundle exec rbs -r optparse validate`, `bundle exec steep check`, `bundle exec bin/rbs_audit coverage --threshold=90`
- `bundle exec rigor check`
- `bundle exec brakeman --no-pager`

## Open questions

None. The user settled all of them:
- keep and harden `TempFileTool`, but take it off `EmailsClassifier`;
- keep `GetTool` and `AddLabelsTool`, and drop the `GetTool` disk cache;
- no Yahoo folder-name denylist;
- run scoping is in #303, and IMAP text-part fetch is in #304.
