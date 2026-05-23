# Evaluations — AI Agent Quick Reference

The Evaluations subsystem provides tools to measure and ensure the quality of AI agent outputs.
It is implemented entirely in-app — no third-party eval framework gem.

## Infrastructure

Domain logic lives in `app/models/evaluation/`, `app/services/evaluation/`, `app/jobs/evaluation/`, and `lib/evaluation/`.

### Key Models

- **Evaluation::Dataset**: A collection of input/expected-output pairs used for testing agents.
- **Evaluation::DatasetSample**: A single test case within a dataset. Holds `input` (JSON fed to the agent) and `expected_tool_calls` (nullable JSON — present when seeded from a production run, absent for synthetic inputs).
- **Evaluation::Prompt**: Versioned system instructions for an agent. Each version is an immutable snapshot of `system_prompt`, `user_prompt`, and `output_schema` captured at the moment the version was created. Also used by the orchestration subsystem to supply the active prompt to agents at runtime.
- **Evaluation::Experiment**: A single run of the sampler against a dataset. Carries `sample_model` (the agent model used during sampling) and `evaluation_model` (the judge LLM model). Has an AASM state machine: `pending → sampling → evaluating → completed` (or `failed`).
- **Evaluation::Sample**: The sampler's output for one dataset sample. Holds `tool_calls` (full execution trace JSON: tool name, arguments, result for each call) and `output` (the agent's final response). Belongs to `Experiment`, `DatasetSample`, and `Prompt`.
- **Evaluation::EvaluationResult**: The numeric score (1–5) assigned to a sample by the judge.
- **Evaluation::Metric**: Defined rubrics (e.g. "Accuracy", "Tone") scoped to an agent, used by the judge.
- **Evaluation::Justification**: The judge LLM's reasoning for each assigned score.

## Evaluation Process

1. **Dataset Creation**: Historical action run data or curated/synthetic examples are added to an `Evaluation::Dataset` as `DatasetSample` rows.
2. **Sampling**: `Evaluation::Sampler` runs the agent against each dataset sample using `sample_model`. Write tools are blocked during sampling and return a sentinel string. The full tool call trace and final output are persisted as an `Evaluation::Sample`.
3. **80% threshold check**: Once all sampling jobs complete, the experiment transitions to `evaluating` only if at least 80% of samples were produced successfully. Otherwise it transitions to `failed`.
4. **Judging**: `LLMJudgeEval` takes each sample and calls a judge LLM (configured per-experiment via `evaluation_model`).
5. **Scoring**: The judge returns a JSON array of scores (1–5) and justifications for each active metric.
6. **Storage**: Results are stored in `evaluation_evaluation_results` and `evaluation_justifications`.

## Experiment Jobs

- **Evaluation::ExperimentJob**: Transitions the experiment to `sampling` and enqueues one `SamplingJob` per dataset sample.
- **Evaluation::SamplingJob**: Calls `Evaluation::Sampler` for a single dataset sample. When the last sampling job finishes, checks the 80% threshold and either transitions to `evaluating` (enqueuing one `EvaluationJob` per sample) or marks the experiment `failed`.
- **Evaluation::EvaluationJob**: Runs all evaluators against a single sample, then decrements the pending counter and marks the experiment `completed` when it reaches zero.

## Sampler and Evaluator

- **`Evaluation::Sampler`** (`app/services/evaluation/sampler.rb`): Runs the agent via `RuntimeAgentBuilder` using `experiment.sample_model`. Before execution, wraps each tool where `tool_class.readonly?` is false with a no-op that returns `"[write tool blocked during sampling]"` and logs the blocked call. Captures the full tool call trace and persists an `Evaluation::Sample`.
- **`Evaluation::Evaluators::LLMJudgeEval`** (`lib/evaluation/evaluators/llm_judge_eval.rb`): Calls a judge LLM to score agent responses against active metrics. Sources `expected_tool_calls` from `sample.dataset_sample.expected_tool_calls`; omits the tool-calling dimension from the judge prompt when `expected_tool_calls` is nil.

## Prompt Versioning

`Evaluation::Prompt` rows are immutable snapshots. A new version is created exclusively by `Evaluation::PromptImprover` when it generates an improved prompt. At creation time, `output_schema` is copied from the associated `Orchestration::Agent`, making the version a complete point-in-time snapshot of the agent's evaluation configuration.

`Evaluation::AutoEvalTriggerable` (included in `Evaluation::Prompt`) fires `Evaluation::PromptAutoEvalJob` after each new version is committed, automatically triggering a regression experiment.

## Automated Evaluations

`Evaluation::PromptAutoEvalJob` triggers an experiment whenever a new `Evaluation::Prompt` version is created, ensuring no regression in agent performance goes undetected.

## Model Configuration

| Field | Where | Replaces |
|---|---|---|
| `experiment.sample_model` | `evaluation_experiments` | `DEFAULT_MODEL` env var |
| `experiment.evaluation_model` | `evaluation_experiments` | `JUDGE_LLM_MODEL` env var |
| `EVALUATION_LLM_MODEL` env var | stays as env var | used by `MetricSuggester`, `MetricExtractor`, `SyntheticDatasetJob`, `PromptImprover` — not scoped to a single experiment |

## Metrics and Rubrics

Metrics are scoped to agents. You can define rubrics for `Emails::ClassifyAgent` that differ from `Emails::MappingAgent`. Metrics can be activated/deactivated as needed.
