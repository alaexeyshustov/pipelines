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
- Pushes and GitHub writes nested in `$(...)`/backticks inside double quotes,
  `bash|sh|zsh -c`, `eval` or `xargs` are caught by a raw-text scan that always
  asks (never blocks), so quoted mentions such as `echo "gh pr merge"` ask too.
- Not caught: scripts written to disk and then run, `ruby -e`, `cat`, `curl`
  with `GH_TOKEN`, aliases and shell functions, variable-built commands
  (`$cmd push`), and commands split across string concatenation.
- Root in the container can edit `/etc/claude-code`.
- The real control is keeping secrets out of the mount: `init-worktree` skips
  `.env*`, `credentials.json` and `*token.yaml`, and secrets arrive through
  `SANDBOX_OP_ENVIRONMENT`.

Tests: `ruby .sandbox/test/guard_bash_test.rb`.
