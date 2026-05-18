#!/usr/bin/env bash
# install.sh — one-line installer for the vault-memory skill across all agents.
#
# Usage (one-liner):
#   curl -fsSL https://raw.githubusercontent.com/mieitza/agentskillz/main/vault/install/install.sh | bash
#
# Optional env vars:
#   VAULT_URL    — full SSE endpoint (default: http://100.83.164.37:8088/sse)
#   REPO_RAW     — raw github base for fetching skill/hooks (default: this repo on main)
#   VAULT_DRY_RUN=1 — print what would happen, don't touch anything
#   VAULT_FORCE=1  — overwrite existing skill/hook files without asking
#
# What it does:
#   1. Auto-detects which agents are installed: claude (CC), Claude Desktop,
#      opencode, codex, cursor.
#   2. For each one found, installs the vault-memory skill, registers the
#      vault MCP server, and (where supported) installs session hooks.
#   3. Idempotent — re-running upgrades the skill and re-syncs config without
#      duplicating MCP entries.
#
# Safe on macOS and Linux. No sudo required.

set -euo pipefail

# ---------- config ----------
VAULT_URL="${VAULT_URL:-http://100.83.164.37:8088/sse}"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/mieitza/agentskillz/main/vault}"
VAULT_DRY_RUN="${VAULT_DRY_RUN:-0}"
VAULT_FORCE="${VAULT_FORCE:-0}"

# ---------- helpers ----------
c_cyan="\033[1;36m"; c_yel="\033[1;33m"; c_red="\033[1;31m"; c_grn="\033[1;32m"; c_dim="\033[2m"; c_off="\033[0m"
log()  { printf "${c_cyan}[vault]${c_off} %s\n" "$*"; }
ok()   { printf "${c_grn}[vault]${c_off} %s\n" "$*"; }
warn() { printf "${c_yel}[vault]${c_off} %s\n" "$*" >&2; }
die()  { printf "${c_red}[vault]${c_off} %s\n" "$*" >&2; exit 1; }
run()  {
    if [[ "$VAULT_DRY_RUN" == "1" ]]; then
        printf "${c_dim}+ %s${c_off}\n" "$*"
    else
        eval "$@"
    fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# Cross-platform sed -i shim (BSD vs GNU)
sed_inplace() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# ---------- preflight ----------
OS="$(uname)"
case "$OS" in
    Darwin|Linux) ;;
    *) die "Unsupported OS: $OS (need macOS or Linux)";;
esac

have curl || die "curl is required"

# We need either python3 or jq to merge JSON configs safely
if have python3; then
    JSON_TOOL="python3"
elif have jq; then
    JSON_TOOL="jq"
else
    die "Need python3 or jq for safe JSON merging (install one and re-run)"
fi

log "OS: $OS — JSON tool: $JSON_TOOL — vault: $VAULT_URL"
[[ "$VAULT_DRY_RUN" == "1" ]] && warn "DRY RUN — no changes will be made"

# ---------- download skill & hooks to a temp dir ----------
TMPDIR="$(mktemp -d -t vault-install.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

fetch() {
    # $1 = relative path under $REPO_RAW, $2 = destination
    local rel="$1" dst="$2"
    log "fetching $rel"
    if [[ "$VAULT_DRY_RUN" == "1" ]]; then
        printf "${c_dim}+ curl -fsSL %s -o %s${c_off}\n" "$REPO_RAW/$rel" "$dst"
        # In dry-run, drop a placeholder so the rest of the flow can continue
        mkdir -p "$(dirname "$dst")"
        printf "DRY RUN PLACEHOLDER FOR %s\n" "$rel" > "$dst"
    else
        mkdir -p "$(dirname "$dst")"
        curl -fsSL "$REPO_RAW/$rel" -o "$dst"
    fi
}

