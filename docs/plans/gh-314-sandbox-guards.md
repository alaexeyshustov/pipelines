# Plan: sandbox guards and CI dependency hardening (GH #314)

**Status:** planned | Part of #302 (SEC-15) | Builds on #334 | One PR

No Archspec layer applies. `Archspec.rb` scans only `app/` and `lib/`, and `.rubocop.yml` excludes `.sandbox/**/*`.

## Decisions

- **The guards live in image-baked managed settings.**
  - Sources go in `.sandbox/profiles/lib/claude/`.
  - Both Containerfiles copy them to `/etc/claude-code/managed-settings.json` and `/usr/local/lib/claude-hooks/guard-bash`.
  - Why not the config dir: `/root/.claude` is a shared, agent-writable volume (`profile.env:10`), and `configure_rtk` rewrites it on every start. Managed settings take precedence and merge with rtk's user settings.
  - `attach-worktree` fingerprints `lib_dir` into the image tag, so changes rebuild the image.
  - Fallback if step 1 shows managed settings aren't loaded: run `install_claude_guards` in `session-common.sh` after `configure_rtk`, and `jq`-merge the denies and our hook into `$CLAUDE_CONFIG_DIR/settings.json`.
- **rtk can't weaken "ask".** `rtk hook claude` returns only `updatedInput`, with no `permissionDecision`. The guard strips a leading `rtk ` too.
- **`guard-bash` is one Ruby script (stdlib only).** It behaves the same on the host (bash 3.2, BSD) and in the container, and it is tested with Minitest.
  - It splits commands on `&&`, `||`, `;`, `|`, newlines, `$(`, backticks and parentheses.
  - For each segment it strips `VAR=x`, `rtk`, `env`, `command`, `sudo` and `exec`, plus git global options (`-C`, `-c`, `--git-dir=`, `--work-tree=`, `--no-pager`).
  - It checks block rules first, then ask rules.
- **Outcomes:**
  - Block: exit 2, with the reason on stderr.
  - Ask: print `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":…}}` and exit 0.
  - Allow: exit 0 with no output.
  - Unparseable input that mentions `git … push` or `gh` gets ask.
- **Block:**
  - `git push --force` / `-f` (including `-C dir push -f`);
  - `git reset --hard`;
  - `git clean -f` / `-fd` / `-xfd` (`-n` is allowed);
  - `git branch -D`;
  - `git checkout .` / `-- .`;
  - `git restore .`.
- **Ask:**
  - every other `git push`, including `--force-with-lease` and `+refspec`;
  - every `gh` write subcommand (comment, create, merge, review, edit, close, ready, reopen, delete, transfer, lock, and writes to release, repo, workflow, label, secret and variable);
  - `gh api` with a non-GET `-X`/`--method`, or with `-f`/`-F`/`--field`/`--raw-field`/`--input` (this includes `api graphql`).
- **Allow:** `gh` reads (`view`, `list`, `diff`, `status`, `checks`, `search`, and plain or `-X GET` `api`) and everything else.
- **Read denies (managed, so `**/`-anchored):**
  - `Read(**/.env*)` — this also hides `.env.docker.example`, which is accepted;
  - `Read(**/credentials.json)`;
  - `Read(**/*token.yaml)`;
  - `Read(**/config/*.key)`;
  - `Read(**/storage/**)`.
- **Worktree secrets:** a basename filter is hard-coded in `init-worktree` for `.env`, `.env.*`, `credentials.json` and `*token.yaml`. `.worktreeinclude` stays as is, because Claude Code's host worktrees still need it.
  - Existing worktrees keep their copies; the ADR notes this.
- **Sandbox tests:** the Definition of done runs every file with `for t in .sandbox/test/*_test.rb; do ruby "$t" || exit 1; done`.

## Steps

### 1. Probe hook "ask" under bypass mode (nothing committed)
Use the pinned image (`CLAUDE_CODE_VERSION=2.1.303`) with a scratch `managed-settings.json` that:
- denies `Read(**/.env*)`;
- runs a probe hook that asks on `ASK_PROBE` and blocks (exit 2) on `BLOCK_PROBE`.

Run `rtk init -g --auto-patch`, then `claude --dangerously-skip-permissions`, and check each case:
1. `echo ASK_PROBE` prompts.
2. `git log -1 # ASK_PROBE` prompts after the rtk rewrite.
3. `echo BLOCK_PROBE` is blocked.
4. Read `.env` is refused.
5. `/hooks` lists the managed hook.

If (1) or (2) fails, change ask to block. If (4) or (5) fails, use the config-dir fallback. Record the result in the ADR.


