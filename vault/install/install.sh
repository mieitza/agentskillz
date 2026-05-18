#!/usr/bin/env bash
# vault-memory: one-line installer.
#
#   curl -fsSL https://raw.githubusercontent.com/mieitza/agentskillz/main/vault/install/install.sh | bash
#
# Detects what's on this machine and installs the right pieces:
#   - server role: vault MCP service + autocommit watcher (Linux + systemd)
#   - client role: skill + plugin + hooks for Claude Code, Cowork, OpenCode
#
# Flags:
#   --server           force server-side install (even on macOS)
#   --client           force client-side install (skip server detection)
#   --update           re-run install, overwriting existing files
#   --vault-host HOST  override MCP host (default 100.83.164.37)
#   --vault-port PORT  override MCP port (default 8088)
#   --vault-root DIR   server-side vault directory (default /home/$USER/vault)
#   --branch BRANCH    git branch to fetch sources from (default main)
#   --repo URL         git repo URL (default https://github.com/mieitza/agentskillz)

set -euo pipefail

# ---------- config ----------
REPO_URL="${VAULT_REPO_URL:-https://github.com/mieitza/agentskillz}"
BRANCH="${VAULT_BRANCH:-main}"
VAULT_HOST="${VAULT_HOST:-100.83.164.37}"
VAULT_PORT="${VAULT_PORT:-8088}"
VAULT_ROOT_SERVER="${VAULT_ROOT:-/home/$USER/vault}"
ROLE=""
UPDATE=0

# ---------- args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server)      ROLE="server"; shift ;;
    --client)      ROLE="client"; shift ;;
    --update)      UPDATE=1; shift ;;
    --vault-host)  VAULT_HOST="$2"; shift 2 ;;
    --vault-port)  VAULT_PORT="$2"; shift 2 ;;
    --vault-root)  VAULT_ROOT_SERVER="$2"; shift 2 ;;
    --branch)      BRANCH="$2"; shift 2 ;;
    --repo)        REPO_URL="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "unknown flag: $1" >&2
      exit 2
      ;;
  esac
done

# ---------- pretty ----------
c_blue()  { printf '\033[34m%s\033[0m\n' "$*"; }
c_green() { printf '\033[32m%s\033[0m\n' "$*"; }
c_yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
c_red()   { printf '\033[31m%s\033[0m\n' "$*"; }

step() { c_blue "==> $*"; }
ok()   { c_green "    ok: $*"; }
warn() { c_yellow "  warn: $*"; }
die()  { c_red "  err: $*"; exit 1; }

# ---------- role detection ----------
detect_role() {
  if [[ -n "$ROLE" ]]; then return; fi
  case "$(uname -s)" in
    Linux)
      # If systemd is around and we can write under /etc/systemd, default to server.
      # Otherwise client.
      if command -v systemctl >/dev/null 2>&1 && [[ -w /etc/systemd/system || $EUID -eq 0 ]]; then
        ROLE="server"
      else
        ROLE="client"
      fi
      ;;
    Darwin)
      ROLE="client"
      ;;
    *)
      ROLE="client"
      ;;
  esac
}

# ---------- fetch sources ----------
WORK_DIR=""
fetch_sources() {
  step "fetching agentskillz ($BRANCH) into a temp dir"
  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORK_DIR/agentskillz" >/dev/null 2>&1 \
      || die "git clone failed from $REPO_URL"
  else
    # Fallback: tarball download.
    local tarball="$REPO_URL/archive/refs/heads/$BRANCH.tar.gz"
    curl -fsSL "$tarball" | tar -xz -C "$WORK_DIR"
    mv "$WORK_DIR"/agentskillz-* "$WORK_DIR/agentskillz"
  fi
  ok "sources at $WORK_DIR/agentskillz"
}

SRC=""
set_src() { SRC="$WORK_DIR/agentskillz/vault"; }