fetch "skills/vault-memory/SKILL.md"                "$TMPDIR/skill/SKILL.md"
fetch "client/claude-code/vault-session-start.sh"   "$TMPDIR/hooks/vault-session-start.sh"
fetch "client/claude-code/vault-session-end.sh"     "$TMPDIR/hooks/vault-session-end.sh"
chmod +x "$TMPDIR/hooks/"*.sh 2>/dev/null || true

# ---------- JSON merge helpers ----------
# Merge an MCP server entry into a JSON config file at a given dotted key path.
# Args: $1 = target file, $2 = top-level key (e.g. "mcpServers" or "mcp"),
#       $3 = server name, $4 = JSON value (string)
merge_mcp_entry() {
    local file="$1" parent="$2" name="$3" value="$4"

    if [[ "$VAULT_DRY_RUN" == "1" ]]; then
        printf "${c_dim}+ merge %s.%s into %s${c_off}\n" "$parent" "$name" "$file"
        return 0
    fi

    mkdir -p "$(dirname "$file")"
    [[ -f "$file" ]] || echo "{}" > "$file"

    if [[ "$JSON_TOOL" == "python3" ]]; then
        python3 - "$file" "$parent" "$name" "$value" <<'PY'
import json, sys, pathlib
path, parent, name, value = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
p = pathlib.Path(path)
try:
    data = json.loads(p.read_text() or "{}")
except json.JSONDecodeError:
    print(f"[vault] WARNING: {path} is not valid JSON, backing up and resetting", file=sys.stderr)
    p.rename(str(p) + ".bak")
    data = {}
if not isinstance(data, dict):
    data = {}
data.setdefault(parent, {})
data[parent][name] = json.loads(value)
p.write_text(json.dumps(data, indent=2) + "\n")
PY
    else
        # jq path
        local tmp; tmp="$(mktemp)"
        jq --arg parent "$parent" --arg name "$name" --argjson value "$value" \
           '.[$parent] = (.[$parent] // {}) | .[$parent][$name] = $value' \
           "$file" > "$tmp" && mv "$tmp" "$file"
    fi
}

# ---------- 1. Claude Code ----------
install_claude_code() {
    have claude || { warn "Claude Code (claude CLI) not found — skipping"; return 0; }
    log "→ Installing for Claude Code"

    # 1a. Register the MCP server (idempotent — claude mcp add upserts by name)
    if [[ "$VAULT_DRY_RUN" == "1" ]]; then
        printf "${c_dim}+ claude mcp add --transport sse vault %s --scope user${c_off}\n" "$VAULT_URL"
    else
        # `claude mcp add` errors if it already exists; remove first then re-add
        claude mcp remove vault --scope user >/dev/null 2>&1 || true
        claude mcp add --transport sse vault "$VAULT_URL" --scope user >/dev/null
    fi

    # 1b. Install the skill
    local skill_dir="$HOME/.claude/skills/vault-memory"
    run "mkdir -p '$skill_dir'"
    run "cp '$TMPDIR/skill/SKILL.md' '$skill_dir/SKILL.md'"

    # 1c. Install hooks
    local hooks_dir="$HOME/.claude/hooks"
    run "mkdir -p '$hooks_dir'"
    run "cp '$TMPDIR/hooks/vault-session-start.sh' '$hooks_dir/'"
    run "cp '$TMPDIR/hooks/vault-session-end.sh' '$hooks_dir/'"
    run "chmod +x '$hooks_dir/vault-session-start.sh' '$hooks_dir/vault-session-end.sh'"

    # 1d. Wire hooks into ~/.claude/settings.json
    local settings="$HOME/.claude/settings.json"
    if [[ "$VAULT_DRY_RUN" != "1" ]]; then
        mkdir -p "$(dirname "$settings")"
        [[ -f "$settings" ]] || echo "{}" > "$settings"
        python3 - "$settings" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
try:
    data = json.loads(p.read_text() or "{}")
except json.JSONDecodeError:
    p.rename(str(p) + ".bak")
    data = {}
if not isinstance(data, dict):
    data = {}
hooks = data.setdefault("hooks", {})

def ensure(event, cmd):
    arr = hooks.setdefault(event, [])
    # Already present?
    for group in arr:
        for h in group.get("hooks", []):
            if h.get("command") == cmd:
                return
    arr.append({"hooks": [{"type": "command", "command": cmd}]})

ensure("SessionStart", "~/.claude/hooks/vault-session-start.sh")
ensure("Stop",         "~/.claude/hooks/vault-session-end.sh")
p.write_text(json.dumps(data, indent=2) + "\n")
PY
    else
        printf "${c_dim}+ merge SessionStart + Stop hooks into %s${c_off}\n" "$settings"
    fi

    ok "Claude Code: skill + hooks installed, MCP registered"
}

