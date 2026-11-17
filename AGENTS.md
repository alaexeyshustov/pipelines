## Essentials

- Be brief.
- Dependency rules live in [Archspec.rb](Archspec.rb); run `bundle exec archspec check`. Don't add to `archspec_todo.yml`.
- Check [.agents/rules/](.agents/rules/) for path-specific conventions (services, forms, specs, signatures). Many are enforced by the custom cops in `lib/rubocop/cop/`.

## Definition of done

The local subset of CI (`.github/workflows/ci.yml`); RubyCritic and mutant stay in CI.

- `COVERAGE=true bundle exec rspec`
- `bundle exec rubocop` and `bundle exec archspec check --check-todo`
- `bundle exec rbs -r optparse validate`, `bundle exec steep check`, `bundle exec bin/rbs_audit coverage --threshold=90`
- `bundle exec rigor check` (setup in [Gotchas](docs/claude/gotchas.md#rigor-rigordistyml-rigor-baselineyml))
- `bundle exec brakeman --no-pager`
- JS changed: `pnpm lint` and `pnpm format:check`

## Role subagents (`.claude/agents/`)

The user runs each role in turn: `planner` → `architect` (cross-layer work) → `tester` (red specs) → `implementor` (green) → `tester` (coverage) → `critique`. Each role reports back to the user. `planner`, `architect` and `critique` are read-only; `tester` edits only `spec/`. A big issue's plan is saved to `docs/plans/gh-<n>-<slug>.md` and committed.

## Project context

- [Schema definition](docs/schemas.md)
- [Architecture overview](docs/architecture.md)
- [Orchestration subsystem](docs/orchestration.md)
- [Evaluations subsystem](docs/evals.md)
- [Local models (Ollama) and `LLM_TEST_BACKEND=ollama`](docs/local_models.md)

## [Gotchas](docs/claude/gotchas.md)