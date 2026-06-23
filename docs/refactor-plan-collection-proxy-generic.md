# Refactor Plan: Generic `ActiveRecord::Associations::CollectionProxy` in RBS

Companion to [`refactor-plan-ar-relation-generic.md`](refactor-plan-ar-relation-generic.md), which migrated bare `ActiveRecord::Relation` returns to `_ActiveRecord_Relation[Model, PrimaryKey]`. This plan does the same for `has_many` / `has_and_belongs_to_many` association readers.

## Context

- **18 occurrences** of bare `ActiveRecord::Associations::CollectionProxy` across **15 RBS files** (17 in models, 1 in a `RubyLLM` shim).
- The installed `gem_rbs_collection/activerecord/8.0` declares `class CollectionProxy < Relation` as **non-generic**. Writing `CollectionProxy[Sample]` is rejected as wrong arity, and redeclaring `class CollectionProxy[Model]` in a shim collides with the upstream definition.
- The generic interface `_ActiveRecord_Relation[Model, PrimaryKey]` (already established in the relation refactor) is structurally satisfied by `CollectionProxy` for read/filter/iterate paths.
- The `rbs_rails` generator produces per-model subclasses named `Klass::ActiveRecord_Associations_CollectionProxy`. This refactor adopts that name only where the strictly-typed mutation methods (`<<`, `build`, `create`, `delete`, `destroy`, `replace`) are actually called — so a later `rake rbs_rails:all` won't duplicate the shims we author.

## Approach: generic-by-default, subclass-on-demand

**Default (Option A) — reuse `_ActiveRecord_Relation` and the existing `type relation` alias per model:**

```rbs
module Evaluation
  class Prompt < ApplicationRecord
    type relation = _ActiveRecord_Relation[Prompt, Integer]

    def experiments: () -> Experiment::relation
    def samples:     () -> Sample::relation
  end
end
```

Consumers get typed `where`, `order`, `includes`, `find`, `first`, `to_a`, `each`, `find_each`, `destroy_all`, `delete_all`, `pluck` (return is `Array[untyped]`), etc.

**Escalation (Option B) — declare a per-model `ActiveRecord_Associations_CollectionProxy` subclass only when the codebase actually calls `<<` / `build` / `create` / `create!` / `delete(records)` / `destroy(records)` / `replace` on that association:**

```rbs
module Orchestration
  class Pipeline
    class ActiveRecord_Associations_CollectionProxy < ::ActiveRecord::Associations::CollectionProxy
      include ::Enumerable[Pipeline]
      include ::ActiveRecord::Relation::Methods[Pipeline, ::Integer]
    end
  end
end
```

Then on the parent model:

```rbs
def pipeline_runs: () -> PipelineRun::ActiveRecord_Associations_CollectionProxy
```

The subclass name matches what `rbs_rails` would generate, so if/when the generator is wired in, hand-written shims become drop-in duplicates that we delete in one pass.

**Trade-offs vs. alternatives:**

- vs. bare `ActiveRecord::Associations::CollectionProxy` everywhere: callers actually get a typed `Model` back from `first`, `find`, `to_a`, etc.
- vs. always-subclass for every association: avoids ~17 × ~10 lines of boilerplate that nothing auto-refreshes when a model's PK or namespace changes. Only models that need typed mutation pay the boilerplate cost.
- vs. parameterizing `CollectionProxy[Model]` in a shim: the upstream non-generic definition would conflict; `rbs validate` rejects duplicates with differing arity.

## Inventory

### Option A targets (14 associations — read/filter only)

