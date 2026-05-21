---
status: proposed
---

# Name and extract the upstream schema index

"What schemas are available upstream of this step?" is the same question asked in at least three places: `Pipeline::Validator`, `StepsListComponent`, and `InputMappingComponent`. Each call site re-walks the full pipeline independently. The schema index has no home.

## Decision

Extract the schema-walking logic into `Orchestration::UpstreamSchemaIndex`.

**Interface:** a single query method keyed by step action (the finest grain; step-level views are derivable from it):

```ruby
index = Orchestration::UpstreamSchemaIndex.build(pipeline)
index.schemas_before(step_action)  # → { "_initial" => ..., "classify_result" => ... }
```

**Injection over self-construction:** the index is built once by the caller (controller or coordinator) and injected into both `Pipeline::Validator` and `StepsListComponent`. This eliminates the redundant DB walk — the associations are already eager-loaded by the time the component renders, and the Validator currently re-queries them independently.

**Namespace:** `Orchestration::UpstreamSchemaIndex` (top-level within orchestration, not nested under `Pipeline`). The index is a read-model consumed by components and services at different levels; nesting it under `Pipeline` would misrepresent it as an implementation detail of the model.

## Consequences

- `Pipeline::Validator` stops owning the schema walk and becomes a pure consumer of the index.
- `StepsListComponent` drops `compute_upstream_schemas_per_step` and receives `index:` instead.
- The controller that renders the pipeline detail page builds the index once and passes it to both.
- Tests for `Validator` and `StepsListComponent` can share a single index fixture rather than duplicating pipeline setup.
