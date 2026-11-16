#!/usr/bin/env bash
# PostToolUse hook (GH #286): type-checks the Ruby file Claude just edited and hands Steep's errors back as
# context. Never blocks: a mid-refactor edit may be type-incorrect for a moment.
set -u
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

file=$(jq -r '.tool_input.file_path // empty')
[ -n "$file" ] || exit 0
file=${file#"$PWD/"}

# A signature edit checks the Ruby file it describes.
case "$file" in
  sig/app/*.rbs | sig/lib/*.rbs) file=${file#sig/}; file=${file%.rbs}.rb ;;
esac

# The Steepfile's checked paths; its ignore list still applies.
case "$file" in
  app/jobs/*.rb | app/models/*.rb | app/services/*.rb | app/tools/*.rb | lib/*.rb) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

# Git exports GIT_INDEX_FILE to hooks; see .husky/pre-commit.
output=$(env -u GIT_INDEX_FILE bundle exec steep check --jobs 2 "$file" 2>&1) && exit 0
output=$(printf '%s\n' "$output" | grep -vE '^[.F]*$')

jq -n --arg file "$file" --arg out "$output" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("Steep reports type errors in \($file) (fix the code or its sig/ file):\n\($out)")
  }
}'
