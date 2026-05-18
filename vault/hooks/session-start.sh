#!/usr/bin/env bash
# SessionStart hook: tell Claude to load context for the current project from
# the vault before responding. Emits valid hook JSON (UserPromptSubmit variant
# is NOT used here; SessionStart uses top-level systemMessage).
#
# Per Claude Code's hook schema, top-level fields we may emit include:
#   continue, suppressOutput, stopReason, decision, reason,
#   systemMessage, terminalSequence, permissionDecision, hookSpecificOutput
# SessionStart has no hookSpecificOutput variant — use systemMessage.

set -euo pipefail

PROJECT_SLUG="$(basename "${PWD:-.}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | sed 's/^-*//;s/-*$//')"
PROJECT_SLUG="${PROJECT_SLUG:-session}"

SYSTEM_MSG=$(cat <<EOF
Session start. Before responding to the user, load context for project '${PROJECT_SLUG}' from the vault:

1. Call the vault MCP tool list_directory("working") to confirm 'working/${PROJECT_SLUG}.md' exists.
2. If it exists, call read_file("working/${PROJECT_SLUG}.md") and silently load the Status, Decisions, and the last 1-2 Log entries into context. Do not summarize these to the user unless they ask.
3. If it does not exist, do nothing yet. Create it (via write_file using the vault-memory skill template) only when the work in this session warrants it.

All vault paths are relative to the vault MCP root. Never use absolute host paths.
EOF
)

jq -n --arg msg "$SYSTEM_MSG" '{
  systemMessage: $msg,
  suppressOutput: true
}'
