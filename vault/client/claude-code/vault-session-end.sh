#!/usr/bin/env bash
# vault-session-end.sh — fires on Stop (when Claude finishes responding).
#
# We don't want to fire on every single Stop (that would be every assistant
# turn). Instead, we use a marker file to fire only once per session, and
# only if the session has been long enough to be worth recording.
#
# The hint is non-blocking — it just appears in Claude's context as a
# nudge. Claude decides whether to act on it.
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

# Don't nag on trivial sessions — check that the session is at least
# ~5 minutes old (heuristic: the marker file just got created, so we
# can't measure session length directly; instead the hook is conservative
# and always emits, but only once).

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "Session is wrapping up. If meaningful work was done on project '$SLUG', append a new dated log entry to working/$SLUG.md in the vault using the vault MCP tools. Format: '### YYYY-MM-DD HH:MM — claude-code' followed by 2-5 bullet points covering: what was decided/built, what changed in the codebase, any new open questions. Skip this if the session was trivial (one question, no code changes)."
  }
}
EOF