**Result (2026-11-24, Claude Code 2.1.303, rtk hook installed):** managed settings at `/etc/claude-code/managed-settings.json` load. Under `claude -p --dangerously-skip-permissions`:
- hook `ask` refuses the command (no prompter in `-p`), so bypass does not override `ask`; this holds after the rtk rewrite too;
- exit 2 blocks;
- `Read(**/.env*)` is refused.

The plan stands. The interactive prompt itself is checked in step 6.
### 2. Container guard (red first)
**Files**
- `.sandbox/profiles/lib/claude/managed-settings.json`
- `.sandbox/profiles/lib/claude/hooks/guard-bash`
- `.sandbox/profiles/lib/claude/README.md`, which documents the limits:
  - these are pattern matches;
  - `cat`, `ruby -e`, scripts and `curl` with `GH_TOKEN` get around them;
  - root can edit `/etc`;
  - the real control is keeping secrets out of the mount.
- `COPY` lines in `profiles/claude-matt/Containerfile` and `profiles/claude-omcc/Containerfile`.

**Red tests**
- `.sandbox/test/guard_bash_test.rb` (`Open3`) covers the block, ask and allow cases above, plus:
  - compound commands: `cd a && git push --force` blocks, `cd a && git push` asks;
  - `rtk`-prefixed commands;
  - `echo "git reset --hard …"` is allowed;
  - unparseable input that mentions `gh` asks.
- `.sandbox/test/claude_guard_settings_test.rb` checks that:
  - the JSON parses;
  - the denies equal the five rules;
  - the hook path matches the `COPY` target;
  - the managed file has no rtk hook;
  - both Containerfiles copy both files.

### 3. Keep secrets out of worktrees (red first)
**Files**
- `.sandbox/bin/init-worktree` `install_sandbox_files`: a basename `case` skip next to the `node_modules` skip, and the comment updated to match.
- Stubs `.sandbox/test/support/zed` and `.sandbox/test/support/mise`.

**Red test:** `.sandbox/test/init_worktree_test.rb` runs scratch mode against a temp repo with a bare `origin`. Of `.env`, `.env.local`, `credentials.json`, `token.yaml` and `storage/development.sqlite3`, only the sqlite file reaches the worktree.

### 4. Remove `sandbox/`; update the ADR and README
- `git rm -r sandbox/`.
- `README.md`: replace the OrbStack section with a pointer to ADR 0001.
- `.sandbox/docs/adr/0001-podman-sandbox-for-github-issues.md`:
  - secrets are skipped and come from `SANDBOX_OP_ENVIRONMENT` (#334);
  - a Guards bullet with the probe result;
  - existing worktrees keep their copies;
  - the test command runs every file.
- **Acceptance:** `git grep -n -iE 'orbstack|orb -m|/work/sandbox|block-git' -- ':!docs/research'` is empty.

### 5. Gemfile, CI, lock files and docs
- **`Gemfile`:**
  - drop `:11-12` (the `liquid` gem and its comment);
  - add `gem "bundler-audit", require: false` after `brakeman` in `:development`;
  - run `bundle install`.
- **`.bundler-audit.yml`:** `ignore: []`, with a header requiring a reason per entry.
- **`.github/workflows/ci.yml`, `brakeman` job:** add the step `bundle exec bundle-audit check --update`.
- **`rbs_collection.lock.yaml`:** run `rbs collection update`, keep only the `liquid` removal, then run `rbs collection install`.
- **`archspec_facts/rails.yml`:** run `bundle exec archspec reflect --environment test`.
- **`AGENTS.md` Definition of done:**
  - `bundle exec bundle-audit check --update` (needs network);
  - the `.sandbox` test loop.
- **`docs/claude/gotchas.md`:** a Steep bullet saying to revert unrelated revision bumps after `rbs collection update`.
- **Acceptance:**
  - `git grep -n liquid -- Gemfile Gemfile.lock rbs_collection.lock.yaml` is empty;
  - `bundle-audit` exits 0;
  - `archspec check --check-todo` passes.

### 6. Final verification
Run the Checks below and reconcile the result against the issue's acceptance criteria. Then rebuild the container and walk through the four in-container criteria by hand.

## Checks
- `for t in .sandbox/test/*_test.rb; do ruby "$t" || exit 1; done`
- `bundle exec archspec check --check-todo`
- `bundle exec rbs -r optparse validate`, `bundle exec steep check`, `bundle exec bin/rbs_audit coverage --threshold=90`
- `bundle exec rigor check`
- `bundle exec rubocop`
- `bundle exec brakeman --no-pager`, `bundle exec bundle-audit check --update`
- `COVERAGE=true bundle exec rspec`
