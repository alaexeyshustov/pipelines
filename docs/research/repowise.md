# Research: integrating repowise (GH #168)

Question: can [repowise](https://github.com/repowise-dev/repowise) be wired into local dev, git hooks, CI and Claude Code as #168 proposes, and what has to change in the plan?
Sources: the repowise repo at `main` (README, `action.yml`, `docs/reference/CLI_REFERENCE.md`, `docs/reference/HOOKS_REFERENCE.md`, `docs/scale/AUTO_SYNC.md`, `docs/layers/LANGUAGE_SUPPORT.md`, `docs/reference/TELEMETRY.md`, `docs/business/COMMERCIAL.md`), its source (`packages/cli/src/repowise/cli/hooks.py`, `packages/core/src/repowise/core/ingestion/{framework_edges/rails.py,resolvers/ruby_rails.py,dynamic_hints/ruby.py}`), the PyPI JSON API, the GitHub API (`apps/repowise-bot`) and this repo's own files. Checked on 2026-11-12. I also ran a trial install with `mise exec pipx:repowise@0.60.1`. The Rails findings in §4 first came from reading the source. §4.1 records a run against this repo on 2026-11-17.

**Short answer:** it is feasible, but four of the ticket's assumptions are wrong for this repo:
1. We use **Husky, not Overcommit**.
2. The repo has **no `.mise.toml`**.
3. `repowise init` writes **machine-wide Claude Code hooks** and several repo files we don't want.
4. The CI risk gate is a **size percentile, not a risk predictor**, so it should never block.

Recommendation: adopt it index-only (`--no-prose`) with the CLI's editor setup turned off. Hand-write the Husky hook and the `.mcp.json` entry. Run `repowise risk` in CI as an advisory check through the official action or mise. Defer the hosted PR Bot.

---

## 1. Facts about the tool

| Item | Value |
|---|---|
| Latest | `0.60.1` (2026-11-02); 0.57 → 0.60.1 shipped in 3 weeks. Still pre-1.0. |
| Licence | AGPL-3.0. Fine for internal use, since we don't distribute it. |
| Python | `>=3.11`. Pulls in ~60 deps (tree-sitter grammars, lancedb, scipy, litellm, fastapi, anthropic/openai/google SDKs). |
| Install footprint | `mise exec pipx:repowise@0.60.1` took **~5 min** and **776 MB** on this Mac. |
| LLM | None of the analysis layers (graph, git, health, risk, dead code, PR bot) call an LLM. Prose wiki and `get_answer` synthesis are opt-in (`--prose`, BYOK). |
| Telemetry | **On by default** (anonymous, opt-out): `DO_NOT_TRACK=1`, `REPOWISE_TELEMETRY_DISABLED=1` or `repowise telemetry disable`. |
| Ruby | Full tier: AST symbols, call graph, heritage, health markers (no Extract Method, no test-quality markers). |

## 2. Assumptions in #168 vs this repo

| #168 says | Reality | Consequence |
|---|---|---|
| "Add repowise to `.mise.toml`" | There is no project mise config. mise is configured only globally (`~/.config/mise/config.toml`: node 26, pnpm, ruby 4). Ruby comes from `.ruby-version`; CI uses `ruby/setup-ruby` and `actions/setup-node`. | Adding `.mise.toml` creates a new team-wide toolchain file. Decide whether it holds only repowise or also takes over ruby/node. |
| `"pipx:repowise" = "latest"` | Weekly 0.x releases. | Pin exactly (`"0.60.1"`) from day one. `latest` contradicts the "pinned, reproducible" acceptance criterion. |
| "coexists with Overcommit" | The repo uses **Husky 9** (`package.json` `prepare: husky`, `.husky/pre-commit`). Overcommit is not installed. | The Overcommit tasks don't apply. See §3.2. |
| "Verify `.mcp.json` committed" | `.mcp.json` is committed and holds `rubydex` only. | A repowise entry has to be added. `init` would write one, but see §3.3. |
| `Pipeline`/`Step`/`Action`/`Run` models | Actual models are namespaced: `Orchestration::{Pipeline,Step,Action,StepAction,PipelineRun,ActionRun,Agent}`, `Evaluation::*`. | This matters for association resolution (§4). |

## 3. Integration points

### 3.1 mise / pipx backend (open question 1)

- mise's `pipx:` backend uses **uv** when it is present (`~/.local/bin/uv` is here). uv picked its own managed **CPython 3.14.7** for the venv (`pyvenv.cfg`), so **no Python pin is needed** in `.mise.toml` on machines that have uv.
- Without uv, the backend needs `pipx` and a Python ≥3.11 on PATH. Either add `uv = "<ver>"` to `[tools]` so it is always present (the simplest fix), or pin `python = "3.12"`.
- CI cost: the 5-minute install argues for caching `~/.local/share/mise` (jdx/mise-action caches by default), or for using the official action (§3.4).

Proposed `.mise.toml`:

```toml
[tools]
uv = "0.12"                 # makes the pipx backend independent of system Python
"pipx:repowise" = "0.60.1"

[env]
DO_NOT_TRACK = "1"          # repowise telemetry is opt-out

[tasks."repowise:update"]
run = "repowise update --index-only"

[tasks."repowise:health"]
run = "repowise health --refactoring-targets"

[tasks."repowise:risk"]
run = "repowise risk origin/main...HEAD"
```

`main..HEAD` (as in #168) also counts commits that landed on `main` after branching. `...` scores from the merge-base, which is what a PR means.

### 3.2 Git hook (Husky, not Overcommit)

`repowise hook install` is Husky-aware (`hooks.py::_husky_user_hook_dir`). It sees `core.hooksPath = .husky/_` and writes a marker-delimited block to **`.husky/post-commit`**, the committed file, not the regenerated shim dir. It does not block: it runs `repowise update` in the background, and it exits early unless `.repowise/state.json` exists, so teammates without an index pay nothing.

Problem: `_hook_script()` **pins the absolute path of the installing machine's binary** (e.g. `'/Users/<me>/.local/share/mise/installs/pipx-repowise/0.60.1/bin/repowise'`). The code comment says "git hooks are never committed", which is false under Husky. Running `repowise hook install` would therefore commit a per-machine path into `.husky/post-commit`. That path falls back to a PATH lookup, so it isn't broken, but it is noisy and leaks a home path. It also goes stale on every version bump.

Recommendation: don't use `repowise hook install`. Hand-write `.husky/post-commit` and resolve through mise so it works from IDEs and GUI git clients where the shell's mise activation is absent:

```sh
# Background-refresh the repowise index; no-op without a local index.
[ -f .repowise/state.json ] || exit 0
command -v mise >/dev/null 2>&1 || exit 0
(mise run repowise:update >> .repowise/.update.log 2>&1 &)
```

(`repowise update` holds its own lock and queues commits that arrive while it runs, per AUTO_SYNC.md "How updates work".) The optional `--security` pre-commit block is not worth adding: brakeman already runs in `.husky/pre-commit`.

### 3.3 `repowise init` and Claude Code MCP

A default `repowise init` (`--editor-setup` is on by default) writes:

- **machine-wide:** a `repowise` MCP entry in `~/.claude.json` and Claude Desktop config. It also adds `SessionStart`/`PostToolUse`/`PostToolUseFailure` hooks on `Read|Edit|Write|Grep|Glob` in `~/.claude/settings.json`, sets `env.ENABLE_TOOL_SEARCH=true`, and offers a "distill" hook that rewrites Bash output and Read results. That one would collide with the RTK hook already in use.
- **in the repo:** `.mcp.json`, `.claude/CLAUDE.md`, `.vscode/mcp.json`, `.vscode/extensions.json`, a managed `AGENTS.md` section, and the post-commit hook.

That is far beyond "MCP server access". Use:

```sh
repowise init --no-prose --no-editor-setup --no-distill-hook --no-claude-md --no-agents
```

(`--no-editor-setup` also skips the git hook.) Then add the entry to `.mcp.json` by hand:

```json
"repowise": { "type": "stdio", "command": "mise", "args": ["exec", "--", "repowise", "mcp", "."] }
```

Also add `.repowise/` to `.gitignore`: the index is per-machine.

Each teammate must run `init` once before the MCP tools return anything. The tool names in the acceptance criteria exist and are on by default: `get_overview`, `get_context`, `get_risk`, `get_answer`, `get_symbol`, `search_codebase`, `get_change_risk`, `get_why`, `get_health`, `get_dead_code`. The `lean` profile (`--tools lean`) keeps 6 of them, which is worth using next to rubydex.

### 3.4 CI: `repowise risk` (open question 3)

- `repowise risk` needs **no index and no key**: pure git plus learned constants. It needs history, so the job needs `actions/checkout` with `fetch-depth: 0`. The default baseline is 200 recent commits, and it returns exit 2 with fewer than 8.
- `--format github` emits `::notice::` / `::error::` and writes markdown to `$GITHUB_STEP_SUMMARY`. With no REVSPEC it scores the PR's `target...HEAD` by itself.
- **Should it block?** No. The CLI reference says the percentile is "size and spread among recent repo commits (size, not danger)" and that "about (100 − P)% fail by design; answer with a split or second reviewer, not a fix". It is a PR-size nudge, not a quality gate. Keep it advisory permanently. If something should block later, use `health check` (`health-fail-on: introduced`), which flags code-shape findings the PR introduces.

Two ways to run it:

| | mise (`jdx/mise-action` + `mise run repowise:risk -- --format github`) | Official action `repowise-dev/repowise@v0.60.1` with `checks: risk` |
|---|---|---|
| Version pin | `.mise.toml` (single source) | `version:` input (second place to bump) |
| Install | mise + uv; cached after first run | `setup-python` + `pip install` each run |
| Extras | — | one updatable PR comment (`comment: true`, `GITHUB_TOKEN` only), SARIF upload, `health`/`security`/`doc-drift` gates, impacted-test selection |

The ticket's "no bare pip" criterion is about reproducibility. The action's `version:` input satisfies that, but mise keeps one source of truth. Recommendation: use mise for `risk` now. Switch to the action if we later want its PR comment or SARIF.

### 3.5 Repowise PR Bot

The GitHub App (`apps/repowise-bot`) is **hosted by repowise.dev**. It asks for `contents: write`, `workflows: write`, `checks: write`, `pull_requests: write`, `issues: write`, and subscribes to `push`/`pull_request`. The repo is public, so it costs nothing, but that is broad write access, including to workflows, for a third party. The action's `comment: true` posts a similar summary comment with only the job's `GITHUB_TOKEN`. Recommendation: skip the app and use the action comment if we want PR comments. Installing the app is a repo-owner decision either way.

### 3.6 `--provider anthropic` (BYOK)

Defer it. Everything in the acceptance criteria works with `--no-prose`. Prose adds per-page LLM cost on `init`, plus regeneration on every post-commit `update` unless `--index-only`. The mise task above passes `--index-only` for that reason.

## 4. Rails awareness (open question 2)

From the source, not a run:

- **Routes → controller actions:** regexes over `resources`, `get … to:` and `namespace` (`framework_edges/rails.py`).
- **Zeitwerk:** turned on by `config/application.rb`. It indexes only a **fixed list of autoload roots**: `app/{models,controllers,services,jobs,mailers,helpers,channels,policies}` and `lib` (`resolvers/ruby_rails.py`). This repo's **`app/components` (65 files), `app/tools` (16), `app/forms` (11) and `app/schemas` (1)** are absent, so constant references into them won't resolve to files. Concerns dirs are treated as a `concerns/` namespace rather than collapsed. Custom acronyms (`RBS`, `UI`, `JSON`, `RuboCop`) happen to snake-case correctly with its `camel_to_snake`.
- **ActiveRecord associations:** one regex, `(belongs_to|has_many|has_one|has_and_belongs_to_many)\s+:(\w+)`. It singularizes crudely, tries `app/models/<name>.rb`, then falls back to a lookup by **file stem only**. **`class_name:` is ignored**, and all 35 `class_name:` associations here are namespaced (`Orchestration::…`, `Evaluation::…`). They still mostly resolve by stem luck. One risk: the `agent.rb` stem collides (`app/models/orchestration/agent.rb` vs `lib/evaluation/improvement/agent.rb`). `app/models` is indexed first, so association edges land on the model. (`lib/pipeline.rb`, the other collision, was removed in GH #228.)
- **Dynamic hints:** `send`/`public_send`, `const_get`, `define_method`, `delegate … to:`.
- **Not modelled:** callbacks, scopes, `has_many through:` semantics, state machines, `ApplicationService`/form conventions.

Verify before relying on the graph. After `init`, call `get_context(targets=["app/models/orchestration/step.rb"], include=["callers"])` and check that `Orchestration::Pipeline`, `StepAction` and the `app/components` callers appear. If components are missing, that is an upstream issue to file: autoload roots should come from `config.autoload_paths`.

### 4.1 Verification run (2026-11-17, repowise 0.60.1, `origin/main` at `587222da`)

`mise run repowise:init` (index-only) took 58 s: 6,297 nodes, 10,977 edges. It wrote only `.repowise/`; `~/.claude/settings.json` and `~/.claude.json` gained no repowise entries.

Callers from `repowise context <file> --include callers`, compared with a grep for the constant:

| Target | repowise callers | grep baseline | Verdict |
|---|---|---|---|
| `app/models/orchestration/step.rb` | `steps_controller.rb`, `step_spec.rb`, `steps_run_list_component.rb`; imported by `pipeline.rb`, `step_action.rb` | same, plus a type comment in `lib/orchestration/pipeline_validator.rb` | Resolves, including the namespaced `class_name:` associations |
| `app/components/orchestration/action_run_component.rb` | none | `step_run_component.rb` | **Missing** |
| `app/forms/orchestration/pipeline_run_form.rb` | none | `pipelines_controller.rb` | **Missing** |
| `app/tools/records/insert_rows_tool.rb` | none | `lib/orchestration/tool_resolver.rb` | **Missing** |
| `app/components/application_component.rb` | 3 files in `lib/view_primitives/ui` | 26 subclasses, all in `lib/view_primitives/ui` | Partial |

This confirms the source reading: constants under `app/components`, `app/forms` and `app/tools` don't resolve. Upstream issue still to file: autoload roots should come from `config.autoload_paths`.

What works well is the history layer, the reason for adopting repowise. `get_risk(changed_files=["app/models/orchestration/step.rb"])` returned `missing_cochanges: [step_spec.rb, sig/app/models/orchestration/step.rbs, pipeline_spec.rb]` and the five associated models under `may_break`. `tests_to_run` is unusable: there are no graph edges from RSpec files, so it falls back to all 218 test files.

`repowise risk A...B` (three-dot) is parsed and gives the same result as `git diff A...B`.

## 5. Overlap with existing tooling

| repowise layer | Already here |
|---|---|
| `health` (complexity, LCOM4, god class, churn × complexity) | RubyCritic in CI (`rubycritic` job), Reek, RuboCop metrics |
| dependency graph / layering | `archspec` (enforced), rubydex MCP (symbol index) |
| `security check` | Brakeman (pre-commit and CI) |
| change risk, co-change, ownership, bus factor, PR-size percentile | **nothing**. This is the new value. |

## 6. Revised task list for #168

1. Add `.mise.toml` (§3.1) with an exact pin, `uv`, and `DO_NOT_TRACK`. Decide whether ruby/node move into it too.
2. Add `.repowise/` to `.gitignore`. Document `repowise init --no-prose --no-editor-setup --no-distill-hook --no-claude-md --no-agents`.
3. Add the `repowise` entry to `.mcp.json` via `mise exec` (§3.3). Consider `--tools lean`.
4. Hand-write `.husky/post-commit` (§3.2). Drop the Overcommit sub-tasks.
5. Add an advisory CI job: `fetch-depth: 0`, mise-action, `mise run repowise:risk -- --format github`, `continue-on-error: true`.
6. Run the Rails verification (§4) and record the result in this doc.
7. PR Bot: decide app vs. action `comment: true` (recommended: action).
8. BYOK prose: defer.
9. Document `mise run repowise:health` in README for orchestration-layer changes.
