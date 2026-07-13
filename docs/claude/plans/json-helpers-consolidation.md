# Plan: Consolidate JSON parse/generate duplication into `JSON::Helpers`

Status: **approved** — implement via ralph, TDD required.

## ADR

**Decision:** Wire up the existing (currently zero-caller) `lib/json/helpers.rb` (`JSON::Helpers.safe_parse`/`.safe_generate`) across the genuinely duplicated `JSON.parse`/`JSON.generate` call sites, and add one new helper method (`parse_maybe`). Ship as a single, narrowly-scoped, low-risk PR.

**Drivers:**
1. `JSON::Helpers` already exists, is autoloaded, and is correctly implemented — it should be adopted, not duplicated.
2. Preserve existing behavior exactly, especially the fail-loud/raise semantics at sites that intentionally don't rescue bad JSON (tool/job code, and one write-path controller action).
3. Bound "other pure functions" strictly to what recurs 3+ times with genuinely identical semantics — reject anything that only looks similar on the surface.

**Alternatives considered (and rejected, with rationale):**
- *Extend scope to a shared JSON-Schema helper module* (`SchemaValidator::SCALAR_TYPES` + `SchemaBuilder::TYPES/ENUM_TYPES/NUMERIC_TYPES`) — investigated and rejected: these are structurally unrelated constructs (a type→Ruby-class Hash vs. plain string arrays), each used exactly once, with zero literal duplication between them. If JSON-schema duplication is still perceived, it likely lives elsewhere (e.g. view/ERB layer) and needs a fresh, separate investigation.
- *"Fix" `experiments_controller.rb`'s `activate` action* (a write path with `prompt.update!`) by routing malformed metadata through `safe_parse(fallback: {})` — rejected: this would silently overwrite corrupt stored metadata with `{}` and persist it, discarding data rather than just avoiding a crash. That's a product decision, not a mechanical dedup, and contradicts the fail-loud principle this same plan applies everywhere else.
- *Wire `prompt_improver.rb:78`'s ternary to the same `parse_maybe` helper* — rejected: it branches on `is_a?(Hash)` (not `is_a?(String)`) and parses a different variable than the other two "identical-looking" ternaries; for non-String/non-Hash input it would silently change behavior (uncaught `TypeError` → swallowed pass-through).
- *Wire `llm_judge_eval.rb`'s two parse sites* — rejected: they're guarded by an outer method-level `rescue JSON::ParserError, TypeError → []`, a different case (fail-loud/return-empty) from the sites being swapped; reconciling `parse_output`'s inner fallback semantics against `safe_parse`'s would need its own analysis.
- *Also extract `strftime` date-formatting and `deep_stringify_keys` duplication* — rejected as scope creep: different family (presentational, not JSON), below or at the edge of the 3+ occurrence bar, adds view-layer risk to a backend-focused refactor.

**Why chosen:** This is the only option that satisfies "extract JSON.parse duplication" and stays behavior-preserving and low-risk, without silently changing behavior on write paths or edge cases the surface-level pattern-match missed.

**Consequences:** ~6 files touched, all mechanically verifiable via existing/new specs plus `steep check`. One (`gist_export_service.rb`) carries a theoretical, practically-unreachable behavioral delta (non-String body → `nil` instead of raised `TypeError`), documented rather than hidden. Several adjacent "looks similar" sites are explicitly left alone with recorded reasons, available as separately-scoped follow-ups.

**Follow-ups (not part of this PR):**
- `experiments_controller.rb:~130` (`activate`) — needs a tracked issue and an explicit product decision: is today's fail-loud 500-on-corrupt-metadata intentional, or a latent bug worth fixing (and how, without data loss)?
- `prompt_improver.rb:78` — needs a domain-assumption spec (is `content` guaranteed String-or-Hash?) before any helper-based swap.
- `llm_judge_eval.rb`'s two parse sites — needs reconciliation of its inner/outer rescue semantics before touching.
- Possible JSON-schema duplication elsewhere (if still perceived) — needs fresh investigation.
- `strftime`/`deep_stringify_keys` duplication — noted as a candidate for a separate, unrelated cleanup.

## Scope (single PR)

1. Add `JSON::Helpers.parse_maybe(value, fallback: nil)` to `lib/json/helpers.rb`: returns `value` unchanged if not a `String`, else `JSON.parse`s it (no rescue — preserves fail-loud behavior).
2. Wire `app/services/evaluation/metric_suggester.rb:52` and `lib/evaluation/metric_extractor.rb:43` (both genuinely identical `content.is_a?(String) ? JSON.parse(content) : content` ternaries) to `parse_maybe`.
3. Wire to `JSON::Helpers.safe_parse` / `.safe_generate`:
   - `app/controllers/evaluation/experiments_controller.rb:75` (read-only render)
   - `app/services/interviews/gist_export_service.rb:51` (retaining its existing `parsed.is_a?(Hash) ? parsed.transform_keys(&:to_s) : nil` post-processing unchanged)
   - `lib/orchestration/normalize_action_run_failure.rb`'s `parse_json` (line 160) and `stringify` (~line 198)
