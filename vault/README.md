# Shared Agent Memory Vault

A single source of truth for project memory across Claude Desktop, Claude
Code, and OpenCode. Hosted on `agentsmith` (100.83.164.37), reachable
over Tailscale, exposed via MCP.

## Architecture

```
                          ┌─────────────────────────────┐
                          │   agentsmith (Linux box)    │
                          │   100.83.164.37 (tailscale) │
                          │                             │
   Claude Desktop ──SSE──▶│   supergateway :8088        │
   (Mac)                  │      │                      │
                          │      ▼                      │
   Claude Code ───SSE────▶│   @modelcontextprotocol/    │
   (any machine)          │   server-filesystem (stdio) │
                          │      │                      │
   OpenCode ─────SSE─────▶│      ▼                      │
                          │   /home/misha/vault/        │
                          │   ├── working/              │
                          │   ├── reference/            │
                          │   └── archive/              │
                          │   (git repo, auto-commits)  │
                          └─────────────────────────────┘
```

## Installation order

### 1. On agentsmith

```bash
scp -r vault-pkg/ misha@100.83.164.37:~/
ssh misha@100.83.164.37
cd vault-pkg/server
./install-vault.sh
```

This sets up the vault directory, git repo, systemd service, and
auto-commit timer. Idempotent — re-run anytime.

Verify it's up:

```bash
systemctl --user status vault-mcp.service
curl -v http://100.83.164.37:8088/sse  # from your Mac
```

### 2. On your Mac (Claude Desktop)

Follow `client/claude-desktop/README.md`. Short version: merge the JSON
snippet into `~/Library/Application Support/Claude/claude_desktop_config.json`,
then restart Claude Desktop completely (Cmd+Q).

### 3. On every machine running Claude Code

Follow `client/claude-code/README.md`. Short version:

```bash
claude mcp add --transport sse vault http://100.83.164.37:8088/sse --scope user
mkdir -p ~/.claude/hooks ~/.claude/skills
cp client/claude-code/vault-session-start.sh ~/.claude/hooks/
cp client/claude-code/vault-session-end.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/vault-*.sh
cp -r skills/vault-memory ~/.claude/skills/
```

Then merge the `hooks` snippets into `~/.claude/settings.json`.

### 4. (Optional) OpenCode

```bash
cp -r skills/vault-memory ~/.config/opencode/skills/
```

And add the vault MCP server to your `opencode.json`:

```json
{
  "mcp": {
    "vault": {
      "type": "sse",
      "url": "http://100.83.164.37:8088/sse"
    }
  }
}
```

## First-run: backfill

Once everything is up, seed the working space with the current state of
your active projects. From any Claude Desktop or Claude Code session
connected to the vault, paste:

```
Create these files in the vault's working/ directory with the standard
frontmatter and sections (Status, Decisions, Open questions, Log):

- cartoon-pipeline.md — Status: bootstrap package built (ComfyUI + Wan 2.2),
  smoke test ran into OOM on GB10, debugging memory layout. Open Q: which
  knob — quantization or tiled VAE decode?
- digisign.md — Status: pitch package sent. Awaiting response from
  DigiSign CTO/PKI lead.
- charterpulse.md — Status: full engineering contract bundle complete
  (CONTRACTS.md, SESSIONS.md, 17 test files). Decision pending: start
  S1 this week or shelve behind cartoon + digisign.
- brainmap.md — Status: 11-service system + dashboard + Telegram bot + 9
  email automations delivered. Invoice pending.
- affiliate.md — Status: platform delivered (~80h). Invoice pending at
  "small favor" rate; market price quoted in parallel.
```

After that, every session has shared context. No more split brain.

## Operating rules

- **Start of session**: agent reads `working/<slug>.md` for the project.
- **During session**: write decisions as they're made (don't batch).
- **End of session**: append a dated log entry. The SessionEnd hook nudges.
- **Closing a project**: move `working/<slug>.md` → `archive/<slug>.md`.
- **Stable knowledge**: write to `reference/` (e.g. `reference/dgx-spark-gotchas.md`).

## Why this design

- **Files, not a DB.** Markdown is the universal interchange format. Any
  tool can read and write it. No schema migrations, no daemon to keep
  running besides the MCP shim.
- **Git is the WAL.** Every change is committed. Roll back, diff, blame —
  all free.
- **Tailscale is the trust boundary.** No OAuth, no API keys. Your
  tailnet ACLs control access. Port 8088 binds to the Tailscale IP only,
  not 0.0.0.0.
- **MCP is the wire protocol.** Both surfaces speak it. Adding more
  clients (OpenCode, Cursor, custom agents) is a config-only change.
- **No vendor lock-in.** If MCP dies tomorrow, the vault is still just a
  folder of markdown files in a git repo. Nothing to migrate.

## Common operations

```bash
# View recent changes
cd /home/misha/vault && git log --oneline -20

# Roll back an accidental overwrite
cd /home/misha/vault && git show HEAD~1:working/charterpulse.md

# Search across the whole vault
cd /home/misha/vault && rg "decision" --type md

# Move a finished project to archive
mv /home/misha/vault/working/foo.md /home/misha/vault/archive/foo.md

# Restart the MCP service after editing the unit
systemctl --user daemon-reload
systemctl --user restart vault-mcp.service

# Tail service logs
journalctl --user -u vault-mcp.service -f
```
