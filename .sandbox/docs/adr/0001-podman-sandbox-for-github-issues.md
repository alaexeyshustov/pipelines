---
status: accepted
---

# Podman sandbox per GitHub issue, Claude Code profiles only

Ported from the propstack `.codex` toolkit: one Git worktree per issue under
`.sandbox/worktrees/`, and one Podman container per (worktree, profile) running
Claude Code with `--dangerously-skip-permissions` against that worktree.

## Usage

```bash
gem install dry-cli sqlite3            # once per host Ruby
claude setup-token                     # once per host; save to ~/.claude-container/oauth-token
.sandbox/bin/init-worktree 42          # worktree + branch for GitHub issue #42, opens Zed
.sandbox/bin/attach-worktree 42        # claude-matt (default)
.sandbox/bin/attach-worktree 42 claude-omcc
.sandbox/bin/recreate-worktree 42 --dry-run
.sandbox/bin/db_helper cleanup_finished   # removes sandboxes whose issues are closed
ruby .sandbox/test/db_helper_test.rb
```

## Decision

- **Issue tracker is GitHub, via `gh`.** Identifiers are `GH-<number>`; every
  entry point accepts `42`, `#42`, `GH-42`, or the issue URL.
- **Branch names are derived deterministically**, not by an LLM: label → type
  (`bug` → `fix`, `refactor` → `refactor`, `documentation`/`chore` → `chore`,
  otherwise `feat`) plus `gh-<number>-<title slug>` (slug ≤ 50 chars). The
  worktree is named after the branch without its type prefix.
- **Own SQLite registry** at `.sandbox/bin/sandbox.sqlite` (gitignored, not
  shared with propstack): `issues` caches number/title/state/branch (the
  branch stays stable even if the title is edited later), plus the
  `worktrees` and `sandbox_containers` tables carried over unchanged.
  `cleanup_finished` refreshes each active issue's state with `gh` and
  finishes containers whose issue is `CLOSED`.
- **Claude-only profiles**: `claude-matt` (Matt Pocock skills, default) and
  `claude-omcc` (oh-my-claudecode). The Codex profiles, Linear lookup,
  Datadog/pup, Postgres/Redis/Elasticsearch wiring, OMX hook and Codex memory
  sync are dropped. The app uses SQLite in `storage/`, so no host database
  services are needed.
- **`.sandbox/` is tracked in this repository** (propstack kept `.codex` as a
  separate nested repo). Helpers always resolve the primary checkout through
  the Git common directory, so they are not copied into worktrees; instead
  `init-worktree` copies the untracked files listed in `.worktreeinclude`
  (`.env`, Google credentials, dev databases), skipping `node_modules`, which
  lives on a per-container volume.
- `CLAUDE_CONFIG_DIR=/root/.claude` keeps `.claude.json` on the profile's
  home volume, so onboarding and session history survive container rebuilds.
- **Containers run as `linux/amd64`** (Rosetta on Apple Silicon). sqlite-vec
  publishes its Linux ARM gem as `arm64-linux`, which Linux Ruby
  (`aarch64-linux`) never selects, so the app cannot `bundle install` on
  native arm64. The architecture is part of the image tag and of the
  bundle/node_modules volume names so nothing built for another architecture
  is reused. Revisit if sqlite-vec starts publishing `aarch64-linux` gems.
- **rtk** is installed from its pinned release (checksums pinned in the
  Containerfiles), and every session runs `rtk init -g --auto-patch`, giving
  the container the same Bash hook, `RTK.md` and `@RTK.md` import as the host.
  Only the rtk part of the host's global `CLAUDE.md` is reproduced.
- `db_helper` runs on the host Ruby with global gems rather than the app's
  bundle, so it works before `bundle install` and across Ruby upgrades.

## Consequences

- Worktrees are branched from `origin/main`; until `.sandbox/` is merged
  there, run the helpers from the primary checkout (as `init-worktree`
  prints).
- Adding a profile is still just a `profiles/<name>/` directory with a
  `profile.env`, `Containerfile` and `claude-session`.
