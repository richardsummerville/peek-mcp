import Foundation

/// Caller context for audit entries.
enum Caller: String, Codable, Sendable {
    case cli, mcp
}

/// One line in the audit log.
struct AuditEntry: Codable {
    let ts: String
    let kind: String
    let caller: String
    let app: String?
    let windowId: UInt32?
    let displayId: UInt32?
    let region: Bounds?
    let bytes: Int?
    let denyReason: String?

    init(
        kind: String,
        caller: Caller,
        app: String? = nil,
        windowId: UInt32? = nil,
        displayId: UInt32? = nil,
        region: Bounds? = nil,
        bytes: Int? = nil,
        denyReason: String? = nil
    ) {
        self.ts = ISO8601DateFormatter.string(
            from: Date(),
            timeZone: .gmt,
            formatOptions: [.withInternetDateTime, .withFractionalSeconds]
        )
        self.kind = kind
        self.caller = caller.rawValue
        self.app = app
        self.windowId = windowId
        self.displayId = displayId
        self.region = region
        self.bytes = bytes
        self.denyReason = denyReason
    }
}

/// Append-only JSONL audit log. Logs every capture (or denial), nothing
/// else — list_windows / list_displays don't carry privacy weight.
enum AuditLog {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("peek", isDirectory: true)
    }

    static var path: URL {
        directory.appendingPathComponent("log.jsonl")
    }

    /// Best-effort append. Audit failures must not break captures —
    /// silently swallow any IO error after a single stderr breadcrumb.
    static func record(_ entry: AuditEntry) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(entry)
            data.append(0x0a)  // newline
            if FileManager.default.fileExists(atPath: path.path) {
                let handle = try FileHandle(forWritingTo: path)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: path, options: .atomic)
            }
        } catch {
            FileHandle.standardError.write(
                "peek: audit log write failed: \(error.localizedDescription)\n".data(using: .utf8)!
            )
        }
    }

    /// Last N lines, oldest first. Returns empty if the log doesn't exist.
    static func tail(lines: Int) throws -> [String] {
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        let text = try String(contentsOf: path, encoding: .utf8)
        let all = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return Array(all.suffix(max(0, lines)))
    }

    static func clear() throws {
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        try FileManager.default.removeItem(at: path)
    }
}
