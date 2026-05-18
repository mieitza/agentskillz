---
description: Read the vault file for a project and summarize current state
argument-hint: [project slug — defaults to inferring from current context]
---

Read the vault file for "$ARGUMENTS" (or infer the project slug from the current
working directory or recent conversation if no argument was given) and summarize
its current state.

## Process

1. **Resolve the slug.** If `$ARGUMENTS` is non-empty, treat it as the slug.
   Otherwise, infer it: ask the user which project, or use the most recent
   project the conversation referenced. Lowercase and kebab-case the slug.

2. **Read the file.** Call `vault.read_file` on `working/<slug>.md`. If the
   file does not exist, call `vault.list_directory("working")` to show the
   available slugs and ask the user to pick one (or offer to create a new file
   following the vault-memory skill's "Creating a new project file" guidance).

3. **Summarize.** Produce a tight summary in this exact shape:

   ```
   ## <Project name> — <status from frontmatter>

   **Status:** <verbatim from the ## Status section>

   **Open questions:**
   - <each bullet from ## Open questions>

   **Last log entry:** <timestamp and one-line summary of the last ### entry>

   **Recent decisions** (last 3):
   - <date>: <decision>
   ```

4. **Stop.** Do not append to the file or take further action unless the user
   asks. This command is read-only.

If the user asks "what was I working on" without a slug, list every file in
`working/` instead — one line per project with its status and last-updated
timestamp — and ask which one they want to dig into.
