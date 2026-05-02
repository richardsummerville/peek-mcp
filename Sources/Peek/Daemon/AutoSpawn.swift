import Foundation
import Darwin

/// Logic for shim → daemon coordination: connect to existing daemon
/// or spawn a new detached one and wait for it to come up.
enum AutoSpawn {
    /// Try connecting to the daemon socket. Returns the connected fd
    /// on success, or nil if no daemon is listening.
    static func tryConnect() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = SocketPath.path
        let pathLength = min(path.utf8.count, MemoryLayout.size(ofValue: addr.sun_path) - 1)
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            path.withCString { src in
                _ = memcpy(dest.baseAddress, src, pathLength)
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result == 0 {
            return fd
        }
        close(fd)
        return nil
    }

    /// Spawn a fully-detached `peek daemon` process. Inherits no stdio.
    /// Logs go to the daemon's own log file (~/Library/Application Support/peek/daemon.log).
    static func spawnDaemon() throws {
        let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["daemon"]
        // Detach from parent: redirect all stdio to /dev/null + the daemon log.
        let logURL = AuditLog.directory.appendingPathComponent("daemon.log")
        try? FileManager.default.createDirectory(at: AuditLog.directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        // Don't wait — we want it detached.
    }

    /// Wait up to `timeoutSeconds` for the daemon socket to accept
    /// connections. Returns the connected fd or nil on timeout.
    static func waitForDaemon(timeoutSeconds: Double = 3.0) -> Int32? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let fd = tryConnect() { return fd }
            usleep(50_000)  // 50ms
        }
        return nil
    }

    /// One-shot: connect to existing daemon, or spawn one and connect.
    static func connectOrSpawn() throws -> Int32 {
        if let fd = tryConnect() { return fd }
        try spawnDaemon()
        guard let fd = waitForDaemon() else {
            throw POSIXError(.ETIMEDOUT, message: "daemon failed to come up after spawn")
        }
        return fd
    }
}
