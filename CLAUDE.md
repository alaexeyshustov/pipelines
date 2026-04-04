Rails 8.1 / Ruby 4.0 application that runs a **multi-agent job-application tracking pipeline**. It pulls emails from Gmail and Yahoo Mail, classifies them with Mistral AI, labels them in the provider, and maintains an SQLite database of job applications and interview progress.

- Use TDD for new features and refactoring.
- Use rubycritic for refactoring.
- Testing Framework: RSpec (No Shoulda Matchers), VCR cassettes to stub API calls.
- Use .rbs type signatures [rbs.md](docs/rbs.md). **After every code change, always update or create the matching `.rbs` file under `sig/` mirroring the source path.**
- Schema Definition (keep synchronized) [schemas.md](docs/schemas.md)
- Mutation testing: `bundle exec rake mutant:baseline` for a full-codebase baseline run. CI reports score for changed files only (`--since origin/main`). Target: 50%. Subjects configured in `.mutant.yml`.
- **Hard-won discoveries:** If something took significant effort to figure out (non-obvious gotcha, tricky integration, surprising behavior), add a brief note about it here so future agents don't repeat the work.
