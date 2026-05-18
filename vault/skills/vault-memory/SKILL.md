---
name: vault-memory
description: Read and write to the shared agent memory vault. Use whenever the user references a project by name, asks "what was I working on", asks to remember or recall something across sessions, or when starting/ending work on a project. The vault is the single source of truth for project state shared across Claude Desktop, Claude Code, and OpenCode.
---

# vault-memory

The vault is a git-backed markdown filesystem exposed via the `vault` MCP
server. It is the shared memory layer across all Claude surfaces.

## When to use this skill

**Read from the vault when:**
- The user references a project by name ("what's the status of CharterPulse?")
- The user asks what they were working on ("what was I doing last week?")
- The user asks you to recall a past decision ("why did we choose libSQL?")
- A session starts in a project directory (the SessionStart hook will hint
  at the slug — read `working/<slug>.md` if it exists)

**Write to the vault when:**
- The user makes a decision worth remembering ("ok let's go with FastAPI")
- A meaningful chunk of work completes (PR merged, contract drafted, bug fixed)
- The user explicitly says to remember something
- A session is ending and substantive work was done (append a log entry)

**Don't use the vault for:**
- One-shot questions ("what's the capital of France")
- Code that lives in a repo (the repo is the source of truth for code)
- Anything the user explicitly marks as ephemeral

## Vault layout

```
/home/misha/vault/
├── working/      active projects — read on session start, written often
├── reference/    stable knowledge — decision records, "how X works" docs
└── archive/      closed projects — rarely touched, searchable
```

## File conventions

Every project file has this structure:

```markdown
---
project: <slug>
status: active | paused | done
owner: misha
updated: <iso-8601>
---

# <Project name>

## Status
One paragraph describing the current state. Overwrite this on each
meaningful update — it's a snapshot, not history.

## Decisions
- 2026-05-18: chose libSQL over sqlite-vec because of native FLOAT32 support
- 2026-05-15: dropped sqlx, going direct on the libsql crate
Bulleted, dated, immutable. Once written, don't edit — add a new line.

## Open questions
- Should the F3 contract enforce uniqueness on (source, external_id)?
- What's the retention policy for the audit log?
Bulleted, mutable. Remove entries when resolved.

## Log
Append-only timeline. Newest at the bottom.

### 2026-05-18 14:32 — claude-code
- Implemented F1, F2, F3 contracts
- Tests passing for F1 and F2; F3 needs the uniqueness decision
- Open question added: retention policy

### 2026-05-15 09:10 — claude-desktop
- Reviewed PRD v0.5
- User confirmed the vector_top_k rowid join pattern
```

## How to operate

### Reading
1. List the working directory: `vault.list_directory("working")`
2. If the project slug is known, read `working/<slug>.md` directly.
3. If not, search: `vault.search_files("working", "<keyword>")`.

### Writing
Prefer `edit_file` over `write_file` so you don't accidentally clobber
content written by another agent. Pattern for appending a log entry:

1. Read the current file.
2. Find the `## Log` section.
3. Append `### <timestamp> — <agent-name>` followed by your bullets at
   the end of the file.
4. Update the frontmatter `updated:` field.

For status updates, replace just the `## Status` paragraph — don't rewrite
decisions or log entries.

### Creating a new project file
If `working/<slug>.md` doesn't exist and the user is starting work on
something new, propose creating it with the standard frontmatter and
empty sections. Ask before creating — don't auto-create.

## Concurrency

The vault auto-commits every 2 minutes. Two agents writing to the same
file at the same time is rare but possible. Mitigations:
- The append-only Log section means simultaneous writes produce adjacent
  entries, not corruption.
- The `## Status` section is the only one that gets overwritten — if you
  notice your write was overwritten, just append a note in the Log
  ("status was overwritten by parallel session, current state is X").

## Agent identity

When writing log entries, sign with your surface:
- `claude-code` from Claude Code
- `claude-desktop` from Claude Desktop
- `opencode` from OpenCode

This lets the user audit which agent did what.
