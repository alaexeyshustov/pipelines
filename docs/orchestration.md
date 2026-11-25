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

Service actions (`kind: service`) run a class from `Orchestration::ServiceRegistry` (`lib/orchestration/executors/`). An executor includes `Orchestration::Executable` and declares:

- `input_schema(**props)`, checked against its `initialize` keywords and validated before the step runs;
- `output_schema(**props)` (optional), the shape of the hash it returns: an object with every declared key required. It is not checked against `initialize`. `PipelineValidator.output_schema_for(action)` serves it (an agent action serves the agent's own), so the validator and the steps list can check the paths a later step maps from it;
- `self.run_hints` (optional), a `Hash` of input field to a line of text. `Orchestration::RunHints.call(pipeline)` asks the first action of the first enabled step and the pipeline page shows the text under that field of the run dialog (`EmailsList` shows when each provider was last synced).

Example: "Email Ingestion" (on demand, `config/pipelines/email_ingestion.json`, [ADR 0018](adr/0018-ingestion-steps-in-pipeline.md)) has six steps: `EmailsList`, `EmailsClassify`, `EmailsEmbed`, `AttachmentsIngest`, `DocumentsClassify`, `DocumentsEmbed`. They pass record ids, never records: step 1 outputs `{ "email_ids" => [...], "providers" => { "gmail" => {mode, fetched, stored, duplicates, failed}, ... } }` (a failed provider has the mode it attempted, or `unknown`, zero counts and an `error`; a skipped one only `mode: "skipped"`), steps 2 and 3 take those ids, step 4 outputs `document_ids` (it downloads only listed tagged emails (Gmail and Yahoo) that have no document yet; a failed attachment is not retried, since step 1 stops listing an email once it is tagged and embedded. It also lists the documents of the listed emails and every document of a tagged email left `pending`, `failed` or unembedded, so a later run finishes them), steps 5 and 6 take them. Each step works through its ids one record at a time and reports `failed: [{ "id", "error" }]` instead of failing (the embed steps also list as `skipped` the records that are not tagged or have no text); step 1 raises only when no requested provider worked (every one failed or lacked credentials). A failed ActionRun stores no output, only its error text, so that error carries the per-provider output as JSON.

Executors run inside `Async` tasks, and `ActiveSupport::CurrentAttributes` are isolated per fiber, so `PipelineRunner` sets `Orchestration::Current.pipeline_run` inside each task.

### Stale runs (heartbeat)

A run whose `PipelineRunJob` died (a deploy, a crash) stays `running` and would block `PipelineRunForm` and `SchedulerJob` for ever. `orchestration_pipeline_runs.heartbeat_at` is set when a run starts and before and after each step by `PipelineRunner`, and by the per-record loops of the executors, the per-message loop of `Email::InboxSync` and the per-attachment loop of `Document::IngestEmailAttachments` through `Orchestration::Heartbeat.beat` (at most once a minute; a no-op outside a run). A pending or running run whose heartbeat (else `started_at`, else `created_at`) is older than `PipelineRun::STALE_AFTER` (10 minutes) no longer blocks: `PipelineRun.blocking` is what `Pipeline#run_in_progress?` and `SchedulerJob` use. Only one item (one message fetch, one OCR call) that takes longer than that can make a live run look stale. A queued run that never started falls back to `created_at`, so it also stops blocking after 10 minutes (accepted). If `DocumentsEmbed`'s duplicate detection raises after the embedding succeeded, the document stays embedded, `Document::DetectDuplicatesJob` is enqueued and the id is also listed in `failed`.

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
