Rails 8.1 / Ruby 4.0 application that runs a **multi-agent job-application tracking pipeline**. It pulls emails from Gmail and Yahoo Mail, classifies them with Mistral AI, labels them in the provider, and maintains an SQLite database of job applications and interview progress.

## TDD
  **Always use TDD**

  - Always run `bundle exec rubocop -a` after making changing a file to fix style issues
  - Always run `bundle exec rspec -f FILE` after making changing a file to run a single test file
  - Always Run `steep check` after modifying type signatures to catch errors early

## Overview

- Schema Definition (keep synchronized) [schemas.md](docs/schemas.md)
- **Architecture & Subsystems:**
  - [Architecture Overview](docs/architecture.md)
  - [Orchestration Subsystem](docs/orchestration.md)
  - [Evaluations (Leva) Subsystem](docs/evals.md)

## Gotchas
  - Use .claude/rules for components-specific rules.
  - **JavaScript toolchain:** Uses **pnpm** (not npm/yarn). Always use `pnpm install`, `pnpm run build`, `pnpm run build:watch`. Never use `npm install` or `yarn`. Controllers are written in **TypeScript** (`app/javascript/controllers/*.ts`), bundled by esbuild via `pnpm run build`.
    - **Hard-won discoveries:** If something took significant effort to figure out (non-obvious gotcha, tricky integration, surprising behavior), add a brief note about it here so future agents don't repeat the work.
      - **Secondary effects after structural changes (dev only):** After running `rails db:migrate`, `rails db:schema:load`, or `rails db:reset`, always: (1) restart the Rails server to clear stale attribute reflection caches, and (2) run `Rails.cache.clear` in the Rails console. Skipping this causes "unknown attribute" errors and broken UI. 
      - **If you edited `db/seeds.rb` during the task (dev only):** run `rails db:seed` before finishing — modals and pipeline steps won't appear otherwise.
