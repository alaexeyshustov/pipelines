# Spike: RubyLLM native evaluation vs. `lib/evaluation` (GH #194)

Scope: can RubyLLM's native evaluation replace the in-app judge / sampler / experiments? Locked version: `ruby_llm 2.1.1` (`Gemfile:14`, `Gemfile.lock:557`). Gem source path below is `$(bundle show ruby_llm)` = `/bundle/ruby/4.0.0/gems/ruby_llm-2.1.1`, abbreviated `GEM/lib/ruby_llm/...`.

Legend: **[F]** = fact with citation. **[I]** = my inference.

## TL;DR

- **[F]** RubyLLM 2.1.0+ **does** ship native evaluation (`RubyLLM::Evaluation`, `RubyLLM::Judge`, `RubyLLM::Judgment`). The app already runs 2.1.1, so no upgrade is needed.
- **[F]** It is a synchronous, in-process, file/DB-agnostic test-style runner with pass/fail/unknown verdicts. It has no persistence, no job fan-out, no experiment state, no 1-5 numeric rubric scoring for ordinary chat models.
- **[I]** Verdict: **partially adopt**. Keep the experiment/dataset/sampler/dashboard machinery custom. Adopt the cheap RubyLLM features around it (usage ledger for judge cost, schema tightening, fallbacks). Optionally add native `RubyLLM::Evaluation` + RSpec `evaluates` as a separate CI regression gate. Do **not** replace `LLMJudgeEval` with `RubyLLM::Evaluation`.

---

## Part 1 - Current system

### Components and interfaces

| Component | Where | Interface (sig/ where present) |
|---|---|---|
| Judge evaluator | `lib/evaluation/evaluators/llm_judge_eval.rb:3` | `evaluate(sample, dataset_sample, agent_name:, model:) -> Array[metric_result]`, `evaluate_and_store(experiment, sample) -> Array[EvaluationResult]` (`sig/lib/evaluation/evaluators/llm_judge_eval.rbs`); `metric_result = {metric_name:, score: Float, justification:}` |
| Judge agent | `lib/evaluation/judge/agent.rb:3` | `class Agent < ::RubyLLM::Agent`, `chat_model Chat`, `model LlmModels.judge`, `schema { array :evaluations { object { metric_name, score:integer, justification } } }` (lines 4-15); sig is an empty class |
| Response parser | `lib/evaluation/evaluators/judge_response_parser.rb:3` | `.parse(content)` coerces to array, drops entries with score outside 1.0..5.0 or blank fields (`:59-61`); `.parse_output` |
| Result writer | `lib/evaluation/evaluators/judge_result_writer.rb:4` | `.call(metric_results:, experiment:, dataset_sample:, sample:, evaluator_class:)`; one transaction `insert_all!` of results + justifications (`:24-33`) |
| Sampler | `app/services/evaluation/sampler.rb:2` | `.call(experiment:, dataset_sample:, prompt:) -> Sample` (`sig/app/services/evaluation/sampler.rbs`); builds a real runtime agent via `Orchestration::SamplingGateway.build` (`lib/orchestration/sampling_gateway.rb:6`), wraps non-readonly tools with a sentinel (`sampler.rb:44-62`), persists tool-call trace + output (`:32-42`) |
| Jobs | `app/jobs/evaluation/{experiment,sampling,evaluation}_job.rb` | `ExperimentJob` fans out one `SamplingJob` per dataset sample (`experiment_job.rb:14`); last sampler applies the 80% threshold (`sampling_job.rb:41-52`, ADR 0009); one `EvaluationJob` per sample calls `LLMJudgeEval.new.evaluate_and_store` (`evaluation_job.rb:18`); `retry_on RubyLLM::Error, attempts: 3` in both jobs |
| Experiment | `app/models/evaluation/experiment.rb:2` | AASM `pending -> sampling -> evaluating -> completed` / `failed` (`:17-39`); counters `pending_samples_count`, `pending_evaluations_count` guard transitions (`:77-83`) |
| Dataset seeding | `lib/evaluation/dataset_seeder.rb:2` | `.call(agent_name:, sample_size: 20)` copies completed `Orchestration` runs into `DatasetSample`s with `ToolCallExtractor.call(run.chat)` as `expected_tool_calls` (`:24-34`) |
| Prompt improver | `lib/evaluation/prompt_improver.rb:2` | `.call(experiment:, model:)`; second `RubyLLM::Agent` (`Evaluation::Improvement::Agent`, `:66`) consuming justifications |
| Metric extractor / suggester | `lib/evaluation/metric_extractor.rb:24`, `app/services/evaluation/metric_suggester.rb` | plain `RubyLLM.chat(...).with_instructions(...).ask` with free-form JSON parsing (no schema) |
| Experiment creation | `lib/evaluation/create_experiment_from_draft.rb:7` | wizard draft -> `Experiment` + `ExperimentJob.perform_later` |
| Model registry | `config/initializers/llm_models.rb` | `LlmModels.judge` / `.evaluation`: Setting table, then ENV, then default `gpt-5.4` (`:17-18`) |

