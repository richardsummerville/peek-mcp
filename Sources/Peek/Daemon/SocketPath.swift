import Foundation

/// Where the daemon's Unix socket lives. Shared between daemon (binds)
/// and shim (connects). Lives next to the audit log so cleanup is
/// obvious.
enum SocketPath {
    static var url: URL {
        AuditLog.directory.appendingPathComponent("daemon.sock")
    }

    static var path: String { url.path }
}
