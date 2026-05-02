import AppKit
import ArgumentParser
import Foundation

/// MCP server entry point. Brings up an AppKit event loop on the main
/// thread (so the menu bar UI works), runs the MCP stdio loop on a
/// background task, and exits cleanly when either the host disconnects
/// (stdio EOF) or the user clicks the kill switch.
struct Serve: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run as an MCP server over stdio (with menu-bar indicator)."
    )

    @Flag(name: .long, help: "Suppress the menu-bar indicator (headless mode).")
    var noMenuBar: Bool = false

    func run() throws {
        let showMenuBar = !noMenuBar
        let sem = DispatchSemaphore(value: 0)

        // We're called from ArgumentParser's async dispatch on a
        // cooperative thread, but NSApp.run() must execute on the OS
        // main thread. Push the whole AppKit lifecycle onto main and
        // block here until it returns.
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.accessory)
            if showMenuBar {
                MenuBarController.shared.install()
            }

            // MCP stdio loop runs in the background. When it exits
            // (host disconnect / EOF on stdin), we terminate NSApp so
            // the process can wind down.
            Task.detached(priority: .userInitiated) {
                await MCPServer().run()
                await MainActor.run { NSApp.terminate(nil) }
            }

            // Blocks main until NSApp.terminate(_:) is called either
            // by the kill switch or by the MCP loop's exit path above.
            NSApplication.shared.run()
            sem.signal()
        }

        sem.wait()
    }
}
