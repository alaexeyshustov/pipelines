# Evaluations — AI Agent Quick Reference

The Evaluations subsystem measures the quality of AI agent outputs. Grading and the regression gate use RubyLLM's native evaluation primitives (`RubyLLM::Judge`, `RubyLLM::Evaluation`); experiments, datasets, prompt versions, the dashboard and the job fan-out are in-app. See [ADR 0012](adr/0012-native-rubyllm-evaluation.md).

Inside `module Evaluation` always write `RubyLLM::Evaluation` fully qualified (the bare name resolves to our namespace).

## Infrastructure

Domain logic lives in `app/models/evaluation/`, `app/services/evaluation/`, `app/jobs/evaluation/`, and `lib/evaluation/`.

### Key Models

- **Evaluation::Dataset**: A collection of input/expected-output pairs used for testing agents.
- **Evaluation::DatasetSample**: A single test case within a dataset. Holds `input` (JSON fed to the agent) and `expected_tool_calls` (nullable JSON — present when seeded from a production run, absent for synthetic inputs). There is no reference-answer column.
- **Evaluation::Prompt**: Versioned system instructions for an agent. Each version is an immutable snapshot of `system_prompt`, `user_prompt`, and `output_schema` captured at the moment the version was created. Also used by the orchestration subsystem to supply the active prompt to agents at runtime.
- **Evaluation::Experiment**: A single run of the sampler and judge against a dataset. Carries `sample_model` (the agent model) and `evaluation_model` (the judge model). AASM state machine: `pending → running → completed` (or `failed`). One counter, `pending_samples_count`, tracks unfinished samples.
- **Evaluation::Sample**: The sampler's output for one dataset sample. Holds `tool_calls` (tool name, arguments, result per call) and `output` (the agent's final response). Belongs to `Experiment`, `DatasetSample`, and `Prompt`. A sample exists only while its grading is pending or done: a failed sample is deleted.
- **Evaluation::EvaluationResult**: One metric grade for one sample. `score` is **normalized 0.0..1.0** (higher is better); `raw` holds the native answer (`to_h`), `confidence` the judge's confidence (nil for probabilities), `passed` the verdict against `Metric#minimum` (nil when no minimum).
- **Evaluation::Metric**: A rubric scoped to an agent. `kind` is `probability` (yes/no, default), `score` (ordered `levels`, an array of descriptions) or `choice` (`levels` is `{option => {description, value}}`). `minimum` (0.0..1.0, nullable) is the per-metric pass threshold; `weight` weights the metric in the sample grade.
- **Evaluation::Justification**: Text reason for a result. Derived, not model-written (see Grading).

## Evaluation Process

1. **Dataset creation**: Historical action runs or curated/synthetic examples become `DatasetSample` rows.
2. **Fan-out**: `Evaluation::ExperimentJob` starts the experiment (`pending → running`), sets `pending_samples_count` to the dataset size and enqueues one `Evaluation::SampleJob` per dataset sample.
3. **Per sample** (`SampleJob`, inside `Evaluation::UsageScope`): `Evaluation::Sampler` runs the agent, then `Evaluation::Grader` judges the sample and `Grader::ResultWriter` stores the results and justifications in one transaction. Then the job decrements the counter.
4. **Completion**: the job that brings the counter to zero completes the experiment if at least 80% of dataset samples are fully graded (`Experiment::COMPLETION_THRESHOLD`); otherwise it fails it.

## Jobs

- **Evaluation::ExperimentJob**: starts the run and enqueues the `SampleJob`s. Re-run on a `running` experiment it re-enqueues only samples that have no `Sample` yet, and only when no `SampleJob` of that experiment is still queued or claimed.
- **Evaluation::SampleJob**: sample, grade, persist, release the slot. Idempotent: an existing `Sample` is reused and grading that already ran is skipped.
- **Retry policy**: RubyLLM already retries HTTP failures and falls back across models, so a `RubyLLM::Error` that reaches the job is final: the half-finished sample is deleted, the slot is released, no job retry. Only raw transport errors (`Faraday::ConnectionFailed`, `Faraday::TimeoutError`, `Net::OpenTimeout`, `Net::ReadTimeout`) get one outer retry (`attempts: 2`); when it is exhausted the slot is released the same way. A run therefore always finishes.

## Sampler

`Evaluation::Sampler` (`app/services/evaluation/sampler.rb`) runs the agent as the body of a native `RubyLLM::Evaluation` (`evaluator false`: sampling only) built from `DatasetCases.for_sample`, and persists the captured `Evidence` (messages, tool calls, results) as an `Evaluation::Sample`. Write tools (`readonly?` false) are replaced by a no-op returning `"[write tool blocked during sampling]"`.

