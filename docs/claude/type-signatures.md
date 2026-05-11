# Type signatures

Use this guidance for Ruby and RBS changes that touch typed code paths.

- After any signature edit, run `bundle exec rbs -r optparse validate sig/**/*.rbs sig/**/**/*.rbs sig/**/**/**/*.rbs`.
- Then run `bundle exec steep check`.
- If `rbs collection install` fails intermittently, retry once before treating it as a real problem.
- If a gem lacks RBS types, add or update a type shim instead of skipping the check.
- `void?` is invalid RBS syntax; if Ruby can return `nil`, use the real nullable type such as `String?` or `bool?`.
- Keep RBS nilability aligned with actual Ruby call paths.
- For deeper signature rules, see [docs/rbs.md](../rbs.md) and [.claude/rules/signatures.md](../../.claude/rules/signatures.md).