### Data model (`db/structure.sql`)

`evaluation_datasets` (`:33`), `evaluation_dataset_samples` (`:62`: `input` json, `expected_tool_calls` json nullable, `source_run_id`), `evaluation_prompts` (`:34`: versioned, `output_schema`), `evaluation_metrics` (`:35`: per-agent rubric, `weight`, `active`), `evaluation_experiments` (`:94`: `sample_model`, `evaluation_model`, `status`, two pending counters), `evaluation_samples` (`:68`: `tool_calls` json, `output`), `evaluation_evaluation_results` (`:81`: `score` float, `evaluator_class`), `evaluation_justifications` (`:37`: `metric_name`, `justification`), `evaluation_wizard_drafts` (`:47`). Chat persistence for RubyLLM: `chats` (`:128`), `messages` (`:138`), and RubyLLM's usage ledger `ruby_llm_usages` (`:146`, has polymorphic `owner`).

### How the flow works

1. Dataset: seeded from production runs (`DatasetSeeder`) or synthetic (`SyntheticDatasetJob`); `docs/evals.md` "Evaluation Process".
2. Sampling: one job per sample, real tools with write tools blocked (ADR 0008).
3. 80% threshold, then evaluating (ADR 0009).
4. Judging: one `EvaluationJob` per sample; the judge receives a JSON blob with instructions, input, expected/actual tool calls, output, output schema, and active metrics (`llm_judge_eval.rb:64-77`) and returns one score (1-5) + justification per metric.
5. Storage: `JudgeResultWriter`. Overall and per-metric averages are SQL aggregates (`evaluation_result.rb:12-22`).
6. Dashboard: `Evaluation::DashboardController`, `ExperimentsController`, ViewComponents under `app/components/evaluation/` (dashboard, experiment detail, comparison, score-over-time, wizard). They read `EvaluationResult`/`Justification` rows and `LLMJudgeEval.judge_model` (`experiment_detail_component.rb:60`). They have no dependency on RubyLLM types.

### Existing RubyLLM usage

- **[F]** `ruby_llm 2.1.1`; `ruby_llm-monitoring 0.4.0` (third-party engine, mounted at `/monitoring`, `config/routes.rb:8`; `Gemfile.lock:567`). OpenAI protocol pinned to `:chat_completions` (`config/initializers/ruby_llm.rb`).
- **[F]** Already used: `RubyLLM::Agent` subclass with `schema` DSL (judge, improver), `RubyLLM::Agent.new(chat:)` + `with_model/with_tools/with_schema` (`lib/orchestration/runtime_agent_builder.rb:8-41`), `acts_as_chat` (`app/models/chat.rb:4`), `RubyLLM::Tool`, `RubyLLM.chat` (metric extractor), `RubyLLM::Error` retries. The evaluation judge is therefore **already** a RubyLLM structured-output call. It is just not using RubyLLM's evaluation classes.

### Rules that constrain a migration