# ---------- 2. Claude Desktop ----------
install_claude_desktop() {
    local cfg
    case "$OS" in
        Darwin) cfg="$HOME/Library/Application Support/Claude/claude_desktop_config.json";;
        Linux)  cfg="$HOME/.config/Claude/claude_desktop_config.json";;
    esac

    # Detection: presence of the Claude Desktop app dir
    case "$OS" in
        Darwin)
            if [[ ! -d "/Applications/Claude.app" && ! -d "$HOME/Applications/Claude.app" ]]; then
                warn "Claude Desktop not found in /Applications — skipping"
                return 0
            fi
            ;;
        Linux)
            # Heuristic: config dir exists OR the binary is on PATH
            if [[ ! -d "$HOME/.config/Claude" ]] && ! have claude-desktop; then
                warn "Claude Desktop not detected on Linux — skipping"
                return 0
            fi
            ;;
    esac

    log "→ Installing for Claude Desktop"

    # 2a. MCP server config (so the `vault` tools are available in Claude Desktop)
    local entry
    entry=$(cat <<JSON
{
  "command": "npx",
  "args": ["-y", "mcp-remote@latest", "$VAULT_URL"]
}
JSON
)
    merge_mcp_entry "$cfg" "mcpServers" "vault" "$entry"

    # 2b. Cowork plugin (so the SKILL + slash commands are available)
    # Claude Desktop / Cowork doesn't read a skills/ directory — skills come
    # via plugins. We download the .plugin file to ~/Downloads and tell the
    # user to open it; Cowork handles the actual install via its plugin UI.
    local plugin_dst="$HOME/Downloads/vault-memory.plugin"
    if [[ "$VAULT_DRY_RUN" == "1" ]]; then
        printf "${c_dim}+ curl -fsSL %s -o %s${c_off}\n" "$REPO_RAW/install/vault-memory.plugin" "$plugin_dst"
        printf "${c_dim}+ open %s${c_off}\n" "$plugin_dst"
    else
        if curl -fsSL "$REPO_RAW/install/vault-memory.plugin" -o "$plugin_dst" 2>/dev/null; then
            ok "Plugin downloaded to $plugin_dst"
            log "  Opening it now — accept the install prompt in Cowork to enable the skill + /vault-* commands"
            if [[ "$OS" == "Darwin" ]] && have open; then
                # `.plugin` isn't registered as a default extension, so hand
                # it to Claude.app explicitly (Cowork picks it up from there).
                open -a "Claude" "$plugin_dst" 2>/dev/null \
                    || open "$plugin_dst" 2>/dev/null \
                    || true
            fi
        else
            warn "Couldn't download vault-memory.plugin — fetch it manually:"
            warn "  curl -fsSLo ~/Downloads/vault-memory.plugin $REPO_RAW/install/vault-memory.plugin"
            warn "  open ~/Downloads/vault-memory.plugin"
        fi
    fi

    ok "Claude Desktop: MCP configured + plugin queued (restart with Cmd+Q after accepting)"
}

