## Essentials

- Be brief.
- Dependency rules live in [Archspec.rb](Archspec.rb); run `bundle exec archspec check`. Don't add to `archspec_todo.yml`.
- Check [.agents/rules/](.agents/rules/) for path-specific conventions (services, forms, components, state machines, specs, signatures). Many are enforced by the custom cops in `lib/rubocop/cop/`.

## Project context

- [Schema definition](docs/schemas.md)
- [Architecture overview](docs/architecture.md)
- [Orchestration subsystem](docs/orchestration.md)
- [Evaluations subsystem](docs/evals.md)

## [Gotchas](docs/claude/gotchas.md)