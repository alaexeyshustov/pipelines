# Evaluations (Leva) — AI Agent Quick Reference

The Evaluations subsystem (internally referred to as **Leva**) provides tools to measure and ensure the quality of AI agent outputs.

## Infrastructure

The subsystem integrates the `leva` gem and adds domain-specific logic in `app/evals/` and `app/models/evaluation/`.

### Key Parts

- **Leva::Dataset**: A collection of input/expected-output pairs used for testing agents.
- **Leva::Experiment**: A single run of an evaluator against a dataset using a specific agent version/prompt.
- **LLMJudgeEval**: A specialized evaluator (`app/evals/llm_judge_eval.rb`) that uses a "Judge LLM" to score agent responses based on custom metrics.
- **Evaluation::Metric**: Defined rubrics (e.g., "Accuracy", "Tone", "Extraction Quality") used by the Judge LLM.
- **Evaluation::Justification**: Stores the reasoning provided by the Judge LLM for each assigned score.

## Evaluation Process

1.  **Dataset Creation**: Historical chat data or curated examples are added to a `Leva::Dataset`.
2.  **Experiment Execution**: An agent processes the dataset records.
3.  **Judging**: The `LLMJudgeEval` takes the agent's output, compares it with expected tool calls and instructions, and calls a Judge LLM (configured via `JUDGE_LLM_MODEL`).
4.  **Scoring**: The Judge LLM returns a JSON array of scores (1-5) and justifications for each active metric.
5.  **Storage**: Results are stored in `leva_evaluation_results` and `evaluation_justifications`.

## Automated Evaluations

`Evaluation::PromptAutoEvalJob` allows for triggering evaluations automatically when prompts are updated, ensuring no regression in agent performance.

## Metrics and Rubrics

Metrics are scoped to agents. You can define specific rubrics for the `Emails::ClassifyAgent` that differ from the `Emails::MappingAgent`. Metrics can be activated/deactivated as needed.
