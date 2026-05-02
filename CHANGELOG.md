# Changelog

All notable changes to peek are tracked here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/).

## [0.4.1] — 2026-05-02

### Added
- `PEEK_QUALITY` env var with three presets: `fast` (JPEG q=0.5,
  768 px), `balanced` (JPEG q=0.7, 1024 px — default), `lossless`
  (PNG, 2048 px). Drives the MCP capture default; per-call `format`
  parameter still wins. `peek doctor` reports the active preset.
- README documents how to set the env in `~/.zshrc` (per shell) or in
  the MCP host's `env` field (per host).

## [0.4.0] — 2026-05-02

### Added
- **Daemon + shim architecture.** `peek serve` is now a thin stdio
  shim (the binary MCP hosts launch); a single `peek daemon` process
  owns SCK, the menu bar, and the audit log. Multiple Claude
  hosts/sessions = N shims + 1 daemon, instead of N full instances
  each with their own SCK init and ~10 MB resident.
- **Menu-bar indicator** (`NSStatusItem` eye icon) showing last
  capture, recent history (5 most recent), audit log shortcut,
  Screen Recording settings shortcut, and a red **"Kill peek"**
  switch (Cmd-K) that terminates the daemon immediately.
- **Singleton menu-bar lock** for `--standalone` mode so multiple
  in-process instances don't stack icons.
- **JPEG output** as MCP default. CLI defaults to PNG (lossless for
  on-disk saves). MCP `capture_*` tools accept `format: "png"` to
  force lossless.
- `peek daemon` subcommand for running the daemon manually
  (debugging, or as a future LaunchAgent target).
- `peek serve --standalone` / `--no-menu-bar` flags for the legacy
  in-process mode.

### Changed
- Default capture output dimensions capped at **1024 px** longest
  side (was uncapped / native retina). Anthropic's vision pipeline
  downsamples larger images anyway; smaller responses round-trip
  3-5× faster.
- Default JPEG quality 0.7. UI text remains readable; vision-model
  discrimination is unaffected.
- MCP `serverVersion` reports `0.4.0`.

### Fixed
- **Capture deadlock when called from inside `NSApp.run` event loop.**
  `MainActor.run { _ = NSApplication.shared }` (used to bootstrap the
  WindowServer/CoreGraphics connection) didn't reliably resolve
  inside the AppKit run loop. Daemon startup now pre-bootstraps NSApp
  and marks the bootstrap done so per-capture calls skip the hop;
  remaining cases hop via `DispatchQueue.main.async` (which AppKit
  reliably pumps).
- **Shim dropping responses on stdin EOF.** Was calling
  `shutdown(SHUT_RDWR)` on the daemon socket the moment the host
  closed stdin, racing with the daemon's response writes. Changed
  to `SHUT_WR` (half-close) so queued responses still flow back.

## [0.3.0] — 2026-05-02

### Added
- `peek log` subcommand (`tail`, `path`, `clear`).
- Append-only JSONL audit log at
  `~/Library/Application Support/peek/log.jsonl`. Every capture and every
  denial writes one line; `list_*` operations carry no privacy weight
  and are not logged.
- App deny-list with conservative defaults: 1Password (all variants),
  Keychain Access, Apple Passwords (`com.apple.Passwords`, macOS 15+).
- User deny-list overrides at
  `~/Library/Application Support/peek/denylist.json`. User entries are
  additive — defaults are never removed.
- `--force` (CLI) / `force: true` (MCP) bypass for window captures.
- Test suite (Swift Testing) covering DenyList matching and AuditLog
  round-trip.
- MIT LICENSE.

### Changed
- `capture_window` MCP tool description now documents the `force`
  parameter.
- MCP `serverVersion` reports `0.3.0`.

## [0.2.1] — 2026-05-01

### Fixed
- `CGS_REQUIRE_INIT` abort on first capture from the CLI binary.
  `SCScreenshotManager.captureImage` requires the WindowServer /
  CoreGraphics connection to be initialised; we now bootstrap
  `NSApplication.shared` (MainActor-hopped) at the top of each capture
  entry point. The shared singleton is cached after first access, so the
  per-call cost is negligible.

## [0.2.0] — 2026-05-01

### Added
- `peek install` — auto-wires peek into Claude Code (`~/.claude.json`)
  and Claude Desktop (`claude_desktop_config.json`) MCP host configs.
  Supports `--dry-run` and `--uninstall`.
- `peek doctor` — reports Screen Recording permission status and
  detected MCP hosts. `--open-settings` jumps straight to the Privacy
  panel.
- `--app NAME` option on `capture window` (CLI), `app_name` parameter
  on `capture_window` (MCP). Picks the frontmost window for the matching
  app — no `list_windows` round-trip needed.
- `Makefile` (`install`, `uninstall`, `wire`, `unwire`, `doctor`,
  `clean`).
- CLI `--version` flag.

## [0.1.0] — 2026-05-01

### Added
- Initial release. Swift Package, `ScreenCaptureKit`-based.
- CLI subcommands: `list`, `capture`, `serve`.
- Stdio MCP server returning inline image content blocks.
- Five MCP tools: `list_windows`, `list_displays`, `capture_window`,
  `capture_display`, `capture_region`.
