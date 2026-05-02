import AppKit
import ArgumentParser
import Foundation
import Darwin

/// `peek serve` is what MCP host configs point to. By default it runs
/// in *shim* mode: connects to the singleton `peek daemon` (auto-
/// spawning it if not running) and forwards stdio JSON-RPC traffic
/// bidirectionally. `--standalone` falls back to the previous all-in-
/// one behavior (stdio MCP server with its own menu bar — useful for
/// debugging or when daemon mode misbehaves).
struct Serve: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run as an MCP server over stdio (shim by default; --standalone for all-in-one)."
    )

    @Flag(name: .long, help: "Run as a standalone MCP server instead of a shim to the daemon. Each instance brings its own menu bar.")
    var standalone: Bool = false

    @Flag(name: .long, help: "(Standalone only) Suppress the menu-bar indicator.")
    var noMenuBar: Bool = false

    func run() throws {
        if standalone {
            try runStandalone()
        } else {
            try runShim()
        }
    }

    // MARK: - Shim mode (default)

    private func runShim() throws {
        let socketFD: Int32
        do {
            socketFD = try AutoSpawn.connectOrSpawn()
        } catch {
            FileHandle.standardError.write(
                "peek serve: failed to reach daemon: \(error.localizedDescription)\n".data(using: .utf8)!
            )
            throw ExitCode(1)
        }
        defer { close(socketFD) }

        // Bidirectional pump: stdin → socket, socket → stdout.
        // We exit when *either* side closes, which happens when the
        // host disconnects (stdin EOF) or the daemon shuts down.
        let group = DispatchGroup()
        let queueIn = DispatchQueue(label: "peek.shim.stdin")
        let queueOut = DispatchQueue(label: "peek.shim.daemon")

        group.enter()
        queueIn.async {
            defer { group.leave() }
            pump(from: STDIN_FILENO, to: socketFD)
            // stdin EOF — half-close so daemon sees EOF and stops
            // reading, but its already-queued responses still flow
            // back through our read direction. SHUT_RDWR would race
            // and drop pending responses.
            shutdown(socketFD, SHUT_WR)
        }

        group.enter()
        queueOut.async {
            defer { group.leave() }
            pump(from: socketFD, to: STDOUT_FILENO)
        }

        group.wait()
    }

    private func pump(from src: Int32, to dst: Int32) {
        let bufSize = 4096
        var buf = [UInt8](repeating: 0, count: bufSize)
        while true {
            let n = buf.withUnsafeMutableBufferPointer { ptr in
                Darwin.read(src, ptr.baseAddress, bufSize)
            }
            if n <= 0 { return }
            var written = 0
            while written < n {
                let w = buf.withUnsafeBufferPointer { ptr in
                    Darwin.write(dst, ptr.baseAddress?.advanced(by: written), n - written)
                }
                if w <= 0 { return }
                written += w
            }
        }
    }

    // MARK: - Standalone mode (legacy / debug)

    private func runStandalone() throws {
        // Re-implement the previous in-process AppKit + MCP loop.
        let showMenuBar = !noMenuBar
        let sem = DispatchSemaphore(value: 0)

        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.accessory)
            if showMenuBar, MenuBarLock.tryAcquire() {
                MenuBarController.shared.install()
            }

            Task.detached(priority: .userInitiated) {
                await MCPServer().run()
                await MainActor.run { NSApp.terminate(nil) }
            }

            NSApplication.shared.run()
            sem.signal()
        }

        sem.wait()
    }
}
