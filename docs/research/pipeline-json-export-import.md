# Research: Pipeline JSON export / import (GH #206)

Issue text (only detail available): "allow exporting a pipeline to a JSON file and importing it back, e.g. to share or back up pipeline definitions".
Sources: code, `db/structure.sql`, `docs/*.md`, `.agents/rules/*.md`. Line numbers are as of branch `feat/gh-206-pipelines-add-json-export-import` (HEAD 7da62dd).

**Warning: `docs/schemas.md` is stale for orchestration.** It documents `pipelines`, `steps`, `actions`, `step_actions` (`docs/schemas.md:99-177`), but the real tables are `orchestration_*` (renamed by `db/migrate/20260519000002_rename_orchestration_tables.rb`). In `schemas.md`, `actions` still carries `model/tools/prompt/params/output_schema` (`docs/schemas.md:147-153`), but those columns now live on `orchestration_agents` (`db/structure.sql:103`). `schemas.md` also lacks `initial_input_schema`, `step_actions.output_key`, `actions.kind/agent_id`. Treat `db/structure.sql` and the models as authoritative.

---

## 1. Data model

### 1.1 Definition graph (candidates for export)

```
Pipeline 1─* Step 1─* StepAction *─1 Action *─0..1 Agent
```

| Table / model | Exportable columns (structure.sql) | Notes |
|---|---|---|
| `orchestration_pipelines` / `Orchestration::Pipeline` (`app/models/orchestration/pipeline.rb:2`) | `name`, `description`, `enabled`, `cron_expression`, `model`, `initial_input_schema` (json) (`db/structure.sql:21`) | `name` presence-validated only (`pipeline.rb:8`); **no unique index/validation on name**. `cron_expression` validated with Fugit (`pipeline.rb:9,47-49`). |
| `orchestration_steps` / `Step` (`step.rb:2`) | `name`, `position`, `enabled` (`structure.sql:43`) | Unique `[pipeline_id, position]` (`structure.sql:54`); `position` presence + uniqueness validated (`step.rb:10`). |
| `orchestration_step_actions` / `StepAction` (`step_action.rb:2`) | `position`, `output_key`, `input_mapping` (json) (`structure.sql:111`) | Unique `[step_id, output_key]` and `[step_id, position]` (`structure.sql:118-119`). `output_key` must match `/\A[a-z][a-z0-9_]*\z/` (`step_action.rb:5,12-15`). |
| `orchestration_actions` / `Action` (`action.rb:2`) | `name`, `description`, `kind` (`agent`/`service`), `agent_class`, `agent_id` (`structure.sql:105`) | `name` NOT unique (validation `action.rb:10`, no index at `structure.sql:109-110`). Agent-kind needs `agent_id` and blank `agent_class`; service-kind needs `agent_class` that constantizes and includes `Orchestration::Executable` (`action.rb:27-49`). |
| `orchestration_agents` / `Agent` (`agent.rb:2`) | `name` (unique), `description`, `model`, `tools` (json array), `enabled`, `prompt`, `output_schema`, `input_schema` (`structure.sql:103-104`) | Name unique by validation and index (`agent.rb:9`, `structure.sql:104`). Tools restricted to namespaces `Records`/`Emails` and must constantize (`agent.rb:3,55-71`). |

