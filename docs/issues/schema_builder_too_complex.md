# SchemaBuilder is too big and complex

**Status:** draft

**Source:** `app/models/orchestration/schema_builder.rb`

`Orchestration::SchemaBuilder` has grown beyond a single responsibility. The class handles type resolution, mutation traversal, property management, enum/range validation, and schema serialization all in one place. It is long enough to require a `rubocop:disable Metrics/ClassLength` suppression. The complexity makes it hard to follow individual paths and adds friction when adding new schema node types.

**Suggested approach:** identify distinct concerns (e.g. mutation/traversal, validation, serialization) and extract them into collaborating classes or modules.