- `AGENTS.md`: run `bundle exec archspec check`; do not add to `archspec_todo.yml`.
- `Archspec.rb:5-21`: `lib/evaluation/**` and `app/services/**` are `application` layer; `evaluation` component is `lib/evaluation`, `app/models/evaluation`, `app/services/evaluation`; `orchestration` **cannot use** `evaluation`. A native-evaluation wrapper must live in those paths and must not be required from `lib/orchestration`. `RubyLLM` itself is an external gem, not a layer.
- `.agents/rules/services.md`: services expose only `self.call`; no service calling another service's `.call`.
- `.agents/rules/signatures.md`, `Steepfile`: steep checks `lib/`, `app/services`, `app/tools`; hand-written sigs mirror source; avoid `untyped`. **[I]** `sig/` has no RubyLLM type definitions beyond a few references (`git grep RubyLLM -- sig`), and the gem ships no `sig/`, so any new `RubyLLM::Evaluation`/`Judge` usage needs hand-written sigs or `steep:ignore` (the code already uses `# steep:ignore` in `sampler.rb`).
- Name collision **[I]**: inside `module Evaluation`, `Evaluation` resolves to the app module. Subclasses must be written `RubyLLM::Evaluation` fully qualified.

---

## Part 2 - RubyLLM facts (primary sources)

Sources: installed gem `ruby_llm 2.1.1`; https://rubyllm.com (What's New in 2.1, Evaluations, Evaluation Datasets pages); https://github.com/crmne/ruby_llm (releases page, `lib/ruby_llm/evaluation.rb` on `main`). The rubyllm.com `/evaluators/` URL returned 404 when fetched; evaluator behaviour below is taken from the gem source.

### Does RubyLLM have native evaluation? Yes (since 2.1.0)

- **[F]** GitHub releases: `2.1.0` "Adds Judge and Evaluation"; `2.1.1` is a bug-fix release. 2.0.x and earlier releases do not mention them (release notes partly truncated in my fetch, so "earlier" is not fully ruled out). https://github.com/crmne/ruby_llm/releases
- **[F]** https://rubyllm.com/whats-new-in-2-1/ : evaluations, typed judgments, judgment models, reports with tokens and cost.

