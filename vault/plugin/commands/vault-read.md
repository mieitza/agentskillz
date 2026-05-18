---
description: Read a project file from the vault and summarize current state
argument-hint: "<project-slug>"
---

Read `working/$1.md` from the vault using the `vault` MCP server's `read_file` tool. Then output a short summary in this exact shape:

**Status:** <one line distilled from the Status section>
**Last update:** <date and one-line summary of the most recent Log entry>
**Open questions:** <count, and list the top 2 in one line each>
**Next step:** <pulled from Status.Next step>

If `working/$1.md` does not exist, say so and offer to scaffold one from the standard template (see the vault-memory skill). Do not invent content.
