Rails 8.1 / Ruby 4.0 application that runs a **multi-agent job-application tracking pipeline**. It pulls emails from Gmail and Yahoo Mail, classifies them with Mistral AI, labels them in the provider, and maintains an SQLite database of job applications and interview progress.

- Language: Ruby 4.0. 
- Do NOT use Python anywhere.
- Use TDD for new features and refactoring.
- Use rubycritic for refactoring.
- Testing Framework: RSpec
- Do not use shoulda matchers.
- Use VCR casettes to stubb API calls.
- Use .rds  type signatures [rds.md](docs/rbs.md)
- Schemas Defintion (keep synchronised) [schemas.md](docs/schemas.md)
