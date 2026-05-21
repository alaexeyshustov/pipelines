#!/usr/bin/env bash
# Reads a Claude Code session transcript (JSONL) and prints a token usage summary.
# Usage: token-usage.sh [transcript_path]
# If no path is given, auto-detects the latest transcript for the current working directory.

set -euo pipefail

TRANSCRIPT="${1:-}"

if [ -z "$TRANSCRIPT" ]; then
  slug=$(pwd | sed 's|[/._]|-|g')
  TRANSCRIPT=$(ls -t ~/.claude/projects/"${slug}"/*.jsonl 2>/dev/null | head -1 || true)
fi

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  echo "unavailable"
  exit 0
fi

jq -sr '
  [.[] | select(.type == "assistant" and .message.usage != null)] |
  unique_by(.message.id) |
  [.[].message.usage] |
  {
    input:       (map(.input_tokens                 // 0) | add // 0),
    output:      (map(.output_tokens                // 0) | add // 0),
    cache_read:  (map(.cache_read_input_tokens      // 0) | add // 0),
    cache_write: (map(.cache_creation_input_tokens  // 0) | add // 0)
  } |
  "input=\(.input), output=\(.output), cache_read=\(.cache_read), cache_write=\(.cache_write)"
' "$TRANSCRIPT"
