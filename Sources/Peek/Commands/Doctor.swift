import ArgumentParser
import Foundation
import ScreenCaptureKit

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check Screen Recording permission and detected MCP hosts."
    )

    @Flag(name: .long, help: "Open System Settings → Privacy → Screen Recording.")
    var openSettings = false

    func run() async {
        let line = String(repeating: "─", count: 40)
        print("peek doctor")
        print(line)
        print("Binary:  \(Bundle.main.executablePath ?? "?")")
        print("macOS:   \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print()

        let permitted = await checkScreenRecordingPermission()
        if permitted {
            print("[ok]  Screen Recording permission: granted")
        } else {
            print("[!!]  Screen Recording permission: denied")
            print()
            print("      Grant the permission to your terminal app or MCP host:")
            print("        System Settings → Privacy & Security → Screen Recording")
            print()
            print("      After granting, fully quit and reopen that app.")
            if openSettings {
                _ = try? Process.run(
                    URL(fileURLWithPath: "/usr/bin/open"),
                    arguments: ["x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"]
                )
            } else {
                print("      Re-run with `--open-settings` to jump there.")
            }
        }

        print()
        print("MCP hosts:")
        for host in MCPHost.all {
            let exists = FileManager.default.fileExists(atPath: host.configPath)
            if !exists {
                print("  [-]  \(host.name): not installed")
                continue
            }
            let installed = host.peekIsInstalled()
            let mark = installed ? "[ok]" : "[  ]"
            let suffix = installed ? "peek wired in" : "peek not yet installed"
            print("  \(mark)  \(host.name): \(suffix)")
        }
        print()
        if !MCPHost.installed.contains(where: { $0.peekIsInstalled() }) {
            print("Run `peek install` to wire peek into the hosts above.")
        }
    }

    private func checkScreenRecordingPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.current
            return true
        } catch {
            return false
        }
    }
}
