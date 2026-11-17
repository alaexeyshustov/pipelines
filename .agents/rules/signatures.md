---
paths:
  - "sig/**/*.rbs"
---

# RBS signatures

See also [docs/rbs.md](../../docs/rbs.md) and [docs/claude/type-signatures.md](../../docs/claude/type-signatures.md).

- Signatures are hand-written, including ActiveRecord column readers; `rbs_rails` is not run.
- Instead of `untyped`, prefer unions, optionals, generics, interfaces (`_Name`), or type aliases.
- Side-effect-only methods return `void`, not `nil`.
- Declare private helpers too; steep checks `lib/`, `app/jobs`, `app/models`, `app/services` and `app/tools` (see `Steepfile` for the ignore list, which may only shrink).
- ActiveRecord class methods and gem DSL (`acts_as_chat`, AASM events, scopes on a collection proxy) are declared by hand: shared ones in `sig/app/models/application_record.rbs` / `sig/shims/`, model-specific ones in the model's sig.
