# Schemas — AI Agent Quick Reference

Schema format is `:sql` (not `:ruby`) because sqlite-vec `vec0` virtual tables cannot be expressed in the Ruby DSL. Source of truth: `db/structure.sql`.

---

## application_mails

One row per unique job-related email received.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | INTEGER | NO | autoincrement | PK |
| date | DATE | NO | — | Date the email was received |
| provider | STRING | NO | — | `"gmail"` or `"yahoo"` |
| email_id | STRING | NO | — | Provider-assigned message ID; globally unique |
| company | STRING | YES | — | Extracted by LLM; nil if unknown |
| job_title | STRING | YES | — | Extracted by LLM; nil if unknown |
| action | STRING | YES | — | Extracted by LLM; e.g. `"applied"`, `"rejected"` |
| created_at | DATETIME | NO | — | |
| updated_at | DATETIME | NO | — | |

**Indexes:** `email_id` (unique), `date`

**Model constants:**
```ruby
ApplicationMail::COLUMN_NAMES
# => ["date", "provider", "email_id", "company", "job_title", "action"]
```

**Key method:**
```ruby
ApplicationMail.as_rows          # => Array of plain hashes, ordered by date asc
ApplicationMail.as_rows(scope)   # accepts a custom ActiveRecord scope
```

---

## interviews

One row per company + job_title pair; tracks the full interview lifecycle.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | INTEGER | NO | autoincrement | PK |
| company | STRING | NO | — | |
| job_title | STRING | NO | — | |
| status | STRING | YES | `"pending_reply"` | See STATUSES below |
| applied_at | DATE | YES | — | |
| rejected_at | DATE | YES | — | |
| first_interview_at | DATE | YES | — | |
| second_interview_at | DATE | YES | — | |
| third_interview_at | DATE | YES | — | |
| fourth_interview_at | DATE | YES | — | |
| created_at | DATETIME | NO | — | |
| updated_at | DATETIME | NO | — | |

**Indexes:** `[company, job_title]` (unique)

**Model constants:**
```ruby
Interview::STATUSES
# => ["pending_reply", "having_interviews", "rejected", "offer_received"]

Interview::COLUMN_NAMES
# => ["company", "job_title", "status", "applied_at", "rejected_at",
#     "first_interview_at", "second_interview_at",
#     "third_interview_at", "fourth_interview_at"]
```

**Key method:**
```ruby
Interview.as_rows         # => Array of plain hashes, ordered by company, job_title
Interview.as_rows(scope)  # accepts a custom ActiveRecord scope
```

---

## email_vectors

sqlite-vec `vec0` virtual table. Stores 1536-dim float embeddings for RAG. **Not yet wired into the main workflow — reserved for future use.**

| Column | Type | Notes |
|---|---|---|
| email_id | TEXT (PK) | Matches `application_mails.email_id` |
| embedding | FLOAT[1536] | OpenAI-compatible 1536-dim vector |

**Model methods:**
```ruby
EmailVector.upsert_embedding(email_id: id, embedding: float_array)
EmailVector.search(float_array, limit: 5)
# => [{ email_id: "...", distance: 0.12 }, ...]
```

The sqlite-vec extension is loaded on every connection by `config/initializers/sqlite_vec.rb`.

---

## pipelines

An Orchestration pipeline definition.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | INTEGER | NO | autoincrement | PK |
| name | STRING | NO | — | |
| description | TEXT | YES | — | |
| model | STRING | YES | — | Pipeline-level model override; when set, overrides action model and agent default |
| cron_expression | STRING | YES | — | Standard 5-field cron expression; nil disables scheduled runs |
| enabled | BOOLEAN | NO | `true` | |
| created_at | DATETIME | NO | — | |
| updated_at | DATETIME | NO | — | |

**Associations:** `has_many :steps` (ordered by position, `dependent: :destroy`), `has_many :pipeline_runs` (`dependent: :destroy`)

---

## steps

An ordered step within a pipeline.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | INTEGER | NO | autoincrement | PK |
| pipeline_id | INTEGER | NO | — | FK → pipelines |
| name | STRING | NO | — | |
| position | INTEGER | NO | — | Execution order within the pipeline |
| input_mapping | JSON | YES | — | |
| enabled | BOOLEAN | NO | `true` | When false, step is skipped during pipeline execution |
| created_at | DATETIME | NO | — | |
| updated_at | DATETIME | NO | — | |

**Indexes:** `[pipeline_id, position]` (unique)

**Associations:** `belongs_to :pipeline`, `has_many :step_actions` (ordered by position, `dependent: :destroy`), `has_many :actions` through `step_actions`

---

## actions

