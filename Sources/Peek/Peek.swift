import ArgumentParser

@main
struct Peek: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "peek",
        abstract: "macOS screen capture for humans and Claude (MCP).",
        version: "0.3.0",
        subcommands: [List.self, Capture.self, Serve.self, Daemon.self, Install.self, Doctor.self, Log.self]
    )
}
