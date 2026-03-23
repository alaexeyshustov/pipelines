# RBS Type Signatures

All Ruby source files have corresponding RBS signatures under `sig/`, mirroring the source tree:

```
sig/app/models/          ← ApplicationRecord, ApplicationMail, Interview, EmailVector
sig/app/agents/          ← one .rbs per agent class
sig/app/tools/           ← one .rbs per tool class
sig/app/services/        ← MailService
sig/lib/pipeline/        ← JobsWorkflow, Logger, TestWorkflow
sig/lib/emails/          ← GmailAuth, ProviderRegistry
sig/lib/emails/adapters/ ← BaseAdapter, GmailAdapter, YahooAdapter
```

**Signature maintenance rules — apply after every code change:**

- When you **add a new class or module**: create the matching `.rbs` file under `sig/` in the same relative path.
- When you **add or change a method signature** (parameters, return type, visibility): update the corresponding `.rbs` file to match.
- When you **add a constant** (`FOO = ...`): declare it in the `.rbs` with the correct type.
- When you **add an instance variable** assigned in `initialize`: declare it as `@var: Type` in the `.rbs`.
- When you **delete a method or class**: remove its declaration from the `.rbs`.
- When you **rename** anything: update both the `.rb` and the `.rbs` together.

Run `bundle exec rbs validate sig/**/*.rbs sig/**/**/*.rbs sig/**/**/**/*.rbs` after any signature edit to confirm syntax is valid.

**Typing conventions used in this project:**

- Use `untyped` for RubyLLM / ActiveRecord meta-programmed return values that cannot be expressed statically.
- Tool `execute` methods return `untyped` unless the return shape is fully known.
- Agent subclasses have minimal `.rbs` bodies (just `class Foo < RubyLLM::Agent; end`) because all behaviour is declared via DSL macros.
- Hash shapes with known keys use inline literal types: `{ status: String, rows_added: Integer }`.
- Prefer named type aliases (`type foo_result = ...`) over anonymous hashes when a shape is shared or complex.
