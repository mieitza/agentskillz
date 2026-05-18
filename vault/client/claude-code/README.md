# Claude Code — vault MCP config

Claude Code speaks HTTP MCP natively, so no bridge needed.

## 1. Register the vault server

Run this once per machine where you use Claude Code:

```bash
claude mcp add --transport sse vault http://100.83.164.37:8088/sse --scope user
```

`--scope user` puts it in `~/.claude.json` so every project on the
machine sees it. Use `--scope project` only if you want it scoped to one
repo (writes to `.mcp.json` which gets committed).

Verify:

```bash
claude mcp list
```

You should see `vault` with status `connected`.

## 2. Install the SessionStart hook

The hook auto-loads relevant working-space context when a Claude Code
session starts in a project directory.

Copy `vault-session-start.sh` to `~/.claude/hooks/` and make it executable:

```bash
mkdir -p ~/.claude/hooks
cp vault-session-start.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/vault-session-start.sh
```

Then merge this into `~/.claude/settings.json` (under your existing
`hooks` object):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/vault-session-start.sh" }
        ]
      }
    ]
  }
}
```

If you already have a `SessionStart` array, just append the new entry to it.

## 3. (Optional) Install the SessionEnd hook

Same idea, but for the end of the session. The hook reminds you (in the
final agent response) to dump state back to the vault.

```bash
cp vault-session-end.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/vault-session-end.sh
```

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/vault-session-end.sh" }
        ]
      }
    ]
  }
}
```

## 4. The vault-memory skill

The skill at `skills/vault-memory/SKILL.md` teaches Claude Code (and
Claude Desktop) how to use the vault consistently: where to read,
where to write, file conventions, append-only log format.

Install:

```bash
cp -r skills/vault-memory ~/.claude/skills/
```

For OpenCode:

```bash
cp -r skills/vault-memory ~/.config/opencode/skills/
```

## How the pieces fit

```
Claude Desktop (Mac)
    └── mcp-remote (stdio↔SSE bridge, spawned per session)
            └── HTTP/SSE over Tailscale
                    └── agentsmith:8088
                            └── supergateway (SSE↔stdio bridge, systemd service)
                                    └── @modelcontextprotocol/server-filesystem
                                            └── /home/misha/vault (git repo)

Claude Code (any machine)
    └── HTTP/SSE over Tailscale (native, no bridge)
            └── agentsmith:8088
                    └── (same path as above)
```

The vault on disk is the database. Everything else is wire format.
