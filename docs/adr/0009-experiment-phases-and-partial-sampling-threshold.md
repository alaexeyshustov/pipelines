# ADR 0009: Single running state, one counter, and 80% completion threshold

## Status
Accepted (amended by GH #194; originally four phases `pending → sampling → evaluating → completed`)

## Context

Sampling and evaluation were once coupled in a single `RunEvalJob`, which prevented batch-level evaluation. The first fix split the run into two phases (`sampling`, `evaluating`) with two jobs (`SamplingJob`, `EvaluationJob`) and two counters (`pending_samples_count`, `pending_evaluations_count`). The split bought no batch-level behaviour: grading is per sample, RubyLLM has no batch judge, and the phase barrier only delayed grading until the slowest sample finished. It also doubled the failure modes (a sample could fail in either phase).

A natural question remains for any fan-out: what happens if some samples fail? Failing the entire experiment on any single failure is too strict for a subsystem where occasional LLM or tool timeouts are expected.

## Decision

Experiments progress through `pending → running → completed` (or `failed`). One job per dataset sample, `Evaluation::SampleJob`, runs the sampler and then the grader, so a sample is either fully graded or absent.

An `Experiment` tracks a single `pending_samples_count`, initialised to `dataset.dataset_samples.count`. Each `SampleJob` decrements it atomically (under `with_lock`) on success or when it gives up (final `RubyLLM::Error`, or transport retries exhausted); a failed job deletes its half-finished `Sample` first. When the counter reaches zero, the last job completes the experiment if `samples.count >= dataset_samples.count * 0.8` (`Experiment::COMPLETION_THRESHOLD`), otherwise it fails it. Because only fully graded samples survive, the 80% now counts fully graded samples, not merely sampled ones.

Retries: RubyLLM retries HTTP failures and falls back across models, so the job does not `retry_on RubyLLM::Error`. Only raw transport errors get one outer retry. The job always releases its slot so the run terminates.

## Trade-offs considered

**Phases vs. one running state**: explicit phases gave progress visibility but no batch semantics; progress is still visible as `pending_samples_count` against the dataset size. Experiments in the removed `sampling`/`evaluating` states are not migrated.

**Fail-fast vs. partial results**: failing the whole experiment on any single sample failure is simpler but too sensitive to transient errors. 80% ensures a statistically meaningful sample for scoring while tolerating occasional failures.

**Coordinator job vs. atomic counter**: a coordinator job with a deadline introduces timing assumptions and fires even while jobs are still retrying. The atomic counter is precise: the transition fires exactly when the last attempt (success or given up) completes.

**Threshold value**: 80% is a starting point. It is not configurable per-experiment intentionally; adding per-experiment thresholds complicates the wizard and the failure contract without clear benefit at this scale.
