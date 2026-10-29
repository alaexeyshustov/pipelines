# ADR 0012: Grade and gate with native RubyLLM evaluation

## Status
Accepted (GH #194; research in `doc/researches/rubyllm-evaluation.md`, plan in `doc/researches/rubyllm-evaluation-plan.md`)

## Context

The subsystem had a hand-rolled judge: `LLMJudgeEval` asked a chat model for a JSON array of 1-5 scores and justifications, `JudgeResponseParser` parsed it, `JudgeResultWriter` stored it. RubyLLM 2.1 ships `RubyLLM::Judge` (probability, score and choice questions answered from a judgment model's decision distributions) and `RubyLLM::Evaluation` (cases, evidence capture, criteria, RSpec/Minitest integration). Principle: use RubyLLM's implementation wherever it exists and keep custom code only where it has no alternative. No historical data is migrated; the 1-5 scale is not worth keeping.

## Decision

**Grading is `Evaluation::Grader` over a native `RubyLLM::Judge`.** One question per active `Metric`, built at runtime into the `questions:` hash of `Judge#judge` (`Evaluation::Judge::Questions`), one judgment call per sample. `Metric` gains `kind` (`probability` default, `score`, `choice`), `levels` (JSON) and `minimum` (0.0..1.0, nullable pass threshold); `weight` is reused.

**One normalized grade.** RubyLLM keeps native values and offers counts and `pass_rate`, not a single grade. We add `GradeNormalizer` (every answer to 0.0..1.0, higher is better: probability as is, `score / (levels - 1)`, choice as the probability-weighted option values, unknown excluded) and `SampleGrade` (weighted mean by `Metric#weight`). `EvaluationResult#score` stores the normalized value; `raw`, `confidence` and `passed` store the native answer, the judge's confidence and the verdict against `minimum`. `passed` compares the normalized score with `minimum` for every kind (the native `Result#decision` compares raw `Score#score`); the dashboard shows percentages next to the pass rate.

**Justifications are derived.** `Judge#probability/#score/#choice` return distributions with no free text, and the OpenAI decisions payload has none. We do not add a second reviewer pass (extra cost, a second source of truth). The justification text is built from the native answer: metric, percentage, closest level or chosen option description, confidence, distribution. `PromptImprover` consumes that text.

**Judge model.** `gpt-6-luna` (`LlmModels.judge`, overridable by `JUDGE_LLM_MODEL` or the setting), called through the decisions protocol; `Judge::ModelChoice` falls back to `LlmModels.judge`, then RubyLLM's `default_judgment_model` (`jev-latest`) when an old experiment carries a plain chat model.

**Usage ledger.** Every LLM call of an experiment runs inside `Evaluation::UsageScope` (`RubyLLM.with_usage_owner(experiment)`), so `ruby_llm_usages` rows are owned by the experiment; `ExperimentUsageQuery` sums tokens and cost. Auxiliary chats (improver, extractor, suggester) use structured output and `with_fallbacks`.

**Native `RubyLLM::Evaluation` is used twice.** The sampler runs the agent as `perform` and reads the captured `Evidence`; the regression gate (`spec/evals/**`) declares golden cases and criteria and runs through `RubyLLM::Evaluation::RSpec`. Both build cases with `Evaluation::DatasetCases` from `DatasetSample`. The gate is excluded from the default `rspec` run (tag `:eval`, opt in with `EVALS=1`).

**Monitoring filter.** `ruby_llm-monitoring` JSON-dumps event payloads; native evaluation events carry live `Report`/`Trial` objects that recurse without end. `config/initializers/ruby_llm_monitoring.rb` adds `report` and `trial` to its `FILTERED_PAYLOAD_KEYS`.

**Removed:** `LLMJudgeEval`, `Judge::Agent`, `JudgeResponseParser`, `JudgeResultWriter`, the `sampling`/`evaluating` states ([ADR 0009](0009-experiment-phases-and-partial-sampling-threshold.md)).

## Trade-offs considered

**Probability calibration**: probabilities are not calibrated across judgment models, and the weighted mean is our design, not RubyLLM's. Keep weights and `minimum` under review after real runs and compare experiments only on the same judge model.

**Derived vs. model-written reasons**: derived text is deterministic and free but less insightful than prose. It names the level or option description that decided the grade, which is what the improver needs.

**Vendor dependency**: grading needs a judgment-capable model; the fallback keeps old experiments runnable.

**API churn**: `RubyLLM::Judge` and `Evaluation` are new (2.1); gem-facing code is confined to `lib/evaluation` and `Evaluation::Sampler`, with RBS shims in `sig/shims/ruby_llm_{judge,evaluation,accounting}.rbs`.

**Sequential native runner**: `RubyLLM::Evaluation.run` is sequential, so production runs keep our job fan-out and call the native pieces per sample.
