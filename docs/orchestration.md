# Orchestration — AI Agent Quick Reference

The Orchestration subsystem manages the definition and execution of multi-agent workflows (Pipelines).

## Key Models

The subsystem is located in `app/models/orchestration/`:

- **Pipeline**: The top-level definition of a workflow.
- **Step**: A discrete stage within a pipeline. Steps are executed sequentially.
- **Action**: Defines what happens in a step. An action can be an **Agent** call or a specific Ruby **class/method**.
- **Agent**: A configuration for an AI agent, including its name, enabled status, and allowed tools.
- **Prompt**: Versioned system instructions for agents. Each agent can have multiple prompt versions.
- **PipelineRun / StepRun / ActionRun**: Tracks the execution history and status of pipelines, steps, and actions.

## Workflow Execution

1.  A `Pipeline` is composed of multiple `Steps`.
2.  Each `Step` contains `Actions`.
3.  When a `PipelineRun` starts, it creates `StepRuns`.
4.  Each `StepRun` executes its `ActionRuns`.
5.  Status is tracked from `pending` to `running`, and finally `completed` or `failed`.

## Agents and Tools

Orchestration Agents (`Orchestration::Agent`) are restricted to specific tool namespaces:
- `Records`
- `Emails`

A tool is usable only if it is registered in `Orchestration::ToolResolver::REGISTRY`. Stored tool names are looked up there with `ToolResolver.lookup(name)`, which raises `ArgumentError` for anything else; stored names are never constantized. `Orchestration::Agent` validates tool names against `Agent.available_tools` (the files under `app/tools`), and a spec keeps that list equal to the registry keys, so a new tool file must be registered. Caller-supplied `tool_classes:` (e.g. the Sampler's write-blocked subclasses) bypass the registry.

### Untrusted input

Agent input (email subjects, bodies, record fields) is untrusted. `Orchestration::RuntimeAgentBuilder` always prepends `UNTRUSTED_INPUT_PREAMBLE` to the agent's instructions (also for prompt overrides and empty prompts), telling the model to treat input as data and ignore instructions inside it. `Emails::HtmlText` drops hidden elements, scripts, styles and comments before email HTML reaches a model. Tools also limit what a model can do: `Records::TempFileTool` is confined to `tmp/agent_scratch/`, `Emails::GetTool` caps bodies at 32 KB, `Emails::AddLabelsTool` rejects TRASH, SPAM and IMAP flags other than `\Flagged`/`\Seen`, and record tools can read `id` but not write it.

## Service steps

Service actions (`kind: service`) run a class from `Orchestration::ServiceRegistry` (`lib/orchestration/executors/`). Example: "Email Ingestion" (cron `*/30 * * * *`) runs `Orchestration::Executors::EmailsSync`, which calls `Email::SyncInboxJob` for `gmail` and `yahoo`. The ActionRun output is `{ "gmail" => {mode, fetched, stored, duplicates, failed, enqueued}, "yahoo" => ... }` (`enqueued` is 0 until processing is wired in); a provider without credentials is `{ "skipped" => true, "reason" => "no credentials" }`. A failing provider does not stop the other; afterwards the step raises `ProviderFailure`. A failed ActionRun stores no output, only its error text, so that error carries the per-provider output as JSON.

## Configuration

Pipelines and Actions can be configured via the Web UI:
- `/orchestration/pipelines`
- `/orchestration/actions`

New steps can be added to existing pipelines, and actions can be assigned to those steps to build complex automated workflows.

## Evaluation hooks

The evaluation subsystem ([evals.md](evals.md)) depends on orchestration, never the reverse (see [ADR 0011](adr/0011-archspec-layers.md)).

- `Orchestration::SamplingGateway.build` builds an agent from an `Agent`/`Action` record with an optional prompt override, model override and `tool_transform` (used to block write tools). `Evaluation::Sampler` calls it from inside a native `RubyLLM::Evaluation#perform`.
- `Orchestration.prompt_resolver` is injected by an initializer to serve the active `Evaluation::Prompt` at runtime.
- Experiments run as one `Evaluation::SampleJob` per dataset sample (`pending → running → completed | failed`, one `pending_samples_count` counter, 80% completion threshold). Retry policy: no job retry on `RubyLLM::Error` (RubyLLM retries and falls back itself); one outer retry for raw transport errors; the job always releases its counter slot.
- LLM usage of an experiment is attributed with `Evaluation::UsageScope`; orchestration runs outside an experiment have no usage owner.
