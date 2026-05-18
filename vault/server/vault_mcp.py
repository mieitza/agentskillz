#!/usr/bin/env python3
"""
Vault MCP server.

A single source-of-truth filesystem MCP that exposes a git-backed markdown
vault to any agent (Claude Code, Claude Desktop / Cowork, OpenCode). All
paths in tool arguments are RELATIVE to the vault root; the server refuses
any traversal that would escape it.

Tools:
  - list_directory(path)
  - read_file(path)
  - write_file(path, content)        # creates parent dirs as needed
  - edit_file(path, old, new)        # exact-string replace, must match once
  - search_files(query, glob)        # ripgrep over the vault
  - commit_and_push(message)         # explicit checkpoint by an agent

Transport: SSE on /servers/vault/sse (mounted by mcp-proxy or run direct).
Config:    env VAULT_ROOT (default /home/misha/vault), VAULT_BIND (default 0.0.0.0:8088).
"""
from __future__ import annotations

import os
import re
import shlex
import subprocess
from pathlib import Path
from typing import Annotated

from mcp.server.fastmcp import FastMCP
from pydantic import Field

VAULT_ROOT = Path(os.environ.get("VAULT_ROOT", "/home/misha/vault")).resolve()
VAULT_ROOT.mkdir(parents=True, exist_ok=True)

mcp = FastMCP("vault")


# ---------- path safety ---------------------------------------------------

class PathEscape(ValueError):
    """Raised when a requested path would escape the vault root."""


def _resolve(rel: str) -> Path:
    """Resolve a vault-relative path, refusing anything that escapes VAULT_ROOT.

    Rules:
    - empty path or '.' → vault root
    - absolute-looking paths (start with '/') → rejected outright; agents must use
      relative paths
    - paths that traverse out via '..' → rejected via the relative_to() check
    """
    if not rel or rel.strip() in ("", "."):
        return VAULT_ROOT
    if rel.startswith("/"):
        raise PathEscape(
            f"Path {rel!r} is absolute. All paths must be relative to the vault root."
        )
    candidate = (VAULT_ROOT / rel).resolve()
    try:
        candidate.relative_to(VAULT_ROOT)
    except ValueError as e:
        raise PathEscape(
            f"Path {rel!r} resolves outside the vault root. All paths must be relative to the vault."
        ) from e
    return candidate


# ---------- filesystem tools ----------------------------------------------

@mcp.tool()
def list_directory(
    path: Annotated[str, Field(description="Vault-relative path. Use '' or '.' for root.")] = "",
) -> list[dict]:
    """List entries in a directory, with type and size."""
    target = _resolve(path)
    if not target.exists():
        raise FileNotFoundError(f"{path!r} does not exist in the vault.")
    if not target.is_dir():
        raise NotADirectoryError(f"{path!r} is a file, not a directory.")
    entries = []
    for child in sorted(target.iterdir()):
        if child.name.startswith(".git"):
            continue  # don't leak .git internals to agents
        stat = child.stat()
        entries.append({
            "name": child.name,
            "type": "dir" if child.is_dir() else "file",
            "size": stat.st_size,
            "path": str(child.relative_to(VAULT_ROOT)),
        })
    return entries


@mcp.tool()
def read_file(
    path: Annotated[str, Field(description="Vault-relative path to a file.")],
) -> str:
    """Return the full text content of a file."""
    target = _resolve(path)
    if not target.exists():
        raise FileNotFoundError(f"{path!r} does not exist.")
    if not target.is_file():
        raise IsADirectoryError(f"{path!r} is a directory.")
    return target.read_text(encoding="utf-8")


