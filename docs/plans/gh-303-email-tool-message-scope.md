# Plan: scope email tools to messages of the current chat (GH #303)

**Status:** implemented | Follow-up to #299 (#240 SEC-07)

The design is the issue's "Decision (2026-11-24, revised after architect review)". This plan does not reopen it.

## Decisions

- **How a tool says it is scoped.** `Emails::ListTool`, `SearchTool`, `GetTool` and `AddLabelsTool` each define `def self.message_scoped? = true`, next to `self.readonly?`. Each also gets its own `initialize(message_scope: MessageScope.new)` that calls `super()` and sets `@message_scope`.
  - There's no mixin: it is three lines per class and keeps the signatures simple.
  - `RubyLLM::Tool` 2.2.2 has no `initialize` of its own, and `Chat#with_tools` calls `tool.new` on a class with no arguments, so the default must exist.
- **Subclasses keep working.** The Sampler's `Class.new(AddLabelsTool)` inherits both `message_scoped?` and the constructor. So `bind` instantiates it, and its overridden `execute` still returns the sentinel before any scope check. `Evaluation::Sampler` needs no code change.
- **`MessageScope` API** (`app/tools/emails/message_scope.rb`, plain Ruby):
  - `record(messages)` returns `messages` unchanged, so the List and Search tools can end with `@message_scope.record(...)`.
    - Anything that is not an Array is ignored.
    - Items that are not hashes are skipped, and so are items with a nil `:id`.
    - The provider comes from each item's `:provider` (symbol keys, as `Emails::message` has).
  - `allow?(provider:, message_id:, mailbox: nil)` returns a bool.
  - `bind(tool_classes)` returns `Array[singleton(RubyLLM::Tool) | RubyLLM::Tool]` in the same order. Classes that answer `message_scoped?` are instantiated with `new(message_scope: self)`; the rest pass through as classes.
  - `self.refusal(message_id)` returns `{ error: "Message <id> was not returned by list_emails or search_emails in this chat. List or search for it first." }`. Both tools return it, and it tells the model how to recover.
- **Key.**
  - Yahoo: `["yahoo", mailbox.downcase, id]`. The mailbox is `labels.first` when recording and the `mailbox:` argument when checking.
  - Blank or nil mailbox means `INBOX`. This matches `YahooAdapter#build_mailbox`, which uses `label.blank?` and resolves names case-insensitively.
  - Any other provider: `[provider, id]`, ignoring the mailbox.
  - Ids are compared as exact strings, so `"123:42"` (which `ImapInboxReader.split_message_id` would accept) and `"42abc"` are refused when only `"42"` was recorded.
- **Order of checks.** Existing validation runs first and keeps its messages: the provider check in `GetTool`, the label policy in `AddLabelsTool`. The scope check comes next, before any `Emails.*` call. `AddLabelsTool` has no provider check, but an unknown provider is never recorded, so it is refused.
- **Concurrency.** `MessageScope` guards its key `Set` with a `Mutex`.
  - RubyLLM runs tools one after another by default, but `with_tool_options(concurrency:)` exists.
  - If `list_emails` and `get_email` run in the same concurrent round, `get_email` may be refused. That is acceptable because it fails closed.
- **Typing `bind`.** Prefer an RBS interface `Emails::MessageScope::_ScopedToolClass` (`message_scoped?: () -> bool`, `new: (message_scope: MessageScope) -> RubyLLM::Tool`) with a `respond_to?(:message_scoped?)` guard and an inline `#:` assertion. If steep rejects the assertion, use a single-line `# steep:ignore` there, as `Evaluation::Sampler#wrap_write_tools` does. Don't add to the Steepfile ignore list.
- **Builder.** `apply_tools` keeps its `tools.present?` guard and becomes `agent.with_tools(nil).with_tools(*Emails::MessageScope.new.bind(tools))`.
  - `policy.tools` stays classes, so the `ActionExecutor` snapshot `policy.tools.map(&:to_s)` is unchanged.
  - The edge `lib/orchestration` (application layer) to `app/tools` (tools layer) points downward, so it is allowed. Tools never reference `Orchestration`.
