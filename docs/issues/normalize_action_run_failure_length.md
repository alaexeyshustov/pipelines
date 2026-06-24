# NormalizeActionRunFailure is too long — extract pure functions

**Status:** draft

**Source:** `lib/orchestration/normalize_action_run_failure.rb`

`Orchestration::NormalizeActionRunFailure` normalises diverse error shapes (provider HTTP errors, validation errors, generic exceptions) into a unified `Result`. The class needs a `rubocop:disable Metrics/ClassLength` suppression and mixes error-type detection logic with string-formatting and redaction helpers.

**Suggested approach:** extract error-type predicates and redaction/formatting helpers into pure module-level functions (or a small set of value objects), keeping the main class as a dispatcher that selects the right normalizer.
