#!/usr/bin/env bash
# vault-session-end.sh — fires on Stop (when Claude finishes responding).
#
# Fires only once per session via a marker file in /tmp. The output uses
# top-level `systemMessage` because Claude Code's current Stop hook schema
# does NOT accept `hookSpecificOutput.additionalContext` (that's only valid
# for PreToolUse / UserPromptSubmit / PostToolUse / PostToolBatch).
#
# `systemMessage` surfaces as a non-blocking system note Claude sees once.
# It can decide whether to act on it.
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
SLUG="$(basename "$PROJECT_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
MARKER="/tmp/vault-session-end-${SESSION_ID}.done"

# Only fire once per session
if [[ -f "$MARKER" ]]; then
    exit 0
fi
touch "$MARKER"

# Properly JSON-escape the message body so quotes / backslashes / newlines
# can't corrupt the payload.
MSG="Session is wrapping up. If meaningful work was done on project '${SLUG}', append a new dated log entry to working/${SLUG}.md in the vault using the vault MCP tools. Format: '### YYYY-MM-DD HH:MM — claude-code' followed by 2-5 bullet points covering: what was decided/built, what changed in the codebase, any new open questions. Skip this if the session was trivial (one question, no code changes)."

# Use python (always present) to emit valid JSON.
python3 - "$MSG" <<'PY'
import json, sys
print(json.dumps({
    "continue": True,
    "suppressOutput": True,
    "systemMessage": sys.argv[1]
}))
PY
