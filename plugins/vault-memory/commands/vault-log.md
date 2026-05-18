---
description: Append a dated log entry to the current project's vault file
argument-hint: [optional: project slug, or bullet content to log]
---

Append a new log entry to `working/<slug>.md` in the vault.

## Process

1. **Resolve the slug.** If `$ARGUMENTS` starts with a recognizable slug
   (single token, kebab-case, matches a file in `working/`), use it as the
   slug and treat the rest of `$ARGUMENTS` as content. Otherwise, infer the
   slug from current context — recent conversation, working directory, or by
   asking the user.

2. **Determine the agent surface.** Pick the right tag:
   - `claude-desktop` when running inside Claude Desktop or Cowork
   - `claude-code` when running inside Claude Code (CLI)
   - `opencode` when running inside OpenCode
   Default to `claude-desktop` if unsure.

3. **Gather bullets.** If the user provided content in `$ARGUMENTS`, use it.
   Otherwise, synthesize 2–5 bullets from the current session covering:
   what was decided or built, what changed, any new open questions.

4. **Read the file.** Call `vault.read_file` on `working/<slug>.md`. If it
   does not exist, ask the user whether to create it before logging.

5. **Append via `vault.edit_file`.** Insert at the end of the file (after the
   last `### ` log entry):

   ```
   ### <ISO date HH:MM> — <agent-surface>
   - <bullet 1>
   - <bullet 2>
   - <bullet 3>
   ```

   Use `vault.edit_file` (not `write_file`) so a concurrent session's edits
   are not clobbered. Use the current local time, ISO-formatted to the minute.

6. **Update the frontmatter `updated:` field** to the same timestamp.

7. **Confirm.** Reply with one line: "Logged to working/<slug>.md at <time>"
   and the bullets that were written. Do not over-explain.

If `$ARGUMENTS` contains a new open question (text starting with "Q:" or "?"),
add it to `## Open questions` instead of (or in addition to) the log.