A reusable agent configuration.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | INTEGER | NO | autoincrement | PK |
| name | STRING | NO | — | Human label |
| agent_class | STRING | NO | — | Must be an existing constant inheriting `RubyLLM::Agent` |
| description | TEXT | YES | — | |
| model | STRING | YES | — | LLM model override; nil = use workflow default |
| tools | JSON | YES | — | |
| prompt | TEXT | YES | — | System prompt override |
| params | JSON | YES | — | |
| output_schema | JSON | YES | — | JSON Schema subset; validated after each run. `nil` = no validation |
| created_at | DATETIME | NO | — | |
| updated_at | DATETIME | NO | — | |

**Associations:** `has_many :step_actions` (`dependent: :restrict_with_error` — cannot delete if referenced)

**Output schema validation:** When `output_schema` is set, `Orchestration::OutputValidator` validates the action run's output after execution. If validation fails, the `ActionRun` is marked `failed` with the error message. Supported JSON Schema keywords: `type` (`object`, `array`, `string`, `number`, `integer`, `boolean`), `properties`, `required`, `items`. For LLM agent actions, the result content is parsed as JSON before storage when the content is valid JSON.

---

## step_actions

Join table linking a step to an action at a specific position.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | INTEGER | NO | autoincrement | PK |
| step_id | INTEGER | NO | — | FK → steps |
| action_id | INTEGER | NO | — | FK → actions |
| position | INTEGER | NO | — | Execution order within the step |
| params | JSON | YES | — | Per-assignment param overrides |
| created_at | DATETIME | NO | — | |
| updated_at | DATETIME | NO | — | |

**Indexes:** `[step_id, position]` (unique)

---

## pipeline_runs

A single execution of a pipeline.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | INTEGER | NO | autoincrement | PK |
| pipeline_id | INTEGER | NO | — | FK → pipelines |
| status | STRING | NO | `"pending"` | See STATUSES below |
| triggered_by | STRING | YES | — | `"manual"` or `"schedule"`; nil allowed |
| started_at | DATETIME | YES | — | |
| finished_at | DATETIME | YES | — | |
| error | TEXT | YES | — | Set on failure |
| created_at | DATETIME | NO | — | |
| updated_at | DATETIME | NO | — | |

**Indexes:** `status`

**Model constants:**
```ruby
Orchestration::PipelineRun::STATUSES   # => ["pending", "running", "completed", "failed"]
Orchestration::PipelineRun::TRIGGERED_BY # => ["manual", "schedule"]
```

**Associations:** `belongs_to :pipeline`, `has_many :action_runs` (`dependent: :destroy`)

---

## action_runs

A single execution of an action within a pipeline run.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | INTEGER | NO | autoincrement | PK |
| pipeline_run_id | INTEGER | NO | — | FK → pipeline_runs |
| step_action_id | INTEGER | NO | — | FK → step_actions |
| status | STRING | NO | `"pending"` | See STATUSES below |
| input | JSON | YES | — | |
| output | JSON | YES | — | |
| error | TEXT | YES | — | Set on failure |
| started_at | DATETIME | YES | — | |
| finished_at | DATETIME | YES | — | |
| created_at | DATETIME | NO | — | |
| updated_at | DATETIME | NO | — | |

**Indexes:** `status`

**Model constants:**
```ruby
Orchestration::ActionRun::STATUSES   # => ["pending", "running", "completed", "failed"]
```

---

## chats / messages / tool_calls / models

Managed by **RubyLLM** (`acts_as_chat` / `acts_as_message` / `acts_as_tool_call` / `acts_as_model`). Stores full LLM conversation history including thinking tokens, token counts, and tool use.

### chats

| Column | Type | Notes |
|---|---|---|
| id | INTEGER | PK |
| model_id | INTEGER | FK → models (nullable) |
| created_at / updated_at | DATETIME | |

### messages

| Column | Type | Notes |
|---|---|---|
| id | INTEGER | PK |
| chat_id | INTEGER | FK → chats |
| model_id | INTEGER | FK → models (nullable) |
| tool_call_id | INTEGER | FK → tool_calls (nullable) |
| role | STRING | `"user"`, `"assistant"`, `"tool"` |
| content | TEXT | Plain text content |
| content_raw | JSON | Raw provider response |
| thinking_text | TEXT | Extended thinking output |
| thinking_signature | TEXT | |
| thinking_tokens | INTEGER | |
| input_tokens | INTEGER | |
| output_tokens | INTEGER | |
| cached_tokens | INTEGER | |
| cache_creation_tokens | INTEGER | |

**Indexes:** `role`, `chat_id`, `model_id`, `tool_call_id`

### tool_calls

