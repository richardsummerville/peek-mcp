import Foundation

struct MCPHost {
    let name: String
    let configPath: String

    static let claudeCode = MCPHost(
        name: "Claude Code",
        configPath: (NSString("~/.claude.json").expandingTildeInPath as String)
    )

    static let claudeDesktop = MCPHost(
        name: "Claude Desktop",
        configPath: (NSString("~/Library/Application Support/Claude/claude_desktop_config.json").expandingTildeInPath as String)
    )

    static let all: [MCPHost] = [.claudeCode, .claudeDesktop]

    static var installed: [MCPHost] {
        all.filter { FileManager.default.fileExists(atPath: $0.configPath) }
    }

    func peekIsInstalled() -> Bool {
        guard let json = try? readConfig(),
              let servers = json["mcpServers"] as? [String: Any]
        else { return false }
        return servers["peek"] != nil
    }

    func install(binary: String, dryRun: Bool) throws -> InstallChange {
        try mutate(dryRun: dryRun) { json in
            var servers = (json["mcpServers"] as? [String: Any]) ?? [:]
            let existing = servers["peek"] as? [String: Any]
            servers["peek"] = ["command": binary, "args": ["serve"]]
            json["mcpServers"] = servers
            return existing == nil ? .added : .updated
        }
    }

    func uninstall(dryRun: Bool) throws -> InstallChange {
        try mutate(dryRun: dryRun) { json in
            guard var servers = json["mcpServers"] as? [String: Any],
                  servers["peek"] != nil else { return .absent }
            servers.removeValue(forKey: "peek")
            if servers.isEmpty {
                json.removeValue(forKey: "mcpServers")
            } else {
                json["mcpServers"] = servers
            }
            return .removed
        }
    }

    private func readConfig() throws -> [String: Any] {
        let url = URL(fileURLWithPath: configPath)
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HostError.notJSONObject(configPath)
        }
        return json
    }

    private func mutate(
        dryRun: Bool,
        _ body: (inout [String: Any]) -> InstallChange
    ) throws -> InstallChange {
        var json = try readConfig()
        let change = body(&json)
        guard change != .absent, !dryRun else { return change }
        let updated = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        let url = URL(fileURLWithPath: configPath)
        try updated.write(to: url, options: .atomic)
        return change
    }
}

enum InstallChange { case added, updated, removed, absent }

enum HostError: LocalizedError {
    case notJSONObject(String)
    var errorDescription: String? {
        switch self {
        case .notJSONObject(let path): return "Not a JSON object: \(path)"
        }
    }
}
