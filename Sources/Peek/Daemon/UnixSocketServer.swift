import Foundation
import Darwin

/// POSIX Unix domain socket server. Accepts JSON-RPC line-framed
/// connections from peek shims (one per MCP host) and dispatches to
/// the shared MCPServer. Permissions on the socket file are 0600 so
/// only the current user can connect — important since "anyone with
/// access can capture your screen" via this transport.
///
/// `@unchecked Sendable`: `listenFD` is mutated only during
/// `bindAndListen()` (called once from a single thread before
/// `acceptLoop()` starts) and the underlying file descriptor is
/// kernel-managed.
final class UnixSocketServer: @unchecked Sendable {
    private let socketPath: String
    private var listenFD: Int32 = -1
    private let server = MCPServer()

    init(path: String) {
        self.socketPath = path
    }

    func bindAndListen() throws {
        try? FileManager.default.removeItem(atPath: socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO, message: "socket()") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathLength = min(socketPath.utf8.count, MemoryLayout.size(ofValue: addr.sun_path) - 1)
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            socketPath.withCString { src in
                _ = memcpy(dest.baseAddress, src, pathLength)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE, message: "bind(\(socketPath))")
        }

        chmod(socketPath, S_IRUSR | S_IWUSR)

        guard Darwin.listen(fd, 8) == 0 else {
            close(fd)
            throw POSIXError(.EIO, message: "listen()")
        }

        listenFD = fd
    }

    func acceptLoop() async {
        let listenFDLocal = listenFD
        let serverLocal = server
        while true {
            let clientFD = accept(listenFDLocal, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                if errno == EBADF { return }
                continue
            }
            Task.detached {
                await UnixSocketServer.handleConnection(fd: clientFD, server: serverLocal)
            }
        }
    }

    static func handleConnection(fd: Int32, server: MCPServer) async {
        defer { close(fd) }

        var buffer = Data()
        let chunkSize = 4096
        while true {
            var chunk = [UInt8](repeating: 0, count: chunkSize)
            let n = chunk.withUnsafeMutableBufferPointer { ptr in
                Darwin.read(fd, ptr.baseAddress, chunkSize)
            }
            if n <= 0 { return }
            buffer.append(contentsOf: chunk.prefix(n))

            while let nlIndex = buffer.firstIndex(of: 0x0a) {
                let lineData = buffer[..<nlIndex]
                buffer.removeSubrange(...nlIndex)
                if lineData.isEmpty { continue }
                guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    continue
                }
                if let response = await server.handle(request: json) {
                    guard var respData = try? JSONSerialization.data(withJSONObject: response) else { continue }
                    respData.append(0x0a)
                    respData.withUnsafeBytes { ptr in
                        _ = Darwin.write(fd, ptr.baseAddress, respData.count)
                    }
                }
            }
        }
    }
}

struct POSIXError: LocalizedError {
    let code: POSIXErrorCode
    let message: String
    init(_ code: POSIXErrorCode, message: String = "") {
        self.code = code
        self.message = message
    }
    var errorDescription: String? {
        message.isEmpty ? "POSIX error \(code.rawValue)" : "\(message): \(String(cString: strerror(code.rawValue)))"
    }
}
