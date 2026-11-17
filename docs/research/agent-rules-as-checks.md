# Research: enforcing `.agents/rules` with RuboCop and ArchSpec (GH #247)

Question: which conventions in `.agents/rules/*.md` can a check enforce, and is RuboCop, ArchSpec or herb the right tool for each?
Sources: `.agents/rules/*.md`, `docs/claude/*.md`, `Archspec.rb`, `lib/rubocop/cop/**`, `.rubocop.yml`, archspec 1.2.2 (`lib/archspec/dsl.rb`, `lib/archspec/rules/{protocol,dependency}_rules.rb`), `rubocop --show-cops` for rubocop-rspec and rubocop-on-rbs, and the herb research for #262. Checked on 2026-11-17 at `63a52697`.

I ran each proposed ArchSpec rule from a scratch config (`archspec check --config`, with `root`, `todo` and `facts` pointing at the repo). The committed `Archspec.rb` passes with 0 violations, so every hit below comes from the new rules. Violation counts for RuboCop candidates come from `grep` over `spec/`, `sig/` and `app/`.

**Short answer:** 3 rules suit ArchSpec, 10 suit a custom RuboCop cop, and 2 suit herb custom rules. ArchSpec's `cannot_call` matches method names on any receiver, so it can't tell an ActiveRecord `find` from `Array#find`. Use it only for method names that don't exist outside the rule (`perform_later`, `deliver_later`).

## Already enforced

| Rule | Check |
|---|---|
| `self.call` delegates to `new(...).call`; one public method | `App/ServiceMustHaveClassCall`, `App/ServiceMustHaveInstanceCall`, `App/ServiceSinglePublicMethod` |
| Forms inherit `BaseForm` | `App/FormObjectMustInheritBaseForm` |
| `aasm column:` given | `App/AasmMustSpecifyColumn` |
| Component preview exists | `App/ComponentMustHavePreview` |
| No `Current` in components | `App/NoCurrentInComponent` |
| No `double`/`spy` | `App/NoTestDoubles` |
| No `untyped` in RBS | `RBS/Lint/NoUntyped` |
| Unused `let!` | `RSpec/LetSetup` (enabled) |
| Layer direction; orchestration doesn't use evaluation | `Archspec.rb` |

## Changes to existing cops

| Rule | Today | Change | Current violations |
|---|---|---|---|
| Service results follow the Result pattern: `Result = Data.define(...)` | `App/ServiceResultMustUseDataDefine` flags only `Result = Struct.new` | Require each `app/services` class to define `Result = Data.define(...)` and return it. Overlaps with #230 (Success/Failure shape). | 18 of 26 services define no `Result`. Most are query services returning row types (`Hit`, `Row`, `AgentSummary`, `Usage`) or raw values (`gist_uploader`, `text_extractor`, `csv_export_service`). |
| No `sleep` in any spec | `App/NoSleepInSystemSpecs` scoped to `spec/system/` | Rename to `App/NoSleepInSpecs`, scope to `spec/` | 0 |

## ArchSpec candidates

| # | Rule | Archspec | Trial result |
|---|---|---|---|
| A1 | Forms: no jobs or mail in `#save` | `component(:forms, in: "app/forms/**/*.rb").cannot_call(:perform_later, :perform_now, :deliver_later, :deliver_now)` | 0 hits. Detection was confirmed by a probe on `app/services` (hit `prompt_creator.rb:13`). |
| A2 | Forms: no LLM/API calls | `forms.cannot_reference_constants("RubyLLM", "Emails", "Embeddings")` | 0 hits |
| A3 | Models don't enqueue (ADR 0013), which also covers "no AASM callbacks with external side effects" for jobs | `models.cannot_call(:perform_later, :perform_now, :deliver_later, :deliver_now)` | 0 hits |
| — | Models don't reference `RubyLLM`/`Emails`/`Embeddings` | `cannot_reference_constants` | **Rejected:** 7 legitimate hits (`Emails::PROVIDER_NAMES` in validations, `Embeddings::Client::DIMENSIONS`, `RubyLLM.models` in `Orchestration::Agent`). |
| — | No ActiveRecord queries in components | `components.cannot_call(:where, :find, :order, :count, ...)` | **Rejected for ArchSpec:** 7 hits, 5 false positives on arrays/hashes (`@validator_results.find`, `&.first`, `@pagy.last`). With `receiver: "ApplicationRecord"`, 0 hits, including the 2 real ones, because the receivers are association chains. Use RuboCop (R1). |
| — | `UI::` components don't depend on domain code | `component(:ui, ...).cannot_use(:orchestration, :evaluation)` | 0 hits, but weak: `cannot_reference_constants` on model namespaces finds `Tag::NAMES` in `ui/legacy_sidebar_component.rb:52`. Include only if the legacy sidebar moves out of `UI::`. |

