import ArgumentParser
import Foundation

struct Log: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect the local capture audit log.",
        subcommands: [Tail.self, Path.self, Clear.self]
    )

    struct Tail: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "tail",
            abstract: "Print the last N entries (oldest first)."
        )

        @Option(name: [.customShort("n"), .long], help: "Number of entries.")
        var lines: Int = 20

        func run() async throws {
            let entries = try AuditLog.tail(lines: lines)
            if entries.isEmpty {
                FileHandle.standardError.write("(audit log is empty)\n".data(using: .utf8)!)
                return
            }
            for line in entries {
                print(line)
            }
        }
    }

    struct Path: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "path",
            abstract: "Print the audit log file path."
        )

        func run() async throws {
            print(AuditLog.path.path)
        }
    }

    struct Clear: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Delete the audit log."
        )

        @Flag(name: .long, help: "Required to confirm — protects against accidental wipes.")
        var yes = false

        func run() async throws {
            guard yes else {
                throw ValidationError("Pass --yes to confirm. The log lives at: \(AuditLog.path.path)")
            }
            try AuditLog.clear()
            FileHandle.standardError.write("Cleared \(AuditLog.path.path)\n".data(using: .utf8)!)
        }
    }
}
