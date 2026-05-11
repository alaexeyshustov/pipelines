Rails 8.1 / Ruby 4.0 application that pulls Gmail and Yahoo Mail job-application emails, classifies them with Mistral AI, labels them in-provider, and tracks application/interview progress in SQLite.

## Essentials

- JavaScript package manager: `pnpm` (not npm/yarn).
- Asset commands: `pnpm install`, `pnpm run build`, `pnpm run build:watch`.
- Type-signature commands: `bundle exec rbs -r optparse validate sig/**/*.rbs sig/**/**/*.rbs sig/**/**/**/*.rbs`, `bundle exec steep check`.
- Check [.claude/rules/](.claude/rules/) for path-specific guidance for models, services, jobs, views, specs, signatures, and other app layers.

## Task-specific guidance

- [Testing workflow](docs/claude/testing.md)
- [Type signatures](docs/claude/type-signatures.md)

## Project context

- [Schema definition](docs/schemas.md)
- [Architecture overview](docs/architecture.md)
- [Orchestration subsystem](docs/orchestration.md)
- [Evaluations (Leva) subsystem](docs/evals.md)

## [Gotchas](docs/claude/gotchas.md)

If you uncover a new non-obvious gotcha, add a brief note here so future agents do not rediscover it the hard way.