# ---------- server install ----------
install_server() {
  step "installing server (vault MCP + autocommit watcher)"

  command -v python3 >/dev/null 2>&1 || die "python3 required on server"
  command -v git >/dev/null 2>&1 || die "git required on server"

  local install_dir="/opt/vault-mcp"
  local venv="$install_dir/venv"

  sudo mkdir -p "$install_dir"
  sudo cp "$SRC/server/vault_mcp.py" "$install_dir/"
  sudo cp "$SRC/server/vault_watcher.py" "$install_dir/"
  sudo cp "$SRC/server/requirements.txt" "$install_dir/"

  if [[ ! -d "$venv" || $UPDATE -eq 1 ]]; then
    step "creating venv at $venv"
    sudo python3 -m venv "$venv"
  fi
  sudo "$venv/bin/pip" install --quiet --upgrade pip
  sudo "$venv/bin/pip" install --quiet -r "$install_dir/requirements.txt"
  ok "python deps installed"

  # Vault dir + git init if needed.
  if [[ ! -d "$VAULT_ROOT_SERVER/.git" ]]; then
    step "initializing vault at $VAULT_ROOT_SERVER"
    mkdir -p "$VAULT_ROOT_SERVER"
    (cd "$VAULT_ROOT_SERVER" && git init -q && git commit -q --allow-empty -m "init: empty vault")
    mkdir -p "$VAULT_ROOT_SERVER/working" "$VAULT_ROOT_SERVER/reference" "$VAULT_ROOT_SERVER/people"
    cat > "$VAULT_ROOT_SERVER/README.md" <<'README'
# vault
Shared agent memory. See https://github.com/mieitza/agentskillz/tree/main/vault
README
    (cd "$VAULT_ROOT_SERVER" && git add -A && git commit -q -m "init: scaffold layout")
    ok "vault initialized"
  else
    ok "vault already exists at $VAULT_ROOT_SERVER"
  fi

  # systemd units, with the actual paths baked in.
  step "writing systemd units"
  sudo sed -e "s|/home/misha/vault|$VAULT_ROOT_SERVER|g" \
           -e "s|^User=misha|User=$USER|" \
           -e "s|^Group=misha|Group=$USER|" \
           "$SRC/server/vault-mcp.service" \
    | sudo tee /etc/systemd/system/vault-mcp.service >/dev/null
  sudo sed -e "s|/home/misha/vault|$VAULT_ROOT_SERVER|g" \
           -e "s|^User=misha|User=$USER|" \
           -e "s|^Group=misha|Group=$USER|" \
           "$SRC/server/vault-watcher.service" \
    | sudo tee /etc/systemd/system/vault-watcher.service >/dev/null

  sudo systemctl daemon-reload
  sudo systemctl enable --now vault-mcp.service vault-watcher.service
  ok "vault-mcp and vault-watcher running"

  echo ""
  c_green "Server install complete."
  echo "  MCP endpoint: http://$(hostname -I | awk '{print $1}'):$VAULT_PORT/servers/vault/sse"
  echo "  Vault root:   $VAULT_ROOT_SERVER"
  echo "  Status:       systemctl status vault-mcp vault-watcher"
}

# ---------- client install ----------
install_claude_code() {
  step "installing Claude Code plugin (~/.claude/plugins/)"

  local mkt="$HOME/.claude/plugins/marketplaces/vault-memory-local"
  local cache="$HOME/.claude/plugins/cache/vault-memory-local/vault-memory/0.2.0"
  mkdir -p "$mkt/.claude-plugin" "$cache"

  cp -R "$SRC/plugin/." "$cache/"
  # Rewrite .mcp.json with this machine's chosen vault host/port.
  python3 - "$cache/.mcp.json" "$VAULT_HOST" "$VAULT_PORT" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
host = sys.argv[2]; port = sys.argv[3]
cfg = json.loads(p.read_text())
cfg["mcpServers"]["vault"]["args"] = [
  "-y", "mcp-remote@latest",
  f"http://{host}:{port}/servers/vault/sse",
  "--allow-http", "--transport", "sse-only",
  "--static-oauth-client-metadata", "{}"
]
p.write_text(json.dumps(cfg, indent=2) + "\n")
PY

  cat > "$mkt/.claude-plugin/marketplace.json" <<JSON
{
  "name": "vault-memory-local",
  "owner": { "name": "Mihai Nitulescu", "email": "mihai.nitulescu@gmail.com" },
  "plugins": [
    {
      "name": "vault-memory",
      "version": "0.2.0",
      "source": "./",
      "description": "Shared agent memory across Claude Desktop, Claude Code, and OpenCode."
    }
  ]
}
JSON
  ok "plugin installed at $cache"

  step "installing Claude Code hooks (~/.claude/hooks/vault/)"
  mkdir -p "$HOME/.claude/hooks/vault"
  install -m 755 "$SRC/hooks/session-start.sh" "$HOME/.claude/hooks/vault/session-start.sh"
  install -m 755 "$SRC/hooks/stop.sh"          "$HOME/.claude/hooks/vault/stop.sh"

  # Patch settings.json idempotently.
  local settings="$HOME/.claude/settings.json"
  python3 - "$settings" "$HOME/.claude/hooks/vault" <<'PY'
import json, sys, pathlib
settings_path = pathlib.Path(sys.argv[1])
hooks_dir = sys.argv[2]
settings = {}
if settings_path.exists():
    try:
        settings = json.loads(settings_path.read_text())
    except json.JSONDecodeError:
        # don't clobber a broken file silently
        raise SystemExit(f"settings.json at {settings_path} is not valid JSON; fix it and re-run --update")
hooks = settings.setdefault("hooks", {})

def ensure(event, cmd):
    arr = hooks.setdefault(event, [])
    if not any(isinstance(e, dict) and e.get("command") == cmd for e in arr):
        arr.append({"command": cmd})

ensure("SessionStart", f"{hooks_dir}/session-start.sh")
ensure("Stop",         f"{hooks_dir}/stop.sh")

settings_path.parent.mkdir(parents=True, exist_ok=True)
settings_path.write_text(json.dumps(settings, indent=2) + "\n")
PY
  ok "hooks registered in $HOME/.claude/settings.json"
}

