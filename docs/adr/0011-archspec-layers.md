# ADR 0011: Enforce layer order with ArchSpec

## Status
Accepted

## Context

Dependency direction was convention only. Violations crept in (a model callback enqueuing a job, a model probing email adapters). GH #170 adds [ArchSpec](https://archspecrb.dev) to check it mechanically.

## Decision

`Archspec.rb` uses the `:layered` preset with ordered layers (a layer may depend only on itself and layers below):

1. `interface`: controllers, components, helpers
2. `application`: services, forms, jobs, `lib/orchestration`, `lib/evaluation`, `lib/pipeline`
3. `tools`: `app/tools`
4. `domain`: models
5. `infra`: `lib/emails`

`app/tools` is its own layer between application and domain: tools are invoked by agents (application) and call into models and `Emails`, but must not reach back into services or orchestration.

Subsystem components (`orchestration`, `evaluation`) overlap the layers; layers cannot separate siblings, so a component rule forbids orchestration from using evaluation (evaluation depends on orchestration, never the reverse; `Orchestration.prompt_resolver` is injected from an initializer). Because overlapping components become extra targets of the layered allowlists, every layer explicitly admits them.

`:ruby_conventions` is composed on top (no `get_`/`set_`/`is_` method names).

Existing violations are recorded in `archspec_todo.yml` (matched by fingerprint) instead of silent exceptions; `archspec check` runs in CI and the pre-commit hook.

## Consequences

- The baseline holds 17 entries: 5 layer/cycle edges (`BaseForm` -> controller concern, `Evaluation::Wizard::Step1Form` cycle, `Evaluation::Experiment` and `Orchestration::Pipeline` -> application, `Emails::ClassifyTool` -> `Orchestration::Agents::EmailsClassifier`) and 12 `get_*` names in `Emails` and its adapters (rename in a follow-up).
- Private controller `set_*` filters are not flagged by the naming rule.
- Regenerate the baseline only to shrink it: `bundle exec archspec check --update-todo`.
