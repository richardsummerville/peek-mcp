import ArgumentParser
import Foundation

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List visible windows or attached displays.",
        subcommands: [Windows.self, Displays.self]
    )

    struct Windows: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "windows",
            abstract: "List visible windows as JSON."
        )

        @Flag(name: .long, help: "Include offscreen windows.")
        var includeOffscreen = false

        @Option(name: .shortAndLong, help: "Filter by app name (case-insensitive substring).")
        var app: String?

        func run() async throws {
            var windows = try await ScreenCapture.listWindows(includeOffscreen: includeOffscreen)
            if let needle = app?.lowercased() {
                windows = windows.filter { $0.app.lowercased().contains(needle) }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(windows)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0a]))
        }
    }

    struct Displays: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "displays",
            abstract: "List attached displays as JSON."
        )

        func run() async throws {
            let displays = try await ScreenCapture.listDisplays()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(displays)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0a]))
        }
    }
}
