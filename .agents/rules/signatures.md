---
paths:
  - "sig/**/*.rbs"
---

# RBS signatures

See also [docs/rbs.md](../../docs/rbs.md) and [docs/claude/type-signatures.md](../../docs/claude/type-signatures.md).

- `sig/` mirrors the source tree: `app/models/foo.rb` → `sig/app/models/foo.rbs`, `lib/orchestration/x.rb` → `sig/lib/orchestration/x.rbs`.
- Signatures are hand-written, including ActiveRecord column readers; `rbs_rails` is not run.
- Avoid `untyped` (flagged by the `RBS/Lint/NoUntyped` cop); prefer unions, optionals, generics, interfaces (`_Name`), or type aliases. Type collection elements (`Array[String]`, `Hash[Symbol, Integer]`), not bare `Array`/`Hash`.
- Open full namespace blocks (`module Orchestration` / `class Action`); never write `class Orchestration::Action`.
- Side-effect-only methods return `void`, not `nil`.
- Declare private helpers too; steep checks `lib/`, `app/jobs`, `app/models`, `app/services` and `app/tools` (see `Steepfile` for the ignore list, which may only shrink).
- ActiveRecord class methods and gem DSL (`acts_as_chat`, AASM events, scopes on a collection proxy) are declared by hand: shared ones in `sig/app/models/application_record.rbs` / `sig/shims/`, model-specific ones in the model's sig.