4. `experiments_controller.rb:~130` (`activate`, write path) — explicitly excluded, grouped with fail-loud sites (see follow-ups). Do NOT touch.
5. All ~15 fail-loud call sites (14 original + `activate`, + `llm_judge_eval.rb`'s 2) left untouched; verify via `git diff` that none were incidentally changed, and note any missing spec coverage in the PR description (informational only).
6. RBS: widen `safe_parse`'s first param in `sig/lib/json/helpers.rbs` from `String` to `json_object_value` (matches the guarded implementation and the `normalize_action_run_failure.rb` call site's type; confirmed type-only, behavior-neutral change). Add `parse_maybe` sig. `bundle exec rbs -r optparse validate sig/**/*.rbs` and `bundle exec steep check` must both be clean.
7. TDD: spec for `parse_maybe` (String/Hash/Array/nil); behavior-preservation specs at all 6 swap points; explicit documentation (spec comment or PR note) of `gist_export_service.rb`'s theoretical non-String-body delta.
8. **Acceptance checklist:**
   - [ ] `parse_maybe` implemented + spec'd (String/Hash/Array/nil)
   - [ ] 2 ternary sites wired, specs pass
   - [ ] 3 files / 4 swaps wired to `safe_parse`/`safe_generate`, post-processing preserved, specs pass
   - [ ] `gist_export_service` non-String-body edge case documented as accepted low-risk delta
   - [ ] `activate` untouched, excluded, with a tracked follow-up issue + recorded product decision
   - [ ] `safe_parse` sig widened; `rbs validate` + `steep check` clean
   - [ ] Fail-loud sites confirmed untouched via diff; coverage gaps noted
   - [ ] `prompt_improver.rb:78` excluded, noted as follow-up
9. Each item lands as its own commit, independently revertible.

## Reference (from research, for exact context)

Current known call sites (file:line — behavior):
- `app/services/evaluation/metric_suggester.rb:52` — `content.is_a?(String) ? JSON.parse(content) : content` → swap to `JSON::Helpers.parse_maybe(content)`
- `lib/evaluation/metric_extractor.rb:43` — same pattern → swap to `JSON::Helpers.parse_maybe(content)`
- `app/controllers/evaluation/experiments_controller.rb:75` — `JSON.parse(p.metadata || "{}") rescue JSON::ParserError; {}` (read-only) → swap to `JSON::Helpers.safe_parse(p.metadata, fallback: {})`
- `app/controllers/evaluation/experiments_controller.rb:~130` (`activate`) — `JSON.parse(prompt.metadata || "{}")`, then `prompt.update!(metadata: meta.merge(...).to_json)` — **DO NOT TOUCH**
- `app/services/interviews/gist_export_service.rb:51` (`parse_error_body`) — `JSON.parse(body) rescue JSON::ParserError; nil`, followed by `parsed.is_a?(Hash) ? parsed.transform_keys(&:to_s) : nil` → swap parse+rescue to `JSON::Helpers.safe_parse(body, fallback: nil)`, keep the post-processing line unchanged
- `lib/orchestration/normalize_action_run_failure.rb:160` (`parse_json`) — `JSON.parse(value) rescue JSON::ParserError; nil` → swap to `JSON::Helpers.safe_parse(value, fallback: nil)`
- `lib/orchestration/normalize_action_run_failure.rb:~198` (`stringify`) — hand-rolled `JSON.generate` + `rescue JSON::GeneratorError, TypeError` (byte-identical to `safe_generate`) → swap to `JSON::Helpers.safe_generate(value)`
- `lib/json/helpers.rb` (existing): `safe_parse(str, fallback: nil)` guards `return fallback unless str.is_a?(String)` before `JSON.parse`, rescues `JSON::ParserError`; `safe_generate(value)` returns `value.to_s` if already String, else `JSON.generate(value).to_s` rescuing `JSON::GeneratorError, TypeError`.
- `sig/lib/json/helpers.rbs` (existing): `safe_parse: (String str, ?fallback: json_object_value) -> json_object_value` — widen first param to `json_object_value`.
- `sig/shims/types.rbs:36-39`: `json_object_value = json_value | json_array | json_object`, `json_value` includes `nil` — confirms widening is steep-clean.
- `sig/lib/orchestration/normalize_action_run_failure.rbs:51,57` — `parse_json`/`stringify` typed `(json_object_value value) -> ...`.

Explicitly out of scope this PR (see Follow-ups): `prompt_improver.rb:78`, `llm_judge_eval.rb` (`coerce_to_array:57`, `parse_output:130`), all ~14 other fail-loud sites, schema-constant extraction, `strftime`/`deep_stringify_keys` duplication.
