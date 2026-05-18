# One-line installer for the vault-memory skill

Drops the `vault-memory` skill and `vault` MCP config into every supported
agent on the machine — Claude Code, Claude Desktop, OpenCode, Codex CLI,
Cursor, and Continue.dev. Auto-detects which ones you have; skips the rest.

## The one-liner

```bash
curl -fsSL https://raw.githubusercontent.com/mieitza/agentskillz/main/vault/install/install.sh | bash
```

> If you fork the repo, point `REPO_RAW=` at your fork's raw URL base.

## What it does

1. Detects which agents are installed.
2. Downloads the `vault-memory` skill and Claude Code hooks from this repo.
3. For each detected agent:
   - **Claude Code**: registers the `vault` MCP server with `claude mcp add`,
     installs `~/.claude/skills/vault-memory/SKILL.md`, copies the
     `SessionStart` + `Stop` hooks into `~/.claude/hooks/`, and merges them
     into `~/.claude/settings.json` (idempotent — won't duplicate hooks).
   - **Claude Desktop / Cowork**: merges an `mcp-remote`-backed `vault` entry
     into `claude_desktop_config.json` (macOS/Linux paths handled) **and**
     downloads `vault-memory.plugin` to `~/Downloads/` and opens it — Cowork
     prompts you to accept the install, which is where the skill + the
     `/vault-read`, `/vault-log`, `/vault-status` slash commands come from.
   - **OpenCode**: installs the skill into `~/.config/opencode/skills/`
     and merges the SSE MCP entry into `opencode.json`.
   - **Codex CLI**: appends `[mcp_servers.vault]` to `~/.codex/config.toml`
     if not already present.
   - **Cursor**: merges the MCP entry into `~/.cursor/mcp.json`.
   - **Continue.dev**: merges the MCP entry into `~/.continue/config.json`.

Re-running is safe — the JSON merges are upserts.

## Env vars

| Var             | Default                                 | Purpose |
| --------------- | --------------------------------------- | ------- |
| `VAULT_URL`     | `http://100.83.164.37:8088/sse`         | Vault SSE endpoint. Override for non-default tailnet IPs or hostnames. |
| `REPO_RAW`      | `https://raw.githubusercontent.com/mieitza/agentskillz/main/vault` | Base URL for fetching the skill and hooks. Set this when forking. |
| `VAULT_DRY_RUN` | `0`                                     | If `1`, prints every action without touching disk. |
| `VAULT_FORCE`   | `0`                                     | Overwrite existing config entries even if present. |

Examples:

```bash
# Run against a forked repo
REPO_RAW=https://raw.githubusercontent.com/yourname/agentskillz/main/vault \
  bash -c "$(curl -fsSL $REPO_RAW/install/install.sh)"

# Override the vault endpoint
VAULT_URL=http://vault.tailnet.example:8088/sse \
  curl -fsSL https://raw.githubusercontent.com/mieitza/agentskillz/main/vault/install/install.sh | bash

# See what it would do, change nothing
VAULT_DRY_RUN=1 curl -fsSL https://.../install.sh | bash
```

## Verification

After install, restart any running agent (Claude Desktop needs `Cmd+Q`,
not just window close). Then from a chat:

> list the files in the working directory of the vault

If the tool call works, you're done.

If it times out:

```bash
curl -v "$VAULT_URL"
# Should return SSE headers (content-type: text/event-stream)
tailscale status   # confirm tailnet is up
```

## Uninstall

There's no `uninstall.sh` yet because removal is surface-specific:

```bash
# Claude Code
claude mcp remove vault --scope user
rm -rf ~/.claude/skills/vault-memory
rm ~/.claude/hooks/vault-session-{start,end}.sh
# Then hand-edit ~/.claude/settings.json to remove the hook entries.

# Claude Desktop
# Edit ~/Library/Application Support/Claude/claude_desktop_config.json
# and delete the "vault" key under "mcpServers". Cmd+Q to restart.

# OpenCode
rm -rf ~/.config/opencode/skills/vault-memory
# Edit ~/.config/opencode/opencode.json and remove "vault" under "mcp".

# Codex
# Remove the [mcp_servers.vault] block from ~/.codex/config.toml.

# Cursor / Continue
# Remove the "vault" entry from ~/.cursor/mcp.json or ~/.continue/config.json.
```

## Why this layout

Think of the installer as a **package-manager bootstrap** (rustup,
oh-my-zsh): one URL that sniffs the environment and fans out to the right
config files for each runtime. The skill and the MCP wire protocol are
identical across agents — only the config format varies. The installer
abstracts that.
