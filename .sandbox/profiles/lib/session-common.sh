#!/usr/bin/env bash
# Shared by every profile's session entrypoint. Not executable on its own —
# source it, then call the functions below.

set -euo pipefail

# Missing files are skipped. Written with `continue` rather than
# `[[ -f ]] && ...`: a false test as the loop's last command would fail the
# pipeline under pipefail and silently abort the session under set -e.
dependency_fingerprint() {
  local file
  for file in "$@"; do
    [[ -f "$file" ]] || continue
    sha256sum "$file"
  done | sha256sum | awk '{print $1}'
}

install_bundle_dependencies() {
  local marker_path="/bundle/.pipelines-gemfile-lock.sha256"
  local fingerprint
  fingerprint="$(dependency_fingerprint Gemfile Gemfile.lock .bundle/config)"

  if [[ -f "$marker_path" && "$(<"$marker_path")" == "$fingerprint" ]] && bundle check >/dev/null; then
    printf 'Using cached Ruby gems\n'
    return
  fi

  bundle install --jobs 4 --retry 3
  printf '%s\n' "$fingerprint" > "$marker_path"
}

install_pnpm_dependencies() {
  local marker_path="node_modules/.pipelines-pnpm-lock.sha256"
  local fingerprint
  fingerprint="$(dependency_fingerprint package.json pnpm-lock.yaml .npmrc)"

  if [[ -d node_modules && -f "$marker_path" && "$(<"$marker_path")" == "$fingerprint" ]]; then
    printf 'Using cached Node dependencies\n'
    return
  fi

  local install_log="/tmp/pnpm-install.log"
  if pnpm install --frozen-lockfile --fetch-retries 0 --store-dir /pnpm/store >"$install_log" 2>&1; then
    printf '%s\n' "$fingerprint" > "$marker_path"
    return
  fi

  cat "$install_log" >&2
  if grep -q 'ERR_PNPM_TARBALL_INTEGRITY' "$install_log"; then
    # A package was republished at the same version. Clear the stale registry
    # metadata before recording the checksum currently served by the registry.
    printf 'Pruning stale pnpm metadata and refreshing pnpm-lock.yaml\n' >&2
    pnpm store prune --store-dir /pnpm/store
    pnpm install --lockfile-only --ignore-scripts --no-frozen-lockfile --update-checksums --fetch-retries 0 --store-dir /pnpm/store
  elif grep -q 'ERR_PNPM_OUTDATED_LOCKFILE' "$install_log"; then
    printf 'Refreshing pnpm-lock.yaml to match package.json\n' >&2
    pnpm install --lockfile-only --ignore-scripts --no-frozen-lockfile --fetch-retries 0 --store-dir /pnpm/store
  else
    return 1
  fi

  fingerprint="$(dependency_fingerprint package.json pnpm-lock.yaml .npmrc)"
  pnpm install --frozen-lockfile --fetch-retries 0 --store-dir /pnpm/store
  printf '%s\n' "$fingerprint" > "$marker_path"
}

# Steep needs the RBS collection, which is gitignored and so missing from a
# fresh worktree. Install it here rather than letting the pre-commit hook's
# steep run fetch it mid-commit.
install_rbs_collection() {
  bundle exec rbs collection install --frozen
}

install_workspace_dependencies() {
  cd "$SANDBOX_WORKSPACE"
  install_bundle_dependencies
  install_pnpm_dependencies
  install_rbs_collection
}

# The container has no SSH key, so the SSH remote (git@github.com:...) cannot
# fetch or push. Rewrite it to HTTPS authenticated by the host's gh token.
# Global (container-only) config: the repository config is shared with the
# host through the mounted common directory and must stay untouched.
configure_github_https() {
  if [[ -z "${GH_TOKEN:-}" ]]; then
    printf 'No GH_TOKEN; git cannot reach GitHub from this sandbox.\n' >&2
    return 0
  fi

  gh auth setup-git --hostname github.com
  git config --global url."https://github.com/".insteadOf git@github.com:
}

# Same global rtk setup as on the host (`rtk init -g`): the Bash PreToolUse
# hook in settings.json, RTK.md, and an @RTK.md reference in CLAUDE.md, all
# under $CLAUDE_CONFIG_DIR on the profile's home volume. Idempotent, so it is
# safe on every start; a failure only costs the token savings.
configure_rtk() {
  # rtk does not create the directory itself.
  mkdir -p "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  rtk init -g --auto-patch --no-trust-filters >/dev/null \
    || printf 'rtk init failed; continuing without the rtk hook.\n' >&2
}

# Claude Code authentication is a long-lived OAuth token from a one-time
# host-side `claude setup-token`, bind-mounted read-only by attach-worktree.
load_claude_auth() {
  if [[ ! -f /run/host-claude/oauth-token ]]; then
    printf 'Host Claude Code authentication is unavailable in this container.\n' >&2
    printf 'Run "claude setup-token" on the host and save it to ~/.claude-container/oauth-token.\n' >&2
    exit 1
  fi
  export CLAUDE_CODE_OAUTH_TOKEN
  CLAUDE_CODE_OAUTH_TOKEN="$(< /run/host-claude/oauth-token)"

  # Claude Code refuses --dangerously-skip-permissions as root unless it
  # detects a sandbox. This container IS the sandbox (per-worktree, disposable,
  # isolated from the host), so this is the intended escape hatch, not a
  # workaround of the safety check.
  export IS_SANDBOX=1
}

# Starts Claude Code, opening with an overview of the GitHub issue when the
# worktree belongs to one (identifier GH-<number>).
exec_claude() {
  local ticket="${1:-}"

  # Render on the main screen so the host terminal keeps native scrollback and
  # text selection across the attach. On the alternate screen, mouse capture
  # blocks selection, and without it the terminal turns the scroll wheel into
  # Up/Down keys, which page through prompt history.
  export CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1

  if [[ "$ticket" =~ ^GH-([0-9]+)$ ]]; then
    exec claude --dangerously-skip-permissions \
      "Make an overview of GitHub issue #${BASH_REMATCH[1]} (use \`gh issue view ${BASH_REMATCH[1]} --comments\`)."
  fi

  exec claude --dangerously-skip-permissions
}