- **Legacy agent rows: no data migration.** Older databases still have migration-seeded rows whose prompts call `get_email` on ids from the step input, without `ListTool`/`SearchTool`. Their calls are now refused:
  - `Orchestration::Agents::EmailsMapper` (`GetTool`)
  - `Orchestration::Agents::RecordsStorer` (`GetTool`, `AddLabelsTool`)
  - `Orchestration::Agents::RecordsFiller` (`GetTool`; seeded in `20260506000001…:69`, survives `db/seeds.rb:85` while an action uses it)

  The rows keep their tools, prompts and `enabled` flag. The refusal fails closed, and its message tells the model (and anyone reading the trace) what to do. ADR 0018 and `docs/orchestration.md` name the three agents. A user who still needs one adds `ListTool`/`SearchTool` to it or removes the email tools in the agent UI.
- **Docs.**
  - New ADR `docs/adr/0018-email-tools-scoped-to-chat.md` in the existing format (Status / Context / Decision / Consequences).
  - A short amendment note in ADR 0008: sampling `get_email` reads are limited to listed ids.
  - One sentence in the "Untrusted input" paragraph of `docs/orchestration.md`, naming the three legacy agents.
  - One sentence in `docs/evals.md`, where the Sampler is described.

## Red specs (tester, before any implementation)

Specs follow `.agents/rules/specs.md`:
- No `double`, `instance_double` or `spy` (enforced by the `App/NoTestDoubles` cop).
- Partial `allow(Emails).to receive(...)` must keep the real keyword arguments.
- Anonymous classes go through `stub_const` (`App/NoAnonymousClassInSpec`).
- Agent tool instances are read through `agent.chat.to_llm.tools` (a Hash from tool name to instance).

**S1. `spec/tools/emails/message_scope_spec.rb` (new)**
- A new scope refuses Gmail and Yahoo ids.
- Gmail:
  - After `record([{ id: "m1", provider: "gmail", labels: ["INBOX"] }])`, `allow?(provider: "gmail", message_id: "m1")` is true, with or without a `mailbox:`.
  - `"m2"` is false.
  - `provider: "yahoo", message_id: "m1"` is false.
- Yahoo:
  - Record uid `"42"` with `labels: ["Sent"]`. Then mailbox `"Sent"` and `"sent"` are true; `nil`, `"INBOX"` and `"Archive"` are false.
  - Record with `labels: ["INBOX"]` (and separately with `labels: []`). Then `mailbox: nil`, `""` and `"Inbox"` are true.
- Exact ids: with `"42"` recorded, `"123:42"`, `"42abc"`, `" 42"` and `"4"` are refused.
- Skipping:
  - `record(nil)` and `record({ error: "x" })` don't raise.
  - Items that are strings or nil, and a hash with `id: nil`, are skipped and record nothing.
- `record` returns its argument unchanged (same object).
- Two `MessageScope` instances don't share keys.
- `bind`:
  - `[Emails::ListTool, Emails::GetTool, Records::TempFileTool]` gives `[ListTool instance, GetTool instance, Records::TempFileTool]` (same order; the class is passed through as is).
  - Bound tools share the scope. Stub `Emails.list_messages` with its real kwargs and call the bound list tool's `execute`. The bound get tool then fetches the listed id (stubbed `Emails.message`) and refuses another id.
  - `Emails::ClassifyTool.with_classifier(...)` passes through as a class.
  - A `stub_const("BlockedAddLabelsTool", Class.new(Emails::AddLabelsTool))` subclass comes back as an instance of that subclass.
  - `bind([])` is `[]`.

**S2. `spec/tools/emails/get_tool_spec.rb` (change)**
- `subject(:tool)` becomes `described_class.new(message_scope: scope)`, where `scope` has recorded `{ id: "msg_abc", provider: "gmail", labels: ["INBOX"] }`. The existing body-cap, full-format, no-cache and unknown-provider cases stay green.
- New cases:
  - An unscoped tool (`described_class.new`) refuses `msg_abc`, and no Gmail request is made (WebMock `not_to have_been_made`).
  - With the scope, an out-of-scope `msg_other` returns `:error` matching `/list_emails|search_emails/`, and `Emails.message` is not received.
  - Yahoo: uid `"101"` recorded in `"Sent"`. `execute(provider: "yahoo", message_id: "101", label: "Sent")` calls `Emails.message("yahoo", "101", label: "Sent")`. `label: nil` and `label: "Archive"` are refused without calling it, and so is `message_id: "9:101"`.
  - Unknown provider still returns the provider error (the check order is unchanged).

