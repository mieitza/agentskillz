# vault-memory plugin

Shared memory for Claude Desktop / Cowork and Claude Code. Same content drives both surfaces.

## What's inside

- `.claude-plugin/plugin.json` — plugin manifest
- `.mcp.json` — MCP server config (proxies to the vault MCP via `mcp-remote`)
- `skills/vault-memory/SKILL.md` — the canonical vault-memory skill
- `commands/vault-{read,log,status}.md` — slash commands

## Install

Don't install this by hand. Use the top-level installer:

```bash
curl -fsSL https://raw.githubusercontent.com/mieitza/agentskillz/main/vault/install/install.sh | bash
```

The installer detects your surfaces (Claude Code, Claude Desktop, OpenCode) and wires each one up correctly.

## Requirements

- Tailscale connection to the tailnet hosting the vault MCP server (default `100.83.164.37`)
- `npx` on PATH (used by `mcp-remote`)
