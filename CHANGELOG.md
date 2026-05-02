# Changelog

All notable changes to peek are tracked here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/).

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
