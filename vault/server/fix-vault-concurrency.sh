#!/usr/bin/env bash
# fix-vault-concurrency.sh — swap supergateway for mcp-proxy so multiple
# clients can connect simultaneously.
#
# Run on: agentsmith
# Why: supergateway multiplexes one stdio child across all SSE clients,
# which crashes when a second client connects ("Already connected to a
# transport" error). mcp-proxy spawns one child per session.
set -euo pipefail

VAULT_ROOT="${VAULT_ROOT:-/home/misha/vault}"
TAILSCALE_IP="${TAILSCALE_IP:-100.83.164.37}"
MCP_PORT="${MCP_PORT:-8088}"

log() { printf "\033[1;36m[vault-fix]\033[0m %s\n" "$*"; }

# 1. Install mcp-proxy via pipx (clean, isolated, no PATH pollution)
if ! command -v pipx >/dev/null; then
    log "Installing pipx (one-time)"
    sudo apt-get update
    sudo apt-get install -y pipx
    pipx ensurepath
    # shellcheck disable=SC1091
    export PATH="$HOME/.local/bin:$PATH"
fi

if ! command -v mcp-proxy >/dev/null; then
    log "Installing mcp-proxy via pipx"
    pipx install mcp-proxy
else
    log "mcp-proxy already installed — upgrading"
    pipx upgrade mcp-proxy || true
fi

# Resolve absolute paths for the systemd unit
MCP_PROXY_BIN="$(command -v mcp-proxy)"
NPX_BIN="$(command -v npx)"
[[ -n "$MCP_PROXY_BIN" ]] || { echo "mcp-proxy not found after install"; exit 1; }
[[ -n "$NPX_BIN" ]] || { echo "npx not found"; exit 1; }

# 2. Stop the current (broken) service
log "Stopping supergateway-based service"
systemctl --user stop vault-mcp.service || true

# 3. Rewrite the systemd unit to use mcp-proxy
log "Rewriting systemd unit for mcp-proxy"
cat > "$HOME/.config/systemd/user/vault-mcp.service" <<EOF
[Unit]
Description=Shared vault MCP server (filesystem via mcp-proxy, per-connection children)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
Environment=NODE_ENV=production
# mcp-proxy spawns a fresh stdio child per incoming SSE session,
# which is what we need for multi-client (Desktop + Code + OpenCode)
# concurrent access. --pass-environment lets npx find Node correctly.
#
# --allow-origin '*' is fine here because the service binds to the
# Tailscale IP only — only tailnet members can reach the port.
ExecStart=${MCP_PROXY_BIN} \\
    --port=${MCP_PORT} \\
    --host=${TAILSCALE_IP} \\
    --allow-origin=* \\
    --pass-environment \\
    --named-server vault "${NPX_BIN} -y @modelcontextprotocol/server-filesystem ${VAULT_ROOT}"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

# 4. Reload and start
log "Reloading systemd"
systemctl --user daemon-reload
systemctl --user enable --now vault-mcp.service

log "Waiting 3s for service to come up..."
sleep 3

systemctl --user status vault-mcp.service --no-pager -l | head -20

log ""
log "=========================================="
log " New SSE endpoint URL (note: path changed!):"
log "   http://${TAILSCALE_IP}:${MCP_PORT}/servers/vault/sse"
log ""
log " (The /servers/<name>/sse path is mcp-proxy's convention for"
log "  named servers. Clients need to be updated to the new URL.)"
log "=========================================="
