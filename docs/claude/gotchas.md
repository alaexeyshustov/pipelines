# Gotchas

## Development Workflow

- After `rails db:migrate`, `rails db:schema:load`, or `rails db:reset`, restart the Rails server and run `Rails.cache.clear` in the Rails console. Skipping this can leave stale attribute reflection caches and break the UI.
- If you edit `db/seeds.rb`, run `rails db:seed` before finishing or seed-backed UI elements may be missing.

## Naming and model setup

- Always set `self.table_name` explicitly on namespaced models.
- Follow Zeitwerk autoload naming strictly; class names must match file casing (`LLMJudgeEval`, not `LlmJudgeEval`).
- When creating `Leva::Prompt` records in tests or seeds, always provide a non-blank `user_prompt`.

## Validation and constant resolution

- Do not silently default invalid JSON in Rails forms or controllers; surface it as a real validation error, preserve successfully parsed fields, and keep the raw invalid field visible for correction.
- Do not blindly `constantize` persisted class or tool names; centralize resolution and validate the allowed namespaces or classes first.

## Error handling and caching

- Prefer explicit errors over "impossible" Ruby assumptions.
- Do not use broad Ruby `rescue` paths around cache, parse, or system work; rescue only the failure classes you can actually handle.
- When caching or persisting derived Ruby artifacts, preserve lazy-loading behavior so rehydrated objects behave like freshly loaded ones.

## Mutation testing / CI

- `bin/rails db:schema:load` loads `db/structure.sql` by shelling out to the plain `sqlite3` CLI (`ActiveRecord::Tasks::SQLiteDatabaseTasks#structure_load`), which does **not** go through `config/initializers/sqlite_vec.rb`'s `configure_connection` hook. The `CREATE VIRTUAL TABLE email_vectors USING vec0(...)` statement fails with `no such module: vec0` on a fresh DB — this is silent (backticks don't check exit status) and pre-existing; `email_vectors` is documented as "not yet wired into the main workflow" (see `docs/schemas.md`). Not fixed as part of the mutation-CI reliability work; out of scope there.
- `.github/workflows/mutation.yml` must build JS/CSS assets (`pnpm install && pnpm run build && bundle exec rails tailwindcss:build`) before running mutant, same as `ci.yml`'s `rspec` job — otherwise any selected test that renders the full layout (e.g. `spec/requests/orchestration/pipeline_lifecycle_spec.rb`) raises `Propshaft::MissingAssetError` for `tailwind.css`, which mutant reports as a false "Neutral failure" unrelated to the mutation under test.
- `config/database.yml`'s test env `timeout:` (busy-timeout) was raised from 5000ms to 15000ms as defense-in-depth. The primary contention fix is `spec/mutant_helper.rb`'s `ActiveSupport::ForkTracker.after_fork` hook, which gives each `--jobs N` mutant worker its own private on-disk copy of `storage/test.sqlite3` (mutant forks persistent workers that would otherwise all share one file). This hook only registers when `spec/mutant_helper.rb` is required (mutant-only, via `.mutant.yml`'s `requires:`); a plain `bundle exec rspec` run never loads it.
- **Resolved (2026-07-11):** the per-worker DB isolation above previously showed a ~3.2% intermittent `ActiveRecord::StatementInvalid: Could not find table` on a small, deterministic subset of mutations. Root cause: mutant's nested per-mutation "killfork" (`Mutant::Isolation::Fork`) is a plain block-form `Process.fork`, forked from *inside* the persistent worker after `ForkTracker.after_fork`'s `at_exit` (which deletes the worker's private DB file) already registered — the killfork child inherits that at_exit and fires it when its block returns, deleting the still-running worker's own DB file out from under it on every mutation, not just at real worker shutdown. Fixed by guarding the at_exit with an `owner_pid == Process.pid` check (see `spec/mutant_helper.rb`) so only the process that registered it can actually delete. Verified with 0 occurrences across 2 reruns each at `--jobs 1` and `--jobs 2` on the same representative 343-mutation slice.

