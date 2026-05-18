# vault-memory plugin

Shared agent memory for Claude Desktop, Cowork, Claude Code, and OpenCode —
all backed by the same git-versioned markdown vault running on `agentsmith`
over Tailscale.

## What you get

- **Skill: `vault-memory`** — teaches Claude how to read and write the vault
  consistently. File conventions, append-only log format, when to read vs.
  write, agent-identity signing.
- **MCP server: `vault`** — connects to `http://100.83.164.37:8088/servers/vault/sse`
  via `mcp-remote`, exposing the full filesystem MCP surface
  (`read_file`, `write_file`, `edit_file`, `list_directory`, `search_files`).
- **Commands:**
  - `/vault-read [slug]` — read a project file and summarize current state
  - `/vault-log [slug] [bullets]` — append a dated log entry to a project
  - `/vault-status` — list all working projects with status, last update, open Qs

## Install (Claude Desktop / Cowork)

Drop the `.plugin` file into Cowork via the plugin installer UI, or place this
folder under your Cowork plugins directory. After install, restart Claude
Desktop (Cmd+Q + reopen).

## Install (Claude Code / OpenCode / Cursor)

You don't need this plugin — use the one-line installer from the repo root
instead, which handles those surfaces directly:

```bash
curl -fsSL https://raw.githubusercontent.com/mieitza/agentskillz/main/vault/install/install.sh | bash
```

## Prerequisites

- Tailscale connection to the tailnet hosting `agentsmith` (100.83.164.37)
- `npx` available on PATH (needed by `mcp-remote`)
- Vault MCP service running — see `vault/server/install-vault.sh` and
  `vault/server/fix-vault-concurrency.sh` in the parent repo

## How it fits the bigger picture

```
        ┌──────────────────────────────────────────┐
        │       agentsmith (100.83.164.37)         │
        │       vault MCP via mcp-proxy            │
        │       /home/misha/vault (git repo)       │
        └──────────────────▲───────────────────────┘
                           │ HTTP/SSE over Tailscale
        ┌──────────────────┴───────────────────────┐
        │                                          │
   Claude Desktop                      Claude Code / OpenCode
   + vault-memory plugin (this)        + vault-memory skill (one-liner)
```

Both paths land on the same git repo on disk. Two surfaces, one memory.