**S3. `spec/tools/emails/add_labels_tool_spec.rb` (change)**
- The scope records Gmail `msg1` and Yahoo `101` in `INBOX`. The existing label-policy cases and Yahoo forwarding (`mailbox: "Inbox"`) stay green.
- New cases:
  - An unscoped tool refuses `msg1`, and `Emails.modify_labels` is not received.
  - Out-of-scope `msg2` is refused.
  - Yahoo `101` with `mailbox: "Archive"` is refused. The default mailbox (`INBOX`) is allowed.
  - A blocked label on an in-scope id still returns the label-policy error.

**S4. `spec/tools/emails/list_tool_spec.rb` and `spec/tools/emails/search_tool_spec.rb` (change)**
- With `described_class.new(message_scope: scope)`, the result is returned unchanged and `scope.allow?(provider: "gmail", message_id: "msg1")` becomes true afterwards.
- `described_class.new` without arguments still works.

**S5. `spec/lib/orchestration/runtime_agent_builder_spec.rb` (change)**
- The existing `with_tools(Records::TempFileTool)` case stays green, because unscoped classes pass through.
- New cases:
  - With policy tools `[Emails::ListTool, Emails::GetTool]`, `agent.chat.to_llm.tools[:get_email]` is an `Emails::GetTool` instance and `[:list_emails]` is a `ListTool` instance.
  - Listing through the build's list tool lets that build's get tool fetch the id.
  - Two builds have separate scopes: an id listed in build A is refused by build B's get tool.
  - `policy.tools` still equals `[Emails::ListTool, Emails::GetTool]` (classes) after `build`.

**S6. `spec/lib/orchestration/sampling_gateway_spec.rb` (change)**
- An agent row with `tools: ["Emails::ListTool", "Emails::GetTool"]` gives a built agent whose `get_email` is a `GetTool` instance.
- A `tool_transform` that swaps `AddLabelsTool` for a `stub_const` subclass ends up with that subclass bound as an instance.
- The existing "calls the tool_transform with the resolved tool classes" case still receives classes.

**S7. `spec/services/evaluation/sampler_spec.rb` (change)**
- New context: the agent has `tools: ["Emails::GetTool", "Emails::AddLabelsTool"]`, and the stubbed Mistral responses call `add_labels` and then `get_email` on an id from the dataset input.
  - The `add_labels` trace result is `"[write tool blocked during sampling]"`.
  - The `get_email` trace result contains the refusal error.
  - No Gmail request is made.
- The existing TempFileTool, read-only and no-tool cases stay green.

**S8. `spec/lib/orchestration/action_executor_spec.rb` (add one case)**
- For an agent with `Emails::GetTool`, the ActionRun's stored `tools` snapshot is `["Emails::GetTool"]`, not an instance's `inspect` string.

## Steps (implementor, after the specs are red)

### 1. `Emails::MessageScope`
- **Files:** `app/tools/emails/message_scope.rb` (tools layer) and `sig/app/tools/emails/message_scope.rbs`.
  - The sig covers `record`, `allow?`, `bind`, `self.refusal`, the `_ScopedToolClass` interface, the `@keys`/`@mutex` ivars and the private `key_for`/`normalize_mailbox` helpers.
  - No `untyped`: `record: (Array[Emails::message] messages) -> Array[Emails::message]`.
- **Red first:** S1.
- **Acceptance:**
  - S1 is green.
  - `bundle exec archspec explain app/tools/emails/message_scope.rb` puts it in `tools`.
  - `Orchestration::Agent.available_tools` doesn't list it (it is not a `RubyLLM::Tool`), so `tool_resolver_spec` stays green.

