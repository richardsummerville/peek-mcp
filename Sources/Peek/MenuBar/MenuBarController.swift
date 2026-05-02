import AppKit
import Foundation

/// Lightweight record shown in the menu-bar history.
struct CaptureRecord: Sendable {
    let ts: Date
    let kind: String
    let app: String?
    let bytes: Int?
    let denied: Bool
}

/// Bridges capture events from the stdio MCP server (background task) to
/// the AppKit menu bar (main thread). Sendable because captures arrive
/// from arbitrary actor contexts.
@MainActor
final class MenuBarController {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var lastCaptureItem: NSMenuItem?
    private var historySeparator: NSMenuItem?
    private var historyItems: [NSMenuItem] = []
    private var refreshTimer: Timer?

    private var recent: [CaptureRecord] = []
    private let maxHistory = 5

    private init() {}

    /// Install the status item and start the refresh ticker. Idempotent.
    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "peek")
            button.image?.isTemplate = true
        }
        item.menu = buildMenu()
        statusItem = item

        // Refresh "X ago" labels once a second.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLastCaptureItem() }
        }
        if let t = refreshTimer { RunLoop.main.add(t, forMode: .common) }
    }

    /// Nonisolated entry point for capture-event recording. Callable
    /// from any actor / queue. Hops to main internally.
    nonisolated static func record(_ record: CaptureRecord) {
        Task { @MainActor in
            shared.append(record)
        }
    }

    private func append(_ record: CaptureRecord) {
        recent.insert(record, at: 0)
        if recent.count > maxHistory { recent.removeLast() }
        rebuildHistory()
        refreshLastCaptureItem()
        flashIcon(denied: record.denied)
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false

        let header = NSMenuItem(title: "peek 0.3.0", action: nil, keyEquivalent: "")
        header.isEnabled = false
        m.addItem(header)

        m.addItem(.separator())

        let lastCapture = NSMenuItem(title: "Last capture: —", action: nil, keyEquivalent: "")
        lastCapture.isEnabled = false
        m.addItem(lastCapture)
        lastCaptureItem = lastCapture

        let sep = NSMenuItem.separator()
        m.addItem(sep)
        historySeparator = sep

        // History items get inserted between historySeparator and the
        // bottom-of-menu fixed items. Build the bottom items first.
        let openLog = NSMenuItem(
            title: "Open audit log",
            action: #selector(openAuditLog),
            keyEquivalent: ""
        )
        openLog.target = self
        m.addItem(openLog)

        let openSettings = NSMenuItem(
            title: "Screen Recording Settings…",
            action: #selector(openScreenRecordingSettings),
            keyEquivalent: ""
        )
        openSettings.target = self
        m.addItem(openSettings)

        m.addItem(.separator())

        let killItem = NSMenuItem(
            title: "Kill peek (stop captures now)",
            action: #selector(quitServe),
            keyEquivalent: "k"
        )
        killItem.target = self
        // Highlight the kill switch in the menu by giving it bold text.
        killItem.attributedTitle = NSAttributedString(
            string: killItem.title,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0).bold(),
                .foregroundColor: NSColor.systemRed
            ]
        )
        m.addItem(killItem)

        // Standard Cmd-Q also kills, for muscle memory.
        let quit = NSMenuItem(
            title: "Quit peek serve",
            action: #selector(quitServe),
            keyEquivalent: "q"
        )
        quit.target = self
        quit.isHidden = true
        quit.allowsKeyEquivalentWhenHidden = true
        m.addItem(quit)

        menu = m
        return m
    }

    private func rebuildHistory() {
        guard let menu, let separator = historySeparator else { return }
        // Strip old history items
        for item in historyItems { menu.removeItem(item) }
        historyItems.removeAll()
        // Insert each recent capture immediately after the historySeparator
        let insertIndex = menu.index(of: separator) + 1
        for (offset, rec) in recent.enumerated() {
            let item = NSMenuItem(title: format(rec, includeRelative: false), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.insertItem(item, at: insertIndex + offset)
            historyItems.append(item)
        }
    }

    private func refreshLastCaptureItem() {
        guard let lastCaptureItem else { return }
        if let last = recent.first {
            lastCaptureItem.title = "Last: " + format(last, includeRelative: true)
        } else {
            lastCaptureItem.title = "Last capture: —"
        }
    }

    private func format(_ record: CaptureRecord, includeRelative: Bool) -> String {
        let app = record.app ?? record.kind.replacingOccurrences(of: "capture_", with: "")
        let prefix = record.denied ? "denied · " : ""
        if includeRelative {
            return "\(prefix)\(app) · \(relativeTimeString(from: record.ts))"
        }
        return "\(prefix)\(app) · \(absoluteTimeString(from: record.ts))"
    }

    private func relativeTimeString(from date: Date) -> String {
        let interval = max(0, Int(Date().timeIntervalSince(date)))
        if interval < 60 { return "\(interval)s ago" }
        let mins = interval / 60
        if mins < 60 { return "\(mins)m ago" }
        let hours = mins / 60
        return "\(hours)h ago"
    }

    private func absoluteTimeString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    private func flashIcon(denied: Bool) {
        guard let button = statusItem?.button else { return }
        let symbol = denied ? "eye.slash.fill" : "eye.fill"
        let original = NSImage(systemSymbolName: "eye", accessibilityDescription: "peek")
        original?.isTemplate = true
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "peek")
        button.image?.isTemplate = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            button.image = original
        }
    }

    @objc private func openAuditLog() {
        NSWorkspace.shared.open(AuditLog.path)
    }

    @objc private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitServe() {
        NSApp.terminate(nil)
    }
}

private extension NSFont {
    func bold() -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.bold)
        return NSFont(descriptor: descriptor, size: 0) ?? self
    }
}
