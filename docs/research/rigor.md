# Research: integrating Rigor (GH #171)

Question: can the findings and open questions in #171 be resolved, so that Rigor can be added next to Steep?
Sources: the `rigortype` gem 0.4.6 and 0.4.7 as installed (its bundled `docs/manual/`, `docs/handbook/` and `plugins/*/lib` source), the rigortype/rigor repo at `master` `c51a1e5` (2026-11-13: `CHANGELOG.md`, `changelog.d/`, plugin source), upstream issues and milestones (GitHub API), the rubygems.org API, activerecord 8.1.4 source, and this repo's own files. The online manual at <https://rigor.typedduck.fail/manual/> is built from the same `docs/manual/` tree, so page names below match the gem files. Checked on 2026-11-13.

I ran a local trial in throwaway worktrees of `origin/main` (`6dd66440`) and of local `main` (`1dec6627`). Rigor was installed into a scratch `GEM_HOME` on Ruby 4.0.6, and the RBS collection was installed with `rbs collection install --frozen`. Both worktrees have been removed.

**Short answer:** proceed to implementation. Every finding in #171 now has a known cause:
1. **The trial in #171 ran without the RBS collection installed.** Running 0.4.6 on `1dec6627` without `.gem_rbs_collection/` reproduces it exactly: 77 errors, 28 warnings, and 41 classes failing on `NoSuperclassFoundError` at `ActionController::Base`. Findings 2 and 4 mostly come from this.
2. **`unknown-column` is real noise.** The plugin does read `db/structure.sql`, but it parses only PostgreSQL DDL. Our SQLite dump gives it 17 tables, each with a bogus `REFERENCES` column. The fix is a generated Ruby `schema.rb` passed through `schema_file:`.
3. **Of the three false positives**, two are fixed on upstream `master` for 0.4.8, which is not yet released. The third (the member route with `as:`) is an unreported upstream bug. `WizardForm#advance!` is a correct report against our own signature, not a Rigor bug.

With the fixes from §3, the trial drops from 81 to 39 errors. Pin 0.4.7, use a baseline, keep Steep.

---

## 1. Facts about the tool

| Item | Value | Source |
|---|---|---|
| Latest | **0.4.7** (2026-11-03). 0.4.6 was released 2026-10-23. | `rubygems.org/api/v1/versions/rigortype.json` |
| Next | v0.4.8 milestone: 134 closed, 27 open, no date. v0.5.0 will turn effects on by default. | GitHub milestones API; `changelog.d/changed/effects-default-on-v0-5-0.md` |
| Ruby | `required_ruby_version >= 4.0.0, < 4.1` for every 0.4.x release. Our `.ruby-version` 4.0.9 fits. A move to Ruby 4.1 would need a Rigor release that supports it. | rubygems versions API |
| Runtime deps | `prism`, `rbs >= 3.0, < 5.0` (resolved to 4.2.0), `language_server-protocol`. ActiveSupport is *not* a dependency. | rubygems gems API |
| Licence | MPL-2.0 | same |
| Plugins | Ship inside the gem (40 under `plugins/`). There is no umbrella entry, so each one must be listed. | `docs/manual/07-plugins.md` ("there is no umbrella entry") |
| Config | The first of `.rigor.yml` or `.rigor.dist.yml` found wins. The two files are **not merged**; use `includes:` to layer them. | `docs/manual/03-configuration.md` § Discovery |
| Exit codes | `0` clean, `1` errors, `70` internal fatal | `docs/manual/02-cli-reference.md` § Exit codes; `11-ci.md` |

### 1.1 What changed between 0.4.6 and 0.4.7 that affects #171

