# Peek

macOS screen capture for humans and Claude. One Swift binary, two modes:

- **CLI** — `peek list windows`, `peek capture window --id 12345 -o shot.png`
- **MCP server** — `peek serve` speaks the Model Context Protocol over stdio so
  Claude (Code, Desktop, Cursor) can see your screen and specific app windows.

Built on `ScreenCaptureKit` (modern, not the deprecated `CGWindowList`
path). Single ~600-line Swift package, one external dep
(`swift-argument-parser`).

## Build

```bash
cd ~/Documents/Projects/peek-mcp
swift build -c release
```

Binary lands at `.build/release/peek`. Symlink it into your PATH if you want:

```bash
ln -s "$PWD/.build/release/peek" ~/bin/peek
```

## Permissions

ScreenCaptureKit needs **Screen Recording** permission, granted to whichever
process *launches* `peek` — not to `peek` itself. So:

- Run `peek` from Terminal.app → Terminal needs the grant.
- Run via Claude Code in Terminal → Terminal needs the grant.
- Run via Claude Desktop's MCP host → Claude Desktop needs the grant.

First call triggers the system prompt (or fails with TCC error `-3801`). Grant
in **System Settings → Privacy & Security → Screen Recording**, then restart
the host process.

## CLI

```bash
peek list windows                       # JSON: id, title, app, bundleID, bounds, onScreen, layer
peek list windows --app SocialPrep      # filter by app name substring
peek list windows --include-offscreen   # include minimized

peek list displays                      # JSON: id, widthPx, heightPx, frame, scale

peek capture window --id 12345 -o shot.png
peek capture window --id 12345 > shot.png          # PNG bytes to stdout

peek capture display -o screen.png                 # primary display
peek capture display --id 4 -o ext.png             # specific display

peek capture region -x 100 -y 100 -w 800 -h 600 -o region.png
```

All capture commands take `--no-hide-cursor` to keep the cursor in the shot
(default hides it).

## MCP server (Claude Code / Desktop / Cursor)

Add to your MCP client config. For Claude Code (`~/.claude.json` or
`.claude/settings.json` per project):

```json
{
  "mcpServers": {
    "peek": {
      "command": "/Users/ras/Documents/Projects/peek-mcp/.build/release/peek",
      "args": ["serve"]
    }
  }
}
```

Or, for Claude Desktop
(`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "peek": {
      "command": "/absolute/path/to/peek",
      "args": ["serve"]
    }
  }
}
```

Restart the host. You'll see the tools advertised:

- `list_windows` → JSON
- `list_displays` → JSON
- `capture_window` → inline PNG image content block
- `capture_display` → inline PNG
- `capture_region` → inline PNG

The capture tools return MCP `image` content blocks (base64 PNG) — Claude
sees the screenshot directly, no separate file-read round-trip.

## Why not [some existing MCP]?

Reviewed `jhead/macos-screen-mcp` (deprecated APIs, HTTP+SSE returning URLs
Claude can't fetch), `TIMBOTGPT/screen-vision-mcp` (clean but unmaintained),
`sethbang/mcp-screenshot-server` (well-engineered but: Puppeteer dep, returns
file paths instead of inline images, runtime `swift -e` for window lookups,
no `list_windows` tool, no shadow-strip option).

Peek is small enough to read in one sitting and own forever.
