# ADR 0009: Explicit experiment phases and 80% partial-sampling threshold

## Status
Accepted

## Context

Previously, sampling and evaluation were coupled in a single `RunEvalJob`: one job would sample one record then immediately evaluate it. This prevented batch-level evaluation and made the experiment status a single `running` state with no visibility into which phase was active.

A natural question when splitting phases is: what happens if some sampling jobs fail? Failing the entire experiment on any single failure is too strict for a subsystem where occasional LLM or tool timeouts are expected.

## Decision

Experiments progress through four explicit phases: `pending → sampling → evaluating → completed` (or `failed`). Sampling must fully complete before evaluation starts.

An `Experiment` tracks a `pending_samples_count` counter initialised to `dataset.dataset_samples.count`. Each sampling job decrements it atomically (under `with_lock`) on success or on retries exhausted. When the counter reaches zero, the last job evaluates the threshold: if `completed_samples >= total * 0.8`, the experiment transitions to `evaluating` and enqueues evaluation jobs; otherwise it transitions to `failed`.

## Trade-offs considered

**Fail-fast vs. partial results**: failing the whole experiment on any single sample failure is simpler but too sensitive to transient errors. 80% ensures a statistically meaningful sample for scoring while tolerating occasional failures.

**Coordinator job vs. atomic counter**: a coordinator job with a deadline introduces timing assumptions and fires even while jobs are still retrying. The atomic counter is precise — the transition fires exactly when the last attempt (success or exhausted) completes.

**Threshold value**: 80% is a starting point. It is not configurable per-experiment intentionally — adding per-experiment thresholds complicates the wizard and the failure contract without clear benefit at this scale.
