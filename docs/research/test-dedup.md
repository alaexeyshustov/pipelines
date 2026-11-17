# Research: deduplicating the spec suite (GH #188)

Question: which specs assert the same behaviour more than once, and can they be removed or merged without lowering line coverage, mutation coverage or speed?
Sources: this repo at `d8793c4d` (2026-11-17); a full non-js run (`rspec --tag '~js'`, **2974 examples, 0 failures, 80.7 s + 37 s load**) with line coverage recorded per example; and `mutant run` on the subjects involved. Checked on 2026-11-17.

**Short answer: the overlap is small and sits in four places.** Deleting **27 examples** loses **0 covered lines**. Mutation scores stay the same, as long as the one naming bug in §3 is fixed first. Merging two near-identical spec files into shared examples saves about 40 more lines. Runtime gains will be small, about 3–4 s at most. Most cross-layer overlap is just the test pyramid working and should stay.

| # | Cluster | Action | Examples removed |
|---|---|---|---|
| A | `Evaluation::DatasetSeeder` is tested in two files, and the rake task spec repeats its behaviour | Keep one spec in `spec/lib/`, and trim the task spec down to its wiring | 9 (+ about 4 in the task spec) |
| B | `SchemaBuilder` round-trip is tested in both `schema_builder_spec` and `schema_builder_round_trip_spec` | Drop the 2-example block from `schema_builder_spec` | 2 |
| C | `NormalizeActionRunFailure` spec repeats `ProviderErrorResponse` parsing | Drop 5 contexts; first rename one `describe` in the `ProviderErrorResponse` spec (§3) | 5 |
| D | The `pipeline_lifecycle_spec` "edit" block repeats per-endpoint request specs | Drop it after porting 1–2 assertions | 11 |
| E | `Email::SearchQuery` and `Document::SearchQuery` specs are identical apart from the model | Merge into `shared_examples` | 0 (≈40 LOC) |

---

## 1. Method

`spec/support` was left unchanged. A scratch helper loaded with `rspec -r` did the following:
1. It started `Coverage` before boot and eager-loaded the app in `before(:suite)`.
2. It threw away load-time coverage, so class bodies, associations and AASM declarations count for no example.
3. Around each example, it took `Coverage.result(clear: true, stop: false)` and kept the `app/` and `lib/` lines.

That produced 2974 per-example line sets covering 4182 distinct executable lines. Three views came from that data:
- **File subsumption:** pairs of spec files where ≥ 90 % of A's lines are also covered by B. There are 240 such pairs.
- **Identical-coverage groups:** 27 groups that span more than one file.
- **The same `RSpec.describe` constant used in several files**, plus spec basenames that repeat.

Every candidate was then read by hand. Coverage only shows *where* to look. Two examples can run the same lines and still assert different things.

What the signals showed:
- **Cross-layer subsumption is mostly noise.** `requests/home_spec.rb` (24 lines) is a subset of every other request spec, because they all render the layout. Component specs are subsets of the request specs that render those components. That is the intended pyramid, not duplication.
- **Identical-coverage groups are mostly declarative.** One example is the 23 `LlmModels`/`Setting` examples that each touch the same 2 lines. Their assertions differ.
- **162 examples cover no `app/`/`lib/` lines once load time is excluded.** They are model validation and association specs plus `db/seed_*` specs, and they are not duplicates.

## 2. Clusters

### A. `Evaluation::DatasetSeeder`: one class, two unit specs and a task spec

The class is `lib/evaluation/dataset_seeder.rb`. It is specified in both `spec/lib/evaluation/dataset_seeder_spec.rb` (9 examples) and `spec/services/evaluation/dataset_seeder_spec.rb` (13 examples). The second file is misplaced: `.agents/rules` says `spec/lib/` is for `lib/` code.

Each of the 9 `lib/` examples has a counterpart in the `services/` file:

