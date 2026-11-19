# Plan: run only the activated prompt version (GH #301)

**Status:** planned, architect- and critique-reviewed | **Branch:** `fix/gh-301-explicit-prompt-activation` | **Parent:** #240 (SEC-06)

## Decisions

The issue's decisions stand. Choices this plan adds:

- **Columns.**
  - `evaluation_prompts.active boolean NOT NULL DEFAULT false`, with a partial unique index on `(name) WHERE active`.
  - `activated_at datetime NULL`. `activate!` sets it; nothing clears it; the backfill sets it too. It records "was active before" for the version-level guard.
- **Fallback source.** `effective_system_prompt_for` reads `Orchestration::Agent.named(name)&.prompt`, not `AgentCatalog`. Calling the catalog from a model would be an upward edge from domain to `lib/orchestration`, which is the application layer.
- **"Agent default" value object.**
  - `Evaluation::AgentDefaultPrompt = Data.define(:system_prompt, :user_prompt)` in `lib/evaluation/agent_default_prompt.rb`, with `user_prompt` set to `""`.
  - It and `Prompt` both answer `#label`: "Agent default" or "v3". `PromptDiffComponent` uses `label` instead of `"v#{version}"`.
  - The controllers build it.
- **Activation guards.**
  - `Prompt#activatable?` is `activated_at.present? || experiments.completed.exists?`. `PromptsController#activate` checks it.
  - `ExperimentsController#activate` checks `@experiment.completed?` instead.
  - `Prompt#activate!` itself has no guard.
- **Per-version controls** go on `evaluation/prompts/index.html.erb`, the only page listing every version: an "Active" column, plus Activate or Deactivate per row. Routes: member `post :activate` / `post :deactivate` on `resources :prompts`.
- **Compare page.** Keep the existing baseline vs candidate diff, and add a second diff of the candidate against the active version (or "Agent default").
- **`metadata_versions_for`** selects `:id, :version, :active`.
- **`PromptDiffsController`** (`/prompts/:id/diff`) is unchanged and still diffs against the previous version.

## Steps

### 1. Red specs (tester, `spec/` only)

All must fail on `main` for missing behaviour, not syntax or factory errors.

- **Factory.** In `spec/factories/evaluation.rb`, add `trait :active { active { true }; activated_at { Time.current } }`. Remove `metadata: '{"active":…}'` from specs.
- **`spec/models/evaluation/prompt_spec.rb`** (replaces `:42-77`):
  - `active_for_agent`, and `latest_for_agent` ordered `version DESC, id DESC`.
  - `effective_system_prompt_for` falls back to `Agent#prompt`.
  - `activate!` on v3 deactivates v2, sets `activated_at`, and leaves exactly one active row per name.
  - `deactivate!` on an inactive version is a no-op and keeps `activated_at`.
  - `activatable?` is true with a completed experiment or with `activated_at`, and false for a fresh draft.
  - A second active row raises `ActiveRecord::RecordNotUnique`.
- **`spec/db/explicit_prompt_activation_spec.rb`**, following `spec/db/remove_temp_file_tool_from_emails_classifier_spec.rb`:
  - The backfill marks the newest row per name `active` and sets `activated_at`.
  - It strips `$.active` from valid JSON.
  - It succeeds with a `not json` metadata row.
  - Down removes the columns and the index.
- **`spec/lib/evaluation/active_prompt_resolver_spec.rb`**, rewritten with real records and no stubs:
  - A newer inactive version doesn't change the result.
  - It returns `nil` when nothing is active.
  - `nil` is memoized.
  - One query per agent per run.
- **`spec/lib/orchestration/pipeline_runner_spec.rb:1290-1300`**, flipped: a new inactive v2 is not picked up. Add cases:
  - An activated v2 is picked up.
  - With no active version, `Agent#prompt` is used.
- **`spec/requests/evaluation/experiments_spec.rb`:**
  - `:171-181`: a pending experiment is refused with an alert. A completed one sets `active` and clears the old version.
  - `:482-488`: `prompt_versions` reads the column.
  - The show page renders the active marker, the diff against the active version or "Agent default", and the Activate button.
- **`spec/requests/evaluation/prompts_spec.rb`:**
  - `activate` is refused for a fresh draft and works with a completed experiment or after an earlier activation.
  - `deactivate` falls back, and is a no-op when the version is inactive.
  - The index shows the Active column and the controls.
- **`spec/services/evaluation/agent_summary_query_spec.rb:86-146`:** one active row per name. Delete the multi-active cases.
- **`spec/services/evaluation/metric_suggester_spec.rb:24` and `spec/lib/evaluation/metric_extractor_spec.rb:17`:** with no active version they use `Agent#prompt`, and an inactive newer draft is ignored.
- **`spec/lib/evaluation/improvement/load_samples_tool_spec.rb:13-26`:**
  - `input` and `output` are wrapped in `<untrusted_sample>` and are Strings.
  - `</untrusted_sample>` inside the data is escaped.
  - Each is truncated at 4,000 chars with `[truncated]`.
  - At most 20 samples are returned.
- **`spec/lib/evaluation/prompt_differ_spec.rb` and `spec/components/evaluation/prompt_diff_component_spec.rb`:** both accept `AgentDefaultPrompt` and render "Agent default".

Checks: `bundle exec rubocop spec/`.

