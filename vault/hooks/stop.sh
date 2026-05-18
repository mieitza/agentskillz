#!/usr/bin/env bash
# Stop hook: at session end, if meaningful work happened, append a dated log
# entry to the project's working file in the vault and explicitly commit.
#
# Schema note: Stop uses top-level systemMessage. There is NO Stop variant of
# hookSpecificOutput — emitting hookEventName: "Stop" inside hookSpecificOutput
# is invalid and will be rejected by Claude Code.

set -euo pipefail

PROJECT_SLUG="$(basename "${PWD:-.}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | sed 's/^-*//;s/-*$//')"
PROJECT_SLUG="${PROJECT_SLUG:-session}"
AGENT_IDENTITY="${VAULT_AGENT_IDENTITY:-claude-code}"

SYSTEM_MSG=$(cat <<EOF
Session is ending. Decide whether to log:

SKIP if the session was trivial — one factual question, no decisions, no code or config changes.

OTHERWISE, append a Log entry to 'working/${PROJECT_SLUG}.md' in the vault:

1. Call read_file("working/${PROJECT_SLUG}.md"). If it doesn't exist and the work was meaningful, write_file it from the vault-memory skill template first.
2. Append a new entry at the very end of the Log section, format:
   ### YYYY-MM-DD HH:MM — ${AGENT_IDENTITY}
   - 2-5 bullets covering: what was decided/built, what changed in the codebase, any new open questions
   Use UTC and ISO date format.
3. Call commit_and_push("vault: log ${PROJECT_SLUG} — <one-line summary>") to checkpoint.

All paths are relative to the vault MCP root. Never use absolute host paths. Do not edit prior Log entries — append only.
EOF
)

jq -n --arg msg "$SYSTEM_MSG" '{
  systemMessage: $msg,
  suppressOutput: true
}'
