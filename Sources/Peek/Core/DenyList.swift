import Foundation

/// Sensible-default + user-overridable list of apps that peek refuses to
/// capture. Defends against the most common accident: a sensitive
/// window (1Password, banking, Keychain) sitting underneath the one
/// you actually want.
///
/// Window captures (by id or app name) consult the deny-list. Display
/// and region captures do not — those are explicitly chosen by the
/// caller, not pattern-matched.
struct DenyList: Codable {
    /// Bundle IDs that are denied outright. Substring-matched so that
    /// app-suite variants (e.g. `com.1password.1password7`) all hit.
    var bundleIDPatterns: [String]

    /// App-name patterns, matched as case-insensitive substrings of the
    /// owning application name.
    var appNamePatterns: [String]

    static let defaults = DenyList(
        bundleIDPatterns: [
            "com.1password.",
            "com.agilebits.onepassword",
            "com.apple.keychainaccess",
        ],
        appNamePatterns: [
            "1Password",
            "Keychain Access",
        ]
    )

    static var userFile: URL {
        AuditLog.directory.appendingPathComponent("denylist.json")
    }

    /// Load user overrides if present, then merge with defaults.
    /// User-supplied entries are additive — defaults are never removed
    /// (the deny-list errs on the side of safety).
    static func current() -> DenyList {
        var merged = defaults
        if let data = try? Data(contentsOf: userFile),
           let user = try? JSONDecoder().decode(DenyList.self, from: data) {
            merged.bundleIDPatterns = Array(Set(merged.bundleIDPatterns + user.bundleIDPatterns))
            merged.appNamePatterns = Array(Set(merged.appNamePatterns + user.appNamePatterns))
        }
        return merged
    }

    /// Returns a human-readable reason if the window is denied, else nil.
    func denies(window: WindowInfo) -> String? {
        if let bid = window.bundleID?.lowercased() {
            for pattern in bundleIDPatterns where bid.contains(pattern.lowercased()) {
                return "bundle id \(bid) matches deny pattern \"\(pattern)\""
            }
        }
        let app = window.app.lowercased()
        for pattern in appNamePatterns where app.contains(pattern.lowercased()) {
            return "app name \"\(window.app)\" matches deny pattern \"\(pattern)\""
        }
        return nil
    }
}

enum DenyError: LocalizedError {
    case denied(target: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .denied(let target, let reason):
            return "Refusing to capture \(target) — \(reason). Use --force (CLI) or force: true (MCP) to override."
        }
    }
}
