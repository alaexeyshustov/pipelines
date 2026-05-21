---
status: proposed
---

# PRD: Extract Dataset Synthesis Workflow from SyntheticDatasetJob

## Summary

Extract the seven-step synthesis workflow from `SyntheticDatasetJob` into a dedicated `Evaluation::SyntheticDatasetGenerator` service. The job's only remaining responsibilities are enqueuing and translating service outcomes into `WizardDraft` state updates. The service can be tested synchronously and invoked from any entry point without job infrastructure.

## Problem

`SyntheticDatasetJob` chains seven steps inline: fetch system prompt → fetch few-shot samples → build user message → call LLM → parse JSON → create dataset records → update wizard draft status. All of that lives inside the job, creating three pain points:

- **No synchronous entry point.** The workflow cannot be invoked without enqueuing. An admin action, API endpoint, or test helper must go through the job queue.
- **Hard-to-isolate tests.** Specs must use `perform_now` and stub job internals rather than exercising a plain service object.
- **WizardDraft coupling baked into the workflow.** The synthesis logic and the wizard lifecycle management are tangled in one class, making either harder to change independently.

## Goals

- Extract the synthesis workflow into `Evaluation::SyntheticDatasetGenerator`.
- Make the service invokable synchronously from any entry point without job infrastructure.
- Let specs exercise the workflow directly against a service object.
- Slim the job to: call service → update draft on success → update draft on failure.

## Non-Goals

- Changing the synthesis workflow itself (prompt fetching, few-shot sampling, LLM call, JSON parsing, record creation).
- Changing the `WizardDraft` state machine or payload shape.
- Adding retry logic, background processing changes, or new entry points.
- Changing the controller or routes.

## Primary Users

- Developers adding or testing dataset synthesis behavior.
- Developers building future entry points (API actions, admin triggers) that need to synthesize a dataset outside the wizard flow.

## Functional Requirements

### 1. Service interface

`Evaluation::SyntheticDatasetGenerator` must expose a single class-level `.call` method:

```ruby
SyntheticDatasetGenerator.call(
  agent_name:,
  dataset_name:,
  count:,
  hints:   nil,
  model:   nil
) # → Evaluation::Dataset
```

No `draft_token:` parameter. The service knows nothing about `WizardDraft`.

### 2. Service responsibilities

The service owns all seven synthesis steps currently in the job:

1. Fetch the system prompt from `Evaluation::Prompt` for `agent_name`
2. Fetch few-shot samples from existing datasets
3. Build the user message (count, hints, examples)
4. Call the LLM
5. Parse the JSON response
6. Validate that the parsed response is an Array
7. Create `Evaluation::Dataset` with child `Evaluation::SyntheticRecord` rows and `Evaluation::DatasetRecord` join rows

### 3. Service return value

On success the service returns the created `Evaluation::Dataset` object. Callers that need only the ID call `.id` on the result.

### 4. Error propagation

The service raises naturally on any failure — `JSON::ParserError`, `ArgumentError` for non-array responses, LLM errors, etc. No custom error wrapper. Callers are responsible for rescue.

### 5. Slimmed job

`SyntheticDatasetJob` keeps its current keyword interface unchanged. Its body becomes:

```ruby
def perform(draft_token:, agent_name:, dataset_name:, count:, hints: nil, model: nil)
  dataset = SyntheticDatasetGenerator.call(
    agent_name:,
    dataset_name:,
    count:,
    hints:,
    model:
  )
  WizardDraft.find_by!(session_token: draft_token)
    .merge_payload!("dataset_generation" => { "status" => "completed", "dataset_id" => dataset.id.to_s })
rescue StandardError => e
  WizardDraft.find_by!(session_token: draft_token)
    .merge_payload!("dataset_generation" => { "status" => "failed", "error_message" => e.message })
end
```

All draft state management lives in the job. The service is never aware of it.

### 6. RBS signature update

The existing `sig/app/services/evaluation/synthetic_dataset_generator.rbs` must be updated to match the new interface: remove `draft_token:`, change the return type from `String` to `Evaluation::Dataset`.

### 7. Specs

`spec/services/evaluation/synthetic_dataset_generator_spec.rb` (new) owns all workflow coverage:

- System prompt included in LLM call
- Few-shot samples included in LLM messages
- Optional hints included in user message
- Dataset and SyntheticRecord rows created correctly
- DatasetRecord join rows created correctly
- `JSON::ParserError` raised on unparseable LLM output
- `ArgumentError` raised when parsed response is not an Array

`spec/jobs/evaluation/synthetic_dataset_job_spec.rb` slims to three cases:

1. Service called with correct arguments
2. Draft updated to `completed` with `dataset_id` on success
3. Draft updated to `failed` with `error_message` on `StandardError`

## Technical Approach

### Files to change

| File | Change |
|------|--------|
| `app/services/evaluation/synthetic_dataset_generator.rb` | Create — extract workflow from job |
| `app/jobs/evaluation/synthetic_dataset_job.rb` | Replace body with service call + draft updates |
| `sig/app/services/evaluation/synthetic_dataset_generator.rbs` | Remove `draft_token:`, return type `Evaluation::Dataset` |
| `spec/services/evaluation/synthetic_dataset_generator_spec.rb` | Create — all workflow coverage |
| `spec/jobs/evaluation/synthetic_dataset_job_spec.rb` | Slim to three cases |

### Before and after

**Before (job owns everything):**
```ruby
def perform(draft_token:, agent_name:, dataset_name:, count:, hints: nil, model: nil)
  prompt = Evaluation::Prompt.where(name: agent_name)...
  samples = ...
  user_message = ...
  response = RubyLLM.chat(...)
  inputs = JSON.parse(response.content)
  raise ArgumentError, "..." unless inputs.is_a?(Array)
  dataset = Evaluation::Dataset.create!(name: dataset_name)
  inputs.each { |input| ... }
  WizardDraft.find_by!(session_token: draft_token).merge_payload!(...)
rescue StandardError => e
  WizardDraft.find_by!(session_token: draft_token).merge_payload!(...)
end
```

**After (job delegates, service owns workflow):**
```ruby
# app/jobs/evaluation/synthetic_dataset_job.rb
def perform(draft_token:, agent_name:, dataset_name:, count:, hints: nil, model: nil)
  dataset = SyntheticDatasetGenerator.call(agent_name:, dataset_name:, count:, hints:, model:)
  WizardDraft.find_by!(session_token: draft_token)
    .merge_payload!("dataset_generation" => { "status" => "completed", "dataset_id" => dataset.id.to_s })
rescue StandardError => e
  WizardDraft.find_by!(session_token: draft_token)
    .merge_payload!("dataset_generation" => { "status" => "failed", "error_message" => e.message })
end

# app/services/evaluation/synthetic_dataset_generator.rb
module Evaluation
  class SyntheticDatasetGenerator
    def self.call(agent_name:, dataset_name:, count:, hints: nil, model: nil)
      # ... seven synthesis steps ...
    end
  end
end
```

## Success Criteria

- `SyntheticDatasetGenerator.call(...)` can be invoked synchronously in tests and from any entry point without job infrastructure.
- The job body contains no workflow logic — only service delegation and draft state updates.
- All workflow behavior is covered by `spec/services/evaluation/synthetic_dataset_generator_spec.rb`.
- The job spec contains exactly three cases: correct args, draft completed, draft failed.
- The existing RBS signature is updated and passes `steep check`.
- Adding a second entry point (e.g. an API action) requires only calling the service directly — no changes to the job.
