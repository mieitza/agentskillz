# Claude Desktop — vault MCP config

Claude Desktop only supports stdio MCP servers natively. To talk to the
remote vault, we use `mcp-remote` as a translating bridge.

## Where to put this

Edit (or create) `claude_desktop_config.json`:

- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Linux**: `~/.config/Claude/claude_desktop_config.json`
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

## Config

Merge this `mcpServers` entry into your existing config. If you don't have
a config yet, the whole file is just this:

```json
{
  "mcpServers": {
    "vault": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote@latest",
        "http://100.83.164.37:8088/sse"
      ]
    }
  }
}
```

## Verification

1. Quit Claude Desktop completely (Cmd+Q on Mac, not just close the window).
2. Reopen it.
3. Start a new chat. The hammer/tools icon should show vault tools:
   `read_file`, `write_file`, `edit_file`, `list_directory`,
   `search_files`, `move_file`, etc.
4. Test it: ask "list the files in the working directory of the vault".

## Troubleshooting

- If tools don't show up, check the logs:
  - macOS: `~/Library/Logs/Claude/mcp*.log`
  - Linux: `~/.config/Claude/logs/mcp*.log`
- If the connection times out, verify from your Mac:
  ```
  curl -v http://100.83.164.37:8088/sse
  ```
  You should see SSE headers (`content-type: text/event-stream`).
  If it hangs forever, check Tailscale is up: `tailscale status`.
- `mcp-remote` versions before 0.1.16 had an RCE — `@latest` pins forward,
  which is what we want.

## Note on stdio vs HTTP

Claude Desktop spawns `mcp-remote` as a child process via stdio, and
`mcp-remote` opens an SSE connection to the server on agentsmith. So the
Mac → agentsmith wire is HTTP/SSE over Tailscale, and the Desktop ↔
mcp-remote wire is local stdio. You're not exposing the vault to the
public internet — Tailscale ACLs are the only thing that can reach port
8088.
