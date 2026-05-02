import ArgumentParser

@main
struct Peek: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "peek",
        abstract: "macOS screen capture for humans and Claude (MCP).",
        version: "0.4.5",
        subcommands: [
            // Shortcuts (most common forms first in help text)
            Windows.self, Displays.self, WindowShortcut.self, DisplayShortcut.self,
            // Verbose forms (still work, but help readers see shortcuts first)
            List.self, Capture.self,
            // Server + ops
            Serve.self, Daemon.self, Install.self, Doctor.self, Log.self
        ]
    )
}