| Piece | What it is (gem 2.1.1) |
|---|---|
| `RubyLLM::Evaluation` (`GEM/lib/ruby_llm/evaluation.rb:15`) | Subclass with `perform(input)`, optional `setup/assertions/teardown` (`:199-210`), class DSL `dataset`, `evaluator`, `evaluation(name, instructions, minimum:, evaluator:)`, `adapt`, `cases`, `run(dataset:, only:, repetitions:, id:)` (`:30-98`). Assertions are Minitest-style. |
| Dataset (`evaluation/dataset.rb:11-62`, `evaluation/case.rb:19`) | Sources: path or `app/evals/<class>.{yml,yaml,json,jsonl}` auto-discovered, an enumerable, or a **block returning `Case` objects** (so ActiveRecord-backed datasets work; documented at https://rubyllm.com/evaluation-datasets/). `Case(name:, inputs:, metadata:, expected_output:)`; names must be unique; dataset cannot be empty. Only `expected_output` as reference field (`case.rb:20-25`); no `expected_tool_calls` field (could go in `metadata`). |
| Default grading (`evaluation/evaluator.rb:75-113`, `reviewer.rb`) | A `Reviewer < Agent` gets the data as JSON and must return per-criterion `{verdict: pass|fail|unknown, reason}` via an enforced JSON schema. Values: `true/false/nil`. **No numeric score.** `minimum:` is rejected here (`:76-78`). Default criterion: correctness vs `expected_output` (`evaluation.rb:16,185-190`). |
| `RubyLLM::Judge` / `Judgment` (`judge.rb`, `judgment.rb`) | Typed questions: `probability`, `choice`, `score(name, instructions, levels)`. Returns `Probability`/`Choice`/`Score` objects with distributions and confidence (`score.rb:5-26`), plus `tokens` and `cost` (`judgment.rb:52-61`). `minimum:` applies only to these (`result.rb:22-52`). |
| Judgment-capable models | Required for `Judge`/`Score`. In the bundled `models.json`: `gpt-6-luna` (openai) and `jev-latest`/`jev-preview` (typesafe) carry the `judgment` capability; default `default_judgment_model` is `jev-latest` (`configuration.rb:90`). **[F]** The app's judge model default `gpt-5.4` is *not* a judgment model, so `decision_model?` is false and the Reviewer path (pass/fail) is used (`evaluator.rb:52-60`). |
| Report (`evaluation/report.rb`) | In-memory object: `counts`, `pass_rate`, `passed?`, `tokens`, `cost`, `to_h`, `save(path)` writes JSON (`:42-77`). Rake task `ruby_llm:eval[Class,case]` (`GEM/lib/tasks/ruby_llm.rake:5`) saves to `tmp/evaluations/<Class>.json` (per docs https://rubyllm.com/evaluations/). **No DB persistence.** |
| Test integration | `RubyLLM::Evaluation::RSpec#evaluates` and `Minitest#evaluates` (`evaluation/rspec.rb:13`, `minitest.rb:13`). |
| Concurrency | **[F]** `run` iterates cases and repetitions sequentially in one process (`evaluation.rb:113-119`; confirmed against `main`). No parallel option. |
| Instrumentation | `evaluation.ruby_llm`, `evaluation_trial.ruby_llm` events carry `evaluation_id`, per-trial usage via `usage.ruby_llm` (`evaluation.rb:110-121`, `evaluation/runner.rb:40-47`); each trial is wrapped in `RubyLLM.workflow` (`runner.rb:53`). |
| Evidence (`evaluation/evidence.rb`) | Serializes a returned `Agent`/`Chat`/`Message` (incl. tool calls and results) as JSON evidence; AR-backed chats supported via `to_llm` (`:20-26`). |

### Other relevant RubyLLM features (all verified in gem 2.1.1)

| Area | Fact |
|---|---|
| Structured output | `Chat#with_schema` accepts a class or schema hash (`chat.rb:836`); the `Agent` `schema do ... end` DSL is already used in `lib/evaluation/judge/agent.rb`. `schematist ~> 1.1` dependency (`Gemfile.lock:563`). |
| Chat/tool API | `ask`, `complete`, `with_tools`, tool concurrency `:threads`/`:fibers` for tool calls within a chat (`chat/tool_concurrency.rb`). |
| Callbacks | `before_message`, `after_message`, `before_tool_call`, `after_tool_result`, `after_tool_progress`, `before_fallback`, `after_fallback`, `before_request` (`chat.rb:849-913`). |
| Fallbacks | `with_fallbacks(*models, on:)`; default triggers: rate limit, 5xx, overload, Faraday timeouts/connection (`fallback.rb:25-32`). |
| Retries | HTTP-level retry config: `max_retries 3`, interval/backoff (`configuration.rb:210-241`). The app additionally retries at the job layer. |
| Usage / cost | `Judgment#tokens/#cost`, `Report#tokens/#cost`; `RubyLLM.with_usage_owner(record) { }` attributes usage to a record (`ruby_llm.rb:271-276`); `Judge#judge(owner:)` (`judge.rb:148`); AR ledger `ruby_llm_usages` with polymorphic `owner` (`active_record/usage.rb:5-12`) - the table already exists in this app (`db/structure.sql:146`). |
| Model registry | `RubyLLM.models`, `models.json` (1834 models, with `capabilities`, `pricing`); app uses `acts_as_chat` with `ruby_llm_model_id` (`chats` table). |
| Rails | `acts_as_chat`, `acts_as_message`, `acts_as_tool_call`, `acts_as_model`, batch and usage AR helpers (`GEM/lib/ruby_llm/active_record/`). |
| Batch | `RubyLLM.batch(chats)` provider-side batches; `chat.ask_later` (`batch.rb:1-25`, `ruby_llm.rb:339`). Release notes: chat and embedding batches for OpenAI added in 2.0.0 (releases page). Provider coverage beyond that not verified. |
| Embeddings / moderation | `RubyLLM.embed`, `RubyLLM.moderate` (`ruby_llm.rb:350,374`). Neither used by the eval subsystem today. |
| Workflow | `RubyLLM.workflow(name, id:) { |w| w.step(...) }` only adds instrumentation context; "leaving orchestration in ordinary Ruby code" (`workflow.rb:3-5`). |
| Third-party (not RubyLLM) | `ruby_llm-monitoring` (installed; dashboard engine over RubyLLM events, `Gemfile.lock:567`). Contents not verified for this write-up. |

---

## Part 3 - Fit analysis

### Component mapping

| Current | Native equivalent | Replace? | Notes |
|---|---|---|---|
| `LLMJudgeEval` + `Judge::Agent` (1-5 score + justification per metric, DB-defined metrics) | `Evaluation#evaluation(name, instructions)` with Reviewer (pass/fail/unknown + reason); or `Judge#score` (judgment models only) | **No (as a swap)** | **[I]** Loses the 1-5 scale, per-metric weights, and the numeric averages the dashboard and `PromptImprover` rely on. Judge `score` needs `gpt-6-luna`/`jev-*`; and returns a weighted position on levels, a different semantic than an LLM-assigned integer. Metrics are dynamic DB rows (`Metric.active_for_agent`), while native criteria are class-level DSL (a block-style `dataset` exists, criteria do not; **[I]** they could be defined at runtime by building the class dynamically, which is awkward). |
| `JudgeResponseParser` | Enforced schema in native Reviewer | Partly | **[I]** The existing judge already uses a schema, but `score` is an unconstrained `integer`; parser re-validates range. Tightening the schema (min/max, `additionalProperties`) can shrink the parser but not remove range checks for providers that ignore bounds. |
| `Sampler` + `SamplingGateway` (real agent, blocked write tools, tool trace) | `Evaluation#perform(input)` returning an agent; `Evidence` captures messages and tool calls | **No** | **[I]** Sampler is tied to orchestration agent resolution, prompt override and write-blocking, and persists per-sample rows. Native `perform` could wrap `Sampler.call` but adds nothing. |
| `Experiment` (AASM, counters, 80% threshold, SolidQueue fan-out) | `Evaluation.run` (sequential, in-process, no state) | **No** | **[F]** Sequential, no persistence; **[I]** one long synchronous call is incompatible with ADR 0009's per-sample jobs, retries, partial-failure tolerance, and UI progress. |
| `Dataset`/`DatasetSample` (AR; expected tool calls; seeded from prod runs) | `dataset do ... Case.new ... end` | **Adapter only** | **[I]** A small adapter `DatasetSample -> RubyLLM::Evaluation::Case` is easy (`inputs: input`, `metadata: {expected_tool_calls:}`), but only needed if the native runner is used. `expected_output` is absent in the app's data model. |
| Dashboard / results tables | `Report#to_h` JSON | **No** | **[I]** Would need a mapping `Result -> EvaluationResult`; the dashboard stays unchanged only if rows keep the same shape. |
| Model selection (`LlmModels.judge`, per-experiment `evaluation_model`) | `evaluator "model", provider:`; `default_judgment_model` | Compatible | Already equivalent. |
| Cost/token capture for judging | `Judgment#cost`, `ruby_llm_usages` + `with_usage_owner` | **Improve** | **[F]** No eval cost field exists in the eval tables (`structure.sql:81,94`). **[I]** Wrapping judge and sampler calls in `RubyLLM.with_usage_owner(experiment)` gives per-experiment cost via the existing ledger without schema change (verify the AR `Chat`-backed calls also set owner; not tested). |
| Judge resilience | `with_fallbacks` | **Improve** | **[I]** Complements `retry_on`; changes judge model identity per sample, so record the actual model. |
| Judge concurrency | tool concurrency only; batch API for chats | Gap | Already parallel via SolidQueue jobs; provider batch would trade latency for cost (**[I]**, would conflict with the job-per-sample/counter design). |

### What must stay custom

Experiment state machine and job fan-out; 80% threshold; prompt versioning, auto-eval on new prompt versions; wizard and drafts; dataset seeding from production runs; weighted 1-5 metric rubrics stored in DB; dashboard queries; write-blocking sampler.

### Risks

- **[I]** Semantic drift: pass/fail verdicts vs 1-5 scores would invalidate historical comparisons (`ScoreOverTimeComponent`, `Comparison`) unless old and new are kept separate.
- **[I]** Judgment-model dependency: native `score`/`probability` need `gpt-6-luna` or TypeSafe `jev-*`; adds a provider/vendor and cost profile change. The repo pins OpenAI to chat completions (`config/initializers/ruby_llm.rb`); **[F]** the gem comment says OpenAI Decisions is used for `gpt-6-luna` (https://rubyllm.com/whats-new-in-2-1/); compatibility with the pinned protocol is untested.
- **[I]** Young API (first released 2.1.0, one patch later): expect churn. Pin `~> 2.1.1` is already in place.
- **[I]** Test cost: specs use recorded cassettes for LLM calls (comment in `config/initializers/ruby_llm.rb`); a new judge path means re-recording.
- **[I]** Steep/Archspec: new sigs needed; code must live in `lib/evaluation` or `app/services/evaluation` and never be referenced from `lib/orchestration`.
- **[I]** Issue acceptance ("dashboard unchanged", "existing experiments keep working") is best met by *not* changing stored shapes.

### Recommendation: **partially adopt** (do not replace)

The acceptance criteria say "if adopted, judge/scoring behind existing `Evaluation` interfaces". Native evaluation does not offer the required numeric, per-metric, DB-persisted, job-fanned-out behaviour, so replacing the judge path is not justified. Incremental plan, each step independently shippable and keeping `LLMJudgeEval#evaluate(_and_store)`, `JudgeResultWriter`, and table shapes:

1. **Cost capture (small, no schema change).** Wrap `LLMJudgeEval#call_judge` and `Sampler#call` in `RubyLLM.with_usage_owner(experiment)`; add a query (in `Evaluation::AgentSummaryQuery`-style service) summing `ruby_llm_usages` by owner for display later. Spec: owner rows created.
2. **Judge schema hardening.** In `Judge::Agent`, constrain `score` (enum/min/max if supported by `schematist`; verify) and keep `JudgeResponseParser` range check as defence. Update `judge_response_parser_spec`.
3. **Resilience.** Evaluate `with_fallbacks` on the judge chat (record `response.model_id` in `evaluator_class` or metadata if the model varies). Optional.
4. **Optional CI regression gate (separate from dashboard).** Add `RubyLLM::Evaluation` subclasses + `extend RubyLLM::Evaluation::RSpec; evaluates ...` for a few golden cases per agent, with a dataset block adapting `DatasetSample`. Keep it out of the experiment pipeline. Needs sigs/`steep:ignore` and cassette strategy.
5. **Revisit** `RubyLLM::Judge#score` if the team adopts a judgment model; prototype against a few stored samples and compare with current 1-5 scores before any switch.
6. **Docs.** Update `docs/evals.md` (judge/cost sections) and add an ADR; correct the "no third-party eval framework" note to mention native `RubyLLM::Evaluation` was assessed and not adopted. Verify with `bundle exec rspec`, `bundle exec steep check`, `bundle exec archspec check`.

### Open questions / not verified

- Whether `with_usage_owner` attributes usage for `acts_as_chat`-persisted chats (the judge uses `chat_model Chat`) - read of `active_record/usage.rb` only, not executed.
- Whether `schematist` supports numeric bounds that providers enforce.
- Compatibility of `gpt-6-luna` Decisions with `openai_protocol = :chat_completions`.
- Provider coverage of the batch API beyond OpenAI.
- rubyllm.com `/evaluators/` page was unreachable; evaluator semantics here come from gem source.
