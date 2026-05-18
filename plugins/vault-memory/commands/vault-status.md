---
description: List every working project in the vault with status, owner, and last update
---

List every active project in the vault — one row per file in `working/`.

## Process

1. **List files.** Call `vault.list_directory("working")`.

2. **For each `.md` file**, call `vault.read_file` and parse:
   - frontmatter: `project`, `status`, `owner`, `updated`
   - the `## Status` section's first paragraph (one-line summary)
   - count of open questions

3. **Render a compact table:**

   ```
   | Project | Status | Updated | Open Qs | One-line state |
   |---------|--------|---------|---------|----------------|
   | ...     | active | 2026-05-18 | 2 | ... |
   ```

   Sort by `updated` descending so the most recently touched projects are
   at the top.

4. **Below the table**, surface any projects whose `updated` is more than 14
   days old as "stale — consider archiving or moving to paused":

   ```
   **Stale (>14d):** charterpulse (last touch 2026-05-02), affiliate (2026-04-30)
   ```

5. Do not modify any files. This is a read-only overview.
