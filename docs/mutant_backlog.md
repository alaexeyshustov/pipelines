# Mutation testing backlog

The nightly Mutation Testing CI job (`.github/workflows/mutation.yml`) no longer gates on a fixed
90% threshold. It gates on a **regression check** against the committed baseline in
`docs/mutant_baseline.json`, which can only move down through an explicit, reviewed
`RATCHET-DOWN-APPROVED:` PR (enforced by `.github/workflows/mutant_baseline_guard.yml`) — see
`.omc/plans/fix-mutation-testing-ci.md` for the full design rationale.

90% remains the **North Star**, reported non-blockingly in the nightly job summary. This doc is
the prioritized path back up to it: the subjects with the most alive mutations, i.e. the biggest
single-subject wins available, pulled from a full parse of CI run `29223533162` (2026-07-13,
`main@e062e85`, 2686 alive mutations / 259+ subjects total). Closing any one of these does not
move the score much on its own (see the plan's "scoring correction" note — the gap is wide and
shallow, not concentrated in a few pathological subjects) but they're the best entry points for
incremental work.

**Known data-quality caveat (found 2026-07-13 while starting on the `Orchestration::Step`
entries below):** the script used to parse the raw CI log text-matched each alive-mutation diff
block against a following `"(N more alive mutation(s))"` line within a fixed character window.
When a subject has *exactly one* alive mutation, mutant does not print that suffix line at all,
so the parser's window search fell through into the *next* subject's count and misattributed it.
The tell is two or more adjacent table rows sharing the exact same alive count (e.g. the `61`/`61`
pair and the `59`/`59`/`59` run below) — a real coincidence is possible but should be treated as
suspect. Confirmed by direct measurement: `Orchestration::Step#next_sibling` and `#previous_sibling`
each have only 23 total mutations, so 59 alive was never possible for either — both were bleed-
through from `#swap_position_with`'s real, independently-confirmed 59-of-60. **Before starting
work on any row below, re-verify its real alive count first** with a scoped local run:
`bundle exec mutant run --jobs 1 --mutation-timeout 15 '<Subject expression>'`
(`--jobs 1`/a longer timeout matters here too — the default `--jobs 4` produced a false 0-alive
reading for `#previous_sibling` in this sandbox via timeout-under-contention, the same class of
noise `.omc/plans/fix-mutation-testing-ci.md`'s Risks section flags for the nightly job). Rows not
yet re-verified this way should be treated as directional, not exact.

Two items from this list have already been closed (see the equivalent-mutant and coverage work
landed alongside this doc):
- `SqliteVecExtension#configure_connection` (`config/initializers/sqlite_vec.rb:6`, 27 alive,
  0 tests) — closed via `spec/initializers/sqlite_vec_extension_spec.rb`.
- `Interview.as_rows`'s order-tiebreak mutation and `EmailVector.search`'s `row[0]`/`row.at(0)`
  mutation were investigated and reclassified as genuine **equivalent mutants** (a composite DB
  index and identical Array indexing behavior, respectively) — documented inline, not fixable by
  any test, and excluded from this backlog.

## Top offenders by alive-mutation count

| Alive | Selected tests | Subject |
|------:|---:|---|
| 61 | 22 | `Orchestration::ActionRunComponent#raw_response_excerpt` (`app/components/orchestration/action_run_component.rb:44`) — **not yet re-verified, suspect (adjacent duplicate count)** |
| 61 | 25 | `Orchestration::Agent.available_models` (`app/models/orchestration/agent.rb:47`) — **not yet re-verified, suspect (adjacent duplicate count)** |
| 1 | 3 | `Orchestration::Step#next_sibling` (`app/models/orchestration/step.rb:16`) — **re-verified 2026-07-13**: 1 alive / 23 total mutations, not 59. Real gap: `.order(position: :asc).first` → `.first` survives — no test asserts it returns the *closest* sibling above when multiple exist. |
| 1 | 4 | `Orchestration::Step#previous_sibling` (`app/models/orchestration/step.rb:12`) — **re-verified 2026-07-13**: 1 alive / 23 total mutations, not 59. Mirror gap: `.order(position: :desc).first` → `.first` survives. |
| 59 | 22 | `Orchestration::Step#swap_position_with` (`app/models/orchestration/step.rb:20`) — **re-verified 2026-07-13, confirmed accurate**: 59 alive / 60 total. The entire method body → `raise` survives — despite 22 selected tests, none of them assert on this method's actual effect (position swap via the temp-value transaction). Highest-value single target in this table. |
| 53 | 19 | `Orchestration::PipelineValidator#advance_through_array` (`lib/orchestration/pipeline_validator.rb:144`) |
| 47 | 67 | `Orchestration::PipelineRunner#handle_step_failure` (`lib/orchestration/pipeline_runner.rb:33`) |
| 47 | 67 | `Orchestration::PipelineRunner#log_action_failure` (`lib/orchestration/pipeline_runner.rb:217`) |
| 46 | 10 | `Emails::Adapters::ImapBodyParser#decode_part` (`lib/emails/adapters/imap_body_parser.rb:42`) |
| 40 | 3 | `Emails::ListTool#execute` (`app/tools/emails/list_tool.rb:16`) |
| 40 | 10 | `Records::InsertRowsTool#extract_scope_columns` (`app/tools/records/insert_rows_tool.rb:75`) |
| 36 | 26 | `Orchestration::InputMappingResolver#resolve_value` (`lib/orchestration/input_mapping_resolver.rb:15`) |
| 35 | 4 | `Orchestration::StepsRunListComponent#compute_steps_with_action_runs` (`app/components/orchestration/steps_run_list_component.rb:16`) |
| 34 | 19 | `Orchestration::PipelineValidator#advance_through_object` (`lib/orchestration/pipeline_validator.rb:136`) |
| 32 | 31 | `Orchestration::StepComponent#setup_detach_button` (`app/components/orchestration/step_component.rb:28`) |
| 32 | 31 | `Orchestration::StepComponent#setup_remove_button` (`app/components/orchestration/step_component.rb:45`) |
| 30 | 7 | `Emails::Adapters::GmailBodyExtractor#extract_from_multipart` (`lib/emails/adapters/gmail_body_extractor.rb:25`) |
| 30 | 67 | `Orchestration::PipelineRunner#parse_string_content` (`lib/orchestration/pipeline_runner.rb:185`) |
| 29 | 19 | `Orchestration::PipelineValidator#process_mapping_spec` (`lib/orchestration/pipeline_validator.rb:51`) |
| 28 | 47 | `Orchestration::SchemaBuilder.parse_params_children` (`app/models/orchestration/schema_builder.rb:87`) |
| 26 | 10 | `Records::InsertRowsTool#extract_key_columns` (`app/tools/records/insert_rows_tool.rb:83`) |
| 25 | 6 | `Orchestration::InputMappingComponent#mapping_rows` (`app/components/orchestration/input_mapping_component.rb:65`) |
| 24 | 7 | `Emails::Adapters::GmailBodyExtractor#decode_body` (`lib/emails/adapters/gmail_body_extractor.rb:55`) |
| 24 | 56 | `Records::FuzzyMatcher#levenshtein` (`app/tools/records/fuzzy_matcher.rb:30`) |

File paths above have been cross-checked against the current tree (2026-07-13). Line numbers are
as reported by the CI run parsed for this list and may drift slightly with unrelated edits —
re-confirm with `grep -n 'def <method_name>'` if a line looks off before diving in.

## Notes for whoever picks these up

- A high "selected tests" count with a high alive-mutation count (e.g.
  `Orchestration::PipelineRunner#handle_step_failure`, 67 tests / 47 alive) usually means the
  *existing* tests exercise the method but don't assert on the specific branch/value a given
  mutation touches — read the mutant diff (`mutant subject <Name>`, or re-parse a fresh CI run's
  `mutant_output.txt` artifact) before assuming a whole new test is needed; often it's a missing
  assertion in an existing example.
- A near-zero "selected tests" count relative to a subject's total mutation count more often
  means a genuine coverage hole worth a small, focused new spec — but confirm the real alive
  count first per the data-quality caveat above before assuming the scale of the gap.
- Before writing a test to kill any mutation here, rule out the equivalent-mutant possibility
  first (see the two examples closed above) — a test written to kill an unkillable mutation is
  wasted effort and, per this repo's own history (`docs/claude/gotchas.md`), a bad pattern to
  repeat.
- As each item closes, raise `docs/mutant_baseline.json`'s `score` in the same PR (protected by
  `mutant_baseline_guard.yml` — a score increase needs no approval token) and remove or check off
  the corresponding row here.
