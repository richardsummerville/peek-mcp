import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// File-based singleton lock for the menu-bar status item.
///
/// Multiple `peek serve` subprocesses can run at once (Claude Code,
/// Claude Desktop, multiple sessions). Without this lock each would
/// install its own NSStatusItem and the user would see 2-3 eye icons.
///
/// First peek serve to start acquires an exclusive `flock` on
/// `~/Library/Application Support/peek/menubar.lock`. Subsequent
/// instances detect the lock is held and run headless (still serving
/// MCP — just no menu bar). When the lock-holding instance exits, the
/// kernel auto-releases the flock; the next instance to spawn (or
/// the next time someone restarts) wins it.
enum MenuBarLock {
    nonisolated(unsafe) private static var heldHandle: FileHandle?

    /// Attempt to acquire the singleton lock. Returns true if this
    /// instance now owns the menu bar. The handle is retained on
    /// success so the lock survives until process exit.
    static func tryAcquire() -> Bool {
        let url = AuditLog.directory.appendingPathComponent("menubar.lock")

        try? FileManager.default.createDirectory(
            at: AuditLog.directory,
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        guard let handle = try? FileHandle(forUpdating: url) else {
            return false
        }

        let result = flock(handle.fileDescriptor, LOCK_EX | LOCK_NB)
        if result == 0 {
            heldHandle = handle  // retain so the fd lives until exit
            return true
        }

        try? handle.close()
        return false
    }
}
