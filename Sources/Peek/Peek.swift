import ArgumentParser

@main
struct Peek: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "peek",
        abstract: "macOS screen capture for humans and Claude (MCP).",
        subcommands: [List.self, Capture.self, Serve.self]
    )
}
