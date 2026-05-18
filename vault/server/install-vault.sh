#!/usr/bin/env bash
# install-vault.sh — set up the shared agent memory vault on agentsmith
#
# Run on: agentsmith (100.83.164.37) as user `misha`
# What it does:
#   1. Creates /home/misha/vault with working/reference/archive structure
#   2. Initializes a git repo + auto-commit timer
#   3. Installs Node 22 LTS if not present (needed for MCP servers)
#   4. Installs supergateway + @modelcontextprotocol/server-filesystem globally
#   5. Writes a systemd user unit that binds the MCP server to the Tailscale interface
#   6. Enables and starts the service
#
# Idempotent: safe to re-run. Uses a state file at ~/.vault-install.state
set -euo pipefail

# ---------- config ----------
VAULT_ROOT="${VAULT_ROOT:-/home/misha/vault}"
TAILSCALE_IP="${TAILSCALE_IP:-100.83.164.37}"   # agentsmith
MCP_PORT="${MCP_PORT:-8088}"
NODE_VERSION="${NODE_VERSION:-22}"
STATE_FILE="${HOME}/.vault-install.state"

# ---------- helpers ----------
log()  { printf "\033[1;36m[vault]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[vault]\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m[vault]\033[0m %s\n" "$*" >&2; exit 1; }

mark_done() { echo "$1" >> "$STATE_FILE"; }
is_done()   { [[ -f "$STATE_FILE" ]] && grep -qx "$1" "$STATE_FILE"; }

# ---------- preflight ----------
[[ "$(uname)" == "Linux" ]] || die "This script is for Linux only."
[[ "$(id -un)" != "root" ]] || die "Run as your normal user, not root."
command -v systemctl >/dev/null || die "systemd is required."
command -v tailscale >/dev/null || warn "tailscale CLI not found — make sure $TAILSCALE_IP is bound on this host."

# Verify the Tailscale IP is actually on this machine.
if ! ip -4 addr | grep -q "$TAILSCALE_IP"; then
    warn "$TAILSCALE_IP is not on any interface of this host."
    warn "Continuing anyway, but the service will fail to bind if this is wrong."
fi

mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"

# ---------- 1. vault directory structure ----------
if ! is_done "vault-dirs"; then
    log "Creating vault directory structure at $VAULT_ROOT"
    mkdir -p "$VAULT_ROOT"/{working,reference,archive}

    # Seed each space with a README so they're never empty
    cat > "$VAULT_ROOT/README.md" <<'EOF'
# Agent Memory Vault

Shared memory for all Claude agents (Desktop, Code, OpenCode).

## Layout

- `working/`  — active projects, frequently written, always loaded at session start
- `reference/` — stable knowledge (how X works, decision records, domain notes)
- `archive/`  — closed projects, post-mortems, rarely touched

## File conventions

One markdown file per project. Top-level frontmatter:

```yaml
---
project: <slug>
status: active | paused | done
owner: misha
updated: <iso-8601>
---
```

Sections (use these consistently so agents can grep predictably):

- `## Status` — one-paragraph current state
- `## Decisions` — bulleted, dated, immutable once written
- `## Open questions` — bulleted, removed when resolved
- `## Log` — append-only, newest at bottom, each entry headed `### YYYY-MM-DD HH:MM — <agent or human>`

## Discipline

End every meaningful session with: "append today's status and open questions to <project>".
Start every session with: "read the current state of <project>".
EOF

    cat > "$VAULT_ROOT/working/.keep" <<'EOF'
Drop one .md per active project here.
EOF
    cat > "$VAULT_ROOT/reference/.keep" <<'EOF'
Stable, canonical knowledge. Decision records, "how X works" docs.
EOF
    cat > "$VAULT_ROOT/archive/.keep" <<'EOF'
Closed projects. Move from working/ here when done.
EOF

    mark_done "vault-dirs"
else
    log "Vault directories already created — skipping."
fi

# ---------- 2. git repo + auto-commit ----------
if ! is_done "vault-git"; then
    log "Initializing git repo in $VAULT_ROOT"
    cd "$VAULT_ROOT"
    if [[ ! -d .git ]]; then
        git init -q -b main
        git config user.email "agents@aeolus.local"
        git config user.name "Agent Vault"
        # Hide the noisy auto-commits behind a sane default identity, but allow
        # human commits to use the host's normal git config by setting these
        # only at the repo level.
        git add -A
        git commit -q -m "init vault"
    fi
    mark_done "vault-git"
else
    log "Git repo already initialized — skipping."
fi