| `spec/lib/…` | `spec/services/…` |
|---|---|
| creates a Dataset when one does not exist | creates a dataset named after the agent |
| reuses an existing Dataset with the same name | does not duplicate the dataset when called twice |
| creates DatasetSamples for completed ActionRuns | creates a dataset sample linking … / skips action runs with status other than completed |
| does not create DatasetSamples for a different agent | skips action runs for a different agent name |
| skips ActionRuns with no associated chat | skips action runs without a chat |
| stores expected_tool_calls extracted from the chat | stores expected_tool_calls extracted via ToolCallExtractor |
| returns a Result with the correct created count | returns a result with agent_name, created, and skipped counts |
| returns a Result with the correct skipped count | returns correct skipped count on second call |
| respects the sample_size limit | respects sample_size limit |

Coverage agrees: the 24 lines of the `lib/` file are a subset of the 36 lines of the `services/` file.

`spec/tasks/evaluation_seed_dataset_spec.rb` repeats 5 seeder behaviours: it creates the dataset, creates samples, stores the input, and checks two idempotency cases. A rake task spec only needs to check the wiring: arguments reach the seeder, output is printed, and an unknown agent raises.

**Action:**
1. Move the `services/` file to `spec/lib/evaluation/dataset_seeder_spec.rb`, replacing the current one.
2. Cut the task spec down to its wiring examples.

`Evaluation::DatasetSeeder` is not in `.mutant.yml`'s subject list, so the mutation score cannot change.

### B. `Orchestration::SchemaBuilder` round-trip

`spec/models/orchestration/schema_builder_spec.rb:141-171` has a `from_schema → to_schema round-trip` block with 2 examples. It uses one `Person` schema, plus a variant with `format`. `schema_builder_round_trip_spec.rb` runs a table of 13 schemas through the same round trip, and that table includes `format`, `enum`, bounds and objects with `required`. The 60 lines it covers are a subset of the other file's 79.

**Action:** delete the 2-example block. Both files describe `Orchestration::SchemaBuilder`, so mutant selects the corpus file for every subject anyway.

### C. `NormalizeActionRunFailure` re-tests `ProviderErrorResponse`

`NormalizeActionRunFailure` hands provider HTTP errors to `ProviderErrorResponse` (`lib/orchestration/normalize_action_run_failure.rb:24`). Five contexts in `normalize_action_run_failure_spec.rb:84-138` match `provider_error_response_spec.rb:34-72` almost line for line:
- nested `error.message`
- a body that is not JSON
- a JSON array body
- no message or error keys
- the "An unknown error occurred" sentinel

Measured with `mutant run --jobs 4`:

| Subject | Before | 5 contexts removed |
|---|---|---|
| `Orchestration::NormalizeActionRunFailure*` | 400/433, **92.37 %** | 400/433, **92.37 %** |
| `Orchestration::ProviderErrorResponse*` | 79/284, **27.81 %** | 79/284, **27.81 %** |

The removal changes nothing, because mutant never ran those contexts against `ProviderErrorResponse`. That subject's low score is the issue in §3.

**Action:** fix §3 first, then delete the 5 contexts. That leaves the provider-error behaviour tested once, in the spec that mutant actually uses for it.

### D. `requests/orchestration/pipeline_lifecycle_spec.rb` "edit" block

`describe "edit: …"` (lines 121-241, 10 examples) and the "trigger endpoint" example (line 109) each hit one endpoint and assert what the per-endpoint request specs already assert:

| lifecycle example | already in |
|---|---|
| updates pipeline name and description | `pipelines_spec.rb` "PATCH … updates and redirects" |
| renames an existing step | `pipelines_spec.rb:211` |
| adds a new step at the end | `pipelines_spec.rb` (POST steps) |
| attaches a service-object action | `pipelines_spec.rb:297`, `step_actions_spec.rb:20` |
| removes a step | `pipelines_spec.rb:236`; StepAction cascade in `models/orchestration/step_spec.rb:178` |
| moves a step down / up | `pipelines_spec.rb:248-295` (these also cover the edge cases) |
| detaches an action and attaches a different one | `pipelines_spec.rb:449` + `:297` |
| toggles a step's enabled state | `steps_spec.rb:6-25` |
| disables then re-enables the pipeline | `pipelines_spec.rb:417-435` |
| uses the HTTP trigger endpoint to enqueue a run | `pipelines_spec.rb:313-415` |

The "setup" block and the `:llm` "run" block stay. Together they are the one journey test for the whole pipeline.