How the definition is used at runtime:
- Model precedence is pipeline `model`, else agent `model` (`lib/orchestration/agent_resolution_policy.rb:23-25`); prompt and tools come from the agent (`agent_resolution_policy.rb:27-40`). So the pipeline's behavior depends on the **Agent rows** (prompt, tools, output_schema), not only on the pipeline rows.
- Service-kind actions resolve a Ruby class through `action.agent_class` (`action_executor.rb:46-51`; the registry in `lib/orchestration/service_registry.rb:3-9` lists four executors).
- Optional per-run prompt override via `Orchestration.prompt_resolver` (served by the evaluation subsystem's active prompt, `docs/orchestration.md:40`). This is evaluation data, not part of the pipeline definition.

### 1.2 Non-portable IDs / references

- All integer PKs/FKs are DB-local: `pipeline_id`, `step_id`, `step_actions.action_id`, `actions.agent_id` (`structure.sql:18,44,112-116,106`). Export must reference by natural keys, not IDs.
- Natural keys available: `Agent.name` (unique; the only enforced one), `Step.position` (unique within pipeline), `StepAction.output_key` (unique within step), `StepAction.position`. `Action.name` and `Pipeline.name` are **not unique** (see 1.1), so they are weak keys. The seed uses them as keys anyway (`db/seeds.rb:327,348`).
- `input_mapping` references upstream data by **output_key string** (`"from": "fetch_emails"`) or the literal `"_initial"`, never by DB ID (`db/seeds.rb:66-117`; resolution in `lib/orchestration/pipeline_validator.rb:13-17,53-69`). It therefore survives export unchanged, provided `output_key`s are preserved. Note `output_key` is immutable after the first run exists (`step_action.rb:16,20-24`), which is irrelevant for fresh imports.
- `Action` has no unique natural key, and `Action` is a shared, reusable object (`Action has_many :step_actions`, `action.rb:7`; `with_pipeline_counts` joins actions to pipelines, `action.rb:13-19`). An action may be used by several pipelines, so export has to decide between embedding actions inline (denormalized) and a top-level `actions` table referenced by a local key.
- Service-kind `agent_class` is a Ruby constant name: portable across installs of the same code revision, but valid only if that class exists and includes `Executable` (`action.rb:43-47`).

### 1.3 Runtime data - must NOT be exported

- `orchestration_pipeline_runs` (status, timestamps, error, `initial_input`) (`structure.sql:17`; `PipelineRun`, `pipeline_run.rb`).
- `orchestration_action_runs` (input/output, error, `chat_id`, `agent_snapshot`, `error_details`) (`structure.sql:23`). It holds FKs to `step_action_id` and `chats`, so it cannot be recreated across installs. `agent_snapshot` also holds a copy of the prompt (`action_executor.rb:64-71`).
- `chats`/messages/tool calls (RubyLLM-owned, referenced by `chat_id`).
- Evaluation tables (`evaluation_*`) that key on agent **name** strings (`evaluation_datasets.agent_name`, `evaluation_metrics.agent_name`; `docs/schemas.md:308-341`). They are separate subsystems; recommend out of scope.
- Timestamps, `id`s.
- Never put `GITHUB_TOKEN`, email connector configs (`email_connectors.configuration`, `structure.sql:42`) or settings in an export. They are not on the pipeline graph, so ordinary traversal does not touch them.

Deleting rows is constrained: `StepAction has_many :action_runs, dependent: :restrict_with_error` (`step_action.rb:9`), and `Action`/`Agent` restrict deletion while referenced (`action.rb:7`, `agent.rb:7,20,73-78`). An "overwrite" import that destroys and rebuilds steps would fail (or need run history deleted first). The seed does exactly that: `pipeline.pipeline_runs.destroy_all; pipeline.steps.destroy_all` (`db/seeds.rb:356-360`).

---

## 2. Existing patterns that can be reused

| Pattern | Where | Reusability |
|---|---|---|
| Download via `send_data` (CSV) | `app/controllers/interviews_controller.rb:52` (`send_data result.csv, filename: ..., type: "text/csv", disposition: "attachment"`); builder `app/services/interviews/csv_export_service.rb:1-23` | Direct template for a `send_data` JSON download in the pipelines controller. |
| Service with `Data.define` result, `.call` | `app/services/interviews/gist_export_service.rb:8-13` | Result shape reference (`ok`, `message`). |
| JSON helpers | `lib/json/helpers.rb:2-17` (`safe_parse(str, fallback:)`, `safe_generate`, `parse_maybe`) | Parsing uploaded text without raising. |
| `JsonParamsParsing` | `app/controllers/concerns/json_params_parsing.rb:6-9`; included in `BaseForm` (`app/forms/base_form.rb:5`) and `PipelinesController` (`pipelines_controller.rb:3`) | Existing precedent for JSON text from a form field (`initial_input_schema`, `pipelines_controller.rb:68-80`). Its failure mode (silently nils the field on `JSON::ParserError`, `:73-77`) is NOT acceptable for import. |
| Idempotent seed building the whole graph | `db/seeds.rb:300-377` | Shows the construction order (Agents -> Actions -> Pipeline -> Steps -> StepActions) and a name-keyed upsert (`find_or_initialize_by(name:)` for Agent/Action, `find_or_create_by!(name:)` for Pipeline). The importer would be the data-driven generalization of this. |
| Multi-model form with transaction | `lib/orchestration/input_mapping_updater.rb:19-31` (transaction + `ActiveRecord::Rollback` when `PipelineValidator` reports errors); `StepActionCreateForm` (`app/forms/orchestration/step_action_create_form.rb:12-32`) | Pattern for "write, validate whole pipeline, roll back on errors". |
| Pipeline validation | `Pipeline#validate_steps` -> `PipelineValidator` (`pipeline.rb:18-20`; `pipeline_validator.rb:12-19`) returns per-step-action `errors`/`warnings` (unknown `from`, invalid `path`, missing required input). | Post-import semantic validation for free (catches broken `input_mapping` refs). |
| Position/output_key derivation | `Orchestration::OutputKeyDeriver` (`lib/orchestration/output_key_deriver.rb:2-22`) | Can generate keys for missing/colliding `output_key`s. |
| Schema (de)serialization | `app/models/orchestration/schema_builder/serializer.rb:6-60`, `schema_builder/parser.rb` | Only for JSON Schema fields; not needed (schemas are stored as plain JSON). |
| `SchemaValidator` | `lib/orchestration/schema_validator.rb` (used by `PipelineRunForm`, `pipeline_run_form.rb:37`) | Could validate the import payload against a JSON-schema subset (`type`, `properties`, `required`, `items`; `docs/schemas.md:159`). Supports only that subset. |

**Not present** (confirmed by grep over `app lib config/initializers Gemfile`): no `as_json` overrides, no serializers, no jbuilder, no `has_one_attached`/Active Storage, no `file_field`/`UploadedFile` handling, no clone/duplicate feature for pipelines, no YAML seeds. The only `to_json` uses are ad-hoc (e.g. `app/components/orchestration/schema_builder_component.rb:8`). So the exporter and file-upload handling are new code.

---

## 3. Where it fits (architecture + Archspec)

Layering (`Archspec.rb:3-9`; ADR `docs/adr/0011-archspec-layers.md`): interface (controllers/components/helpers) -> application (`app/services`, `app/forms`, `app/jobs`, `lib/orchestration`, `lib/evaluation`, `lib/pipeline`) -> tools -> domain (`app/models`) -> infra. A layer may depend only on itself and layers below (`Archspec.rb:3`). Orchestration must not use evaluation (`Archspec.rb:15-17`). `AGENTS.md` forbids adding to `archspec_todo.yml`.

Proposed placement, all legal under those rules:

1. **Domain logic in `lib/orchestration/`** (application layer, `orchestration` component), e.g. `Orchestration::PipelineExporter` and `Orchestration::PipelineImporter`. Basis: `.agents/rules/services.md:16` ("Most domain logic lives in `lib/` ... follow the style of the surrounding module there") and `docs/architecture.md` ("`lib/orchestration/agents/`", orchestration directory). Neighbours are plain classes with `Data.define` results (`InputMappingUpdater::Result`, `input_mapping_updater.rb:3`, `PipelineValidator::Issue`). They may use `app/models/orchestration/*` (domain, below). Must NOT reference `Evaluation::*`.
   - Alternative: `app/services/orchestration/pipeline_export_service.rb`. Subject to the `App/Service*` cops: only `self.call` public, `Data.define` results, no service calling another service's `.call` (`.agents/rules/services.md:8-12`). `app/services/` currently has no `orchestration/` dir (only `application_mails chats emails evaluation interviews`), so `lib/orchestration` matches precedent better.
2. **Form object** `app/forms/orchestration/pipeline_import_form.rb`, inheriting `::BaseForm` (`.agents/rules/form_objects.md:8`; precedent `PipelineRunForm`, `app/forms/orchestration/pipeline_run_form.rb`): takes the uploaded file/text and a collision strategy, validates, calls the importer, `#save` returns true/false, wraps multi-model writes in a transaction, no side effects (`form_objects.md:10-11`). Controllers may use forms (same or lower layer).
   - Archspec caveat: `BaseForm` is already a baselined violation (`archspec_todo.yml`, `app/forms/base_form.rb:5` "application may not depend on interface" due to `JsonParamsParsing` living in `app/controllers/concerns`). Don't extend that coupling; the form should not call `JsonParamsParsing` from a controller concern in new ways. Use `JSON::Helpers` (`lib/json/helpers.rb`) instead.
3. **Controller** `Orchestration::PipelinesController` (`app/controllers/orchestration/pipelines_controller.rb`): add `export` (member `get`, `send_data` as at `interviews_controller.rb:52`) and `import` (collection `post`) plus `new_import` or a dialog on index. Routes in `config/routes.rb:74-86`: add inside `resources :pipelines do member do ... end end` and `collection do post :import end`. The controller is already ~80 lines; consider a separate `Orchestration::PipelineImportsController` to avoid growth (there is existing documented concern about controller length: `docs/issues/*_controller_length.md`, e.g. `schema_builders_controller_length.md`, `experiments_controller_length.md`).
4. **UI**: "Export" (link, `UI::PageHeaderComponent` `with_action(type: :link ...)`) in `app/views/orchestration/pipelines/show.html.erb:6-44` and "Import" on `index.html.erb:1-3` (`with_action(type: :link/dialog)`; a `:dialog` action type exists, `show.html.erb:10-20`). Any new component needs a preview under `spec/components/previews/` and no AR queries / no `Current` (`.agents/rules/view_components.md:9-11`); prefer reusing `UI::` components.
5. **RBS**: every `lib/`, `app/services`, and `app/tools` change needs a mirrored `sig/lib/orchestration/*.rbs` (`.agents/rules/signatures.md:10-15`; `docs/architecture.md` "After every code change ... update `.rbs`"). Avoid `untyped`; JSON payload types can use the existing `json_object` alias (used in `pipeline_runner.rb:80`).
6. **Specs** (`.agents/rules/specs.md:8-13`): `spec/lib/orchestration/pipeline_exporter_spec.rb`, `pipeline_importer_spec.rb` (round-trip), `spec/forms/orchestration/pipeline_import_form_spec.rb`, `spec/requests/orchestration/pipelines_spec.rb` (export download + multipart import; existing file at that path), optionally `spec/system/` for the UI flow; no `double`/`spy`. Factories exist in `spec/factories/{pipelines,steps,step_actions,actions,orchestration_agents}.rb`.

Auth/CSRF context: `ApplicationController` has no authentication (`app/controllers/application_controller.rb:1-30`); the app is single-tenant/local. CSRF protection is default Rails (disabled only in test, `config/environments/test.rb:28-29`).

---

## 4. Design options

### 4.1 Reference style: IDs vs names vs embedded

| Option | Pros | Cons |
|---|---|---|
| A. Raw ID dump (`as_json`) | Trivial | Not portable; breaks sharing; FK collisions. Reject. |
| B. **Nested tree, referencing by natural key** (pipeline -> steps -> step_actions -> action `{name, kind, agent_class \| agent: "<agent name>"}`) | Human-readable, diffable, matches the seed shape (`db/seeds.rb:300-377`), `input_mapping` already name-based | `Action.name` is not unique; shared actions duplicated across pipelines/steps; agent definitions need handling |
| C. Normalized: top-level `agents[]`, `actions[]` (local keys), `pipeline{steps[]}` | Preserves action sharing, one copy of each agent | More complex importer; keys must be created |

Recommendation: **B, with an embedded `agents[]` section** (optional, see 4.3). Steps hold `step_actions[]`; each carries an inline `action` object `{name, description, kind, agent_class | agent}` where `agent` is the agent name. Preserve array order for steps/step_actions and re-derive `position` from it (1-based) instead of exporting it; this removes unique-position collision risk.

### 4.2 Envelope

```json
{
  "format": "pipeline-export",
  "schema_version": 1,
  "exported_at": "...",
  "pipeline": {
    "name", "description", "enabled", "model", "cron_expression", "initial_input_schema",
    "steps": [{ "name", "enabled", "step_actions": [
      { "output_key", "input_mapping", "action": { "name", "description", "kind", "agent_class" | "agent" } } ] }]
  },
  "agents": [ { "name", "description", "model", "tools", "enabled", "prompt", "input_schema", "output_schema" } ]
}
```

Version field lets the importer reject unknown/future versions explicitly (no schema-version precedent in the repo; this is new). Validate the envelope shape with `Orchestration::SchemaValidator` (subset of JSON Schema: `type/properties/required/items`, `docs/schemas.md:159`) or hand-rolled checks in the form. Note: no `additionalProperties` handling is documented, so unknown keys must be ignored/rejected by explicit code.

### 4.3 Agents: include or reference only?

Pipeline behavior depends on Agent prompt/tools/output_schema (1.1), but agents are shared global rows, and the seeds treat them as environment-managed (`db/seeds.rb:127-298,378-386`, kept in sync with a migration).
- **Reference only**: portable "wiring", small file, but an import against an install missing the agent fails/degrades. Good for same-install backup/clone.
- **Embed definitions** (recommended for "share or back up"): importer does find-by-name; if missing, create it (validated by `Agent` model: tool namespaces allowed and constantizable, `agent.rb:55-71`); if it exists and differs, do NOT silently overwrite (agents are shared by other pipelines and evaluation keys on the name); report as a conflict, or support explicit opt-in `overwrite_agents`.
- Make it a user choice or default to embed. Either way, report missing agents explicitly.

### 4.4 Pipeline name collisions (`Pipeline.name` is not unique)

| Strategy | Notes |
|---|---|
| Reject | Safest, needs a uniqueness check by the importer (no DB constraint to rely on). |
| **Rename** (default; "Name (imported)", "Name (2)") | Non-destructive; makes round-trip trivial; avoids the restrict-on-delete problem (`step_action.rb:9`). Recommended default. |
| Overwrite (replace steps in place) | Requires deleting steps whose step_actions have runs (restrict_with_error at `step_action.rb:9`); seed deletes runs first (`db/seeds.rb:356-360`) - destroying run history is a destructive surprise. If offered: require explicit confirmation, and prefer "update pipeline fields + replace steps only if no runs exist". |

Recommendation: rename by default, with reject as an alternative; defer overwrite to a follow-up or gate it.

### 4.5 Actions

`Action.name` not unique, no natural key. Options: always create new `Action` rows (duplicates over repeated imports), or match on `(kind, agent_class | agent name, name)` and reuse an existing identical action (safer for dedup; avoids polluting `/orchestration/actions`, `actions_controller.rb:6-8`). Recommend find-or-create by that tuple (like `db/seeds.rb:327-332` does by name), never mutating an existing shared action.

### 4.6 Missing/invalid referenced things

- Missing agent (referenced and not embedded): hard error listing names; no partial import.
- Service `agent_class` absent or not `Executable`: fail via `Action` validation (`action.rb:37-49`), surfaced in the form errors. Cross-version note: an export from a newer code revision may name an executor that doesn't exist here; `ServiceRegistry` lists four known classes (`service_registry.rb:3-9`).
- Tools outside `Records`/`Emails` or unknown: `Agent` validation (`agent.rb:55-71`).
- Run `Pipeline#validate_steps` (`pipeline.rb:18`) after building and treat `errors` as import failure and `warnings` as informational, rolling back as in `input_mapping_updater.rb:24-28`.
- `enabled` and `cron_expression`: importing an enabled, scheduled pipeline causes `SchedulerJob` to run it immediately when due (`app/jobs/scheduler_job.rb:17-28`, picks enabled + cron present; reference time = `pipeline.created_at` when never run, `:22`). Recommend importing as **disabled** by default (user opt-in to keep), to avoid surprise runs that call LLMs/email APIs.

### 4.7 Atomicity

Wrap all writes (agents, actions, pipeline, steps, step_actions) in one `ActiveRecord::Base.transaction` and use `save!`/`create!` with `ActiveRecord::RecordInvalid` rescued into form errors (`form_objects.md:10`). Use unique-index safe orders: create the pipeline, then steps with generated positions, then step_actions with generated positions; handle `output_key` uniqueness within a step (`structure.sql:118`) by failing validation with a clear message (`StepAction` validates uniqueness at `step_action.rb:12-15`) or auto-deriving (`OutputKeyDeriver`).

### 4.8 Security of untrusted JSON upload

Because import creates executable-adjacent config (prompts, tool lists, class names), treat the file as untrusted:
- **Never `constantize`/`safe_constantize` unvalidated strings before validation.** The models already gate this: `Action#validate_service_class` requires an existing constant that includes `Orchestration::Executable` (`action.rb:43-47`); `Agent#validate_tool` checks the namespace allowlist before `constantize` (`agent.rb:61-71`). Importer must go through `save`/validations; no `update_columns`/`insert_all` bypass. Note: `safe_constantize` on an arbitrary class name can trigger autoload (side-effect-free for normal code but still run before the `Executable` check); consider checking `agent_class` against `Orchestration::ServiceRegistry::REGISTRY` keys (`service_registry.rb:3-9`) as a tighter allowlist than the model's rule.
- Prompt injection / supply chain: an imported `prompt` and `tools` list (e.g. write tools like `Records::InsertRowsTool`, `Emails::AddLabelsTool`, `db/seeds.rb:191-193`) determine what an LLM can do with the user's email and DB. Show an import preview/summary (agents created, tools granted, schedule) before commit, and default to disabled.
- Size/DoS: cap upload size (no existing limit found in `config/`), cap nesting depth/step count, use `JSON.parse` with `max_nesting` (default 100) and reject non-Hash roots; parse via `JSON::Helpers.safe_parse` (`lib/json/helpers.rb:9-15`) but surface the parse failure (the helper returns the fallback silently).
- Only accept `application/json`/`.json`; read the file with a size bound; do not log the raw payload (note `Orchestration::LogSanitizer` exists, `lib/orchestration/log_sanitizer.rb`, for run logs).
- Use strict allowlisted keys per level (do not `assign_attributes` from the raw hash; mass-assignment of `id`, `created_at`, etc.). Ignore/reject unknown keys.
- No secrets are in the graph; an exporter must construct output from an explicit allowlist (not `as_json`) so future columns (secrets, ids) are not leaked automatically.

### 4.9 Recommendation (summary)

1. Add `Orchestration::PipelineExporter` / `PipelineImporter` in `lib/orchestration/` (+ RBS), `Orchestration::PipelineImportForm` in `app/forms/orchestration/`, controller `export` (GET `send_data`) and `import` (POST multipart), UI buttons via `UI::PageHeaderComponent`.
2. Format: versioned envelope (`format`, `schema_version: 1`), nested pipeline->steps->step_actions->action, agents referenced by name and optionally embedded; positions derived from array order; no IDs, no timestamps, no runs.
3. Import: single transaction, allowlisted keys, model validations + `Pipeline#validate_steps`, rename-on-collision default, imported as disabled by default, report created/reused agents and actions.
4. Round-trip spec: export -> delete -> import -> assert structural equality (names, order, mappings, output keys).

---

## 5. Open questions for the issue author

1. Scope of "pipeline definition": include **Agent** definitions (prompt, tools, model, output_schema) in the file, or only reference agents by name and require them to exist on the target?
2. Shared **Actions**: should an action used by several pipelines be exported once and re-linked, or inlined per step? On import, reuse an identical existing action or always create new ones?
3. Name collision default: reject, rename, or overwrite? If overwrite, what about existing run history (restricted FK, `step_action.rb:9`)?
4. Should an imported pipeline be created **disabled** (to avoid immediate scheduled runs, `scheduler_job.rb:17-28`) and keep or drop `cron_expression`?
5. One pipeline per file, or bulk export/import of all pipelines (back-up use case)? Is a CLI/rake task (alongside the UI) wanted?
6. Cross-version compatibility: how strictly should `schema_version` be enforced; any need to import older/newer files?
7. Should evaluation-related data (metrics/datasets/prompts keyed by agent name, `docs/schemas.md:308-341`) be part of the backup, or explicitly out of scope?
8. Is an import preview/confirmation step desired given an imported prompt+tools can grant an LLM write access to emails/DB?
9. Is there any need to import from untrusted third parties (public sharing), or only between the author's own installs? This changes how strict the allowlist (e.g. `ServiceRegistry` only) must be.
10. Any size limits or format preferences (pretty-printed, filename convention e.g. `pipeline-<slug>.json`)?
11. `docs/schemas.md` is out of date for orchestration tables (see top). Should updating it be part of this issue?

---

## 6. Decisions (from issue author)

- **`agent_class` is exported as a keyword, not a class name.** Map `SomeClass` -> `'agent_some_class'` on export and back to `SomeClass` on import. An unknown keyword is an import error. This replaces free-form class names and doubles as the allowlist.
- **All settings are included**, including full Agent definitions (prompt, tools, model, output_schema) and `cron_expression`.
- **No overwrite import.** Name collisions are rename-or-reject only; existing run history is never touched.
- **Imported pipelines arrive disabled.**
- **Scope is all pipelines** (bulk export/import for backup), in addition to a single pipeline.
- **No untrusted sources.** Files come only from the author's own installs, so the strict `ServiceRegistry`-only hardening is not required; the keyword map, allowlisted keys and model validations still apply.

- **Shared actions (Q2): option A.** Each step embeds its full action inline; import always creates new `Action` rows (no find-or-create, no dedup). Accepted trade-off: repeated imports create duplicate actions and sharing between pipelines is not preserved.
- **Q6, Q7, Q8, Q10, Q11: no.** `schema_version` is not enforced, evaluation data is out of scope, no import preview, no size limit or filename convention, and `docs/schemas.md` is not updated as part of this issue.

All open questions are resolved.