| File | Association | Element type alias |
|---|---|---|
| `sig/app/models/chat.rbs` | `messages` | `Message::relation` (verify alias exists; add if missing) |
| `sig/app/models/chat.rbs` | `action_runs` | `Orchestration::ActionRun::relation` |
| `sig/app/models/orchestration/agent.rbs` | `actions` | `Action::relation` |
| `sig/app/models/orchestration/action.rbs` | `step_actions` | `StepAction::relation` |
| `sig/app/models/orchestration/step.rbs` | `actions` | `Action::relation` |
| `sig/app/models/evaluation/prompt.rbs` | `experiments` | `Experiment::relation` |
| `sig/app/models/evaluation/prompt.rbs` | `samples` | `Sample::relation` |
| `sig/app/models/evaluation/dataset.rbs` | `dataset_samples` | `DatasetSample::relation` (uses `.delete_all` only — interface covers it) |
| `sig/app/models/evaluation/dataset.rbs` | `experiments` | `Experiment::relation` |
| `sig/app/models/evaluation/dataset_sample.rbs` | `samples` | `Sample::relation` |
| `sig/app/models/evaluation/evaluation_result.rbs` | `justifications` | `Justification::relation` |
| `sig/app/models/evaluation/experiment.rbs` | `samples` | `Sample::relation` |
| `sig/app/models/evaluation/experiment.rbs` | `evaluation_results` | `EvaluationResult::relation` |

### Option B targets (4 associations — confirmed mutation call sites)

Detected by grepping `app/` and `lib/` for `.build` / `.create` / `.create!` / `<<` / `replace` / `delete(...records)` / `destroy(...records)` on the association name:

| Association | Call site | Method used |
|---|---|---|
| `Orchestration::Pipeline#steps` | `app/controllers/orchestration/steps_controller.rb:11` | `.build` |
| `Orchestration::Pipeline#pipeline_runs` | `app/forms/orchestration/pipeline_run_form.rb:20`, `app/jobs/scheduler_job.rb:20` | `.create`, `.create!` |
| `Orchestration::Step#step_actions` | `app/forms/orchestration/step_action_create_form.rb:19` | `.build` |
| `Orchestration::PipelineRun#action_runs` | `app/services/orchestration/pipeline_runner.rb:40` | `.create!` |

For each, declare the subclass in the **element** model's own `.rbs` (e.g. `Orchestration::Step::ActiveRecord_Associations_CollectionProxy` lives in `sig/app/models/orchestration/step.rbs`), and reference it from the **parent** model's association reader.

### Out of scope

- `sig/shims/ruby_llm.rbs:30` — `RubyLLM::Agent#messages` returns a collection of `RubyLLM::Message`, not an `ApplicationRecord`. Retype as `Array[RubyLLM::Message]` (or a small `_Enumerable[RubyLLM::Message]` interface) in a separate, single-file change. Tracked here for visibility; not part of the AR migration.

## Phases

### Phase 1 — Spike & validate (1 file, Option A only)

- Pick `sig/app/models/evaluation/prompt.rbs` (already has `type relation`; both associations are read-only — `experiments`, `samples`).
- Replace both returns with `Experiment::relation` / `Sample::relation`.
- Run:
  - `bundle exec rbs -r optparse validate sig/**/*.rbs sig/**/**/*.rbs sig/**/**/**/*.rbs`
  - `bundle exec steep check`
- Confirm chained reads in consumers (e.g. `prompt.samples.where(...).order(...)`) still type-check.
- If green, lock the pattern in. If a consumer breaks because it calls a method not on the interface, note the gap and decide: extend the interface, fall back to a subclass, or annotate the call site.

### Phase 2 — Option A migration (12 associations across 7 model files)

For each row in the Option A table:

1. Ensure the element model declares `type relation = _ActiveRecord_Relation[<Self>, ::Integer]`. Most already do (from the prior relation refactor); add the alias where it's missing (audit needed: `Message`, `Orchestration::Action`, `Orchestration::StepAction`, `Orchestration::ActionRun`, `Justification`).
2. Replace the bare `ActiveRecord::Associations::CollectionProxy` return with `<ElementClass>::relation`.
3. Validate after each file or in one batch — RBS validate is fast.

### Phase 3 — Option B shims (4 associations, ~6 lines each)

In each element model's `.rbs`, add the nested subclass:

```rbs
module Orchestration
  class Step < ApplicationRecord
    type relation = _ActiveRecord_Relation[Step, ::Integer]

    class ActiveRecord_Associations_CollectionProxy < ::ActiveRecord::Associations::CollectionProxy
      include ::Enumerable[Step]
      include ::ActiveRecord::Relation::Methods[Step, ::Integer]
    end
  end
end
```

