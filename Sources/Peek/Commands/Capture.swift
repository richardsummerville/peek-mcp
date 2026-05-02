import ArgumentParser
import Foundation

struct Capture: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Capture a window, display, or region.",
        subcommands: [Window.self, Display.self, Region.self]
    )

    struct CommonOptions: ParsableArguments {
        @Option(name: .shortAndLong, help: "Output PNG path. If omitted, writes PNG bytes to stdout (or opens in Preview with --show).")
        var output: String?

        @Flag(name: .long, inversion: .prefixedNo, help: "Hide the mouse cursor in the capture (default: hide).")
        var hideCursor: Bool = true

        @Flag(name: .long, help: "Open the capture in Preview after writing. Combine with --output to keep the file; without --output, writes to a tempfile and opens it.")
        var show: Bool = false
    }

    struct Window: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "window",
            abstract: "Capture a specific window by ID or app name."
        )

        @Option(name: [.short, .customLong("id")], help: "Window ID (from `peek list windows`).")
        var windowID: UInt32?

        @Option(name: [.short, .customLong("app")], help: "App name (case-insensitive substring). Picks the frontmost matching window.")
        var app: String?

        @OptionGroup var common: CommonOptions

        @Flag(name: .long, help: "Bypass the deny-list (1Password, Keychain, etc.).")
        var force: Bool = false

        func validate() throws {
            if windowID == nil && (app == nil || app?.isEmpty == true) {
                throw ValidationError("Provide --id <window-id> or --app <name>.")
            }
        }

        func run() async throws {
            let result: (data: Data, mimeType: String)
            if let wid = windowID {
                result = try await ScreenCapture.captureWindow(
                    id: wid, hideCursor: common.hideCursor, caller: .cli, force: force
                )
            } else {
                result = try await ScreenCapture.captureWindow(
                    byApp: app!, hideCursor: common.hideCursor, caller: .cli, force: force
                )
            }
            try writeOutput(result.data, path: common.output, show: common.show)
        }
    }

    struct Display: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "display",
            abstract: "Capture an entire display (defaults to primary)."
        )

        @Option(name: [.short, .customLong("id")], help: "Display ID (from `peek list displays`). Defaults to primary.")
        var displayID: UInt32?

        @OptionGroup var common: CommonOptions

        func run() async throws {
            let result = try await ScreenCapture.captureDisplay(
                id: displayID, hideCursor: common.hideCursor, caller: .cli
            )
            try writeOutput(result.data, path: common.output, show: common.show)
        }
    }

    struct Region: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "region",
            abstract: "Capture a rectangular region in display points."
        )

        @Option(name: .short) var x: Int
        @Option(name: .short) var y: Int
        @Option(name: [.short, .customLong("width")]) var width: Int
        @Option(name: [.short, .customLong("height")]) var height: Int

        @Option(name: .long, help: "Display ID. Defaults to primary.")
        var displayID: UInt32?

        @OptionGroup var common: CommonOptions

        func run() async throws {
            let result = try await ScreenCapture.captureRegion(
                x: x, y: y, width: width, height: height,
                displayID: displayID,
                hideCursor: common.hideCursor,
                caller: .cli
            )
            try writeOutput(result.data, path: common.output, show: common.show)
        }
    }
}

func writeOutput(_ png: Data, path: String?, show: Bool) throws {
    let resolvedPath: String?
    if let path = path {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try png.write(to: url)
        FileHandle.standardError.write("Wrote \(png.count) bytes to \(url.path)\n".data(using: .utf8)!)
        resolvedPath = url.path
    } else if show {
        let tmp = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("peek-\(Int(Date().timeIntervalSince1970)).png")
        let url = URL(fileURLWithPath: tmp)
        try png.write(to: url)
        FileHandle.standardError.write("Wrote \(png.count) bytes to \(url.path)\n".data(using: .utf8)!)
        resolvedPath = url.path
    } else {
        FileHandle.standardOutput.write(png)
        resolvedPath = nil
    }
    if show, let p = resolvedPath {
        let proc = Process()
        proc.launchPath = "/usr/bin/open"
        proc.arguments = [p]
        try proc.run()
    }
}
