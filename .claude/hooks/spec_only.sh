#!/usr/bin/env bash
# PreToolUse hook for the tester subagent (GH #258): blocks edits outside spec/.
set -u
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

file=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
[ -n "$file" ] || exit 0
file=${file#"$PWD/"}

case "$file" in
  spec/*) exit 0 ;;
esac

echo "tester may only edit files under spec/ (got $file); hand other changes back to the caller." >&2
exit 2
