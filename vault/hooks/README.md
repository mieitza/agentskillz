# vault-memory hooks

Two hook scripts. Both emit schema-valid JSON via `jq` so quoting never breaks.

| Script              | Event        | What it does                                                          |
| ------------------- | ------------ | --------------------------------------------------------------------- |
| `session-start.sh`  | SessionStart | Nudges Claude to load context for the current project from the vault. |
| `stop.sh`           | Stop         | If meaningful work happened, appends a Log entry and commits.         |

Both detect the project slug from the current working directory's basename, lowercased and kebab-cased. Override per-client by setting `VAULT_AGENT_IDENTITY` in the env (defaults to `claude-code`).

## Schema notes

Claude Code's hook output schema only defines `hookSpecificOutput` variants for **PreToolUse**, **UserPromptSubmit**, **PostToolUse**, and **PostToolBatch**. Stop and SessionStart use the **top-level** fields — `systemMessage`, `suppressOutput`, etc. The earlier version of these hooks emitted `hookSpecificOutput.hookEventName = "Stop"`, which is rejected. That bug is fixed here.

## Wiring

The top-level installer adds these to `~/.claude/settings.json` automatically. To wire them by hand:

```json
{
  "hooks": {
    "SessionStart": [
      { "command": "$HOME/.claude/hooks/vault/session-start.sh" }
    ],
    "Stop": [
      { "command": "$HOME/.claude/hooks/vault/stop.sh" }
    ]
  }
}
```
