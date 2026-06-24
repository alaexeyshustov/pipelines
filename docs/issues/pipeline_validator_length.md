# PipelineValidator is too long

**Status:** draft

**Source:** `lib/orchestration/pipeline_validator.rb`

`Orchestration::PipelineValidator` validates an entire pipeline — step ordering, input/output schema compatibility, mapping keys, circular dependencies — in one class, requiring a `rubocop:disable Metrics/ClassLength` suppression.

**Suggested approach:** split validation concerns by domain (step ordering, schema compatibility, mapping resolution) into separate validator objects that `PipelineValidator` composes, making each concern independently testable.
