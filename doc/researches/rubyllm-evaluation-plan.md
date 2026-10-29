# Raw plan: move evaluation onto RubyLLM (GH #194)

Draft for parallel subagent execution. Facts and citations: [rubyllm-evaluation.md](rubyllm-evaluation.md).

Principles:
- Use RubyLLM's implementation wherever it exists; keep custom code only where RubyLLM has no alternative.
- If a feature/class is only partly similar, switch to RubyLLM and change our integration to fit.
- No migration/backfill of historical data. Old rows may be dropped or become invalid.
- The 1-5 grade is not mandatory. Any grade scale is fine.

## Decisions (fixed)

- **Grading:** native `RubyLLM::Judge` questions, one per metric. Each metric has a `kind`: `probability` (yes/no, RubyLLM's own default for evaluation criteria), `score` (ordered levels, any count/labels) or `choice` (named options).
- **Single grade (what RubyLLM suggests, verified in gem source):** RubyLLM keeps each criterion's native value (`Probability`, `Score`, `Choice`, or a pass/fail boolean from the reviewer path) in `Evaluation::Result`, with an optional `minimum:` threshold giving `passed`/`failed`/`measured`. It only aggregates as counts and `Report#pass_rate`; it has **no** weighted single grade. So we add a thin normalizer on top (below).
- **Judge model:** `gpt-6-luna` (OpenAI, judgment-capable). Fallback `jev-latest`. Confirm in W1.
- **Normalization to one number (our addition, `Evaluation::GradeNormalizer`):** every metric result becomes a float in **0.0..1.0**, higher is better:

  | Native value | Normalized |
  |---|---|
  | `Probability#probability` | as is |
  | `Score#score` (0-based, between `0` and `levels-1`) | `score / (levels - 1)` |
  | `Choice` | `sum(probability_i * value_i)` using per-option values declared on the metric (0.0..1.0); a single `pass` option set is also allowed |
  | reviewer boolean | `true -> 1.0`, `false -> 0.0`, `nil` (unknown) -> excluded |

  Overall grade of a sample = weighted mean of its metric grades using `Metric.weight`, excluding unknowns/errors; experiment grade = mean over samples. Pass/fail uses per-metric `minimum:` (native semantics) plus an experiment-level pass threshold; the native `pass_rate` is reported alongside. Display as a percentage; raw native values stay in a json column for drill-down.
- **Custom, kept:** experiment record, prompt versioning, wizard/drafts, dataset seeding from production runs, dashboard UI, write-tool blocking in the sampler, job fan-out (RubyLLM runs cases sequentially).

## Shared contracts (agree before starting; every workstream codes to these)

1. **Metric definition.** `evaluation_metrics` gains `kind` (`probability` default | `score` | `choice`), `levels` (json: ordered descriptions for `score`; `{option => {description, value}}` for `choice`), `minimum` (float 0.0..1.0, nullable, per-metric pass threshold). Existing `weight` is reused. Owner of the migration: W1.
2. **Result shape.** `evaluation_evaluation_results.score` is the **normalized 0.0..1.0** grade; new columns `raw` (json: native `to_h`), `confidence` (float, nullable), `passed` (boolean, nullable). `evaluation_justifications` stays for text reasons. Owner of the migration: W1 (single migration file, written first, others rebase on it).
3. **Grader.** `Evaluation::Grader.call(experiment:, dataset_sample:, sample:) -> Array[Grade]`, `Grade = Data.define(:metric_name, :score, :raw, :confidence, :passed, :justification, :tokens, :cost)` where `score` is already normalized. `Evaluation::GradeNormalizer.call(value:, metric:) -> Float | nil` and `Evaluation::SampleGrade.call(grades:, metrics:) -> Float` (weighted mean) are W1's too. W1 implements; W3, W5 call.
4. **Case adapter.** `Evaluation::DatasetCases.call(dataset:) -> Array[RubyLLM::Evaluation::Case]` and `.for_sample(dataset_sample)`. W2 implements; W3/W6 call.
5. **Sampler.** `Evaluation::Sampler.call(experiment:, dataset_sample:, prompt:) -> Sample` keeps its signature; internals move to the native `perform`/`Evidence` model. W2 implements; W3 calls.
6. **Usage owner.** Every LLM call made for an experiment runs inside `RubyLLM.with_usage_owner(experiment)`. W4 provides `Evaluation::UsageScope.call(experiment) { ... }` (thin wrapper), others use it.
7. **Namespace.** Inside `module Evaluation` always write `RubyLLM::Evaluation` fully qualified (name collision).
8. **Layering.** New code only in `lib/evaluation`, `app/models/evaluation`, `app/services/evaluation`; nothing in `lib/orchestration` may reference it. `bundle exec archspec check` must pass; no `archspec_todo.yml` additions.

## Workstreams (parallel, disjoint file ownership)

Each agent: read `AGENTS.md`, `.agents/rules/`, `docs/evals.md`, the research doc; write code + specs + hand-written `sig/` for its own files; run its own specs, `steep check`, `rubocop`, `archspec check`; do not touch files owned by another workstream (raise a contract change instead).

### W1 - Grading core (native Judge)
Owns: `lib/evaluation/evaluators/*`, `lib/evaluation/judge/*`, `lib/evaluation/grader*`, the schema migration from contracts 1-2, matching specs/sigs, `spec/factories` for metrics/results.
- Build a `RubyLLM::Judge` at runtime from active DB `Metric` rows (one question per metric, type from `metric.kind`; levels/options from `metric.levels`). Prefer calling `Judge#judge(input, questions: {...}, owner:)` with the dynamic `questions:` hash over generating classes.
- Input to the judge: sample output, input, expected/actual tool calls (same payload idea as today's `llm_judge_eval.rb:64-77`).
- Implement `GradeNormalizer` and `SampleGrade` per the normalization table; unit-test every native value type, `nil`/unknown and error handling.
- Map `Judgment` to `Grade`s (`passed` from `metric.minimum`, mirroring native `Result#decision`); persist via a slim result writer (`insert_all!` of results + justifications in one transaction, as today).
- Open point: `Judge#score` may not return a free-text reason. If not, either (a) add a native `Reviewer`-style reason pass, or (b) derive the justification from level probabilities/`Score` data. Decide and document; W4 (improver) depends on the answer.
- Verify `gpt-6-luna` with `openai_protocol = :chat_completions`; fall back to `jev-latest` if it fails. Update `LlmModels.judge` default.
- Delete: `LLMJudgeEval`, `Judge::Agent`, `JudgeResponseParser`, their specs/sigs.

### W2 - Dataset and system under test
Owns: `lib/evaluation/dataset_seeder.rb`, new `lib/evaluation/dataset_cases.rb`, `app/services/evaluation/sampler.rb`, `lib/evaluation/tool_call_extractor*` (if present), matching specs/sigs.
- `DatasetCases`: `DatasetSample` -> `RubyLLM::Evaluation::Case` (`name` unique per sample, `inputs`, `metadata: {expected_tool_calls:}`, `expected_output` if available).
- Sampler: keep write-tool blocking via `SamplingGateway`; run the agent as the body of a native `perform(input)` and capture the result with `RubyLLM::Evaluation::Evidence` (messages, tool calls, results). Replace hand-rolled tool-call trace persistence with Evidence if it carries the same data; otherwise keep the minimum custom piece and document the gap.
- Keep `DatasetSeeder` and `SyntheticDatasetJob` (no RubyLLM equivalent).
- Confirm the sentinel wrapper still blocks writes inside `perform`.

### W3 - Run orchestration and experiment model
Owns: `app/jobs/evaluation/*`, `app/models/evaluation/experiment.rb`, `lib/evaluation/create_experiment_from_draft.rb`, state-machine migrations (separate migration file from W1's), matching specs/sigs.
- Collapse `SamplingJob` + `EvaluationJob` into one per-sample job: Sampler (contract 5) then Grader (contract 3), wrapped in `UsageScope`.
- Keep `ExperimentJob` fan-out; replace the two pending counters with one; simplify AASM to `pending -> running -> completed | failed`.
- Keep the 80% completion threshold as policy; update ADR 0009 text accordingly.
- Remove job-level `retry_on RubyLLM::Error` where RubyLLM HTTP retries/fallbacks suffice; keep one outer retry for transport errors.
- Optionally subscribe to `evaluation_trial.ruby_llm`-style events for progress instead of counters (only if W3 confirms it works across job processes; otherwise counters stay).
- Stub W1/W2 contracts with fakes until they land.

### W4 - Cost, schemas, resilience, auxiliary agents
Owns: `lib/evaluation/metric_extractor.rb`, `app/services/evaluation/metric_suggester.rb`, `lib/evaluation/prompt_improver.rb`, `Evaluation::UsageScope`, `config/initializers/llm_models.rb`, matching specs/sigs.
- `UsageScope` (contract 6) around `RubyLLM.with_usage_owner`; add a query service summing `ruby_llm_usages` by experiment (cost + tokens) for the dashboard (W5 consumes).
- `MetricExtractor` and `MetricSuggester`: drop free-form JSON parsing, use `with_schema`/Agent schema DSL; suggester must now propose per-metric `levels`.
- `PromptImprover`: consume the justification format decided in W1; keep as a `RubyLLM::Agent`.
- Add `with_fallbacks` to judge-side and improver chats; record the actual model used.
- Verify `with_usage_owner` works with `acts_as_chat` chats and inside SolidQueue jobs.

### W5 - Dashboard and UI
Owns: `app/components/evaluation/*`, `app/controllers/evaluation/*`, views, `Evaluation::*Query` services, component specs and screenshot suite for evaluation pages.
- Scores are now normalized 0.0..1.0: show as percentages; update averages, comparison and score-over-time (axes, thresholds, colour bands). Show pass rate next to the weighted grade; drill-down shows `raw` (level label, probabilities, confidence).
- Show cost/tokens per experiment from W4's query (additive, no layout overhaul).
- Replace `LLMJudgeEval.judge_model` reference with the stored model id.
- Wizard: metric editor gains level definitions.
- Until W1's migration lands, develop against the contract-2 columns using factories.

### W6 - Regression gate, docs, cleanup
Owns: `spec/evals/**` (new), `docs/evals.md`, `docs/schemas.md`, ADRs, `AGENTS.md` label, legacy-named spec factory file/migration remnants, `sig/` index files.
- Add native `RubyLLM::Evaluation` classes with `extend RubyLLM::Evaluation::RSpec; evaluates ...`, a few golden cases per agent, using `DatasetCases` (contract 4).
- Update `docs/evals.md`, `docs/schemas.md`, ADR 0008/0009, add an ADR "native RubyLLM evaluation"; remove references to the old judge/parser/counters; rename legacy-named files and labels so no third-party naming remains.
- Final dead-code sweep after other workstreams merge.

## Integration order

1. W1 lands the migration (contracts 1-2) first, small and fast; all others rebase on it.
2. W1-W5 proceed fully in parallel against the contracts, using fakes where a neighbour is not ready.
3. Merge order: W1, W2, W4 (independent) -> W3 (needs W1+W2) -> W5 (needs schema + W4 query) -> W6.
4. Final gate by the integrator (not a workstream agent): `bundle exec rspec`, `bundle exec steep check`, `bundle exec rubocop`, `bundle exec archspec check`, screenshot suite for evaluation pages.

## Risks

- `RubyLLM::Evaluation`/`Judge` are new (2.1.0): API churn, thin docs.
- Weighted-mean normalization is our design (RubyLLM provides none): probability outputs are not calibrated across judgment models; keep metric weights and thresholds under review after first real runs.
- `Judge#score` may lack a free-text reason (W1 open point); affects the prompt improver.
- Judgment-model vendor dependency; `gpt-6-luna` + chat-completions compatibility unverified.
- Contract drift between parallel agents: any contract change must be raised to the integrator, not edited locally.
- Cassette re-recording across eval specs.
- In-flight experiments when the state machine changes (acceptable: no data preservation required).
