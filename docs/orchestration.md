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

## Configuration

Pipelines and Actions can be configured via the Web UI:
- `/orchestration/pipelines`
- `/orchestration/actions`

New steps can be added to existing pipelines, and actions can be assigned to those steps to build complex automated workflows.
