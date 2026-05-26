# Application Pipeline

A Rails application that fetches job-application emails from Gmail and Yahoo Mail, classifies them with an AI agent, labels them in-provider, and tracks application/interview progress.

## Language

### Email processing

**Email connector**: A configured integration with a mail provider (Gmail, Yahoo Mail) that can fetch messages.
_Avoid_: integration, mail account

**Application mail**: A fetched email record that has been identified as job-application-related.
_Avoid_: email record, mail record

### Orchestration

**Pipeline**: A named sequence of steps that processes email data end-to-end.
_Avoid_: workflow, process

**Step**: One unit of work within a pipeline, bound to an action.
_Avoid_: task, stage

**Action**: A reusable unit of work (agent call or service call) that a step can invoke.
_Avoid_: task, operation

**Agent**: An LLM-backed actor that receives a prompt and produces structured output.
_Avoid_: model, LLM, AI

**Agent snapshot**: An immutable record of the model, prompt, tools, and schema an agent used for a specific run — captured at execution time.
_Avoid_: agent state, agent config

### Evaluation (Leva)

**Experiment**: A single evaluation run of an agent against a dataset using one specific prompt version. Progresses through four phases: `pending → sampling → evaluating → completed` (or `failed`).
_Avoid_: eval run, test run

**Prompt version**: A versioned, named snapshot of a system prompt and user prompt stored in `leva_prompts`. Each improvement produces a new version; the version number auto-increments.
_Avoid_: prompt, instructions

**Dataset**: A named collection of dataset samples used as test cases for an experiment.
_Avoid_: test set, sample set

**Dataset sample**: A single test case within a dataset. Holds the `input` fed to the agent and an optional `expected_tool_calls` trace (present when seeded from a production run, absent for synthetic inputs).
_Avoid_: dataset record, test record, test case

**Sample**: The sampler's output for one dataset sample — the full execution trace captured during sampling: tool calls with arguments and real results, and the agent's final output.
_Avoid_: runner result, prediction

**Sampler**: The component that runs an agent against a dataset sample with real tool calls. Write tools (those where `readonly?` returns false) are blocked and return a sentinel value; read tools execute normally.
_Avoid_: runner, agent runner

**Metric**: A named rubric scoped to an agent that defines one dimension of output quality (e.g. "Tag Relevance"). Scored 1–5 by the judge. Metrics are a prerequisite for creating an experiment — if none exist for an agent, they must be generated before the experiment is created.
_Avoid_: criterion, rule, dimension

**Judge**: The LLM instance that scores a sample against the active metrics for an experiment. When `expected_tool_calls` is present on the dataset sample, the judge compares actual vs. expected tool-calling behaviour as one dimension of quality. Configured via `JUDGE_LLM_MODEL`.
_Avoid_: evaluator LLM, scoring model

**Justification**: The judge's written reasoning for the score it assigned on one metric for one sample.
_Avoid_: explanation, rationale

**Improvement**: An LLM-generated revision of a prompt version, produced by `PromptImprover` from the scores and justifications of a completed experiment. The improver agent can call tools to inspect the full experiment history for the same agent — enabling it to understand direction before generating its revision.
_Avoid_: refinement, update, optimization

**Experiment history**: The set of all completed experiments for a given agent, excluding the experiment currently being improved. Exposed to `PromptImprover`'s agent via three tools: `list_experiments` (score trajectory), `get_experiment_justifications` (full per-sample reasoning), and `get_experiment_prompt` (exact prompt text used). Failed experiments are excluded — failures are infrastructure issues, not prompt signal.
_Avoid_: past runs, previous evals

**Auto-eval**: An experiment automatically triggered when a new prompt version is created, using the same dataset as the previous experiment. Provides immediate feedback on whether the improvement helped.
_Avoid_: automated experiment, post-improvement eval

**Output schema**: The fixed structured-output contract enforced at the API level for an agent (e.g. `{"results": [{"id": ..., "tags": [...]}]}`). Prompt instructions cannot override it.
_Avoid_: response format, output format, JSON shape

**Input schema**: A JSON Schema object that declares what keys and types a step action must supply when invoking an action. For agent-kind actions it is stored on the `Agent` record; for service-kind actions it is derived at load time from the service class's `input_schema` DSL declaration and its `call` keyword arguments. The schema drives both static pipeline validation (missing required inputs) and runtime validation before execution.
_Avoid_: params, input contract, required fields

**Input mapping**: A per-step-action hash that maps each input key the action expects to a source spec. Each spec is one of: `{from:, path:}` (resolve from a prior step's output), `{from: "_initial", path:}` (resolve from the pipeline's initial input), or `{value:}` (inline literal value). Required keys from the action's input schema must be covered by the mapping.
_Avoid_: params, step params, action params

**Executable**: A concern included by service classes that participate in the orchestration pipeline. Provides the `input_schema(types)` DSL to declare parameter types; the schema is derived at first access by cross-referencing the declared types against the `call` method's keyword arguments, raising at load time if they diverge.
_Avoid_: service interface, callable

## Relationships

- A **Pipeline** has one or more **Steps**; each **Step** is bound to one **Action**
- An **Action** may reference an **Agent** (agent-kind) or invoke a service directly (service-kind)
- An **Action** exposes an **Input schema** — sourced from the agent record or derived from the service class
- A **Step action** has an **Input mapping** that satisfies the action's **Input schema** required keys
- An **Experiment** uses one **Dataset** and one **Prompt version**
- A **Dataset** contains one or more **Dataset samples**; each holds an input and optional expected tool call trace
- The **Sampler** produces one **Sample** per **Dataset sample** during the sampling phase
- An **Experiment** produces one **Justification** per **Metric** per **Sample** during the evaluating phase
- **Metrics** must exist for an agent before an experiment can be created
- A **Prompt version** has a fixed **Output schema** that the **Judge** must not contradict when evaluating format compliance
- Each **Improvement** creates a new **Prompt version** and triggers an **Auto-eval**
- `PromptImprover` passes the current experiment's scores and justifications in the initial message; **experiment history** is accessible on-demand via tools scoped to the same agent

## Example dialogue

> **Dev:** "The auto-eval for the new prompt version scored lower on Tag Relevance — should I trigger another improvement?"
> **Domain expert:** "Check the justifications first. If the judge flagged format non-compliance, the issue is probably an output schema mismatch, not tag quality. Fix the schema constraint in the improver before re-running."

## Design decisions

### Evaluation wizard

**`Evaluation::WizardForm`** encapsulates all multi-step wizard logic: finding or creating the draft, extracting step params, building step-specific forms, and finalising the experiment from the draft. It receives `wizard_token:` as a plain string — the controller owns reading and writing `session[:wizard_token]`.

**`Evaluation::WizardComponent`** accepts `form: <WizardForm>` and `current_step:` and decides internally which step sub-component to render. The view template (`new.html.erb`) stays unconditional; no dispatch logic leaks into it.

**`Evaluation::ExperimentDetailComponent`** accepts `experiment:` and exposes all derived display values (`agent_name`, `metrics`, `runner_result_count`, `per_metric_avg`, `runner_model`, `judge_model`, `newer_experiment`) as component methods, replacing the corresponding instance variables in `ExperimentsController#show`.

## Flagged ambiguities

- "prompt" is used loosely to mean both a raw instruction string and a versioned `Orchestration::Prompt` record — resolved: use **prompt version** for the DB record, **instructions** for the raw string value.
- "evaluation" can mean the full subsystem, a single experiment, or a single metric score — resolved: **evaluation** refers to the subsystem; use **experiment** for a run, **score** for a numeric result.
