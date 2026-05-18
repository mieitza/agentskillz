---
name: vault-memory
description: Shared agent memory across Claude Desktop, Claude Code, and OpenCode. Reads and writes a git-backed markdown vault over MCP. Use whenever the user references a project by name, asks "what was I working on", recalls a past decision, wants to remember something across sessions, or finishes a meaningful piece of work that should be logged.
---

# vault-memory

The vault is shared memory across every agent surface I run in (Claude Desktop / Cowork, Claude Code, OpenCode). It is a git-versioned markdown directory exposed over MCP. **All paths are relative to the vault root.** I never see, write, or guess host paths — only MCP tool calls with relative paths.

## When to use this skill

Reach for vault tools when the user:

- mentions a project by name ("the agentskillz repo", "the vault thing", "Project X")
- asks "what was I working on" / "where did we leave off" / "remind me about Y"
- recalls a past decision ("didn't we decide to use Postgres?") — confirm against the vault before answering
- asks me to remember something across sessions
- finishes a non-trivial piece of work — log it before the session ends

If the request is purely conversational ("explain async/await") or one-shot ("rename this file"), skip the vault. Only project-shaped work goes in.

## File layout

The vault root contains a small fixed set of directories. Stay inside them.

```
working/<slug>.md       Active project files. One per project. Slug is kebab-case.
reference/              Long-lived notes that aren't tied to a single project.
people/<slug>.md        Per-person notes (1:1 context, prefs, history).
inbox.md                Append-only scratch when no clear home exists yet. Triage later.
README.md               Vault overview, conventions, link map.
```

If a project doesn't have a `working/<slug>.md` yet and the work is non-trivial, create one (see template below). If the slug is unclear, ask the user.

## Project file template

Every `working/<slug>.md` follows this shape. **Do not invent new top-level sections** — extend Status, Decisions, Open questions, or Log instead.

```markdown
# <slug>

> Working file for the `<slug>` project.
> Append-only log at the bottom; edit Status / Decisions / Open questions inline.

## Status
- **What it is:** (1-2 sentences)
- **Current state:** (exploring / scaffolding / in flight / blocked on X / shipped)
- **Next step:** (one concrete action)

## Decisions
- YYYY-MM-DD — <decision> — <one-line reasoning>

## Open questions
- <question> — <why it matters>

## Log
### YYYY-MM-DD HH:MM — <agent-identity>
- bullet 1
- bullet 2
```

**Agent identity** in log entries: use one of `claude-cowork`, `claude-code`, `opencode`, `cursor`. This is how we know who wrote what when reviewing git history.

## When to read vs. write

**Read first, almost always.** Before logging or making a decision, call `read_file("working/<slug>.md")` to load current state. If it doesn't exist and the work matters, `write_file` it from the template above.

**Write when:**
- starting a session on a known project (refresh Status with current state if it changed)
- a real decision was reached (append to Decisions with date + reasoning)
- a question came up that we don't have an answer to yet (append to Open questions)
- the session is wrapping up and meaningful work happened (append a Log entry)

**Don't write:**
- mid-thought bullet points that might be wrong in 5 minutes
- exhaustive transcripts of what was discussed — summarize to 2-5 bullets
- speculation; if it's a maybe, file it under Open questions, not Decisions

## Append-only log discipline

Log entries go at the bottom, newest last, never edited after the fact. If a previous decision turned out wrong, **supersede** it with a new Decision line dated today — don't delete the old one. Git history is a feature, not a bug.

## Tools available

The vault MCP server exposes:

- `list_directory(path)` — see what's in a folder (path relative to vault root, `""` for root)
- `read_file(path)` — read a file's full contents
- `write_file(path, content)` — create or overwrite a file (parent dirs auto-created)
- `edit_file(path, old, new)` — exact-string replace; `old` must occur exactly once
- `search_files(query, glob)` — regex search across the vault (defaults to `*.md`)
- `commit_and_push(message)` — explicit checkpoint commit. Use at session end or after a big change.

A background watcher will autocommit pending changes after ~30s of quiet. `commit_and_push` is for explicit, well-messaged checkpoints — prefer it when the work is worth a named commit.

## Slash commands

These are convenience wrappers, available in clients that support slash commands:

- `/vault-read <slug>` — read `working/<slug>.md` and summarize current state
- `/vault-log <slug> <bullets>` — append a dated log entry
- `/vault-status` — list all `working/*.md` with current Status block

## What I never do

- Use absolute host paths. The vault MCP root is the only world I see.
- Write outside `working/`, `reference/`, `people/`, or `inbox.md` without checking with the user.
- Edit historical Log entries.
- Commit secrets, credentials, tokens, or API keys. If the user pastes one, refuse to store it and explain why.
- Invent project slugs — ask the user if unclear.