install_cowork() {
  step "building .plugin archive for Claude Desktop / Cowork"

  local out="$HOME/Downloads/vault-memory.plugin"
  ( cd "$SRC/plugin" && zip -qr "$out" . -x '*.DS_Store' )
  # Rewrite the mcp.json inside the zip to use the chosen host/port.
  python3 - "$out" "$VAULT_HOST" "$VAULT_PORT" <<'PY'
import json, sys, zipfile, io, pathlib
out = pathlib.Path(sys.argv[1])
host = sys.argv[2]; port = sys.argv[3]
data = out.read_bytes()
with zipfile.ZipFile(io.BytesIO(data)) as zin:
    members = {n: zin.read(n) for n in zin.namelist()}
cfg = json.loads(members[".mcp.json"])
cfg["mcpServers"]["vault"]["args"] = [
  "-y", "mcp-remote@latest",
  f"http://{host}:{port}/servers/vault/sse",
  "--allow-http", "--transport", "sse-only",
  "--static-oauth-client-metadata", "{}"
]
members[".mcp.json"] = (json.dumps(cfg, indent=2) + "\n").encode()
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zout:
    for n, b in members.items():
        zout.writestr(n, b)
PY

  ok "wrote $out"
  warn "Cowork doesn't auto-install local .plugin files."
  warn "Import it manually: open Claude Desktop -> Settings -> Plugins -> Import .plugin"
  warn "Then quit (Cmd+Q) and reopen."
}

install_opencode() {
  local oc_dir="$HOME/.config/opencode"
  if [[ ! -d "$oc_dir" ]]; then
    warn "OpenCode config dir not found at $oc_dir — skipping. Install OpenCode first."
    return
  fi
  step "installing OpenCode skill + MCP config"

  mkdir -p "$oc_dir/skills/vault-memory"
  cp "$SRC/skill/SKILL.md" "$oc_dir/skills/vault-memory/SKILL.md"

  local mcp_file="$oc_dir/mcp.json"
  python3 - "$mcp_file" "$VAULT_HOST" "$VAULT_PORT" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
host = sys.argv[2]; port = sys.argv[3]
cfg = {}
if p.exists():
    try:
        cfg = json.loads(p.read_text())
    except json.JSONDecodeError:
        raise SystemExit(f"{p} is not valid JSON; fix and re-run")
servers = cfg.setdefault("mcpServers", {})
servers["vault"] = {
  "command": "npx",
  "args": [
    "-y", "mcp-remote@latest",
    f"http://{host}:{port}/servers/vault/sse",
    "--allow-http", "--transport", "sse-only",
    "--static-oauth-client-metadata", "{}"
  ]
}
p.write_text(json.dumps(cfg, indent=2) + "\n")
PY
  ok "OpenCode wired up"
}

install_client() {
  step "client install — detecting surfaces"
  command -v npx >/dev/null 2>&1 || warn "npx not on PATH; mcp-remote will fail until you install Node.js"
  command -v python3 >/dev/null 2>&1 || die "python3 required for config patching"
  command -v jq >/dev/null 2>&1 || warn "jq not on PATH; hooks need it. brew install jq / apt install jq"

  # Claude Code: detect by presence of ~/.claude/plugins/
  if [[ -d "$HOME/.claude/plugins" || $UPDATE -eq 1 ]]; then
    install_claude_code
  else
    warn "no ~/.claude/plugins — skipping Claude Code wiring (re-run after installing it)"
  fi

  # Claude Desktop / Cowork: detect by presence of the app on macOS
  if [[ "$(uname -s)" == "Darwin" && -d "/Applications/Claude.app" ]]; then
    install_cowork
  else
    warn "Claude Desktop not detected — skipping .plugin build"
  fi

  # OpenCode: detect by config dir
  install_opencode

  echo ""
  c_green "Client install complete."
  echo "  Verify Claude Code: ls ~/.claude/plugins/cache/vault-memory-local/vault-memory/0.2.0"
  echo "  Verify hooks:       jq .hooks ~/.claude/settings.json"
  echo "  Vault MCP target:   http://$VAULT_HOST:$VAULT_PORT/servers/vault/sse"
}

# ---------- main ----------
main() {
  detect_role
  fetch_sources
  set_src
  case "$ROLE" in
    server) install_server ;;
    client) install_client ;;
    *) die "unknown role: $ROLE" ;;
  esac
}

main "$@"