# Always (re)write the auto-commit script so updates land
log "Writing auto-commit script"
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/vault-autocommit.sh" <<EOF
#!/usr/bin/env bash
# Auto-commit any vault changes. Runs on a timer.
set -euo pipefail
cd "$VAULT_ROOT"
if [[ -n "\$(git status --porcelain)" ]]; then
    git add -A
    git commit -q -m "auto: \$(date -Iseconds)" || true
fi
EOF
chmod +x "$HOME/.local/bin/vault-autocommit.sh"

# ---------- 3. Node.js 22 LTS ----------
if ! is_done "node-installed"; then
    if command -v node >/dev/null && node -e "process.exit(process.versions.node.split('.')[0] >= $NODE_VERSION ? 0 : 1)" 2>/dev/null; then
        log "Node $(node -v) already installed and >= v$NODE_VERSION — skipping."
    else
        log "Installing Node.js $NODE_VERSION via NodeSource"
        curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    mark_done "node-installed"
else
    log "Node already marked installed — skipping."
fi

# ---------- 4. MCP server + gateway ----------
if ! is_done "mcp-installed"; then
    log "Installing @modelcontextprotocol/server-filesystem and supergateway globally"
    # `sudo` because global npm installs go to /usr/lib/node_modules by default
    sudo npm install -g @modelcontextprotocol/server-filesystem supergateway
    mark_done "mcp-installed"
else
    log "MCP packages already installed — skipping."
fi

# ---------- 5. systemd user unit ----------
log "Writing systemd user unit"
mkdir -p "$HOME/.config/systemd/user"

# Resolve absolute paths so the unit doesn't depend on shell PATH at boot.
NPX_BIN="$(command -v npx)"
[[ -n "$NPX_BIN" ]] || die "npx not found after install."

cat > "$HOME/.config/systemd/user/vault-mcp.service" <<EOF
[Unit]
Description=Shared vault MCP server (filesystem over HTTP, bound to Tailscale)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
Environment=NODE_ENV=production
# supergateway wraps the stdio filesystem server and exposes it over HTTP/SSE.
# --host binds to the Tailscale IP only, never 0.0.0.0 — your tailnet ACLs
# are the trust boundary.
ExecStart=${NPX_BIN} -y supergateway \\
    --stdio "${NPX_BIN} -y @modelcontextprotocol/server-filesystem ${VAULT_ROOT}" \\
    --port ${MCP_PORT} \\
    --host ${TAILSCALE_IP} \\
    --baseUrl http://${TAILSCALE_IP}:${MCP_PORT} \\
    --ssePath /sse \\
    --messagePath /message
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

# Auto-commit timer: runs every 2 minutes if there are unstaged changes.
cat > "$HOME/.config/systemd/user/vault-autocommit.service" <<EOF
[Unit]
Description=Auto-commit vault changes

[Service]
Type=oneshot
ExecStart=$HOME/.local/bin/vault-autocommit.sh
EOF

cat > "$HOME/.config/systemd/user/vault-autocommit.timer" <<EOF
[Unit]
Description=Run vault autocommit every 2 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
Unit=vault-autocommit.service

[Install]
WantedBy=timers.target
EOF

# Enable lingering so user services run without an active login session.
if ! loginctl show-user "$(id -un)" 2>/dev/null | grep -q "Linger=yes"; then
    log "Enabling user lingering (needs sudo, one-time)"
    sudo loginctl enable-linger "$(id -un)"
fi

log "Reloading systemd user units"
systemctl --user daemon-reload
systemctl --user enable --now vault-mcp.service
systemctl --user enable --now vault-autocommit.timer

# ---------- 6. health check ----------
log "Waiting 3s for service to come up..."
sleep 3
if systemctl --user is-active --quiet vault-mcp.service; then
    log "vault-mcp.service is running."
else
    warn "vault-mcp.service is NOT running. Check logs with:"
    warn "    journalctl --user -u vault-mcp.service -n 50 --no-pager"
fi

# Try a quick TCP check
if command -v ss >/dev/null && ss -tln | grep -q ":${MCP_PORT}\b"; then
    log "Port ${MCP_PORT} is listening."
else
    warn "Port ${MCP_PORT} doesn't appear to be listening yet."
fi

log ""
log "=========================================="
log " Vault MCP server is up."
log ""
log " Endpoint (SSE):   http://${TAILSCALE_IP}:${MCP_PORT}/sse"
log " Vault root:       ${VAULT_ROOT}"
log " Auto-commit:      every 2 minutes via systemd timer"
log ""
log " Service control:"
log "   systemctl --user status vault-mcp.service"
log "   systemctl --user restart vault-mcp.service"
log "   journalctl --user -u vault-mcp.service -f"
log "=========================================="
