# Peek

macOS screen capture for humans and Claude. One Swift binary, two modes:

- **CLI** — `peek list windows`, `peek capture window --app SocialPrep`
- **MCP server** — `peek serve` speaks the Model Context Protocol over stdio
  so Claude (Code, Desktop, Cursor) can see your screen and specific app
  windows.

Built on `ScreenCaptureKit` (modern, not the deprecated `CGWindowList`
path). One Swift package, one external dep (`swift-argument-parser`).

## Install

```bash
git clone <this-repo> ~/Documents/Projects/peek-mcp
cd ~/Documents/Projects/peek-mcp
make install                # builds + symlinks to /usr/local/bin/peek
peek install                # wires it into Claude Code & Claude Desktop
peek doctor                 # check Screen Recording permission
```

That's it. Three commands, fully wired.

If `/usr/local/bin` is not on your `PATH` (rare), set `PREFIX=$HOME` so
`make install` lands the binary in `$HOME/bin/peek`.

## Permissions

ScreenCaptureKit needs **Screen Recording** permission, granted to whichever
process *launches* `peek` — not to `peek` itself:

- Run `peek` from Terminal.app → Terminal needs the grant.
- Run via Claude Code in Terminal → Terminal needs the grant.
- Run via Claude Desktop's MCP host → Claude Desktop needs the grant.

`peek doctor` reports whether the grant is in place. First capture call
triggers the system prompt (or fails with TCC error `-3801`). Grant in
**System Settings → Privacy & Security → Screen Recording**, then fully quit
and reopen the host process. `peek doctor --open-settings` jumps straight
there.

## CLI

```bash
peek list windows                       # JSON: id, title, app, bundleID, bounds, onScreen, layer
peek list windows --app SocialPrep      # filter by app name substring
peek list windows --include-offscreen   # include minimized

peek list displays                      # JSON: id, widthPx, heightPx, frame, scale

peek capture window --app SocialPrep -o shot.png   # frontmost matching window
peek capture window --id 12345 -o shot.png         # exact window
peek capture window --app SocialPrep > shot.png    # PNG bytes to stdout
peek capture window --app 1Password --force        # bypass deny-list

peek capture display -o screen.png                 # primary display
peek capture display --id 4 -o ext.png             # specific display

peek capture region -x 100 -y 100 -w 800 -h 600 -o region.png

peek install                            # wire into MCP hosts
peek install --dry-run                  # show what would change
peek install --uninstall                # remove

peek doctor                             # permission + host status
peek doctor --open-settings             # also opens Privacy panel

peek log tail                           # last 20 audit entries (JSONL)
peek log tail -n 100                    # last 100
peek log path                           # print log file path
peek log clear --yes                    # wipe the log
```

All capture commands take `--no-hide-cursor` to keep the cursor in the shot
(default hides it).

## Audit log

Every capture (and every denial) appends one JSON line to
`~/Library/Application Support/peek/log.jsonl`. One entry per call, no
exceptions. The log is never read by peek itself — it exists so *you*
can answer "what has Claude actually seen?":

```bash
peek log tail | jq .
```

Schema:

```json
{
  "ts": "2026-05-02T18:42:13.123Z",
  "kind": "capture_window",            // or capture_display, capture_region, denied
  "caller": "mcp",                     // or cli
  "app": "SocialPrep",
  "windowId": 12345,
  "bytes": 482103,
  "denyReason": null
}
```

`list_windows` / `list_displays` are not logged — they carry no privacy
weight.

## Deny-list

Window captures (by id or app name) consult a deny-list before doing the
SCK call. Defaults:

- `1Password` (all variants — bundle id `com.1password.*`, `com.agilebits.onepassword`)
- `Keychain Access` (`com.apple.keychainaccess`)

A denied capture writes a `kind: "denied"` audit entry and returns an
error:

```
Refusing to capture 1Password — bundle id com.1password.1password matches deny pattern "com.1password.". Use --force (CLI) or force: true (MCP) to override.
```

Add your own patterns at `~/Library/Application Support/peek/denylist.json`:

```json
{
  "bundleIDPatterns": ["com.mybank."],
  "appNamePatterns": ["My Bank"]
}
```

Defaults are always merged in — user entries are additive, never
replacement.

Display and region captures don't consult the deny-list (they're
explicit area choices, not pattern-matched targets).

## MCP server

`peek install` writes the right entry into:

- Claude Code: `~/.claude.json`
- Claude Desktop: `~/Library/Application Support/Claude/claude_desktop_config.json`

Then restart your host. The tools advertised:

| Tool              | Args                                                                  | Returns          |
|-------------------|-----------------------------------------------------------------------|------------------|
| `list_windows`    | `include_offscreen?: bool`                                            | text JSON        |
| `list_displays`   | —                                                                     | text JSON        |
| `capture_window`  | `window_id: int` *or* `app_name: string`, `hide_cursor?`, `force?`    | inline PNG image |
| `capture_display` | `display_id?: int`, `hide_cursor?`                                    | inline PNG image |
| `capture_region`  | `x, y, width, height: int`, `display_id?`, `hide_cursor?`             | inline PNG image |

Capture tools return MCP `image` content blocks (base64 PNG) — Claude sees
the screenshot directly, no separate file-read round-trip.

For other hosts (Cursor, etc.) add manually:

```json
"mcpServers": {
  "peek": {
    "command": "/usr/local/bin/peek",
    "args": ["serve"]
  }
}
```

## Develop in Xcode

```bash
open Package.swift
```

Xcode treats it as a project, gives you Run/Debug/Test, and indexes
ScreenCaptureKit normally.

## Why not [some existing MCP]?

Reviewed `jhead/macos-screen-mcp` (deprecated APIs, HTTP+SSE returning
URLs Claude can't fetch), `TIMBOTGPT/screen-vision-mcp` (clean but
unmaintained), `sethbang/mcp-screenshot-server` (well-engineered but:
Puppeteer dep, returns file paths instead of inline images, runtime
`swift -e` for window lookups, no `list_windows` tool).

Peek is small enough to read in one sitting and own forever.
