import ArgumentParser
import Foundation

/// Top-level shortcut subcommands. The verbose `peek list windows` and
/// `peek capture window --app …` forms still work; these wrappers exist
/// because `peek windows` and `peek window Safari` are what people
/// actually type.

struct Windows: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "windows",
        abstract: "List visible windows (shortcut for `peek list windows`)."
    )

    @Flag(name: .long, help: "Include offscreen / minimized windows.")
    var includeOffscreen = false

    @Option(name: .shortAndLong, help: "Filter by app name (case-insensitive substring).")
    var app: String?

    func run() async throws {
        var inner = List.Windows()
        inner.includeOffscreen = includeOffscreen
        inner.app = app
        try await inner.run()
    }
}

struct Displays: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "displays",
        abstract: "List attached displays (shortcut for `peek list displays`)."
    )

    func run() async throws {
        try await List.Displays().run()
    }
}

struct WindowShortcut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "window",
        abstract: "Capture a window by app name (shortcut for `peek capture window --app …`)."
    )

    @Argument(help: "App name (case-insensitive substring). Picks the frontmost matching window.")
    var app: String

    @Option(name: .shortAndLong, help: "Output PNG path. If omitted, writes bytes to stdout (or opens in Preview with --show).")
    var output: String?

    @Flag(name: .long, inversion: .prefixedNo, help: "Hide the mouse cursor (default: hide).")
    var hideCursor: Bool = true

    @Flag(name: .long, help: "Bypass the deny-list (sensitive apps refuse capture by default).")
    var force: Bool = false

    @Flag(name: .long, help: "Open the capture in Preview after writing.")
    var show: Bool = false

    func run() async throws {
        let result = try await ScreenCapture.captureWindow(
            byApp: app, hideCursor: hideCursor, caller: .cli, force: force
        )
        try writeOutput(result.data, path: output, show: show)
    }
}

struct DisplayShortcut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "display",
        abstract: "Capture a display (shortcut for `peek capture display`)."
    )

    @Option(name: [.short, .customLong("id")], help: "Display ID. Defaults to primary.")
    var displayID: UInt32?

    @Option(name: .shortAndLong, help: "Output PNG path. If omitted, writes bytes to stdout (or opens in Preview with --show).")
    var output: String?

    @Flag(name: .long, inversion: .prefixedNo, help: "Hide the mouse cursor (default: hide).")
    var hideCursor: Bool = true

    @Flag(name: .long, help: "Open the capture in Preview after writing.")
    var show: Bool = false

    func run() async throws {
        let result = try await ScreenCapture.captureDisplay(
            id: displayID, hideCursor: hideCursor, caller: .cli
        )
        try writeOutput(result.data, path: output, show: show)
    }
}