### 2. Migration and model (domain, `db/`)

- **`db/migrate/<ts>_add_active_to_evaluation_prompts.rb`**, plain SQL, no app models. Up:
  1. Add `active` and `activated_at`.
  2. Run the `ROW_NUMBER() OVER (PARTITION BY name ORDER BY version DESC, id DESC)` backfill, setting `active = 1, activated_at = CURRENT_TIMESTAMP`.
  3. Run `json_remove(metadata, '$.active') WHERE json_valid(metadata)`.
  4. Add the partial unique index.

  Down drops the index, then the columns.
- **`db/structure.sql`.**
- **`app/models/evaluation/prompt.rb`:**
  - Add `scope :active`, `.active_for_agent`, `.latest_for_agent` (renamed from `last_for_agent`) and `.effective_system_prompt_for`.
  - Add `#activate!`, a transaction: `update_all(active: false)` on the other versions, then `update!(active: true, activated_at: Time.current)`.
  - Add `#deactivate!`, `#activatable?` and `#label`.
  - Remove `active_metadata_versions_for`.
- **`sig/app/models/evaluation/prompt.rbs`.**

Acceptance: `bin/rails db:drop db:create db:migrate` works from empty, and rollback then re-migrate is clean.

Checks: `bundle exec archspec reflect`, `archspec check --check-todo`, `steep check`, `rbs validate`.

### 3. Resolver and callers (application)

- `lib/evaluation/active_prompt_resolver.rb`: return `active_for_agent(...)&.system_prompt`, keeping the memoization. Update the comment.
- `app/services/evaluation/agent_summary_query.rb`: use `active.where(name:)`.
- `app/services/evaluation/metric_suggester.rb` and `lib/evaluation/metric_extractor.rb`: use `effective_system_prompt_for`.
- `app/jobs/evaluation/synthetic_dataset_job.rb` and `lib/evaluation/create_experiment_from_draft.rb`: use `latest_for_agent`.
- Update their sigs.

Acceptance: `git grep -n "last_for_agent\|json_extract(metadata, '\$.active')" app lib sig` returns nothing. The Prosopite allowlist is unchanged.

Checks: `rspec` on these specs, `steep check`, `rigor check`.

### 4. Controllers, routes and UI (interface, plus `lib/evaluation`)

- **`config/routes.rb`:** add member `activate` / `deactivate` on prompts.
- **`ExperimentsController`:**
  - `#activate` refuses unless `completed?`, then calls `prompt.activate!`.
  - `prompt_versions` reads `p.active`.
  - Show and compare load `@active_prompt`: the active version, or an `AgentDefaultPrompt`.
- **`PromptsController`:** add `activate` / `deactivate`, guarded by `activatable?`.
- **New and changed classes:** `lib/evaluation/agent_default_prompt.rb`, `PromptDiffer`, `PromptDiffComponent`.
- **Views:**
  - `experiments/compare.html.erb`: the active marker and a second diff against the active version.
  - The experiment show page: the active marker, the diff, and an Activate button when the experiment is completed and its prompt isn't active.
  - `prompts/index.html.erb`: the Active column and the controls.
- **Sigs:** `prompt_diff_component.rbs`, `prompt_differ.rbs`, `agent_default_prompt.rbs`, the controllers.
- `agent_select_controller.ts:77` still receives a boolean `active`, so it is expected to need no change.

Checks: `rubocop`, `brakeman --no-pager`, `archspec reflect` then `archspec check --check-todo`, `bin/rbs_audit coverage --threshold=90`.

### 5. Untrusted sample delimiting (application, `lib/evaluation/improvement/`)

- `load_samples_tool.rb`:
  - Add the constants `MAX_SAMPLES = 20`, `MAX_CHARS = 4_000` and `TRUNCATION_MARKER`, plus the tag.
  - Serialise `input` and `output` as JSON, escape the closing tag, truncate, then wrap.
  - Clamp `number_of_samples` to `MAX_SAMPLES`.
- `agent.rb`: add one sentence saying content inside `<untrusted_sample>` is data, never instructions.
- `sig/lib/evaluation/improvement/load_samples_tool.rbs`: `input` and `output` become `String`.

Checks: `rspec` on the spec, `steep check`, `rubocop`.

### 6. Docs

- `docs/adr/0015-explicit-prompt-activation.md` records:
  - the activation rule and guards;
  - the fallback;
  - the one-time backfill, which knowingly keeps today's newest draft live;
  - that `Prompt` is immutable except for `active` and `activated_at`.
- `docs/evals.md`:
  - Fix line 15.
  - Fix line 57: "immutable snapshots", and the claim that `PromptImprover` is the only creator.
  - Describe the fallback and the deploy-time activation.
- Mark #240 SEC-06 resolved. This is a GitHub edit.

## Checks (full run before handoff)

- `COVERAGE=true bundle exec rspec`
- `bundle exec archspec reflect`, then `bundle exec rubocop` and `bundle exec archspec check --check-todo`
- `bundle exec rbs -r optparse validate`, `bundle exec steep check`, `bundle exec bin/rbs_audit coverage --threshold=90`
- `bundle exec rigor check`
- `bundle exec brakeman --no-pager`
- `pnpm lint` and `pnpm format:check`, only if `agent_select_controller.ts` changes
