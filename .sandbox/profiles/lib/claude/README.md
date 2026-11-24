# Claude Code guards for the sandbox

`managed-settings.json` and `hooks/guard-bash` are baked into the image by both
Containerfiles (`/etc/claude-code/managed-settings.json`,
`/usr/local/lib/claude-hooks/guard-bash`). Managed settings take precedence over
the agent-writable config volume (`/root/.claude`) and merge with rtk's user
settings, so `--dangerously-skip-permissions` does not switch them off.

- Read denies: `.env*`, `credentials.json`, `*token.yaml`, `config/*.key`, `storage/**`.
- `guard-bash` blocks (exit 2): `git push --force`/`-f`, `git reset --hard`,
  `git clean -f`, `git branch -D`, `git checkout .`, `git restore .`.
- It asks for confirmation on every other `git push` (including
  `--force-with-lease` and `+refspec`) and on `gh` writes (`pr`/`issue` comment,
  create, merge, review, edit, close...; `gh api` with a non-GET method or fields).
- Reads (`gh ... view|list|diff`, `gh api` GET) and everything else pass.

## Limits

- These are pattern matches on the command text, not a sandbox.
- `cat`, `ruby -e`, scripts, and `curl` with `GH_TOKEN` get around them, as do
  command substitutions inside double quotes.
- Root in the container can edit `/etc/claude-code`.
- The real control is keeping secrets out of the mount: `init-worktree` skips
  `.env*`, `credentials.json` and `*token.yaml`, and secrets arrive through
  `SANDBOX_OP_ENVIRONMENT`.

Tests: `ruby .sandbox/test/guard_bash_test.rb`.
