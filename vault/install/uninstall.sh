#!/usr/bin/env bash
# Clean uninstall for vault-memory client install. Server uninstall is a
# manual systemctl disable + rm -rf /opt/vault-mcp — kept manual on purpose so
# you don't nuke a vault by accident.

set -euo pipefail

step() { printf '\033[34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m    ok: %s\033[0m\n' "$*"; }

step "removing Claude Code plugin entries"
rm -rf "$HOME/.claude/plugins/marketplaces/vault-memory-local"
rm -rf "$HOME/.claude/plugins/cache/vault-memory-local"
ok "plugin removed"

step "removing hooks"
rm -rf "$HOME/.claude/hooks/vault"

if [[ -f "$HOME/.claude/settings.json" ]]; then
  python3 - "$HOME/.claude/settings.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
data = json.loads(p.read_text())
hooks = data.get("hooks", {})
for ev in ("SessionStart", "Stop"):
    if ev in hooks:
        hooks[ev] = [e for e in hooks[ev]
                     if not (isinstance(e, dict)
                             and isinstance(e.get("command",""), str)
                             and "/hooks/vault/" in e["command"])]
        if not hooks[ev]:
            del hooks[ev]
p.write_text(json.dumps(data, indent=2) + "\n")
PY
fi
ok "hooks deregistered"

step "removing OpenCode skill (if installed)"
rm -rf "$HOME/.config/opencode/skills/vault-memory" 2>/dev/null || true

if [[ -f "$HOME/.config/opencode/mcp.json" ]]; then
  python3 - "$HOME/.config/opencode/mcp.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
data = json.loads(p.read_text())
data.get("mcpServers", {}).pop("vault", None)
p.write_text(json.dumps(data, indent=2) + "\n")
PY
fi
ok "OpenCode wiring removed"

echo ""
printf '\033[32mUninstall complete. Quit and reopen Claude Desktop / Code for changes to apply.\033[0m\n'