@mcp.tool()
def write_file(
    path: Annotated[str, Field(description="Vault-relative path. Parent dirs are created as needed.")],
    content: Annotated[str, Field(description="Full file contents (UTF-8).")],
) -> dict:
    """Write a file, overwriting if it exists. Returns size and path."""
    target = _resolve(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    return {"path": str(target.relative_to(VAULT_ROOT)), "size": len(content.encode("utf-8"))}


@mcp.tool()
def edit_file(
    path: Annotated[str, Field(description="Vault-relative path to an existing file.")],
    old: Annotated[str, Field(description="Exact text to find. Must occur exactly once.")],
    new: Annotated[str, Field(description="Replacement text.")],
) -> dict:
    """Exact-string replace in a file. Errors if old doesn't appear exactly once."""
    target = _resolve(path)
    if not target.exists():
        raise FileNotFoundError(f"{path!r} does not exist.")
    text = target.read_text(encoding="utf-8")
    count = text.count(old)
    if count == 0:
        raise ValueError(f"old string not found in {path!r}.")
    if count > 1:
        raise ValueError(
            f"old string occurs {count} times in {path!r}; expand it until it's unique."
        )
    target.write_text(text.replace(old, new, 1), encoding="utf-8")
    return {"path": str(target.relative_to(VAULT_ROOT)), "replacements": 1}


@mcp.tool()
def search_files(
    query: Annotated[str, Field(description="Regex pattern to search for.")],
    glob: Annotated[str, Field(description="Optional file glob, e.g. '*.md'")] = "*.md",
    max_results: Annotated[int, Field(description="Cap on matches returned.")] = 100,
) -> list[dict]:
    """Search file contents across the vault. Uses ripgrep if available, else Python fallback."""
    if _have_rg():
        return _rg_search(query, glob, max_results)
    return _py_search(query, glob, max_results)


def _have_rg() -> bool:
    try:
        subprocess.run(["rg", "--version"], capture_output=True, check=True)
        return True
    except (FileNotFoundError, subprocess.CalledProcessError):
        return False


def _rg_search(query: str, glob: str, max_results: int) -> list[dict]:
    cmd = ["rg", "--no-heading", "--line-number", "--with-filename",
           "--glob", glob, "--max-count", str(max_results), query, str(VAULT_ROOT)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    results = []
    for line in proc.stdout.splitlines()[:max_results]:
        # format: <path>:<line>:<text>
        parts = line.split(":", 2)
        if len(parts) != 3:
            continue
        path, lineno, text = parts
        rel = str(Path(path).resolve().relative_to(VAULT_ROOT))
        results.append({"path": rel, "line": int(lineno), "text": text})
    return results


def _py_search(query: str, glob: str, max_results: int) -> list[dict]:
    pattern = re.compile(query)
    results = []
    for path in VAULT_ROOT.rglob(glob):
        if ".git" in path.parts:
            continue
        if not path.is_file():
            continue
        try:
            for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if pattern.search(line):
                    results.append({
                        "path": str(path.relative_to(VAULT_ROOT)),
                        "line": i,
                        "text": line,
                    })
                    if len(results) >= max_results:
                        return results
        except UnicodeDecodeError:
            continue
    return results


# ---------- git tool ------------------------------------------------------

@mcp.tool()
def commit_and_push(
    message: Annotated[str, Field(description="Commit message. Should describe what changed and why.")],
) -> dict:
    """Explicitly commit and push pending vault changes. Use at session end or for important checkpoints."""
    # Stage everything, including deletes.
    _git("add", "-A")
    # Skip the commit if there's nothing staged.
    status = _git("status", "--porcelain")
    if not status.strip():
        return {"committed": False, "reason": "nothing to commit"}
    _git("commit", "-m", message)
    # Push is best-effort: report success/failure without raising.
    try:
        _git("push")
        pushed = True
        push_err = None
    except subprocess.CalledProcessError as e:
        pushed = False
        push_err = e.stderr.strip() if e.stderr else str(e)
    return {"committed": True, "pushed": pushed, "push_error": push_err, "message": message}


def _git(*args: str) -> str:
    """Run a git command in the vault root and return stdout."""
    cmd = ["git", "-C", str(VAULT_ROOT), *args]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise subprocess.CalledProcessError(
            proc.returncode, cmd, output=proc.stdout, stderr=proc.stderr
        )
    return proc.stdout


# ---------- entrypoint ----------------------------------------------------

def main() -> None:
    """Run the MCP server over SSE."""
    bind = os.environ.get("VAULT_BIND", "0.0.0.0:8088")
    host, port = bind.rsplit(":", 1)
    mcp.settings.host = host
    mcp.settings.port = int(port)
    mcp.run(transport="sse")


if __name__ == "__main__":
    main()
