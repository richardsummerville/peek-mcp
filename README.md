# Peek

macOS screen capture for humans and Claude. One Swift binary, two modes:

- **CLI** — `peek list windows`, `peek capture window --app Safari -o shot.png`.
- **MCP server** — `peek serve` speaks the [Model Context Protocol][mcp]
  over stdio so Claude (Code, Desktop, Cursor) can see your screen and
  specific app windows. Captures are returned as inline image content
  blocks — no file-path round-trip.

Built on `ScreenCaptureKit` (the modern API, not the deprecated
`CGWindowList` path). Single Swift package, one external dep
(`swift-argument-parser`). MIT licensed.

[mcp]: https://modelcontextprotocol.io

## Install

```bash
brew install richardsummerville/tap/peek
```

> No Brew? Skip to [Develop](#develop) for the source-build path
> (`make install`).

After installing the binary, you need to do two more things to make
Claude actually able to use peek:

### 1. Wire peek into your MCP host configs

```bash
peek install
```

This edits `~/.claude.json` (Claude Code) and Claude Desktop's config
file to add peek as an MCP server. Use `peek install --dry-run` to see
the changes first, `peek install --uninstall` to remove.

**Restart Claude.app fully (Cmd-Q + reopen)** so it picks up the new
MCP entry.

### 2. Grant Screen Recording permission

ScreenCaptureKit needs **Screen Recording** permission, granted to
whichever app *launches* peek — not to peek itself:

| You run peek via…             | Grant Screen Recording to… |
|-------------------------------|----------------------------|
| Terminal (`peek capture …`)   | **Terminal.app**           |
| Claude Code or Claude Desktop | **Claude.app**             |

Run the diagnostic — it'll tell you exactly what's missing:

```bash
peek doctor                  # report status
peek doctor --open-settings  # also opens the Privacy panel
```

In **System Settings → Privacy & Security → Screen Recording**, toggle
on the relevant app, then **fully quit and reopen it** (the toggle
doesn't apply retroactively to running processes).

You'll know it's working when `peek doctor` shows
`[ok] Screen Recording permission: granted`.

> **Brew quirk.** macOS marks Homebrew-installed binaries with a
> `com.apple.provenance` xattr that TCC may treat as a distinct app
> needing its own Screen Recording entry — even when the host
> (Claude.app) already has the grant. If granting just the host
> doesn't work, also add `/opt/homebrew/bin/peek` to the Screen
> Recording list (`+` button, Cmd+Shift+G, paste the path). `peek
> doctor` detects this case and prints the exact steps.

### First capture

From Terminal, sanity-check that the binary works:

```bash
peek capture window --app Finder -o /tmp/x.png && open /tmp/x.png
```

From Claude (after the steps above), ask: *"Use peek to capture my
Finder window."* Claude will call peek's MCP tool and you'll see the
screenshot inline.

## CLI

```bash
peek list windows                       # JSON: id, title, app, bundleID, bounds, layer
peek list windows --app Safari          # filter by app name substring
peek list windows --include-offscreen   # include minimized

peek list displays                      # JSON: id, widthPx, heightPx, frame, scale

peek capture window --app Safari -o shot.png    # frontmost matching window
peek capture window --id 12345 -o shot.png      # exact window
peek capture window --app Safari > shot.png     # PNG bytes to stdout
peek capture window --app 1Password --force     # bypass deny-list

peek capture display -o screen.png              # primary display
peek capture display --id 4 -o ext.png          # specific display

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

All capture commands take `--no-hide-cursor` to keep the cursor in the
shot (default hides it). CLI captures default to PNG (lossless).

## MCP integration

`peek install` writes the right entry into:

- **Claude Code:** `~/.claude.json`
- **Claude Desktop:** `~/Library/Application Support/Claude/claude_desktop_config.json`

Restart your host. Tools advertised:

| Tool              | Args                                                              | Returns          |
|-------------------|-------------------------------------------------------------------|------------------|
| `list_windows`    | `include_offscreen?: bool`                                        | text JSON        |
| `list_displays`   | —                                                                 | text JSON        |
| `capture_window`  | `window_id: int` *or* `app_name: string`, `hide_cursor?`, `force?`, `format?` | inline image     |
| `capture_display` | `display_id?: int`, `hide_cursor?`, `format?`                     | inline image     |
| `capture_region`  | `x, y, width, height: int`, `display_id?`, `hide_cursor?`, `format?` | inline image     |

Capture tools default to the **lossless** preset (PNG, 2048 px cap) —
sharp UI, no JPEG artifacts on text. Larger responses + slower
round-trips than JPEG; if you'd rather optimise for speed, swap the
preset (see below). Per-call `format: "png"` or `format: "jpeg"`
overrides everything. The `force` boolean (window captures only)
bypasses the deny-list.

### Changing the default

Set `PEEK_QUALITY` in your environment to swap presets:

| Preset      | Format    | Cap    | Typical size |
|-------------|-----------|--------|--------------|
| `fast`      | JPEG q=0.5| 768 px | ~80 KB       |
| `balanced`  | JPEG q=0.7| 1024 px| ~150 KB      |
| `lossless`  | PNG       | 2048 px| ~1 MB (default) |

Per shell session: `export PEEK_QUALITY=lossless` in `~/.zshrc`.

Per MCP host: add `env` to the host's mcpServers entry. Example for
Claude Desktop:

```json
"mcpServers": {
  "peek": {
    "command": "/opt/homebrew/bin/peek",
    "args": ["serve"],
    "env": { "PEEK_QUALITY": "lossless" }
  }
}
```

`peek doctor` shows the current preset.

For other hosts (Cursor, etc.) add manually:

```json
"mcpServers": {
  "peek": {
    "command": "/opt/homebrew/bin/peek",
    "args": ["serve"]
  }
}
```

## Knowing it's running, turning it off

When peek is active you'll see an **eye icon in your menu bar**. Click
it for:

- *Last capture: <app> · Xs ago* (refreshes every second)
- The 5 most recent captures (CLI and MCP both flow through here)
- "Open audit log" — jumps to the JSONL file
- "Screen Recording Settings…" — jumps to the Privacy panel
- **"Kill peek (stop captures now)"** in red, Cmd-K — terminates the
  daemon immediately. All MCP tool calls will fail until the next time
  Claude tries one (which auto-respawns peek).

Under the hood: `peek serve` (what MCP hosts launch) is a thin shim
that connects to a singleton `peek daemon` over a Unix socket. The
daemon owns ScreenCaptureKit and the menu bar; shims forward JSON-RPC
back and forth. Multiple Claude hosts = N shims + 1 daemon, not N full
instances. `peek serve --standalone` keeps the older all-in-one mode
for debugging.

## Audit log

Every capture (and every denial) appends one JSON line to
`~/Library/Application Support/peek/log.jsonl`. The log is never read
by peek itself — it exists so *you* can answer "what has Claude
actually seen?":

```bash
peek log tail | jq .
```

Schema:

```json
{
  "ts": "2026-05-02T18:42:13.123Z",
  "kind": "capture_window",            // or capture_display, capture_region, denied
  "caller": "mcp",                     // or cli
  "app": "Safari",
  "windowId": 12345,
  "bytes": 482103,
  "denyReason": null
}
```

`list_windows` / `list_displays` carry no privacy weight and are not
logged.

## Deny-list

Window captures (by id or app name) consult a deny-list before
invoking ScreenCaptureKit. Defaults:

- 1Password (all bundle id variants)
- Keychain Access (`com.apple.keychainaccess`)
- Apple Passwords (`com.apple.Passwords`, macOS 15+)

A denied capture writes a `kind: "denied"` audit entry and returns:

```
Refusing to capture 1Password — bundle id com.1password.1password matches
deny pattern "com.1password.". Use --force (CLI) or force: true (MCP) to
override.
```

Add your own at `~/Library/Application Support/peek/denylist.json`:

```json
{
  "bundleIDPatterns": ["com.mybank."],
  "appNamePatterns": ["My Bank"]
}
```

User entries are **additive** — defaults are never removed.

Display and region captures don't consult the deny-list (they're
explicit area choices, not pattern-matched targets).

## Develop

Requires Xcode 16+ / Swift 6+ and macOS 14+ (for ScreenCaptureKit's
single-shot APIs).

Source build (skip Brew):

```bash
git clone https://github.com/richardsummerville/peek-mcp
cd peek-mcp
make install                       # → /usr/local/bin/peek
make install PREFIX=$HOME          # → ~/bin/peek (no sudo)
```

If `make install` fails with "Permission denied" on `/usr/local/bin`
and you don't have Brew, use the `PREFIX=$HOME` form. Make sure
`~/bin` is on your `PATH`:

```bash
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

Then continue with `peek install` and `peek doctor` exactly as in the
[Install](#install) section above.

Run the test suite:

```bash
swift test
```

Open in Xcode:

```bash
open Package.swift
```

Xcode treats `Package.swift` as a project — Run/Debug/Test, full
ScreenCaptureKit indexing.

Repo layout:

```
Sources/Peek/
├── Peek.swift                  // @main entry, ArgumentParser
├── Commands/                   // CLI subcommands
│   ├── List.swift
│   ├── Capture.swift
│   ├── Serve.swift             // MCP shim by default
│   ├── Daemon.swift            // singleton daemon
│   ├── Install.swift           // wires MCP hosts
│   ├── Doctor.swift            // permission + status check
│   └── Log.swift               // audit log subcommand
├── Core/
│   ├── ScreenCapture.swift     // SCK wrapper
│   ├── DenyList.swift
│   ├── AuditLog.swift
│   └── MCPHosts.swift          // Claude Code / Desktop config writers
├── MCP/
│   └── Server.swift            // hand-rolled JSON-RPC server
├── Daemon/
│   ├── SocketPath.swift
│   ├── UnixSocketServer.swift  // accept loop
│   └── AutoSpawn.swift         // shim → daemon spawning
└── MenuBar/
    ├── MenuBarController.swift // NSStatusItem
    └── MenuBarLock.swift       // singleton flock
```

## Why not [some existing MCP]?

Reviewed `jhead/macos-screen-mcp` (deprecated APIs, HTTP+SSE returning
URLs Claude can't fetch), `TIMBOTGPT/screen-vision-mcp` (clean but
unmaintained), `sethbang/mcp-screenshot-server` (well-engineered but:
Puppeteer dep, returns file paths instead of inline images, runtime
`swift -e` for window lookups, no per-app deny-list, no audit log).

Peek's design choices that aren't in the others:
- Daemon + shim architecture — one peek instance regardless of host count.
- Single menu-bar indicator with a kill switch.
- Audit log of every capture + denial.
- Deny-list with sensible defaults (password managers, keychain).
- Inline image content blocks (not file paths).
- JPEG default with `format: "png"` opt-in for lossless.

## License

MIT — see [LICENSE](LICENSE).
