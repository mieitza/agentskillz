#!/usr/bin/env python3
"""
Vault git autocommit watcher.

Watches VAULT_ROOT for changes and commits + pushes after DEBOUNCE_SECONDS
of quiet. Acts as a safety net alongside the explicit `commit_and_push`
MCP tool: even if an agent forgets to commit, work isn't lost.

Strategy: polling-based (no inotify/fswatch dependency, runs everywhere).
Compares `git status --porcelain` snapshots once per POLL_INTERVAL. When
changes appear, starts a debounce timer. If no further changes within
DEBOUNCE_SECONDS, commits with an auto-generated message.

Config (env):
    VAULT_ROOT        path to vault git repo (default /home/misha/vault)
    POLL_INTERVAL     seconds between status checks (default 5)
    DEBOUNCE_SECONDS  quiet period before commit (default 30)
    AUTO_PUSH         "1" to git push after commit (default "1")
"""
from __future__ import annotations

import logging
import os
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

VAULT_ROOT = Path(os.environ.get("VAULT_ROOT", "/home/misha/vault")).resolve()
POLL_INTERVAL = float(os.environ.get("POLL_INTERVAL", "5"))
DEBOUNCE_SECONDS = float(os.environ.get("DEBOUNCE_SECONDS", "30"))
AUTO_PUSH = os.environ.get("AUTO_PUSH", "1") == "1"

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s vault-watcher %(levelname)s %(message)s",
)
log = logging.getLogger("vault-watcher")


def git_status() -> str:
    """Return `git status --porcelain` output (stable across versions)."""
    proc = subprocess.run(
        ["git", "-C", str(VAULT_ROOT), "status", "--porcelain"],
        capture_output=True, text=True, check=False,
    )
    if proc.returncode != 0:
        log.error("git status failed: %s", proc.stderr.strip())
        return ""
    return proc.stdout


def auto_commit() -> bool:
    """Run add/commit/push. Return True if a commit was made."""
    status_before = git_status()
    if not status_before.strip():
        return False

    # Count changed files for a slightly informative commit message.
    n_files = len([line for line in status_before.splitlines() if line.strip()])
    ts = datetime.now().strftime("%Y-%m-%d %H:%M")
    msg = f"vault: auto {ts} ({n_files} file{'s' if n_files != 1 else ''})"

    try:
        subprocess.run(["git", "-C", str(VAULT_ROOT), "add", "-A"], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(VAULT_ROOT), "commit", "-m", msg], check=True, capture_output=True)
        log.info("committed: %s", msg)
    except subprocess.CalledProcessError as e:
        log.error("commit failed: %s", (e.stderr or b"").decode("utf-8", "replace").strip())
        return False

    if AUTO_PUSH:
        try:
            subprocess.run(["git", "-C", str(VAULT_ROOT), "push"], check=True, capture_output=True)
            log.info("pushed")
        except subprocess.CalledProcessError as e:
            log.warning("push failed: %s", (e.stderr or b"").decode("utf-8", "replace").strip())
            # Don't return False — the commit still happened.
    return True


def run() -> None:
    log.info("watching %s (poll=%ss, debounce=%ss, push=%s)",
             VAULT_ROOT, POLL_INTERVAL, DEBOUNCE_SECONDS, AUTO_PUSH)

    last_status = git_status()
    quiet_since: float | None = None

    while True:
        time.sleep(POLL_INTERVAL)
        current = git_status()

        if current != last_status:
            # Something changed since last poll: reset the debounce timer.
            quiet_since = time.monotonic()
            last_status = current
            continue

        if current.strip() and quiet_since is not None:
            # No new changes this tick, but there are still pending changes.
            quiet_for = time.monotonic() - quiet_since
            if quiet_for >= DEBOUNCE_SECONDS:
                if auto_commit():
                    last_status = git_status()  # likely empty now
                quiet_since = None


def _shutdown(signum, frame):  # noqa: ARG001
    log.info("received signal %s, exiting", signum)
    sys.exit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)
    run()
