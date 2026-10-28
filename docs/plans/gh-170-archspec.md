# Plan: integrate ArchSpec (GH #170)

**Status:** PR 1 implemented | **Branch:** `feat/gh-170-integrate-archspec`

## Decisions

- Preset: `:layered` with custom ordered layers, plus explicit component rules.
- `:ruby_conventions` composes on top (see [Ruby conventions](#ruby-conventions)).
- `app/tools` is its own layer, a connector between application and domain.
- `Emails::Adapters` stops being referenced from `EmailConnector` (moved out of the model).
- Existing violations that can't be fixed in this PR go to a `Todo` baseline file, not silent exceptions.

## Target `Archspec.rb` (draft, to be validated with `archspec explain`)

```ruby
architecture :layered, layers: {   # order matters: top may depend on everything below
  interface:   %w[app/controllers/**/*.rb app/components/**/*.rb app/helpers/**/*.rb],
  application: %w[app/services/**/*.rb app/forms/**/*.rb app/jobs/**/*.rb
                  lib/orchestration/**/*.rb lib/evaluation/**/*.rb lib/pipeline/**/*.rb],
  tools:       "app/tools/**/*.rb",
  domain:      "app/models/**/*.rb",
  infra:       "lib/emails/**/*.rb"
}
architecture :ruby_conventions

# layers can't separate sibling subsystems, so add component rules:
component(:orchestration, in: %w[lib/orchestration/**/*.rb app/models/orchestration/**/*.rb])
  .cannot_use(:evaluation)
component(:evaluation, in: %w[lib/evaluation/**/*.rb app/models/evaluation/**/*.rb
                              app/services/evaluation/**/*.rb])
# models must not depend on services, jobs or controllers (implied by layer order; add explicit rule if not)
```

Open points for step 2 (confirm with `archspec explain`):
- `lib/orchestration` → `app/tools` (allowlist constants) is application → tools: allowed by order.
- `app/tools` → `lib/orchestration/agents/*` (1 reference) is tools → application: an upward edge. Fix or baseline.
- `config/initializers/orchestration.rb` names `Evaluation::ActivePromptResolver`: outside scanned globs, no change needed.
- `app/services/evaluation/active_prompt_resolver.rb` is the adapter for `Orchestration.prompt_resolver`; check it doesn't create an orchestration → evaluation edge.

## Steps

### 1. Bootstrap
- Add `gem "archspec", "~> 1.1", require: false` to the `development, test` group in `Gemfile`.
- `bundle install`, `bundle exec archspec init`, replace the generated file with the draft above.

### 2. Classify
- `archspec explain` on `lib/orchestration/executors/*.rb`, `lib/orchestration/agents/*.rb`, `app/tools/**`, `app/models/concerns/evaluation/*.rb`, `lib/pipeline/*.rb`.
- Fix globs until classification matches the layer table. `app/agents/` is empty (agents live in `lib/orchestration/agents/`), so it is not listed.

### 3. First `archspec check`
Expected findings from the repo scan:

| Finding | Action |
|---|---|
| `app/models/concerns/evaluation/auto_eval_triggerable.rb:6` enqueues `Evaluation::PromptAutoEvalJob` (domain → application) | **Fix** (step 4) |
| `app/models/email_connector.rb` references `Emails::Adapters::*` (domain → infra) | **Fix** (step 5) |
| `app/tools` → `Orchestration::Agents::EmailsClassifier` (tools → application) | Inspect; fix if trivial, else baseline |
| `get_*` / `set_*` names | See [Ruby conventions](#ruby-conventions) |

Anything left that is not fixed goes into the baseline file with `archspec check --todo`-style generation (verify the exact CLI flag in `lib/archspec/cli.rb`), committed as `.archspec_todo.yml`.

### 4. Remove the callback (test-first)
- Move the `PromptAutoEvalJob.perform_later` enqueue out of `Evaluation::AutoEvalTriggerable` into the code that creates prompts (service/form object, per `.agents/rules/services.md`).
- Delete the concern and its `include`; update/replace its spec.
- Update `.rbs` under `sig/` for every touched file; run `sentinel check` and `steep check`.

### 5. Move adapters out of `EmailConnector`
Interpretation: the model keeps data and validations only; adapter resolution and connection probing move to `lib/emails` (or a service), and callers use that. Confirm placement before implementing.
- `EmailConnector#test_connection`, `resolve_adapter_class`, `probe_connection`, `run_provider_check` and the `connect_*_adapter` helpers move to a collaborator (candidate: `Emails::ConnectionTester` using `Emails::ProviderRegistry`).
- The collaborator writes `status` / `last_connected_at` back, so the caller (`Settings::EmailConnectorsController`, via a service) owns the update, not the model.
- Specs first, then `.rbs`.

### 6. Ruby conventions
`:ruby_conventions` forbids `get_*` / `set_*` / `is_*` method names project-wide. Current hits:
- `set_*` in 13 controllers (`set_pipeline`, `set_step`, `set_agent`, `set_pagination_params` ...). This is the standard Rails `before_action` idiom.
- `get_message`, `get_labels`, `get_unread_count` in `lib/emails.rb` and `lib/emails/adapters/*`. Public API, used by tools and specs.

Proposal: **adopt it**, and handle the hits this way:
- Baseline the controller `set_*` filters (Rails idiom, renaming gains nothing), or rename to `load_*` if the team prefers zero baseline entries.
- Rename `get_*` in `Emails` to plain names (`message`, `labels`, `unread_count`) in a separate follow-up PR, because it touches tools, specs and sigs. Baseline until then.
- Fallback if this proves too noisy: drop `:ruby_conventions` from this PR and file a follow-up. Decide after the first `check` run shows the real count.

### 7. Wire in CI and the pre-commit hook
- `.github/workflows/ci.yml`: add `bundle exec archspec check` next to rubocop.
- `.husky/pre-commit`: add after "Running rubocop...".
- Remove the `harness: add archspec to precommit` TODO item.

### 8. Docs
- Link `Archspec.rb` from `docs/architecture.md`; reference it in `AGENTS.md`.
- Fix stale entries in `docs/architecture.md`: `app/agents/` and `app/evals/` do not exist; agents are in `lib/orchestration/agents/`.
- Add an ADR in `docs/adr/` for the layer order and the tools layer.

### 9. Verify
- `archspec check` exits 0 on a clean tree.
- Negative checks (temporary, reverted): `Evaluation::` reference in `lib/orchestration`; a job reference in a model. Both must fail `check`.
- `rubocop`, `steep check`, `sentinel check`, `rspec --tag '~js'`.

## Suggested PR split
1. Gem + `Archspec.rb` + baseline + CI/hook + docs (steps 1-3, 7-9).
2. Callback removal (step 4).
3. Adapters out of `EmailConnector` (step 5).
4. Ruby-conventions renames (step 6, follow-up).

## Deviations (PR 1)
- Added `todo "archspec_todo.yml"` to `Archspec.rb`; baseline is `archspec_todo.yml` (17 entries, generated with `archspec check --update-todo`).
- Overlapping subsystem components (`orchestration`, `evaluation`) become extra targets of the layered allowlists, so each layer also calls `can_only_use :orchestration, :evaluation` (rules for the same source merge). Evaluation component is declared before orchestration (unknown-component error otherwise).
- Baseline: 12 `get_*` in `Emails` + adapters; 5 layer edges (see ADR 0011). More than the plan expected: `BaseForm` -> controller concern, `Evaluation::Experiment` and `Orchestration::Pipeline` -> application, plus the tools -> agent edge and a cycle.
- Private controller `set_*` filters are not flagged, so no baseline entries for them.
- The `harness: add archspec to precommit` TODO item does not exist in the repo; nothing to remove.
- ADR is 0011.
