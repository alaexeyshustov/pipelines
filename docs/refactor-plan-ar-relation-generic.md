# Refactor Plan: Generic `ActiveRecord::Relation` in RBS Signatures

## Context

- **76 occurrences** of bare `ActiveRecord::Relation` across **37 RBS files**.
- The installed `gem_rbs_collection/activerecord/8.0` declares `class Relation` as non-generic, so `ActiveRecord::Relation[X]` is rejected by Steep.
- A generic top-level interface exists: `_ActiveRecord_Relation[Model, PrimaryKey]` (already used by `activestorage/7.0/lib/attached/many.rbs` as precedent).
- The interface gives `self` for chainable methods (`where`, `order`, `joins`, `distinct`, etc.) and `Model` for terminal ones (`first`, `find_by`, `take`).

## Approach: per-model `type relation` alias

Each model owns a nested type alias:

```rbs
module Evaluation
  class Prompt < ApplicationRecord
    type relation = _ActiveRecord_Relation[Prompt, Integer]

    def self.where: (**top attrs) -> relation
    def self.order: (*top) -> relation
    def self.distinct: () -> relation
  end
end
```

Consumers reference it as `Evaluation::Prompt::relation`:

```rbs
@prompts: Evaluation::Prompt::relation
def prompts: () -> Evaluation::Prompt::relation
```

**Trade-offs vs. alternatives:**

- vs. inline `_ActiveRecord_Relation[Prompt, Integer]` everywhere: more concise, single source of truth per model, easier to migrate if interface changes.
- vs. top-level shim aliases (`type prompt_relation = ...`): keeps namespacing intact, no shim file to maintain.
- vs. redeclaring `class Relation[Elem]` in a shim: avoids fighting the gem collection's existing declaration (which would cause duplicate-definition errors).

## Phases

### Phase 1 — Spike & validate (1 file)

- Add `type relation = _ActiveRecord_Relation[Prompt, Integer]` to `sig/app/models/evaluation/prompt.rbs`.
- Replace its three `ActiveRecord::Relation` returns with `relation`.
- Run `bundle exec steep check` to confirm the interface is accepted and that chained calls in implementation files (e.g., `Prompt.where(...).order(...)`) still type-check.
- If green, lock in the pattern. If not, fall back to inline `_ActiveRecord_Relation[Prompt, Integer]`.

### Phase 2 — Models (12 files)

Add `type relation = _ActiveRecord_Relation[<Self>, Integer]` and migrate returns:

| File | Methods to retype |
|---|---|
| `evaluation/prompt.rbs` | `where`, `order`, `distinct` |
| `evaluation/dataset.rbs` | `where`, `left_joins` |
| `evaluation/metric.rbs` | `for_agent`, `active` |
| `evaluation/evaluation_result.rbs` | `where`, `joins`, `group` |
| `evaluation/sample.rbs` | `where`, `includes`, `order` |
| `evaluation/experiment.rbs` | `where`, `joins`, `includes`, `order` |
| `evaluation/justification.rbs` | `joins`, `includes`, `eager_load`, `where` |
| `application_mail.rbs` | `search`, `groupped`, `as_rows` param |
| `interview.rbs` | `search`, `as_rows` param |
| `email_connector.rbs` | `all` |

Skip `application_record.rbs` — base-class methods can't name a concrete `Model` without true F-bound generics.

### Phase 3 — Consumers (controllers, components, forms, services, lib)

Mechanical find/replace, scoped per-file (one type per ivar/return):

- **Controllers (12)** — `@chats`, `@mails`, `@interviews`, `@prompts`, `@experiments`, `@justifications`, `@email_connectors`, `@runs` (×2), `@agents` (×2), `@actions` (×3), `@steps` (×2), `@pipelines`, `@using_actions`.
- **Components (6)** — `step_component.rbs` (`@actions` + `initialize` param), `experiment_detail_component.rbs` (`metrics`, `dataset_samples`), 3 wizard step components, `metric_list_component.rbs`.
- **Forms (3)** — `step1_form.rbs` (`prompts`), `step2_form.rbs` (`metrics`), `step3_form.rbs` (`datasets`).
- **Services (1)** — `interviews/batch_service.rbs` (`collect_dates` param).
- **Lib (2)** — `list_experiments_tool.rbs` (`load_experiments`), `dataset_seeder.rbs` (`candidate_runs`).

### Phase 4 — Special cases

- **`Paginable#paginate`** — currently `(ActiveRecord::Relation) -> [Pagy, ActiveRecord::Relation]`. Make it generic at the method level:

  ```rbs
  def paginate: [Model, PrimaryKey] (_ActiveRecord_Relation[Model, PrimaryKey] collection) -> [Pagy, _ActiveRecord_Relation[Model, PrimaryKey]]
  ```

- **`models_controller.rbs @models`** — currently typed as `ActiveRecord::Relation` but actually holds an `Array[RubyLLM::Model]` from `pagy(:offset, ...)`. Out of scope for this refactor; flag separately.
- **`application_record.rbs`** — leave the `def self.where: -> ActiveRecord::Relation` etc. as-is. These are the generic fallbacks for any subclass that doesn't override.

### Phase 5 — Verify

- `bundle exec rubocop` — should stay clean.
- `bundle exec steep check` — expect zero errors.
- Spot-check a few `.rb` consumers (e.g., `Evaluation::Comparison`, `BatchService`) to confirm chained queries still resolve.

## Risks

- **Interface gaps** — `_ActiveRecord_Relation` may not declare every method that the codebase calls on relations (e.g., custom scopes). If Steep flags missing methods on the interface, fall back to keeping that call site's type as `ActiveRecord::Relation` (untyped).
- **`CollectionProxy` returns** — model `has_many` associations return `CollectionProxy`, not the interface. Existing signatures already use `ActiveRecord::Associations::CollectionProxy` for these and aren't affected.
- **Cascading FATALs** — a previous attempt with `ActiveRecord::Relation[X]` produced cascading `InvalidSubstitutionError` FATALs (because `Relation` isn't generic). Using the interface instead of parameterizing the class avoids that failure mode entirely.

## Estimated effort

- Phase 1: 5 min (spike).
- Phase 2: 15 min (12 model files, 25 method signatures).
- Phase 3: 30 min (24 consumer files, mostly find/replace).
- Phase 4: 10 min (`Paginable` generic, `models_controller` flag).
- Phase 5: 5 min (run linters).

**Total: ~1 hour.** Single commit, since the spike validates the pattern up front.