**Action:**
1. Check two lifecycle assertions that the per-endpoint specs may not have yet: the new step lands at `position` 3, and the `StepAction` count drops through the request. Port them if they are missing.
2. Delete the 11 examples.

Pipeline and step controllers are on mutant's ignore list, so the mutation score cannot change.

### E. `Email::SearchQuery` / `Document::SearchQuery`: merge, don't delete

The two service classes are identical apart from the model and the `Hit` field (`diff app/services/{email,document}/search_query.rb`). Lines 1-44 of the two specs differ only in factory and attribute names. Those lines hold the 7 text-mode examples plus the parametrised FTS-operator examples. The ranking itself lives in the shared `ranked_search`, so each model still needs its own check.

**Action:** create `shared_examples "ranked full-text search"` in `spec/support/shared_examples/`, parametrised by factory, text attributes and hit reader. Leave the model-specific semantic and hybrid examples where they are. This merges code; it removes no examples.

## 3. Side finding: mutant skips most of `ProviderErrorResponse`'s spec

Mutant chooses which tests to run for a subject by turning example-group descriptions into match expressions. `provider_error_response_spec.rb:25` is named `describe "#status, #body, #parsed_error, #message"`, which does not parse as an expression. As a result, mutant runs only **3 of the 10** examples (`Selected-Tests: 3`).

Renaming it to `describe "#message"` raises the selection to **10** and the score from **27.81 % to 85.56 %** (243/284). It is the only `describe` in `spec/` that names several methods (`grep -rnE 'describe "[#.][^"]*[, ][#.]' spec`).

This matters for the issue as a whole. When two specs overlap, delete the copy that mutant does *not* select. Otherwise the mutation score can fall even though line coverage stays the same.

## 4. Checked and kept

- **`integration/orchestration/pipeline_runner_integration_spec.rb` ⊂ `lib/orchestration/pipeline_runner_spec.rb`** by coverage. It is the VCR/`:llm` end-to-end path through real RubyLLM, so it has a different purpose and stays.
- **7 `gmail_adapter*_spec.rb` files**, all for one class. They split by method and never assert the same thing twice. Combining them would only save the repeated `let(:json)` and `before { setup_gmail }` lines. The class is also on mutant's ignore list.
- **Gmail/IMAP adapter specs ⊂ `jobs/email/sync_inbox_job_spec.rb`**, and **component specs ⊂ request specs.** These are integration tests running unit-tested code, which is the expected pyramid.
- **`chats/` and `interviews/batch_service_spec.rb`** (3 + 2 examples). They are alike but too small for shared examples to pay off.

## 5. Acceptance criteria

| Criterion | Status |
|---|---|
| Duplicates identified | Clusters A–E above. |
| Removed or merged | Not done yet: this is the plan. |
| Line coverage does not drop | Per-example data: dropping the 27 examples in A–D leaves **0 lines** covered only by them. |
| Mutation coverage does not drop | C was measured and stays at 92.37 %. A, B and D are outside the mutant scope or are selected through another file. §3 should land first. |
| Runtime the same or lower | The affected files take about 7 s in isolation, and removing their duplicates saves roughly 3–4 s of the 80 s run. This criterion passes, but the gain is minor. |

The task-spec trim in A was not measured, and E was not built.

## 6. Result (A–D applied)

- **Examples:** 2974 → **2942** (−32: A 9 + 5 from the task spec, B 2, C 5, D 11). The rename in §3 was done first.
- **Lines covered:** 4182 → **4182**, with 0 lines lost, measured by re-running the per-example coverage.
- **Mutation:**

| Subject | Before | After |
|---|---|---|
| `ProviderErrorResponse` | 27.81 % | **85.56 %** |
| `NormalizeActionRunFailure` | 92.37 % | 92.37 % |
| `SchemaBuilder` | 88.96 % | 88.96 % |

- **Ported before deleting:** the pipeline `description` update, now in `pipelines_spec.rb` "updates and redirects". Every other lifecycle assertion already existed in another spec.
- **Changed in the task spec:** it now checks the printed summary line, which no spec asserted before.

E (shared examples for `SearchQuery`) is a merge, not a removal, and is still open.