- `call.argument-type-mismatch` fell from 25 to 6 in the trial. Cause: "A `params[:key]` read in a controller no longer draws `call.argument-type-mismatch` at a declared `String` parameter" (CHANGELOG 0.4.7, #2445).
- The 0.4.6 `SuperclassMismatchError` on `ActiveRecord::StatementInvalid` is gone (seen in the trial on `1dec6627`). Cause: "`rigor-activerecord` beside an activerecord 7.1 or later `rbs collection` no longer fails to build `ActiveRecord::StatementInvalid`" (CHANGELOG 0.4.7, #2464).
- None of finding 1, the routes bug or the activejob bug changed in 0.4.7.

### 1.2 Unreleased on `master`, planned for 0.4.8

| Fragment | Effect on us |
|---|---|
| `changelog.d/fixed/activejob-keyword-arguments-arity.md` (#2944, #2954) | Fixes the `PromptAutoEvalJob.perform_later(prompt_id:)` false positive. |
| `changelog.d/fixed/rails-routes-resolved-helpers.md` (#2948, #2960) | Fixes a second routes false positive the trial found: `attr_reader :base_url` in `Tags::TaggingsComponent` was reported as an unknown helper. |
| `changelog.d/fixed/lockfile-stdlib-entries.md` (#2946, #2958) | `type: stdlib` entries in `rbs_collection.lock.yaml` (we have `ripper`) start loading. A `sig/` stub that duplicates a stdlib method would then fail to build. We have none (`grep "class Ripper" sig/` finds nothing). |
| `changelog.d/fixed/activerecord-select-block.md` (#3165) | Types `relation.select { }` as an Array. Does not affect the `Document.select(:id)` case in §3.5. |
| `changelog.d/fixed/fix-install-mise-rbs-shadow.md` (#2949) | Documents that `mise use gem:rigortype` can shadow `bundle exec rbs` when the bundle path is the default (see §3.6). |

The `routes_parser.rb` and the SQLite handling in `structure_sql_parser.rb` are unchanged on `master` (diffed against 0.4.7).

## 2. Trial results

The base config is the one from #171. "AS" means ActiveSupport was reachable by Rigor (§3.0). Counts come from `rigor check --no-cache --format=json` and cover errors, warnings and info.

| # | Tree / version / setup | err | warn | info | Notes |
|---|---|---|---|---|---|
| A | `1dec6627`, 0.4.6, AS, **no `.gem_rbs_collection/`** | **77** | **28** | 282 | Exactly #171's numbers. `definition-build-failed`: "41 RBS class definition(s) failed … `RBS::NoSuperclassFoundError` on `ActionController::Base`". `missing-gem` reports 218 gems with no RBS. |
| A′ | `1dec6627`, 0.4.6, AS, collection installed | 66 | 40 | 283 | 3 classes fail (`StatementInvalid` superclass mismatch; fixed in 0.4.7) |
| B | `origin/main`, 0.4.7, collection, **AS not reachable** | 73 | 53 | 39 | 2× `load-error`: `Rigor::Plugin::Inflector::Unavailable … cannot load such file -- active_support/inflector`. The activerecord and rails-routes plugins report nothing. |
| C | `origin/main`, 0.4.6, collection, AS | 101 | 50 | 310 | |
| D | `origin/main`, 0.4.7, collection, AS | **81** | 50 | 311 | Starting point for the fixes. 12 `unknown-column`, 1 `definition-build-failed`. |
| E | D + `schema_file: tmp/rigor/schema.rb` (§3.1) | 68 | 46 | 322 | `unknown-column` 12 → 0, `def.return-type-mismatch` 36 → 32 (column readers are now typed) |
| E′ | D + reduced mode (both schema paths missing) | 69 | 50 | 323 | Column checks turned off instead of fixed |
| F | E + `join_sources` overload (§3.2) | 68 | 45 | 322 | `definition-build-failed` 1 → 0 |
| G | F + `BroadcastLogger` overlay (§3.5) | **39** | 45 | 322 | `call.undefined-method` 53 → 24 |
| H | E + `spec` in `paths:` | 271 | 21 764 | 824 | 21 719 `call.unresolved-toplevel` (§3.7) |

Other numbers:
- Cold run: 10.5–14.4 s, peak 413–468 MB.
- Warm full run with cache: 1.2 s.
- `--incremental`: 13.1 s on the first run, which builds the snapshot, then 0.24 s.
- `rigor baseline generate` on E: "206 bucket(s) covering 406 diagnostic(s)". The next `rigor check` exits 0.
- Dropping `rigor-rspec`, `rigor-rspec-rails` and `rigor-factorybot` from E gives identical counts (68/46), because nothing under `paths: [app, lib]` uses them.

## 3. Findings

### 3.0 New: the Rails plugins need ActiveSupport reachable by Rigor

`rigor-activerecord`, `rigor-rails-routes` and `rigor-actionpack` inflect names "**only** with the real `ActiveSupport::Inflector`". The inflector is resolved "from Rigor's host gem environment first, then from the analyzed project's own bundler install tree". When neither is found, the plugin degrades to "**no diagnostics**" (`rigortype-0.4.7/lib/rigor/plugin/inflector.rb:5-29`). The project bundle is found through `<project>/.bundle/config` `path`, `vendor/bundle`, or a global `bundle config path`. Rigor never looks in the default `GEM_HOME` (`docs/manual/03-configuration.md` § Dependency RBS discovery).

This repo installs to the default path (there is no `.bundle/config`), so a standalone Rigor sees **no** ActiveSupport here. Trial B shows the result: a `load-error` warning, and both plugins report nothing.

Fix: run Rigor through the app bundle (`bundle exec rigor`), which already has activesupport 8.1.4 (§3.6). Trials C–H ran with ActiveSupport reachable.

### 3.1 Finding 1: `plugin.activerecord.unknown-column` on every column

**Cause (confirmed).** The plugin *does* read `db/structure.sql`. It falls back to `structure_sql_file` (default `db/structure.sql`) when `schema_file` (default `db/schema.rb`) is absent (`plugins/rigor-activerecord/lib/rigor/plugin/activerecord.rb:23-25,129-133`). But the parser expects `pg_dump` output with "one column per line, the body closes on a line starting with `)`" (`…/activerecord/structure_sql_parser.rb:8-28`). The plugin docs say: "It reads PostgreSQL DDL only" (`docs/manual/plugins/rigor-activerecord.md` § Limitations).

Our dump is SQLite, with one line per `CREATE TABLE` (`config/application.rb:43` `schema_format = :sql`, adapter `sqlite3`). Running the plugin's own parser on our `db/structure.sql` returns 17 tables, and each has the column `["REFERENCES"]`. So every real column, `id` included, is "unknown".

There is no SQLite support on `master`, and no upstream issue for it. Searches for "sqlite" and "structure.sql" found only #2965 and #2964, which are about PostgreSQL types.

**Options:**

| Option | Result in trial | Cost |
|---|---|---|
| a. Generate a Ruby-DSL schema and set `schema_file:` | E: 0 false positives, real column checks, better column typing | A ~10-line script. Needs activerecord + sqlite3, which the app bundle already has. |
| b. Reduced mode: point both paths at missing files | E′: silent. "The schema gates the COLUMN surface and nothing else" (`activerecord.rb:38-45`). | Loses the column checks, one of the selling points in #171 |
| c. `disable: [plugin.activerecord.unknown-column]` | Not run. The bogus 17-table schema would stay loaded and keep mistyping column readers on those tables. | Worse than b |

**Recommendation: option a.** One catch: Rails' own Ruby dumper crashes on our multi-line FTS5 virtual tables. `VIRTUAL_TABLE_REGEX = /USING\s+(\w+)\s*\((.*)\)/i` (`activerecord-8.1.4/lib/active_record/connection_adapters/sqlite3_adapter.rb:322`) does not match across newlines, so `arguments.split` raises `NoMethodError` on nil (`sqlite3/schema_dumper.rb:16`). I reproduced the crash. So `SCHEMA_FORMAT=ruby SCHEMA=… bin/rails db:schema:dump`, which Rails 8.1 does support (`database_tasks.rb:434-438,472`), does not work as-is. The script I used loads the SQL into an in-memory DB and skips `_fts` tables. It needs no app boot:

```ruby
# script/rigor_schema.rb — run with: bundle exec ruby script/rigor_schema.rb
require "active_record"
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.connection.raw_connection.execute_batch(File.read("db/structure.sql").gsub(%r{/\*.*?\*/}m, ""))
ActiveRecord::SchemaDumper.ignore_tables = [/_fts/]
FileUtils.mkdir_p("tmp/rigor")
File.open("tmp/rigor/schema.rb", "w") { |f| ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, f) }
```

This produced 36 `create_table` blocks. Rigor read the file even with `exclude: ["tmp/**"]` (verified). Set `structure_sql_file:` to a path that does not exist. Then a missing `schema.rb` falls back to reduced mode, not to the broken SQLite parse. Also file an upstream feature request for SQLite `structure.sql`.

### 3.2 Finding 2: `rbs.coverage.definition-build-failed` (41 classes, `NoSuperclassFoundError` on `ActionController::Base`)

**Cause (confirmed by reproduction).** `.gem_rbs_collection/` was not installed in the tree that was analysed. Trial A (no collection) reproduces the exact counts and message from #171. It lists the same conflicting files: `sig/app/controllers/application_controller.rbs`, `sig/app/forms/base_form.rbs`, `sig/app/jobs/application_job.rbs`, … With the collection installed (A′, D), the 41-class failure is gone.

Two clues give it away: `missing-gem` reports 218 gems without RBS instead of 174, and a related `NoMixinFoundError … ::ActiveRecord::Relation::Methods` appears on stderr. Neither `sig/shims` nor rbs_rails is at fault. `.gem_rbs_collection/` is gitignored, so any fresh worktree or CI job has to run `rbs collection install` first.

`rbs collection install --frozen` using Rigor's bundled `rbs` 4.2.0 works without the app bundle: "83 gems' RBSs now installed" from our lockfile (rbs 3.10.4 wrote it).

**Remaining failure on `origin/main` (0.4.7).** One class still fails: `Arel::SelectManager`, with `RBS::DuplicatedMethodDefinitionError` on `#join_sources`. It is declared both at `sig/shims/external_gems.rbs:248` and in the activerecord 8.1 collection (`activerecord-generated.rbs:31536`, `() -> untyped`). Fix: turn the shim into an overload by adding `| ...` under `def join_sources: () -> Array[Arel::Nodes::Join]`, the same way the neighbouring `def on:` is written. Trial F: 0 build failures. `rbs parse` passes. **Steep / `rbs validate` were not run on this change**, because the app bundle was not installed in the trial.

### 3.3 Finding 3: the three false positives

| Diagnostic | Verdict | Evidence | Action |
|---|---|---|---|
| `plugin.rails-routes.unknown-helper` `compare_evaluation_experiment_path` (`app/controllers/evaluation/prompts_controller.rb:14`) | **Upstream bug, unreported, still on `master`** | The route is `get "compare/:candidate_id", action: :compare, as: :compare` inside `namespace :evaluation` → `resources :experiments` → `member` (`config/routes.rb:47,68-72`). Running the plugin's `RoutesParser.parse` on our routes registers `evaluation_compare_experiment_path` with arity 2 and path `/evaluation/experiments/:experiment_idcompare/:candidate_id`. The namespace prefix lands before the `as:` name, and the slash is missing. Rails would name it `compare_evaluation_experiment`. Only the *symbol* shorthand (`get :status_frame`) takes the member path (`routes_parser.rb:974-978`). A string path with `as:` falls through to the generic `explicit_route_helper_name`. `get "metrics/:metric_name", as: :metric_results` on line 74 has the same problem, but nothing calls it yet. | Baseline it, or add `# rigor:disable plugin.rails-routes.unknown-helper` on the line. File upstream with the 3-line repro. |
| `plugin.activejob.wrong-arity` `PromptAutoEvalJob.perform_later(prompt_id:)` (`app/services/evaluation/prompt_creator.rb:13`) | **Upstream bug, fixed on `master`, will ship in 0.4.8** | #2944 ("fires on `perform_later` / `perform_now` calls that pass keyword arguments"), fixed by #2954 (`d3229e7b3`, milestone v0.4.8). Still fires in 0.4.7 (trial D). | Baseline it. It drops out after the bump. |
| `call.possible-nil-receiver` `WizardForm#advance!` (`app/forms/evaluation/wizard_form.rb:24`) | **Correct report against our own signature, not reachable at runtime** | `step_form` is a `case` with no `else`, and its RBS says so: `-> (Step1Form \| … \| Step4Form)?` (`sig/app/forms/evaluation/wizard_form.rbs`). The only caller passes `@wizard_form.step` (`app/controllers/concerns/evaluation/experiment_wizard.rb:31`), which is clamped to `1..WIZARD_STEPS`. Steep never saw it because it does not check `app/forms` (`Steepfile`). | Fix the code: add `else raise ArgumentError` and drop the `?` from the RBS. |
| *(new)* `unknown-helper` `base_url` (`app/components/tags/taggings_component.rb:15`) | Upstream bug, fixed on `master` | It is an `attr_reader`. See #2948 / #2960. | Baseline it |
| *(new)* `call.possible-nil-receiver` `result.warnings` after `result&.warnings&.any?` (`app/controllers/orchestration/step_actions_controller.rb:50`) | Likely a Rigor narrowing gap through a `&.` chain | Not checked upstream | Triage during implementation |

### 3.4 Finding 4: `ActiveRecord::Relation#order/find/select` undefined

**Not reproduced.** No run, including A, reports `order`, `find` or `select` as undefined on a Relation. Run A has an AR cluster of 25 diagnostics in `call.undefined-method`: `save`, `destroy`, `table_name=`, `primary_key=` and `exists?` on models. That cluster disappears once the collection is installed, so it is part of finding 2.

What remains on `origin/main` with 0.4.7 is a smaller AR group:
- **Plugin relation signatures stand down.** The plugin's `sig/active_record/relation.rbs` declares `ActiveRecord::Relation` with one type parameter, and the collection declares it with none. Rigor reports this as `rbs.coverage.plugin-signature-stood-down` (info) and keeps the collection's version. As a result, `Document.select(:id)` resolves to `Kernel#select` (`call.argument-type-mismatch`, `app/services/document/detect_duplicates.rb:38`, a line that already carries `# steep:ignore`), and `Model.exists?` is undefined in 2 places. A Rigor-only lockfile without activerecord would not help: the rbs_rails model signatures include `::ActiveRecord::Relation::Methods`, which comes from the collection.
- **Scopes are missing on association proxies.** `pipeline.runs.recent_first` / `.in_progress` (`app/models/orchestration/pipeline.rb:19,23`) are reported because `sig/app/models/orchestration/pipeline_run.rbs` declares the scopes only as `def self.…`, not on `ActiveRecord_Associations_CollectionProxy`. That is a gap in our signatures. Fix it in `sig/`.

**`pre_eval:` is the wrong tool.** It walks files "to register project monkey-patches" (`docs/manual/03-configuration.md`, Type sources). These methods are not project monkey-patches. `rigor triage` prints its "Register the defining file via `pre_eval:` … or add an RBS overlay" hint for any method undefined across many files. On `origin/main` that cluster is `ActiveSupport::BroadcastLogger#error/debug/info` (29 diagnostics). The collection's activesupport 8.1 RBS declares `debug?`/`error!` but not `debug`/`info`/`warn`/`error`/`fatal`. **The RBS overlay is the right fix.** A 10-line `sig/shims/broadcast_logger.rbs` that declares those six methods removed all 29 (trial G). Steep also loads `sig/`, and the collection has no such methods, so nothing collides.

### 3.5 Remaining errors after G (39), for the triage step

They fall into these groups:
- **Gems without RBS** (`Signet::OAuth2::Client`, `Google::Apis::GmailV1::*`, `Zip::File#find_entry`, `Pagy`, `RubyLLM::Models#refresh`, `UI::ActionComponent::RawComponent#with_content`): extend `sig/shims`.
- **Signature drift Rigor exposes:**
  - `Document#update!(attributes)` against `def update!: (**top)` in `sig/app/models/application_record.rbs:40`;
  - `Message#tokens`;
  - the `models_controller.rb` record shape.
- **Probable Rigor false positives:**
  - `builder.format` resolving to `Kernel#format` (`schema_builder/serializer.rb:35-37`);
  - `Rails.root.glob(...)` elements typed `String` (`app/models/orchestration/agent.rb:35`).
- The rows in §3.3.

Note: Rigor does not honour `# steep:ignore`. Its form is `# rigor:disable <rule>` (`docs/handbook/appendix-steep.md` § Suppression). We have 58 `steep:ignore` comments in 20 files, so baseline those lines rather than double-annotating them.

### 3.6 Open question: where to pin Rigor

Upstream gives two answers depending on context:
- **Installation chapter:** mise is "Recommended". The CI-only Gemfile is for when "your team already runs everything through Bundler and wants Rigor on the same footing — not as a first choice" (`docs/manual/01-installation.md`).
- **CI chapter:** "A CI-only `Gemfile` (recommended)", with a Dependabot `bundler` entry for `/.github/rigor` (`docs/manual/11-ci.md` § Pinning Rigor's version). That text still says `~> 0.2`, so pin exactly instead.

**mise is out.** The repo has no `mise.toml` or `.tool-versions`; CI and hooks run everything through `bundle exec`. Our bundle uses the default path (no `.bundle/config`), which is exactly the case where #2949 says a mise `gem:rigortype` install shadows `bundle exec rbs`. A mise-installed Rigor also cannot see ActiveSupport (§3.0).

**For this repo: the app Gemfile** (decided during implementation; this note first proposed a separate `.github/rigor/Gemfile`).
- Rigor's runtime deps already resolve inside `Gemfile.lock`: `rbs >= 3.0, < 5.0` (we have 4.2.0, shared with Steep 2.1), `prism` 1.9.0, `language_server-protocol` 3.17. Adding `rigortype` changed no other locked version.
- ActiveSupport 8.1.4 is already in the bundle, so there is no second copy to keep equal to `Gemfile.lock`, and CI needs no second `bundle install`.
- The existing Dependabot `bundler` entry for `/` covers it.
- Trade-off accepted: Rigor and Steep must agree on one `rbs` version. If a future Rigor needs an `rbs` that Steep does not accept, move Rigor to a separate Gemfile then.

```ruby
group :development do
  # 0.x is an evaluation trial upstream; pin exactly and regenerate .rigor-baseline.yml on bump (GH #171).
  gem "rigortype", "0.4.8", require: false
end
```

Do **not** add `rbs-inline`, even though `rbs.coverage.inline-annotations-unsynthesized` suggests it. Our 8 annotated files already have hand-written `sig/` files, and loading both would declare those methods twice (`docs/manual/03-configuration.md` `sig_gen.inline_declared`).

### 3.7 Open question: `spec/` in `paths:`

**No, not now.** Trial H adds 21 719 `call.unresolved-toplevel` warnings (`expect` 3694, `it` 2761, `described_class` 1354, `create` 1313, …), 95 `possible-nil-receiver` and 41 `unknown-helper`, and it doubles the run time to 21 s. The reason is that `rigor-rspec` only checks `let`/`subject` duplicates and self-references, and narrows through matchers. It does not type the RSpec DSL (`docs/manual/plugins/rigor-rspec.md`). `test_paths:` auto-detects `spec/`, but "Test roots are not analysed unless `paths:` also lists them" (`03-configuration.md`). Drop `rigor-rspec`, `rigor-rspec-rails` and `rigor-factorybot` from `plugins:` until `spec/` is analysed, since they change nothing today (§2).

### 3.8 Open question: keep Steep or replace it

**Keep both.**
- Upstream says: "The two tools are complementary, not exclusive", and gives a coexistence pattern where CI runs both as separate gates (`docs/handbook/appendix-steep.md` § A coexistence pattern).
- Steep carries contracts Rigor does not replace here: `rbs_audit coverage --threshold=90` (`ci.yml:76`), `rbs-sentinel` freshness, and the `steep:ignore` escapes.
- Rigor 0.x pins only `docs/compatibility.md` items as stable.
- Rigor's value is the paths Steep does not check. Steep checks only `app/services`, `app/tools` and `lib` (`Steepfile`). Rigor caught the `WizardForm` nil case in `app/forms`.
- Do **not** run `rigor sig-gen --write`. That is step 5 of the `rigor-project-init` skill (`docs/manual/14-rails-quickstart.md`). It would write into the `sig/` that rbs_rails and rbs-sentinel own.

## 4. Recommended config

```yaml
# .rigor.dist.yml (committed). A per-dev .rigor.yml replaces it entirely; use `includes: [.rigor.dist.yml]` to layer.
target_ruby: "4.0"
paths: [app, lib]
exclude: ["vendor/**", "tmp/**"]
signature_paths: [sig]
rbs_collection: { lockfile: rbs_collection.lock.yaml }
baseline: .rigor-baseline.yml
plugins:
  - rigor-railties
  - gem: rigor-activerecord
    config:
      schema_file: tmp/rigor/schema.rb          # generated by script/rigor_schema.rb (§3.1)
      structure_sql_file: tmp/rigor/absent.sql  # never parse the SQLite dump; missing schema = reduced mode
  - rigor-actionpack
  - rigor-rails-routes
  - rigor-actionmailer
  - rigor-activejob
```

`severity_profile:` is omitted because `balanced` is the default (`14-rails-quickstart.md` Step 2). No `disable:` is needed once §3.1 is in place.

## 5. Recommendation: proceed to implementation

Updated plan, replacing the checklist in #171:

1. **Pin the tool:** add `rigortype` to the app Gemfile's development group (§3.6). Add `.rigor/` to `.gitignore`.
2. **Fix the inputs:**
   - add `script/rigor_schema.rb` (§3.1);
   - add the `| ...` overload on `Arel::SelectManager#join_sources` (§3.2);
   - add `sig/shims/broadcast_logger.rbs` (§3.4);
   - add scope methods on the CollectionProxy signatures for `PipelineRun`.
   Run `rbs validate` and `steep check --jobs 2` after the signature edits (`docs/claude/type-signatures.md`).
3. **Fix the real bug:** make `WizardForm#step_form` exhaustive (§3.3).
4. **Add the config:** `.rigor.dist.yml` as in §4.
5. **Triage and baseline:** run `rigor triage`, fix what §3.5 calls drift, then `rigor baseline generate`. That baseline will hold the routes `compare` bug, the two items fixed upstream and the remaining gem-RBS gaps.
6. **CI:** add a `rigor` job next to `steep`:
   - `setup-ruby` with `bundler-cache`;
   - `bundle exec rbs collection install`;
   - `bundle exec ruby script/rigor_schema.rb`;
   - `bundle exec rigor check`;
   - cache `.rigor/cache` keyed on `Gemfile.lock` + `github.sha`, with a restore-key prefix (`11-ci.md` § Persisting the analysis cache).
   GitHub annotations are auto-detected.
7. **Pre-commit:** add `rigor check --incremental` (0.24 s warm, §2). It needs the schema script and collection, which the hook already depends on through Steep.
8. **Upstream:** file the member-route `as:` naming bug and a SQLite `structure.sql` request. When 0.4.8 ships, bump the pin and run `rigor baseline` regenerate to shrink it (the activejob and `base_url` entries drop out).
9. **Docs:** add a short section to AGENTS.md / `docs/` covering how to run it, how to refresh `tmp/rigor/schema.rb`, and the rule that the baseline only shrinks.

## 6. Where evidence is thin

- **The #171 trial setup is inferred, not observed.** It rests on an exact count match (77/28, 41 classes) with a no-collection run on the same commit. Where that run happened, and why its collection was missing, is unknown.
- **Finding 4's specific methods (`order`/`find`/`select` on Relation) were never reproduced.** The resolution above covers the AR clusters that did appear.
- **Unreleased fixes were not run.** Running the `master` source was blocked in this session, so the 0.4.8 fixes are taken from the changelog fragments and issue threads, not executed.
- **The trial used Ruby 4.0.6, not the repo's 4.0.9.** Rigor accepts both, but behaviour on 4.0.9 was not observed.
- **The `join_sources` overload and the `BroadcastLogger` shim were not checked with Steep or `rbs validate`.**
- **The `ActiveSupport::BroadcastLogger` shim signatures** (`(?untyped, ?untyped) ?{ } -> bool`) were written by hand from `::Logger`'s shape. They were not checked against Rails 8.1's real `BroadcastLogger` definitions.

## 7. Implementation outcome (2026-11-17)

Implemented on branch `feat/rigor` with the app Gemfile (§3.6). Differences from the plan above:
- **More shim/collection duplicates than the trial saw.** The RBS collection had been updated since the trial (lockfile change in `98ac6ece`). `ViewComponent::Base#render_in`, `Zip::File.open_buffer`/`#read` and 13 `Net::IMAP` methods were now declared both in `sig/shims/external_gems.rbs` and in the collection, failing 71 class builds in Rigor. Steep passed because it builds classes lazily. Fix: `| ...` overloads, or dropping the shim where the collection's signature is a superset (`render_in`, `Zip::Error`, `Zip::File#read`). `Zip::File.open_buffer` keeps a `StringIO` overload, which Steep needs.
- **Stdlib lockfile entries.** #2946 (skipped `type: stdlib` lockfile entries) did bite: `Net::IMAP < Net::Protocol` and ActionView's `< ::Ripper` failed to build. Worked around with `libraries: [net-protocol, ripper]` on 0.4.7, removed with the 0.4.8 bump.
- **PipelineRun CollectionProxy scopes** were already declared; no change.
- **Gem gaps closed with shims:** Signet client, `GmailService#get_user_message_attachment`, `MessagePart#filename`, `Pagy#last`/`#series_nav`, `RubyLLM::Models#refresh`, and `Message#tokens` in `sig/app/models/message.rbs`.
- **Errors:** 43 → 7. Baselined: the two routes helpers (§3.3), the activejob arity (§3.3), `Document.select(:id)` (§3.4), and three Rigor narrowing gaps (recursive JSON type through `is_a?(Hash)`, a `&.` chain, a `#:` inline assertion). The baseline has 188 buckets / 371 diagnostics, mostly info and warnings.
- **Timings on Ruby 4.0.6:** cold ~15 s / 840 MB; `--incremental` warm 0.4 s.
- **Bumped to 0.4.8** (released 2026-11-15) before merging. This confirms the §1.2 fixes on our code: the activejob keyword-arity and `base_url` false positives are gone, the stdlib lockfile entries load (so `libraries:` was removed with no build failures), and one `def.override-return-widened` warning in `settings/email_connectors_controller.rb` cleared. The regenerated baseline only shrank: 188 → 185 buckets, 371 → 368 diagnostics, 5 errors. 0.4.8 reports the project config as `.rigor.dist.yml` rather than `.rigor.yml` in diagnostics. The member-route `as:` bug is still present.
