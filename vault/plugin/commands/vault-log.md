---
description: Append a dated log entry to a project file in the vault
argument-hint: "<project-slug> -- <bullets, semicolon-separated>"
---

Append a new log entry to `working/$1.md` using the `vault` MCP server.

Steps:
1. Call `read_file("working/$1.md")` to confirm the file exists and to grab the current trailing content. If it doesn't exist, scaffold it from the vault-memory skill template, then proceed.
2. Construct the new entry. Use the current date and time in UTC, format `YYYY-MM-DD HH:MM`. Agent identity is your client name: `claude-code`, `claude-cowork`, `opencode`, or `cursor`.
3. Parse the bullets from `$2` (split on `;`, strip whitespace, skip empties). If `$2` is empty, infer 2-4 bullets from this conversation's most recent meaningful work.
4. Call `edit_file` to append the entry at the end of the file (or `write_file` with the full new content if `edit_file`'s exact-match constraint is awkward).
5. Call `commit_and_push` with message `vault: log $1 (<date>)`.

Output: a single line confirming what was appended and where.
