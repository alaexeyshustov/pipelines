# SchemaBuildersController is too long

**Status:** draft

**Source:** `app/controllers/orchestration/schema_builders_controller.rb`

`Orchestration::SchemaBuildersController` accumulates many actions covering the full schema-builder UI (building, adding/removing properties, editing nodes, enum management, etc.). The class is long enough to need a `rubocop:disable Metrics/ClassLength` suppression. Each action mixes param parsing, schema mutation, and response rendering inline.

**Suggested approach:** extract shared param-parsing and schema-mutation helpers into private service objects or a dedicated form object, keeping each action a thin delegator.
