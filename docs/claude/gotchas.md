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
