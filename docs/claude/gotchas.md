# Gotchas

## ArchSpec reflection facts (`archspec_facts/`)

`archspec check` fails with `facts.stale` when an input of `archspec_facts/rails.yml` changed since it was generated (inputs are tracked by digest). Regenerate and commit it in the same change:

```sh
bundle exec archspec reflect --environment test
```

- Inputs: `app/models/**/*.rb` (associations, validators, concerns), `config/**/*.{rb,yml,yaml}`, `Gemfile`, `Gemfile.lock`, and `RAILS_ENV`. A gem bump alone makes the facts stale.
- No other ENV is captured, so a model whose associations depend on ENV is reflected with the test environment's values.
- `bundle exec archspec check --reflect` refreshes stale facts before checking, but boots `development` by default; prefix it with `RAILS_ENV=test` (the committed facts are for `test`, and a worktree may have no development DB).
- CI runs plain `check` and never boots the app, so stale facts fail CI rather than being regenerated there.

## Steep (`Steepfile`, `.claude/hooks/steep_check.sh`)

- Steep checks `lib/`, `app/jobs`, `app/models`, `app/services` and `app/tools`. The `ignore` entries in `Steepfile` are known gaps: remove one when its files type-check, never add one to get a change through.
- A Claude Code `PostToolUse` hook runs `steep check` on each edited Ruby file in those paths (and on the Ruby file behind an edited `sig/app` or `sig/lib` signature), about 4 s per edit. Its errors arrive as context; it never blocks the edit.
- `rbs_collection.yaml` ignores `ruby_llm`: `sig/shims/ruby_llm*.rbs` types the API this app uses, and loading the collection's version too duplicates declarations. After `rbs collection update`, check `steep check` for `Different superclasses` / duplicate-declaration errors from newly added gems.

## Rigor (`.rigor.dist.yml`, `.rigor-baseline.yml`)

- Rigor is a second static checker next to Steep (GH #171). It infers types from the code and checks all of `app/` and `lib/`, including controllers, forms and components that Steep skips. Steep keeps the coverage gate; never run `rigor sig-gen --write`, which writes into `sig/`.
- Before the first run, and after a `db/structure.sql` change: `bundle exec rbs collection install` and `bundle exec ruby script/rigor_schema.rb`. Without the collection Rigor reports dozens of bogus build failures; without `tmp/rigor/schema.rb` the activerecord plugin runs without column checks.
- Run `bundle exec rigor check`. The husky pre-commit hook runs `rigor check --incremental` (under 1 s warm) and regenerates the schema when `db/structure.sql` is newer. CI fails only on diagnostics not in `.rigor-baseline.yml`. The baseline only shrinks: fix new diagnostics (or add `# rigor:disable <rule>` on the line) rather than regenerating it. After fixing baselined ones, or after bumping the pinned `rigortype`, run `bundle exec rigor baseline regenerate` and check that the diff only removes entries.
- Rigor ignores `# steep:ignore`; lines that need it for Steep stay in the baseline.
- Steep builds RBS classes lazily, so a shim that duplicates a method the collection now declares can pass `steep check`. Rigor reports it as `rbs.coverage.definition-build-failed`. Make the shim an overload with `| ...` rather than deleting it.
