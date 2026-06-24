# CreateExperimentFromDraft#call is not wrapped in a transaction

**Status:** draft

**Source:** `lib/evaluation/create_experiment_from_draft.rb:18`

`Evaluation::CreateExperimentFromDraft#call` performs several writes: it resolves or creates a prompt, creates an experiment record, enqueues `ExperimentJob`, and destroys the draft. These steps are not wrapped in a database transaction. A failure after `create_experiment!` but before `draft.destroy` leaves an orphaned draft; a failure after `draft.destroy` but before the job is enqueued means the experiment is never run.

**Suggested approach:** wrap `resolve_prompt`, `create_experiment!`, and `draft.destroy` in `ActiveRecord::Base.transaction`. Enqueue `ExperimentJob` in an `after_commit` callback or via Rails 8 `after_create_commit` to guarantee the job fires only once the transaction commits.