## RuboCop candidates

| # | Rule | Cop sketch | Current violations |
|---|---|---|---|
| R1 | No ActiveRecord queries in components | In `app/components/**/*.rb`, flag `where`/`order`/`find_by`/`pluck`/`count`/`exists?`/`includes`/`joins` whose receiver chain starts at a constant or an ivar association (`@x.samples.count`), but not a plain ivar (`@results.find`). Heuristic. | 2: `evaluation/experiment_detail_component.rb:48` (`Metric.for_agent(...).order`), `:52` (`@experiment.samples.count`) |
| R2 | No AASM callbacks with external side effects | Flag `after`/`before`/`after_commit`/`success`/`error` options or blocks inside `aasm do` that call `perform_later`/`deliver_*` or reference `RubyLLM`. A3 already covers the job case model-wide, so R2 is only needed for `RubyLLM`. | 0 (only `Evaluation::Experiment` uses AASM, with no callbacks) |
| R3 | Variants instead of CSS classes | Flag `class:`/`classes:`/`css_class:`/`html_class:` keywords in component `initialize`. | 2: `ui/legacy_table_component/{cell,column}_component.rb` (`classes:`) |
| R4 | `stub_const` instead of inline anonymous classes | Flag `Class.new` in `spec/` unless it's the value argument of `stub_const`. | 24 `Class.new` in specs, ~14 not under `stub_const` (e.g. `connection_tester_spec.rb:5,24`, `pipeline_import_form_spec.rb:8`) |
| R5 | Create records in their final state, no `update!` in `before` | Flag `update`/`update!` inside `before` blocks. | ~19 calls, nearly all in `spec/lib/orchestration/pipeline_runner_spec.rb` |
| R6 | RBS: open full namespace blocks | Custom RBS cop (rubocop-on-rbs has none): flag `class A::B`/`module A::B` declarations. | 7: `sig/app/components/ui/action_component.rbs` (5), `legacy_tabs_component.rbs` (2) |
| R7 | RBS: no bare `Array`/`Hash` | Extend `RBS/Lint/NoUntyped` to flag `Array`/`Hash` with no type arguments. | 0 |
| R8 | `sig/` mirrors the source tree | Spec or rake task (not a per-file cop): each `sig/{app,lib}/**/*.rbs` has a matching `.rb`. | 6 orphans: `sig/lib/rubocop/rbs/cop_base.rbs`, `sig/lib/rubocop/cop/app/form_object_must_include_active_model.rbs`, `sig/app/models/{model,tool_call}.rbs`, `sig/app/services/interviews/gist_export_executor.rbs`, `sig/app/components/interviews/search_form_component.rbs` |

R8 also catches stale signatures left behind by deletions, such as the `service_must_not_call_service.rbs` removal in this issue.

## herb candidates (blocked on #262)

herb supports custom rules as `.mjs` in `.herb/rules/` (see the herb research for #262).

| # | Rule | Current violations |
|---|---|---|
| H1 | Templates only call methods (no logic in `.erb`) | herb's opt-in `erb-no-silent-statement` reports 62. Too broad as-is; needs a custom rule or allowlist. |
| H2 | Prefer slots over `render Child.new` in templates | 10 templates, including the 3 known exceptions (`step_action_editor`, `input_mapping`, `schema_builder`). |

## Not checkable

Services return expected failures and raise unexpected ones (#230 adds a `raise` cop). Forms wrap multi-model writes in a transaction and copy `RecordInvalid` errors. `enum` vs AASM. Stubs match real keyword signatures (`instance_double` covers this). Factory attributes and traits. Where each spec type lives. System specs drive the UI. Hand-written RBS, `void` returns, nilability. Everything in `docs/claude/`.
