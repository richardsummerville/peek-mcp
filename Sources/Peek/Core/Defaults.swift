import Foundation

/// User-configurable defaults driven by the `PEEK_QUALITY` env var.
/// Read once at process start (Swift `static let` is lazy + thread-safe).
///
/// Override per-MCP-host by adding `env: { "PEEK_QUALITY": "lossless" }`
/// to the mcpServers entry in your host config. Override per-shell
/// session with `export PEEK_QUALITY=fast` in ~/.zshrc. Per-call
/// override still works via the MCP `format` parameter.
enum QualityPreset: String, Sendable {
    case fast
    case balanced
    case lossless

    static let current: QualityPreset = {
        guard let raw = ProcessInfo.processInfo.environment["PEEK_QUALITY"]?.lowercased(),
              let preset = QualityPreset(rawValue: raw) else {
            return .lossless
        }
        return preset
    }()

    /// Output format the preset implies.
    var format: ScreenCapture.OutputFormat {
        switch self {
        case .fast:     return .jpeg(quality: 0.5)
        case .balanced: return .jpeg(quality: 0.7)
        case .lossless: return .png
        }
    }

    /// Cap on the longest output dimension (pixels).
    var maxOutputDimension: Double {
        switch self {
        case .fast:     return 768
        case .balanced: return 1024
        case .lossless: return 2048
        }
    }

    /// Human-readable summary for `peek doctor`.
    var summary: String {
        switch self {
        case .fast:     return "fast — JPEG q=0.5, 768 px cap"
        case .balanced: return "balanced — JPEG q=0.7, 1024 px cap"
        case .lossless: return "lossless — PNG, 2048 px cap (default)"
        }
    }
}
