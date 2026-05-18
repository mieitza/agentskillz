# Landing this change in the agentskillz repo

This whole `vault/` tree was generated as one unit and is meant to replace anything currently at `vault/` in the GitHub repo. Don't merge file-by-file.

## One-shot

```bash
git clone git@github.com:mieitza/agentskillz.git
cd agentskillz
git checkout -b vault-rewrite

# Wipe the current vault/ and drop the new one in.
rm -rf vault
cp -R /path/to/outputs/agentskillz/vault .

# Sanity check: every file should be present.
find vault -type f | sort

# Make the scripts executable.
chmod +x vault/install/install.sh vault/install/uninstall.sh \
         vault/hooks/session-start.sh vault/hooks/stop.sh

git add vault/
git commit -m "vault: full rewrite — single installer, server services, schema-correct hooks"
git push -u origin vault-rewrite
```

Open a PR, merge to main. The installer URL in the README points at `main`, so the next `curl ... | bash` on any machine pulls the new version.

## What changed vs. the prior plugin-only version

- Server-side MCP and autocommit watcher are now first-class (`server/`), with systemd units.
- One installer (`install/install.sh`) handles server + client + per-surface wiring.
- Hooks use schema-correct top-level `systemMessage` (previous version emitted invalid `hookSpecificOutput.hookEventName="Stop"`).
- MCP server has explicit `commit_and_push` tool; watcher is now a safety net, not the primary commit path.
- Plugin manifest bumped to 0.2.0.
- README and docs describe the architecture as a single integrated system.

## Rollback

```bash
git revert <merge-commit>
git push
```

Then re-run the installer with `--update` on every machine.
