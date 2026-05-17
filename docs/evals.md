# Evaluations — AI Agent Quick Reference

The Evaluations subsystem provides tools to measure and ensure the quality of AI agent outputs.
It is implemented entirely in-app — no third-party eval framework gem.

## Infrastructure

Domain logic lives in `app/evals/`, `app/models/evaluation/`, `app/runners/`, and `app/jobs/evaluation/`.

### Key Models

- **Evaluation::Dataset**: A collection of input/expected-output pairs used for testing agents.
- **Evaluation::DatasetRecord**: A single record in a dataset, polymorphically linked to a `recordable` (e.g. `Orchestration::ActionRun`).
- **Evaluation::Prompt**: Versioned system instructions for an agent. Each version is an immutable snapshot of `system_prompt`, `user_prompt`, and `output_schema` captured at the moment the version was created. Also used by the orchestration subsystem to supply the active prompt to agents at runtime.
- **Evaluation::Experiment**: A single run of a runner against a dataset. Carries `sample_model` (the agent model used during sampling) and `evaluation_model` (the judge LLM model).
- **Evaluation::RunnerResult**: The agent's raw prediction for one dataset record during an experiment.
- **Evaluation::EvaluationResult**: The numeric score assigned to a runner result by an evaluator.
- **Evaluation::Metric**: Defined rubrics (e.g. "Accuracy", "Tone") scoped to an agent, used by the judge.
- **Evaluation::Justification**: The judge LLM's reasoning for each assigned score.

## Evaluation Process

1. **Dataset Creation**: Historical chat data or curated examples are added to an `Evaluation::Dataset`.
2. **Experiment Execution**: A runner processes each dataset record using the agent configured with `sample_model`.
3. **Judging**: `LLMJudgeEval` takes the agent's output and calls a judge LLM (configured per-experiment via `evaluation_model`).
4. **Scoring**: The judge returns a JSON array of scores (1–5) and justifications for each active metric.
5. **Storage**: Results are stored in `evaluation_runner_results`, `evaluation_evaluation_results`, and `evaluation_justifications`.

## Experiment Jobs

- **Evaluation::ExperimentJob**: Iterates all dataset records and schedules one `RunEvalJob` per record with staggered delays.
- **Evaluation::RunEvalJob**: Runs a single record through the runner and all evaluators, then marks the experiment complete when it is the last record.

## Runners and Evaluators

- **`BaseRun`** (`app/runners/base_run.rb`): Abstract interface. Subclasses implement `#execute(recordable)`. `execute_and_store` wraps the result in an `Evaluation::RunnerResult`.
- **`BaseEval`** (`app/evals/base_eval.rb`): Abstract interface. Subclasses implement `#evaluate(runner_result, recordable)`. `evaluate_and_store` wraps the score in an `Evaluation::EvaluationResult`.
- **`StubbedAgentRun`**: Runs the agent with tool calls stubbed against expected tool call sequences. Uses `experiment.sample_model` as the agent model.
- **`LLMJudgeEval`**: Calls a judge LLM (via `experiment.evaluation_model`) to score agent responses against active metrics.

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
