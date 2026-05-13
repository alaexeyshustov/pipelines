# PRD: LLM Provider Error Observability for Agentic Pipelines

## Summary

Improve observability for orchestration agent runs that use `ruby_llm` so provider failures no longer surface as generic `"unknown error"` messages. The system should capture structured diagnostics for HTTP/API failures, transport failures, and invalid model output, then expose those details in pipeline records, logs, and operator UI.

## Problem

Today, failures from LLM providers can collapse into low-signal errors with little actionable detail. This makes it hard to understand why a pipeline failed, debug provider-specific issues, and distinguish between infrastructure failures and model output problems.

Current pain points:

- 4xx and 5xx provider responses may surface as generic errors.
- Invalid or malformed provider responses are not described clearly.
- Model output that should be valid JSON may fail parsing without useful diagnostics.
- Operators lack a concise summary plus drill-down details in the run UI.

## Goals

- Capture structured failure details for orchestration agent runs.
- Distinguish provider/API failures from invalid model output failures.
- Preserve useful provider context including status code, provider name, parsed error fields, and a redacted/truncated raw response excerpt.
- Show concise summaries at the pipeline-run level.
- Show detailed diagnostics at the action-run level.
- Emit structured logs for failed LLM calls.

## Non-Goals

- Changing retry behavior, backoff, or failure-state transitions.
- Modifying successful execution behavior.
- Building a generic observability framework for all app subsystems.
- Patching `ruby_llm` unless application-level extraction proves insufficient.

## Primary Users

- Operators reviewing failed orchestration runs
- Developers debugging provider and prompt issues

## Scope

Initial scope focuses on orchestration agents/pipelines using these providers:

- OpenAI
- Mistral
- Gemini
- Anthropic

## User Stories

- As an operator, when a pipeline fails, I can see a concise error summary on the pipeline run.
- As an operator, when an action run fails, I can inspect structured details about the provider response.
- As a developer, I can tell whether the failure came from provider HTTP/API behavior, transport/network issues, or invalid model output.
- As a developer, I can correlate a failure with the generated chat and agent configuration used for that run.

## Functional Requirements

### 1. Failure categorization

The system must classify failures into distinct categories:

- `provider_http_error`
- `transport_error`
- `invalid_model_output`

### 2. Structured diagnostics on action runs

The system must persist structured diagnostics on failed `action_runs`.

Proposed fields:

- `category`
- `provider`
- `model`
- `status_code`
- `message`
- `parsed_error`
- `raw_response_excerpt`
- `chat_id`
- `request_context`

`request_context` may reuse already-persisted metadata such as `agent_snapshot`.

### 3. Pipeline-run summary

The system must continue showing a concise summary on `pipeline_runs.error`.

The pipeline run should not carry the full structured payload by default. Full diagnostics should live on the failed `action_run`.

### 4. Provider/API error extraction

When `ruby_llm` raises a provider-related exception, the application must extract details from the exception and underlying response when available, including:

- HTTP status code
- Provider name
- Raw response body excerpt
- Parsed provider error structure, when parseable

The implementation should work cleanly for OpenAI, Mistral, Gemini, and Anthropic.

### 5. Invalid model output handling

If an orchestration agent is expected to return structured JSON and the model output cannot be parsed as required, the system must treat that as `invalid_model_output` instead of a generic failure.

The diagnostics must include:

- The parse failure message
- A redacted/truncated excerpt of the raw model output

### 6. Logging

For failed LLM calls, the application must emit structured log entries containing enough context to debug failures without opening the database first.

Preferred log fields:

- failure category
- provider
- model
- status code
- action run ID
- pipeline run ID
- chat ID
- summary message

### 7. UI presentation

The run UI must:

- show a concise failure summary by default
- hide raw payload details behind a disclosure
- present structured diagnostics in a readable format for operators

## Data Handling Requirements

- Raw provider payloads must be redacted or truncated before persistence.
- The system must avoid storing full unbounded payloads in the database or showing them by default in UI.
- Sensitive request or prompt data should not be introduced unnecessarily into persisted diagnostics.

## UX Requirements

### Pipeline run

- Show a short, human-readable error summary.
- Keep the view high-signal and scannable.

### Action run

- Show summary first.
- Provide an expandable section for structured diagnostics.
- Provide an expandable section for raw response excerpt.

## Technical Approach

### Preferred approach

Implement this at the application layer around orchestration agent execution.

Expected shape:

- add a JSON column such as `action_runs.error_details`
- introduce an orchestration-level error extraction/normalization service
- update `PipelineRunner` to persist structured diagnostics on failure
- update action-run UI components to render summary + disclosure

### Fallback approach

If application-level handling cannot reliably access enough provider information, use a narrow monkey patch or extension around `ruby_llm` error handling.

## Success Criteria

- Failed orchestration runs no longer present opaque `"unknown error"` messages when provider details are available.
- Operators can identify the failure category from the UI without reading logs.
- Developers can inspect structured failure details for action runs and quickly determine provider, status, and response shape.
- Invalid JSON/model-output failures are clearly distinguishable from provider HTTP/API failures.

## Risks and Considerations

- Provider error payloads vary by vendor and may require normalization logic.
- Some failures may bypass HTTP error middleware and surface as transport exceptions instead.
- Over-capturing raw payloads could leak sensitive data if redaction is incomplete.
- UI should avoid overwhelming operators with low-level details by default.

## Open Questions

- Should provider-specific parsed error fields be normalized into a common shape beyond the first version?
- Should monitoring events from `ruby_llm_monitoring_events` be linked directly from failed action runs in a later iteration?
- Should the same observability pattern be extended to non-orchestration RubyLLM entry points after orchestration is complete?
