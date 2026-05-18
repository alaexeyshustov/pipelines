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

**Experiment**: A single evaluation run of an agent against a dataset using one specific prompt version.
_Avoid_: eval run, test run

**Prompt version**: A versioned, named snapshot of a system prompt and user prompt stored in `leva_prompts`. Each improvement produces a new version; the version number auto-increments.
_Avoid_: prompt, instructions

**Dataset**: A named collection of input records used as test cases for an experiment.
_Avoid_: test set, sample set

**Metric**: A named rubric scoped to an agent that defines one dimension of output quality (e.g. "Tag Relevance"). Scored 1–5 by the judge.
_Avoid_: criterion, rule, dimension

**Judge**: The LLM instance that scores agent output against the active metrics for an experiment. Configured via `JUDGE_LLM_MODEL`.
_Avoid_: evaluator LLM, scoring model

**Justification**: The judge's written reasoning for the score it assigned on one metric for one dataset record.
_Avoid_: explanation, rationale

**Improvement**: An LLM-generated revision of a prompt version, produced by `PromptImprover` from the scores and justifications of a completed experiment.
_Avoid_: refinement, update, optimization

**Auto-eval**: An experiment automatically triggered when a new prompt version is created, using the same dataset as the previous experiment. Provides immediate feedback on whether the improvement helped.
_Avoid_: automated experiment, post-improvement eval

**Output schema**: The fixed structured-output contract enforced at the API level for an agent (e.g. `{"results": [{"id": ..., "tags": [...]}]}`). Prompt instructions cannot override it.
_Avoid_: response format, output format, JSON shape

## Relationships

- A **Pipeline** has one or more **Steps**; each **Step** is bound to one **Action**
- An **Action** may reference an **Agent** (agent-kind) or invoke a service directly
- An **Experiment** uses one **Dataset** and one **Prompt version**
- An **Experiment** produces one **Justification** per **Metric** per dataset record
- A **Prompt version** has a fixed **Output schema** that the **Judge** must not contradict when evaluating format compliance
- Each **Improvement** creates a new **Prompt version** and triggers an **Auto-eval**

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
