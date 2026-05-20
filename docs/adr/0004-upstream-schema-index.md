---
status: proposed
---

# Name and extract the upstream schema index

"What schemas are available upstream of this step?" is the same question asked in at least three places: `Pipeline::Validator`, Rails model validation on `Pipeline`, `InputMappingUpdater` after an update, and `StepActionsController` to populate dropdowns. Each call site re-walks the full pipeline independently. The schema index has no home.

Extract the schema-walking logic into a named module (e.g., `UpstreamSchemaIndex`) that builds the map once from a pipeline and exposes a query interface. `Pipeline::Validator` becomes a consumer of that index rather than the owner of the walk. The dropdown renderer and the validator share the same index without duplicating fixture setup in their respective tests.
