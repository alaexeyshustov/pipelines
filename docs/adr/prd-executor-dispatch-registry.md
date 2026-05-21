---
status: proposed
---

# PRD: Explicit Executor Dispatch Registry

## Summary

Replace the `constantize`-based executor dispatch in `PipelineRunner` with an explicit hash registry. The registry becomes the single authoritative list of service executors; `PipelineRunner` looks up through it without knowing or trusting the class name string at runtime.

## Problem

`PipelineRunner` currently dispatches to service executors by calling `action.agent_class&.constantize`. The `Executable` concern documents the expected interface (`.call(input, params) → Hash`) but does not enforce it — it is a comment only. This creates three pain points:

- **No compile-time contract.** Any typo in the stored class name or a renamed class causes a `NameError` at runtime, inside a running pipeline.
- **Invisible seam.** There is no single place that lists all registered executors. Auditing or adding one requires searching across namespaces.
- **Hard-to-write tests.** Specs must stub `constantize` rather than pass an object that satisfies the actual interface.

## Goals

- Remove the `constantize` call from `PipelineRunner`.
- Make the full set of service executors auditable in one place.
- Allow test doubles that satisfy the `.call` interface rather than stubbing constant lookup.
- Eliminate the `Executable` concern, which provides no enforcement.

## Non-Goals

- Changing the executor `.call(input, params) → Hash` interface.
- Renaming the `agent_class` database column (it continues to serve as the lookup key).
- Changing agent dispatch (the `RuntimeAgentBuilder` path remains untouched).
- Adding dynamic registration or plugin-style executor loading.

## Primary Users

- Developers adding or auditing service executors.
- Developers writing specs for `PipelineRunner` and executor behavior.

## Functional Requirements

### 1. Executor registry constant

`PipelineRunner` must define a private frozen hash constant mapping the stored class name string to the executor class:

```ruby
EXECUTORS = {
  "Emails::FetchExecutor"              => Emails::FetchExecutor,
  "Orchestration::QueryExecutor"       => Orchestration::QueryExecutor,
  "Orchestration::IngestionExecutor"   => Orchestration::IngestionExecutor,
  "Interviews::GistExportExecutor"     => Interviews::GistExportExecutor
}.freeze
```

### 2. Dispatch via registry

The `run_agent` method must look up the executor through `EXECUTORS` instead of calling `constantize`:

```ruby
klass = EXECUTORS.fetch(action.agent_class) do
  raise ArgumentError, "Unregistered executor: #{action.agent_class}"
end
{ output: klass.call(input, params), raw_content: nil }
```

The `ArgumentError` on unknown key matches today's behavior and is caught by the existing `handle_action_failure` path.

### 3. Remove the `Executable` concern

Delete `app/concerns/orchestration/executable.rb`. Remove `include Orchestration::Executable` from all four executor files. The interface contract is owned by RBS signatures and tests; the no-op module adds no enforcement value.

### 4. No boot-time validation

Do not add startup checks that verify each registered class responds to `.call`. RBS signatures and specs cover the interface contract. The `fetch` guard handles unknown keys at runtime.

### 5. Specs

Existing specs that stub `constantize` must be updated. Test doubles for `PipelineRunner` unit tests should satisfy the actual `.call(input, params) → Hash` interface and be injected via `stub_const` on `EXECUTORS`:

```ruby
stub_const("Orchestration::PipelineRunner::EXECUTORS", {
  "FakeExecutor" => ->(input, params) { { "result" => "ok" } }
})
```

## Technical Approach

### Files to change

| File | Change |
|------|--------|
| `app/services/orchestration/pipeline_runner.rb` | Add `EXECUTORS` private constant; replace `constantize` dispatch |
| `app/concerns/orchestration/executable.rb` | Delete |
| `app/services/emails/fetch_executor.rb` | Remove `include Orchestration::Executable` |
| `app/services/orchestration/query_executor.rb` | Remove `include Orchestration::Executable` |
| `app/services/orchestration/ingestion_executor.rb` | Remove `include Orchestration::Executable` |
| `app/services/interviews/gist_export_executor.rb` | Remove `include Orchestration::Executable` |
| `sig/` | Update or add RBS signatures for executor interface and registry constant |
| Specs | Replace `constantize` stubs; add test for unregistered key path |

### Dispatch before and after

**Before:**
```ruby
klass = action.agent_class&.constantize
raise ArgumentError, "Service class not found: #{action.agent_class}" unless klass
{ output: klass.call(input, params), raw_content: nil }
```

**After:**
```ruby
klass = EXECUTORS.fetch(action.agent_class) do
  raise ArgumentError, "Unregistered executor: #{action.agent_class}"
end
{ output: klass.call(input, params), raw_content: nil }
```

## Success Criteria

- `constantize` no longer appears in `PipelineRunner`.
- All four executors are listed in `EXECUTORS`; the full set is visible in one place.
- The `Executable` concern and all its `include` sites are removed.
- Specs for executor dispatch do not stub `constantize`.
- Adding a fifth executor requires one new class file and one line in `EXECUTORS` — nothing else.
