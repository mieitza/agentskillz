# vault — shared agent memory

One git-backed markdown vault, served over MCP, used by every agent surface (Claude Desktop / Cowork, Claude Code, OpenCode). Everything in this directory is part of a single integrated system — no glue scripts, no out-of-band patches.

## Architecture

```
                ┌─────────────────────────────────────────────┐
                │       agentsmith (100.83.164.37)            │
                │                                             │
                │   vault-mcp.service   ──► MCP over SSE      │
                │   vault-watcher.service ─► git autocommit   │
                │                                             │
                │   /home/<user>/vault  (git repo)            │
                │     working/<slug>.md                       │
                │     reference/                              │
                │     people/                                 │
                │     inbox.md                                │
                └──────────────────▲──────────────────────────┘
                                   │ HTTP/SSE over Tailscale
              ┌────────────────────┼─────────────────────┐
              │                    │                     │
       Claude Code           Claude Desktop          OpenCode
       (plugin + hooks)      (.plugin import)        (skill + mcp.json)
```

Every client speaks to the same MCP server. Writes happen through MCP tools (`read_file`, `write_file`, `edit_file`, `commit_and_push`). The server is path-sandboxed: agents see only vault-relative paths, never host paths.

Two commit paths, by design:
- **Explicit** — agents call `commit_and_push("<message>")` at meaningful checkpoints (the Stop hook does this automatically).
- **Background safety net** — `vault-watcher.service` polls every 5s and commits anything that's been quiet for 30s, so nothing is ever lost if an agent skips the explicit call.

## Directory map

```
vault/
├── server/              MCP server + autocommit watcher (Python)
│   ├── vault_mcp.py
│   ├── vault_watcher.py
│   ├── requirements.txt
│   ├── vault-mcp.service        systemd unit for the MCP server
│   └── vault-watcher.service    systemd unit for the watcher
├── skill/
│   └── SKILL.md         Canonical vault-memory skill (used by every surface)
├── plugin/              Claude Desktop / Cowork + Claude Code plugin bundle
│   ├── .claude-plugin/plugin.json
│   ├── .mcp.json
│   ├── commands/        Slash commands: /vault-read /vault-log /vault-status
│   └── skills/vault-memory/SKILL.md   (copy of skill/SKILL.md)
├── hooks/               SessionStart + Stop hooks for Claude Code
│   ├── session-start.sh
│   └── stop.sh
└── install/
    ├── install.sh       One-line installer (server or client, auto-detected)
    └── uninstall.sh     Clean client uninstall
```

## Install

One line, anywhere:

```bash
curl -fsSL https://raw.githubusercontent.com/mieitza/agentskillz/main/vault/install/install.sh | bash
```

On a Linux server with systemd, it installs the MCP service + watcher.
On macOS or a non-systemd machine, it installs the client side (plugin + hooks + OpenCode wiring).

Flags:

```
--server | --client      force a role
--update                 re-run, overwriting existing files
--vault-host HOST        MCP host (default 100.83.164.37)
--vault-port PORT        MCP port (default 8088)
--vault-root DIR         server-side vault dir (default /home/$USER/vault)
--branch BRANCH          git branch to fetch (default main)
--repo URL               source repo (default https://github.com/mieitza/agentskillz)
```

## Updating

```bash
curl -fsSL https://raw.githubusercontent.com/mieitza/agentskillz/main/vault/install/install.sh | bash -s -- --update
```

Idempotent. Re-runs the same steps with `--update` semantics.

## Uninstall (client)

```bash
curl -fsSL https://raw.githubusercontent.com/mieitza/agentskillz/main/vault/install/uninstall.sh | bash
```

Server uninstall is intentionally manual: `sudo systemctl disable --now vault-mcp vault-watcher && sudo rm -rf /opt/vault-mcp`. The vault itself is never touched by the installer.

## How the pieces talk

1. Any agent loads the **vault-memory skill** at session start (or on demand) — it teaches the agent the file layout, log format, and which tool to call for which job.
2. The **plugin** ships the skill, the `/vault-*` slash commands, and the `.mcp.json` so Claude Desktop / Code can find the MCP server.
3. The **MCP server** (`vault-mcp.service`) exposes `read_file`, `write_file`, `edit_file`, `list_directory`, `search_files`, `commit_and_push`. All paths are vault-relative.
4. The **SessionStart hook** reminds the agent to load `working/<slug>.md` for the current project before responding.
5. The **Stop hook** reminds the agent to append a Log entry and call `commit_and_push` if meaningful work happened.
6. The **watcher** (`vault-watcher.service`) is the safety net: if step 5 is skipped, it autocommits 30s after the last write.

## Landing changes in this repo

The whole tree under `vault/` is the source of truth. To make a change:

```bash
git clone git@github.com:mieitza/agentskillz.git
cd agentskillz
# edit files under vault/
git add vault/
git commit -m "vault: <what changed>"
git push
```

Then on each client and on the server: `curl ... | bash -s -- --update`.

No glue scripts. No `fix_my_mistake.sh`. If something's broken, the fix lands in the same files everyone else pulls.
