---
description: List all active projects in the vault with their current status
---

List every project in the vault and summarize state.

Steps:
1. Call `list_directory("working")` to get the project files.
2. For each `<slug>.md`, call `read_file` and parse out the Status section and the most recent Log entry.
3. Render a compact table with columns: project, state, last update, open Qs.

Sort by last-update date descending. Cap at 20 rows; if there are more, say so and suggest a filter.

Output one line at the top: `<N> active projects in vault`.
