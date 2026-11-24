# Claude Code guards for the sandbox

`managed-settings.json` and `hooks/guard-bash` are baked into the image by both
Containerfiles (`/etc/claude-code/managed-settings.json`,
`/usr/local/lib/claude-hooks/guard-bash`). Managed settings take precedence over
the agent-writable config volume (`/root/.claude`) and merge with rtk's user
settings, so `--dangerously-skip-permissions` does not switch them off.

- Read denies: `.env*`, `credentials.json`, `*token.yaml`, `config/*.key`, `storage/**`.
- `guard-bash` blocks (exit 2): `git push --force`/`-f`, `git reset --hard`,
  `git clean -f` (not with `-n`), `git branch -D` / `--delete --force`,
  `git checkout -f`, `git checkout .` / `HEAD .`, `git restore .` / `:/`
  (not `--staged` alone). Any `-...` git option before the subcommand is skipped,
  and the command word is matched by basename (`/usr/bin/git`).
- It asks for confirmation on every other `git push` (including
  `--force-with-lease` and `+refspec`) and on every `gh` command that is not a
  known read. Allowlist: `issue|pr view|list|diff|status|checks`, `search`,
  `run view|list|watch`, `release view|list`, `repo view`, `auth status`,
  `--version`/`help`, and `gh api` without a method other than GET or field
  flags (`-f`, `-F`, `--field`, `--raw-field`, `--input`).
- Wrappers are looked through: `rtk [proxy]`, `env`, `command`, `sudo`, `exec`,
  `time`, `nohup`, `nice`, `timeout`, `builtin`, `VAR=1`, `!`, `{`, `then`.
- It fails closed: a hook error, an unexpected payload, invalid UTF-8 (a block
  becomes an ask) or nesting deeper than 20 levels asks; it never exits 1.

## Limits

- These are pattern matches on the command text, not a sandbox.
- Code nested in `bash|sh|zsh -c`, `eval`, `xargs`, `$(...)`/backticks inside
  double quotes, and a heredoc fed to a shell (or unquoted with `$(...)`) is
  parsed with the same rules, but a block becomes an ask (never blocks, never
  allows). A plain quoted mention such as `echo "git reset --hard"` is only an
  argument and passes. Other heredoc bodies are data and pass
  (`cat > s.sh <<'EOF'`), so `python <<EOF` with `git push` inside is not seen.
- A bare `git`/`gh` word after an unknown command (`watch git push`,
  `find -exec git push`) is judged and asks. Pushes and GitHub writes
  mentioned in any argument text (`echo "gh pr merge"`,
  `python -c '...git push...'`) ask through a last-resort text scan.
- Not handled: `| sh` / `| bash` (a script piped into a shell), `bash <<<`
  here-strings, `bash <(...)` process substitution, `find -exec` with anything
  but a bare `git`/`gh` word (`-exec sh -c`), scripts written to disk and then
  run, `ruby -e`, `cat`, `curl` with `GH_TOKEN`, aliases and shell functions,
  variable-built commands (`$cmd push`), `$'\x70ush'` escapes, commands
  split across string concatenation, and escaped backticks nested in a
  backtick substitution inside double quotes
  (``echo "`echo \`git reset --hard\``"``; pushes and GitHub writes there still
  ask through the text scan).
- Destructive git the guard does not recognise passes: `reset --merge`,
  `stash drop`, `branch -M`, `update-ref -d`, `worktree remove --force`,
  `checkout -- '*'`, and anything behind a git alias (`alias.`, config or
  `-c`; `-c alias.*` asks). Also not seen: `${IFS}` in place of a space and
  code in an interpreter (`python -c`, `ruby -e`).
- Over-asking is kept on purpose: a quoted mention of `git push` or a GitHub
  write inside an argument (an `rg`/`grep` pattern, a commit message) asks
  through the text scan, because the guard cannot tell it from a nested command.
- Root in the container can edit `/etc/claude-code`.
- The real control is keeping secrets out of the mount: `init-worktree` skips
  `.env*`, `credentials.json` and `*token.yaml`, and secrets arrive through
  `SANDBOX_OP_ENVIRONMENT`.

Tests: `for t in .sandbox/test/*_test.rb; do ruby "$t" || exit 1; done`.
