import ArgumentParser
import Foundation

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Wire peek into installed MCP hosts (Claude Code, Claude Desktop)."
    )

    @Flag(name: .long, help: "Remove peek from all detected configs.")
    var uninstall = false

    @Flag(name: .long, help: "Show what would change without writing.")
    var dryRun = false

    @Option(name: .long, help: "Path to peek binary. Defaults to the running binary.")
    var binary: String?

    func run() throws {
        let path = binary ?? Bundle.main.executablePath ?? CommandLine.arguments[0]
        let resolved = (path as NSString).expandingTildeInPath
        let hosts = MCPHost.installed

        guard !hosts.isEmpty else {
            print("No MCP-compatible hosts detected. Looked for:")
            for host in MCPHost.all {
                print("  - \(host.name): \(host.configPath)")
            }
            print("\nInstall Claude Code or Claude Desktop, then re-run `peek install`.")
            return
        }

        if !uninstall {
            print("Binary: \(resolved)")
            print()
        }

        for host in hosts {
            do {
                let change = uninstall
                    ? try host.uninstall(dryRun: dryRun)
                    : try host.install(binary: resolved, dryRun: dryRun)
                let prefix = dryRun ? "[dry-run] " : ""
                switch change {
                case .added:   print("\(prefix)added    \(host.name)  (\(host.configPath))")
                case .updated: print("\(prefix)updated  \(host.name)  (\(host.configPath))")
                case .removed: print("\(prefix)removed  \(host.name)  (\(host.configPath))")
                case .absent:  print("\(prefix)skipped  \(host.name)  (peek not present)")
                }
            } catch {
                print("error    \(host.name)  (\(error.localizedDescription))")
            }
        }

        if !uninstall && !dryRun {
            print()
            print("Restart your MCP host to load peek.")
            print("If captures fail with TCC error -3801, run `peek doctor`.")
        }
    }
}
