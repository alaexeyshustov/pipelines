# PipelineRunner is too long

**Status:** draft

**Source:** `lib/orchestration/pipeline_runner.rb`

`Orchestration::PipelineRunner` handles step sequencing, input/output wiring, action dispatch, error recording, and run status updates in one class, needing a `rubocop:disable Metrics/ClassLength` suppression.

**Suggested approach:** extract step execution and output wiring into a `StepExecutor` collaborator, leaving `PipelineRunner` as a thin loop that sequences steps and persists run state.
