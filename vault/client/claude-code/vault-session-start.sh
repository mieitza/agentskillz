#!/usr/bin/env bash
# vault-session-start.sh — inject project context from the vault at session start.
#
# Logic:
#   1. Look at $CLAUDE_PROJECT_DIR (or $PWD as fallback).
#   2. Derive a project slug from the directory name.
#   3. Check if working/<slug>.md exists in the vault via MCP — but we can't
#      call MCP from a shell hook, so instead we emit a system message
#      telling Claude to read it itself. This is the MCP-native way: hint,
#      don't fetch.
#
# Output: JSON on stdout per the Claude Code hook contract.
#         An "additionalContext" string gets injected into the system prompt.
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
SLUG="$(basename "$PROJECT_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')"

# Emit the hint. The agent will then call vault.read_file on its own.
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "You have access to a shared memory vault via the 'vault' MCP server. The current project directory is '$PROJECT_DIR' (slug: '$SLUG'). At the start of this session, use the vault MCP tools to read working/$SLUG.md if it exists. If it does, summarize the current Status and Open questions to the user before proceeding. If it doesn't exist, ask the user whether to create it. At the end of the session, append a new dated entry to the Log section with what was done and any new open questions."
  }
}
EOF