## Grading

- **`Evaluation::Grader`** (`lib/evaluation/grader.rb`) builds one native `RubyLLM::Judge#judge` call per sample with one question per active metric of the agent (`Evaluation::Judge::Questions`), the sample payload as input (`Judge::Input`: instructions, input, expected and actual tool calls, output, output schema; tool calls are omitted when `expected_tool_calls` is nil), and returns `Array[Grade]`. The judge model is `experiment.evaluation_model`, resolved by `Judge::ModelChoice` (must have the `judgment` capability, falling back to `LlmModels.judge` and then RubyLLM's `default_judgment_model`).
- **Normalization** (`Evaluation::GradeNormalizer`): `Probability` → its probability; `Score` → `score / (levels - 1)`; `Choice` → `sum(probability_i * value_i)` using per-option `value` (an option with `"pass" => true` and no value counts 1.0); `nil` (unknown) is excluded.
- **Sample grade** (`Evaluation::SampleGrade`): weighted mean of the metric scores by `Metric#weight`; nil when nothing is gradeable. Experiment grade is the mean over samples; the dashboard shows percentages next to the pass rate (`PassRateQuery`, `MetricPassRateQuery`).
- **Justifications**: `Judge#probability/#score/#choice` return distributions with no free text. The justification is built from the native answer (metric, percentage, closest level or chosen option description, confidence, distribution). There is no second reviewer pass. `Evaluation::PromptImprover` reads these.
- **Usage**: every LLM call of an experiment runs inside `Evaluation::UsageScope.call(experiment)` so `ruby_llm_usages.owner` points at it; `Evaluation::ExperimentUsageQuery` sums tokens and cost for the dashboard.

## Regression gate

`spec/evals/**` holds native `RubyLLM::Evaluation` classes (`Evaluation::Regression::*Evaluation`, base in `spec/evals/support/agent_evaluation.rb`). Each pins one code-defined agent (`Orchestration::Agents::*`) to a few golden cases built with `Evaluation::DatasetCases.for_sample`, runs it tool-free, and grades it with declared criteria (`evaluation :name, "...", minimum:`) on a `RubyLLM::Judge` using `LlmModels.judge`. The spec files wire them with `extend RubyLLM::Evaluation::RSpec; evaluates described_class`.

- Default `bundle exec rspec`: only the offline examples run (cases load, agent builds tool-free). The live examples are tagged `:eval` and excluded in `spec/rails_helper.rb`; nothing hits the API.
- Run the gate: `EVALS=1 OPENAI_API_KEY=... MISTRAL_API_KEY=... bundle exec rspec spec/evals`. Needs real provider keys. Interactions are recorded to `spec/cassettes/evals/*.yml` (VCR `new_episodes`) and replayed afterwards; delete a cassette to re-record. Check that cassettes hold no secrets before committing (VCR filters the known key env vars).
- Add a case: append to the agent's `golden [...]`. Add an agent: subclass `AgentEvaluation` (`agent`, `golden`, `evaluation`) and add a matching `*_evaluation_spec.rb`.

## Prompt Versioning

`Evaluation::Prompt` rows are immutable snapshots. A new version is created exclusively by `Evaluation::PromptImprover` when it generates an improved prompt. At creation time, `output_schema` is copied from the associated `Orchestration::Agent`, making the version a complete point-in-time snapshot of the agent's evaluation configuration.

`Evaluation::AutoEvalTriggerable` (included in `Evaluation::Prompt`) fires `Evaluation::PromptAutoEvalJob` after each new version is committed, automatically triggering a regression experiment.

## Automated Evaluations

`Evaluation::PromptAutoEvalJob` triggers an experiment whenever a new `Evaluation::Prompt` version is created, ensuring no regression in agent performance goes undetected.

## Model Configuration

| Field | Where | Replaces |
|---|---|---|
| `experiment.sample_model` | `evaluation_experiments` | `DEFAULT_MODEL` env var |
| `experiment.evaluation_model` | `evaluation_experiments` | `JUDGE_LLM_MODEL` env var (`LlmModels.judge`, default `gpt-6-luna`, is the fallback when it is blank or not a judgment model) |
| `EVALUATION_LLM_MODEL` env var | stays as env var | used by `MetricSuggester`, `MetricExtractor`, `SyntheticDatasetJob`, `PromptImprover` — not scoped to a single experiment |

## Metrics and Rubrics

Metrics are scoped to agents. You can define rubrics for `Emails::ClassifyAgent` that differ from `Emails::MappingAgent`. Metrics can be activated/deactivated as needed. `MetricSuggester` and `MetricExtractor` use structured output (`with_schema`) and the suggester proposes `kind` and its `levels` or `options`.