Then update the **parent** model's association reader:

| Parent file | Reader | New return type |
|---|---|---|
| `sig/app/models/orchestration/pipeline.rbs` | `steps` | `Step::ActiveRecord_Associations_CollectionProxy` |
| `sig/app/models/orchestration/pipeline.rbs` | `pipeline_runs` | `PipelineRun::ActiveRecord_Associations_CollectionProxy` |
| `sig/app/models/orchestration/step.rbs` | `step_actions` | `StepAction::ActiveRecord_Associations_CollectionProxy` |
| `sig/app/models/orchestration/pipeline_run.rbs` | `action_runs` | `ActionRun::ActiveRecord_Associations_CollectionProxy` |

The subclass inherits `build` / `create` / `create!` / `<<` / `delete` / `destroy` / `replace` from the parent `::ActiveRecord::Associations::CollectionProxy` (which exists in the gem collection). Steep won't validate the **arguments** to `build` / `create` (the parent's signature is `_EachPair` = untyped pairs), but the **return** is properly `<Element>` because the parent's signatures return `untyped` and the subclass refines them via `Relation::Methods[Klass, PK]`.

> **Note:** If the inherited `untyped`-returning `build` / `create` proves insufficient for downstream typing (i.e. Steep keeps inferring `untyped`), copy the rbs_rails template overrides for those methods into the subclass. Match the rbs_rails wording verbatim so a future `rake rbs_rails:all` produces identical output and the shim can be deleted cleanly.

### Phase 4 — `RubyLLM::Agent#messages` (1 file, separate concern)

- Replace the bare `CollectionProxy` return in `sig/shims/ruby_llm.rbs:30` with `Array[Message]` or an `interface _Enumerable[T]` over `RubyLLM::Message`.
- Verify whatever calls `agent.messages` in `app/` only uses `Enumerable`-style methods.

### Phase 5 — Verify

- `bundle exec rbs -r optparse validate sig/**/*.rbs sig/**/**/*.rbs sig/**/**/**/*.rbs` — zero errors.
- `bundle exec steep check` — zero new errors.
- `bundle exec rubocop` — clean.
- Spot-check the four Option B call sites and a couple of Option A consumers (e.g. `Evaluation::AgentSummaryQuery`, `Orchestration::PipelineRunner`) to confirm typed access.

## Risks

- **Interface gaps on Option A** — if a consumer calls a method on a collection that isn't in `_ActiveRecord_Relation` (e.g. a model-defined scope, or `size` / `length` / `empty?` which rely on `Enumerable` being included on the concrete class), Steep flags it. Two responses:
  - Add the method to the element model's relation interface (extend `type relation` with `& _ScopeMethods`).
  - Escalate that association from Option A to Option B (the subclass `include ::Enumerable[Klass]` covers `size`/`length`/`empty?`).
- **`build` / `create` arg validation is still untyped** — both Option B and rbs_rails' generated form rely on `_EachPair`. This refactor does not improve kwarg validation; it only improves return-type inference.
- **Future `rbs_rails` adoption** — the four hand-written subclasses are intentionally named to match what the generator emits. The day someone runs `rake rbs_rails:all`, those four files duplicate; we delete the hand-written blocks in a single cleanup PR. No other Option B sites should be added without recording them here.
- **Pluralized vs. singularized aliases** — relation aliases live under the element class (`Sample::relation`), not under a plural form. Don't introduce `Samples::relation`.

## Estimated effort

- Phase 1: 10 min (spike + validate).
- Phase 2: 20 min (12 associations, mostly mechanical; small audit for missing `type relation` aliases).
- Phase 3: 20 min (4 subclasses, 4 reader updates, validate).
- Phase 4: 10 min (`RubyLLM::Agent#messages`).
- Phase 5: 10 min (full validate + steep + rubocop, spot-check).

**Total: ~70 min.** Recommend splitting into two commits — Option A migration (Phases 1 + 2 + 4) as one mechanical change, Option B shims (Phase 3) as a second commit so the boilerplate cost is reviewable on its own.
