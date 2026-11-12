# ADR 0011: Enforce layer order with ArchSpec

## Status
Accepted

## Context

Dependency direction was convention only. Violations crept in (a model callback enqueuing a job, a model probing email adapters). GH #170 adds [ArchSpec](https://archspecrb.dev) to check it mechanically.

## Decision

`Archspec.rb` uses the `:layered` preset with ordered layers (a layer may depend only on itself and layers below):

1. `interface`: controllers, components, helpers
2. `application`: services, forms, jobs, `lib/orchestration`, `lib/evaluation`, `lib/pipeline`, rake tasks (`lib/tasks/**/*.rake`)
3. `tools`: `app/tools`
4. `domain`: models
5. `infra`: `lib/emails`

`app/tools` is its own layer between application and domain: tools are invoked by agents (application) and call into models and `Emails`, but must not reach back into services or orchestration.

Subsystem components (`orchestration`, `evaluation`) overlap the layers; layers cannot separate siblings, so a component rule forbids orchestration from using evaluation (evaluation depends on orchestration, never the reverse; `Orchestration.prompt_resolver` is injected from an initializer). The layer allowlists do not admit these components: since archspec 1.2 a reference passes when any component owning its target is allowed, so admitting them would let every layer reach `lib/orchestration` and `lib/evaluation`. (Under 1.1 every owner had to be allowed, so each layer admitted them; kept under 1.2, that admission hid three layer edges, GH #249.)

`:ruby_conventions` is composed on top (no `get_`/`set_`/`is_` method names).

Existing violations are recorded in `archspec_todo.yml` (matched by fingerprint) instead of silent exceptions; `archspec check --check-todo` runs in CI and the pre-commit hook, so it also fails when the baseline lists violations that no longer occur.

`reflect :rails` adds what Rails resolves at runtime (association targets, custom validators, conditional concern effects), so e.g. a `has_many` from an orchestration model to an `Evaluation::*` model breaks the component rule. `archspec reflect --environment test` boots the app once and writes `archspec_facts/rails.yml`, which is committed: CI runs plain `check` and never boots the app, and fails with `facts.stale` when a model or reflection input changed without regenerating the facts (see `docs/claude/gotchas.md`).

Other archspec 1.2 features, not adopted (GH #249):
- `descendants_of:` for `Data.define` results: `App/ServiceResultMustUseDataDefine` already enforces the result shape; revisit with the Success/Failure result type (#230) if a dependency rule on results becomes useful.
- ERB view components: views are mostly ViewComponents (already in `interface`); add a `views` component only with a concrete agreed rule.

## Consequences

- The baseline is empty. GH #249 fixed every entry: `Evaluation::Experiment` no longer calls `AgentCatalog`; `Orchestration::Pipeline#validate_steps` is gone (callers use `PipelineValidator`); `JsonParamsParsing` moved to `app/forms/concerns` (application layer), breaking the `BaseForm` cycle; `Orchestration::ToolResolver` injects `EmailsClassifier` into `Emails::ClassifyTool` via `.with_classifier`; and the `Emails` `get_*` methods became `message`/`labels`/`unread_count` (LLM-facing tool names such as `get_labels` are unchanged).
- Private controller `set_*` filters are not flagged by the naming rule.
- Regenerate the baseline only to shrink it: `bundle exec archspec check --update-todo`. `--check-todo` enforces this for fixed violations; line-only shifts no longer change the file.
- Model, association, validator, config or Gemfile edits require regenerating `archspec_facts/` in the same commit.
