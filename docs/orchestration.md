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

Tools must be valid Ruby classes that can be constantized.

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