### 2. Make the four tools scoped
- **Files (tools layer):** `app/tools/emails/{list,search,get,add_labels}_tool.rb`, plus their sigs in `sig/app/tools/emails/`.
  - Each tool gets `self.message_scoped?`, `initialize(message_scope: MessageScope.new)` and `@message_scope`.
  - List and Search wrap their result in `@message_scope.record(...)`.
  - Get checks `allow?(provider:, message_id:, mailbox: label)` and AddLabels checks `allow?(provider:, message_id:, mailbox:)`. Both return `MessageScope.refusal(message_id)` before calling `Emails`.
  - Each sig adds `self.message_scoped?: () -> bool`, `initialize: (?message_scope: MessageScope) -> void` and `@message_scope: MessageScope`.
- **Red first:** S2, S3, S4.
- **Acceptance:** S2 to S4 are green, and an unscoped `GetTool.new` / `AddLabelsTool.new` makes no provider call.

### 3. Bind a scope per build
- **Files:**
  - `lib/orchestration/runtime_agent_builder.rb` (application layer; `apply_tools` only, its sig is unchanged).
  - `sig/shims/ruby_llm.rbs`: `RubyLLM::Agent#with_tools` becomes `(*(singleton(Tool) | Tool)? tools) -> self`.
- **Red first:** S5, S6, S7, S8.
- **Acceptance:**
  - S5 to S8 are green with no change to `Evaluation::Sampler`, `SamplingGateway`, `AgentResolutionPolicy` or `ToolResolver`.
  - `bundle exec steep check` passes.

### 4. Docs
- **Files:**
  - `docs/adr/0018-email-tools-scoped-to-chat.md`. Status: Accepted (GH #303; resolves SEC-07 in #240).
    - Context: #299 left scoping out.
    - Decision: per-chat scope, binding in the builder, the key rules, fail closed.
    - Consequences: listing tools must come first; sampling `GetTool` reads are narrowed; the legacy EmailsMapper, RecordsStorer and RecordsFiller rows get refusals and are left unchanged (no data migration); user agents that pass ids in their input get refusals.
  - `docs/adr/0008-sampler-real-tool-calls-with-write-blocking.md`: a one-line "Amended by ADR 0018" note.
  - `docs/orchestration.md` (Untrusted input paragraph) and `docs/evals.md` (Sampler paragraph): one sentence each.
- **Red first:** none (docs only).
- **Acceptance:** every bullet of the issue's Decision appears in ADR 0018, and the docs name the three legacy agents.

## Checks

The parts of the `AGENTS.md` definition of done that this change touches:
- `COVERAGE=true bundle exec rspec`
- `bundle exec rubocop` and `bundle exec archspec check --check-todo` (no new `archspec_todo.yml` entries)
- `bundle exec rbs -r optparse validate`, `bundle exec steep check`, `bundle exec bin/rbs_audit coverage --threshold=90`
- `bundle exec rigor check`
- `bundle exec brakeman --no-pager` and `bundle exec bundle-audit check --update`

Not needed:
- `archspec reflect`: no file under `app/models`, `config` or the Gemfile changes. Run it if any of those do change.
- `.sandbox` tests and `pnpm lint` / `pnpm format:check`: neither the sandbox nor any JS is touched.

## Requirement map

| Issue requirement | Step | Verification |
|---|---|---|
| Per-chat `Emails::MessageScope`, injected in `RuntimeAgentBuilder#apply_tools` | 1, 3 | S1, S5 |
| List/Search record, Get/AddLabels check | 2 | S2–S4 |
| Out-of-scope id gives `{ error: }` and no provider call | 2 | S2, S3 |
| Yahoo `(provider, mailbox, id)`, Gmail `(provider, id)`, exact ids, nil/non-hash skipped | 1 | S1, S2, S3 |
| Two builds get separate scopes | 3 | S5 |
| Unscoped tool refuses everything (fail closed) | 2 | S2, S3 |
| `policy.tools` stays classes (ActionExecutor snapshot) | 3 | S5, S8 |
| `with_tools` shim widened | 3 | steep |
| Sampling works, including write-blocked `AddLabelsTool` | 3 | S6, S7 |
| Legacy rows: no migration, documented (EmailsMapper, RecordsStorer, RecordsFiller) | 4 | review |
| ADR 0018 + `docs/orchestration.md` note | 4 | review |
| Definition of done passes | all | Checks |
