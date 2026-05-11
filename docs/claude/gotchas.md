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

