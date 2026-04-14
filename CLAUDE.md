Rails 8.1 / Ruby 4.0 application that runs a **multi-agent job-application tracking pipeline**. It pulls emails from Gmail and Yahoo Mail, classifies them with Mistral AI, labels them in the provider, and maintains an SQLite database of job applications and interview progress.

- This project uses Rails with SQLite — be aware of SQLite-specific extension issues (e.g., vec0, sqlite_vec) when modifying schema or running `db:test:prepare`
- Prefer configurable singleton patterns with class methods for service objects
- Use TDD for new features and refactoring.
  - Always run `bundle exec rspec` after making changes to models, services, or specs
  
- Use Rubocop omakase style. Run `bundle exec rubocop -a` after editing Ruby files
- Use rubycritic for refactoring.
- Testing Framework: RSpec, FactoryBot, VCR.
- Views: ViewComponent, Tailwind CSS, Turbo, Stimulus.
- Use .rbs type signatures [rbs.md](docs/rbs.md). **After every code change, always update or create the matching `.rbs` file under `sig/` mirroring the source path.**
  - Run `steep check` after modifying type signatures to catch errors early
- Schema Definition (keep synchronized) [schemas.md](docs/schemas.md)
- Mutation testing: `bundle exec rake mutant:baseline` for a full-codebase baseline run. CI reports score for changed files only (`--since origin/main`). Target: 50%. Subjects configured in `.mutant.yml`.
- Use .claude/rules for components-specific rules.
- **JavaScript toolchain:** Uses **pnpm** (not npm/yarn). Always use `pnpm install`, `pnpm run build`, `pnpm run build:watch`. Never use `npm install` or `yarn`. Controllers are written in **TypeScript** (`app/javascript/controllers/*.ts`), bundled by esbuild via `pnpm run build`.
- **Hard-won discoveries:** If something took significant effort to figure out (non-obvious gotcha, tricky integration, surprising behavior), add a brief note about it here so future agents don't repeat the work.
  - **Secondary effects after structural changes (dev only):** After running `rails db:migrate`, `rails db:schema:load`, or `rails db:reset`, always: (1) restart the Rails server to clear stale attribute reflection caches, and (2) run `Rails.cache.clear` in the Rails console. Skipping this causes "unknown attribute" errors and broken UI. 
  - **If you edited `db/seeds.rb` during the task (dev only):** run `rails db:seed` before finishing — modals and pipeline steps won't appear otherwise.