# ---------- 3. OpenCode ----------
install_opencode() {
    have opencode || { warn "opencode CLI not found — skipping"; return 0; }
    log "→ Installing for OpenCode"

    # Skill
    local skill_dir="$HOME/.config/opencode/skills/vault-memory"
    run "mkdir -p '$skill_dir'"
    run "cp '$TMPDIR/skill/SKILL.md' '$skill_dir/SKILL.md'"

    # opencode.json — top-level "mcp" key
    local cfg="$HOME/.config/opencode/opencode.json"
    local entry
    entry=$(cat <<JSON
{
  "type": "sse",
  "url": "$VAULT_URL"
}
JSON
)
    merge_mcp_entry "$cfg" "mcp" "vault" "$entry"
    ok "OpenCode: skill + MCP config installed"
}

# ---------- 4. Codex CLI ----------
install_codex() {
    have codex || { warn "codex CLI not found — skipping"; return 0; }
    log "→ Installing for Codex CLI"

    # Codex uses ~/.codex/config.toml for MCP entries.
    # We use python to do a TOML merge safely (tomllib is read-only in 3.11;
    # for write we fall back to a simple append-if-missing because TOML lacks
    # a stdlib writer).
    local cfg="$HOME/.codex/config.toml"
    if [[ "$VAULT_DRY_RUN" == "1" ]]; then
        printf "${c_dim}+ ensure [mcp_servers.vault] block in %s${c_off}\n" "$cfg"
    else
        mkdir -p "$(dirname "$cfg")"
        [[ -f "$cfg" ]] || touch "$cfg"
        if ! grep -q '^\[mcp_servers\.vault\]' "$cfg"; then
            cat >> "$cfg" <<EOF

[mcp_servers.vault]
command = "npx"
args = ["-y", "mcp-remote@latest", "$VAULT_URL"]
EOF
        else
            warn "Codex: [mcp_servers.vault] already present, leaving as-is (set VAULT_FORCE=1 to overwrite)"
        fi
    fi
    ok "Codex CLI: MCP config installed"
}

# ---------- 5. Cursor ----------
install_cursor() {
    # Cursor stores MCP in ~/.cursor/mcp.json
    case "$OS" in
        Darwin)
            local app="/Applications/Cursor.app"
            [[ -d "$app" || -d "$HOME/Applications/Cursor.app" || -d "$HOME/.cursor" ]] || {
                warn "Cursor not found — skipping"; return 0;
            }
            ;;
        Linux)
            [[ -d "$HOME/.cursor" ]] || have cursor || {
                warn "Cursor not found — skipping"; return 0;
            }
            ;;
    esac

    log "→ Installing for Cursor"
    local cfg="$HOME/.cursor/mcp.json"
    local entry
    entry=$(cat <<JSON
{
  "command": "npx",
  "args": ["-y", "mcp-remote@latest", "$VAULT_URL"]
}
JSON
)
    merge_mcp_entry "$cfg" "mcpServers" "vault" "$entry"
    ok "Cursor: MCP config installed"
}

# ---------- 6. Continue.dev (bonus, MCP-aware) ----------
install_continue() {
    [[ -d "$HOME/.continue" ]] || { warn "Continue.dev not found — skipping"; return 0; }
    log "→ Installing for Continue.dev"
    local cfg="$HOME/.continue/config.json"
    local entry
    entry=$(cat <<JSON
{
  "command": "npx",
  "args": ["-y", "mcp-remote@latest", "$VAULT_URL"]
}
JSON
)
    merge_mcp_entry "$cfg" "mcpServers" "vault" "$entry"
    ok "Continue.dev: MCP config installed"
}

# ---------- run all ----------
INSTALLED=0
for fn in install_claude_code install_claude_desktop install_opencode install_codex install_cursor install_continue; do
    if $fn; then
        INSTALLED=$((INSTALLED + 1))
    fi
done

echo
if [[ $INSTALLED -eq 0 ]]; then
    warn "No agents detected. Install one of: claude (Claude Code), Claude Desktop, opencode, codex, cursor."
    exit 1
fi

ok "Done. Vault endpoint: $VAULT_URL"
echo
echo "Next steps:"
echo "  • Restart any running agent so it picks up the new MCP config."
echo "  • Test from a chat: \"list the files in the working directory of the vault\""
echo "  • If a request times out, verify reachability:  curl -v $VAULT_URL"
