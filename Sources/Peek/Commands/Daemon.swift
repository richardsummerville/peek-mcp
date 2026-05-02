import AppKit
import ArgumentParser
import Foundation

/// Long-running peek daemon. Owns:
///   - The Unix socket that shims connect to.
///   - The single menu-bar status item.
///   - The AppKit run loop (so menu-bar UI works).
///
/// Exits cleanly when the user clicks "Kill peek" in the menu, or
/// when the process is sent SIGTERM.
struct Daemon: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Run the peek daemon (single-instance background service for shims)."
    )

    @Flag(name: .long, help: "Suppress the menu-bar indicator (headless daemon).")
    var noMenuBar: Bool = false

    func run() throws {
        // Refuse to start a second daemon — protects against accidental
        // double-launch by detecting an existing socket connection.
        if AutoSpawn.tryConnect() != nil {
            FileHandle.standardError.write(
                "peek daemon already running (socket at \(SocketPath.path) is live).\n".data(using: .utf8)!
            )
            throw ExitCode(2)
        }

        let server = UnixSocketServer(path: SocketPath.path)
        do {
            try server.bindAndListen()
        } catch {
            FileHandle.standardError.write(
                "peek daemon: failed to bind \(SocketPath.path): \(error.localizedDescription)\n".data(using: .utf8)!
            )
            throw ExitCode(1)
        }

        let showMenuBar = !noMenuBar
        let sem = DispatchSemaphore(value: 0)

        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.accessory)
            if showMenuBar {
                MenuBarController.shared.install()
            }

            // Accept loop runs in background.
            Task.detached(priority: .userInitiated) {
                await server.acceptLoop()
            }

            // Block main thread on AppKit event loop until kill switch.
            NSApplication.shared.run()
            sem.signal()
        }

        sem.wait()

        // Clean up socket file on graceful exit.
        try? FileManager.default.removeItem(atPath: SocketPath.path)
    }
}