| Column | Type | Notes |
|---|---|---|
| id | INTEGER | PK |
| message_id | INTEGER | FK → messages |
| tool_call_id | STRING | Provider-assigned ID (unique) |
| name | STRING | Tool function name |
| thought_signature | TEXT | |
| arguments | JSON | Default: `{}` |

**Indexes:** `tool_call_id` (unique), `name`, `message_id`

### models

| Column | Type | Notes |
|---|---|---|
| id | INTEGER | PK |
| model_id | STRING | Provider model identifier |
| name | STRING | Human name |
| provider | STRING | e.g. `"mistral"`, `"openai"` |
| family | STRING | |
| model_created_at | DATETIME | |
| context_window | INTEGER | |
| max_output_tokens | INTEGER | |
| knowledge_cutoff | DATE | |
| modalities | JSON | Default: `{}` |
| capabilities | JSON | Default: `[]` |
| pricing | JSON | Default: `{}` |
| metadata | JSON | Default: `{}` |

**Indexes:** `[provider, model_id]` (unique), `provider`, `family`

---

## Evaluation tables

Models live in `app/models/evaluation/` (see [evals.md](evals.md)). Scores are normalized 0.0..1.0.

### evaluation_datasets / evaluation_dataset_samples
| Column | Type | Notes |
|---|---|---|
| `evaluation_datasets.name`, `description`, `agent_name` | string/text | `agent_name` nullable |
| `evaluation_dataset_samples.dataset_id` | FK | required |
| `evaluation_dataset_samples.input` | JSON | required; fed to the agent |
| `evaluation_dataset_samples.expected_tool_calls` | JSON | nullable; present when seeded from a production run |
| `evaluation_dataset_samples.source_run_id` | integer | nullable |

### evaluation_prompts
`name` (agent), `version`, `system_prompt`, `user_prompt`, `output_schema` (JSON), `metadata`. Immutable versions.

### evaluation_experiments
| Column | Type | Notes |
|---|---|---|
| `dataset_id`, `prompt_id` | FK | `prompt_id` nullable |
| `sample_model`, `evaluation_model` | string | agent model, judge model |
| `status` | string | `pending` (default), `running`, `completed`, `failed` |
| `pending_samples_count` | integer | default 0; the single run counter, decremented by each `SampleJob` |
| `metadata` | text (JSON) | |

### evaluation_samples
`experiment_id`, `dataset_sample_id`, `prompt_id` (FKs), `tool_calls` (JSON: `tool_name`, `arguments`, `result` per call), `output` (text).

### evaluation_metrics
| Column | Type | Notes |
|---|---|---|
| `agent_name`, `name` | string | unique together |
| `description` | text | the judge question / rubric |
| `weight` | decimal | default 1.0; weight in the sample grade |
| `active` | boolean | default true |
| `kind` | string | `probability` (default), `score`, `choice` |
| `levels` | JSON | `score`: array of >= 2 level descriptions; `choice`: `{option => {"description", "value" (0.0..1.0)}}`; optional for `probability` |
| `minimum` | float | nullable, 0.0..1.0; per-metric pass threshold |

### evaluation_evaluation_results
One row per metric per sample.
| Column | Type | Notes |
|---|---|---|
| `experiment_id`, `dataset_sample_id`, `sample_id` | FK | |
| `evaluator_class` | string | `Evaluation::Grader` |
| `score` | float | normalized 0.0..1.0, nullable (unknown) |
| `raw` | JSON | native answer (`to_h`) |
| `confidence` | float | nullable; nil for probabilities |
| `passed` | boolean | nullable; verdict against `Metric#minimum` |

### evaluation_justifications
`evaluation_result_id`, `metric_name`, `justification` (text derived from the native answer).

### ruby_llm_usages (evaluation use)
RubyLLM's usage ledger. `owner_type`/`owner_id` point at the `Evaluation::Experiment` (set by `Evaluation::UsageScope`); `Evaluation::ExperimentUsageQuery` sums tokens and `total_cost` per experiment.

---

## Quick perks

- `ApplicationMail.as_rows` and `Interview.as_rows` return `Array<Hash<String, String|nil>>` — safe to pass directly to LLM tool responses.
- All `STATUSES` / `TRIGGERED_BY` constants are frozen arrays — use them for validation or display without querying the DB.
- `email_vectors` KNN search returns results sorted by distance ascending (nearest first).
- Orchestration objects cascade on destroy: `Pipeline → Steps → StepActions`; `PipelineRun → ActionRuns`. Actions block deletion if any `StepAction` references them.
- `Chat` → `Message` (has_many), `Message` → `ToolCall` (has_many) — load with `Chat.includes(messages: :tool_calls)` to avoid N+1.
- Schema is loaded via `db/structure.sql`, not `db/schema.rb` — run `rails db:schema:load` (not `rails db:migrate`) on a fresh database.
