# Testing workflow

Use true TDD for code changes: write and run the failing example first, implement the change, then rerun the targeted spec.

- After Ruby or spec changes, run `bundle exec rubocop -a`.
- Rerun the targeted spec file with `bundle exec rspec path/to/spec_file.rb`.
- If the change also touches RBS, follow the checks in [Type signatures](type-signatures.md).
- For deeper spec conventions, see [.claude/rules/specs.md](../../.claude/rules/specs.md).
