import Foundation
import ScreenCaptureKit
import CoreGraphics
import AppKit

struct WindowInfo: Codable {
    let id: UInt32
    let title: String
    let app: String
    let bundleID: String?
    let bounds: Bounds
    let onScreen: Bool
    let layer: Int
}

struct DisplayInfo: Codable {
    let id: UInt32
    let widthPx: Int
    let heightPx: Int
    let frame: Bounds
    let scale: Double
}

struct Bounds: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }
}

enum CaptureError: LocalizedError {
    case windowNotFound(UInt32)
    case windowNotFoundByApp(String)
    case displayNotFound
    case noDisplays
    case invalidRegion
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .windowNotFound(let id): return "Window not found: \(id)"
        case .windowNotFoundByApp(let app): return "No on-screen window found for app: \(app)"
        case .displayNotFound: return "Display not found"
        case .noDisplays: return "No displays available"
        case .invalidRegion: return "Region must have positive width and height"
        case .encodingFailed: return "Failed to encode image as PNG"
        }
    }
}

enum ScreenCapture {
    /// Output dimensions are capped at this on the longest side. Claude's
    /// vision pipeline downsamples anything larger before processing, so
    /// shipping more pixels just wastes encode + transport + model time.
    /// 1568 matches Anthropic's documented effective max input dimension.
    static let maxOutputDimension: Double = 1568

    /// Scale factor to apply to a native (width, height) so the longer
    /// side is at most `maxOutputDimension`. Returns 1.0 if already fits.
    private static func capScale(width: Double, height: Double) -> Double {
        let longest = max(width, height)
        return longest <= maxOutputDimension ? 1.0 : maxOutputDimension / longest
    }

    /// Bootstraps the AppKit/CoreGraphics connection to the WindowServer.
    /// Required for SCScreenshotManager.captureImage when running as a
    /// pure CLI binary — without this, captures abort with
    /// `CGS_REQUIRE_INIT` (CGInitialization.c).
    ///
    /// Daemon mode initializes NSApp during startup and calls
    /// `markBootstrapped()` so the per-capture path can skip the hop
    /// entirely. CLI mode does the hop on first capture.
    ///
    /// Hop uses DispatchQueue.main.async (which AppKit's NSApp.run
    /// loop reliably pumps) rather than MainActor.run (which can
    /// deadlock inside the AppKit event loop).
    nonisolated(unsafe) private static var bootstrapped = false

    static func markBootstrapped() {
        bootstrapped = true
    }

    private static func bootstrap() async {
        if bootstrapped { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if Thread.isMainThread {
                _ = NSApplication.shared
                bootstrapped = true
                cont.resume()
            } else {
                DispatchQueue.main.async {
                    _ = NSApplication.shared
                    Self.bootstrapped = true
                    cont.resume()
                }
            }
        }
    }

    static func listWindows(includeOffscreen: Bool = false) async throws -> [WindowInfo] {
        await bootstrap()
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: !includeOffscreen
        )
        return content.windows.map { w in
            WindowInfo(
                id: w.windowID,
                title: w.title ?? "",
                app: w.owningApplication?.applicationName ?? "Unknown",
                bundleID: w.owningApplication?.bundleIdentifier,
                bounds: Bounds(w.frame),
                onScreen: w.isOnScreen,
                layer: w.windowLayer
            )
        }
    }

    static func listDisplays() async throws -> [DisplayInfo] {
        await bootstrap()
        let content = try await SCShareableContent.current
        return content.displays.map { d in
            DisplayInfo(
                id: d.displayID,
                widthPx: d.width,
                heightPx: d.height,
                frame: Bounds(d.frame),
                scale: scaleFactor(for: d.displayID)
            )
        }
    }

    static func findWindow(byApp appName: String) async throws -> WindowInfo? {
        let needle = appName.lowercased()
        let windows = try await listWindows(includeOffscreen: false)
        let matches = windows.filter { $0.app.lowercased().contains(needle) }
        // Prefer normal app windows (layer 0) with a non-empty title.
        return matches.first(where: { $0.layer == 0 && !$0.title.isEmpty })
            ?? matches.first(where: { $0.layer == 0 })
            ?? matches.first
    }

    static func captureWindow(
        byApp appName: String,
        hideCursor: Bool = true,
        caller: Caller,
        force: Bool = false,
        format: OutputFormat = .png
    ) async throws -> (data: Data, mimeType: String) {
        guard let window = try await findWindow(byApp: appName) else {
            throw CaptureError.windowNotFoundByApp(appName)
        }
        return try await captureWindow(id: window.id, hideCursor: hideCursor, caller: caller, force: force, format: format)
    }

    static func captureWindow(
        id: UInt32,
        hideCursor: Bool = true,
        caller: Caller,
        force: Bool = false,
        format: OutputFormat = .png
    ) async throws -> (data: Data, mimeType: String) {
        await bootstrap()
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw CaptureError.windowNotFound(id)
        }
        let info = WindowInfo(
            id: window.windowID,
            title: window.title ?? "",
            app: window.owningApplication?.applicationName ?? "Unknown",
            bundleID: window.owningApplication?.bundleIdentifier,
            bounds: Bounds(window.frame),
            onScreen: window.isOnScreen,
            layer: window.windowLayer
        )
        if !force, let reason = DenyList.current().denies(window: info) {
            AuditLog.record(AuditEntry(
                kind: "denied", caller: caller, app: info.app, windowId: id, denyReason: reason
            ))
            MenuBarController.record(CaptureRecord(
                ts: Date(), kind: "capture_window", app: info.app, bytes: nil, denied: true
            ))
            throw DenyError.denied(target: info.app, reason: reason)
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = scaleForWindow(window) ?? 2.0
        let nativeW = Double(window.frame.width) * Double(scale)
        let nativeH = Double(window.frame.height) * Double(scale)
        let cap = capScale(width: nativeW, height: nativeH)
        let cfg = SCStreamConfiguration()
        cfg.width = Int(nativeW * cap)
        cfg.height = Int(nativeH * cap)
        cfg.showsCursor = !hideCursor
        cfg.capturesShadowsOnly = false
        cfg.ignoreShadowsDisplay = true
        cfg.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: cfg
        )
        let encoded = try encode(image, as: format)
        AuditLog.record(AuditEntry(
            kind: "capture_window", caller: caller, app: info.app, windowId: id, bytes: encoded.data.count
        ))
        MenuBarController.record(CaptureRecord(
            ts: Date(), kind: "capture_window", app: info.app, bytes: encoded.data.count, denied: false
        ))
        return encoded
    }

    static func captureDisplay(
        id: UInt32?,
        hideCursor: Bool = true,
        caller: Caller,
        format: OutputFormat = .png
    ) async throws -> (data: Data, mimeType: String) {
        await bootstrap()
        let content = try await SCShareableContent.current
        guard !content.displays.isEmpty else { throw CaptureError.noDisplays }
        let display: SCDisplay
        if let id = id {
            guard let match = content.displays.first(where: { $0.displayID == id }) else {
                throw CaptureError.displayNotFound
            }
            display = match
        } else {
            display = content.displays.first!
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let nativeW = Double(display.width)
        let nativeH = Double(display.height)
        let cap = capScale(width: nativeW, height: nativeH)
        let cfg = SCStreamConfiguration()
        cfg.width = Int(nativeW * cap)
        cfg.height = Int(nativeH * cap)
        cfg.showsCursor = !hideCursor
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: cfg
        )
        let encoded = try encode(image, as: format)
        AuditLog.record(AuditEntry(
            kind: "capture_display", caller: caller, displayId: display.displayID, bytes: encoded.data.count
        ))
        MenuBarController.record(CaptureRecord(
            ts: Date(), kind: "capture_display", app: nil, bytes: encoded.data.count, denied: false
        ))
        return encoded
    }

    static func captureRegion(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        displayID: UInt32? = nil,
        hideCursor: Bool = true,
        caller: Caller,
        format: OutputFormat = .png
    ) async throws -> (data: Data, mimeType: String) {
        await bootstrap()
        guard width > 0, height > 0 else { throw CaptureError.invalidRegion }
        let content = try await SCShareableContent.current
        guard !content.displays.isEmpty else { throw CaptureError.noDisplays }
        let display: SCDisplay
        if let id = displayID {
            guard let match = content.displays.first(where: { $0.displayID == id }) else {
                throw CaptureError.displayNotFound
            }
            display = match
        } else {
            display = content.displays.first!
        }
        let scale = scaleFactor(for: display.displayID)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let nativeW = Double(width) * Double(scale)
        let nativeH = Double(height) * Double(scale)
        let cap = capScale(width: nativeW, height: nativeH)
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = CGRect(x: x, y: y, width: width, height: height)
        cfg.width = Int(nativeW * cap)
        cfg.height = Int(nativeH * cap)
        cfg.showsCursor = !hideCursor
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: cfg
        )
        let encoded = try encode(image, as: format)
        AuditLog.record(AuditEntry(
            kind: "capture_region",
            caller: caller,
            displayId: display.displayID,
            region: Bounds(CGRect(x: x, y: y, width: width, height: height)),
            bytes: encoded.data.count
        ))
        MenuBarController.record(CaptureRecord(
            ts: Date(), kind: "capture_region", app: nil, bytes: encoded.data.count, denied: false
        ))
        return encoded
    }

    /// Output format. PNG is lossless (good for CLI saves to disk).
    /// JPEG is ~5-10x smaller and is the right default for MCP captures
    /// where the consumer is the model, which downsamples and tokenizes
    /// well below JPEG's discrimination threshold.
    enum OutputFormat {
        case png
        case jpeg(quality: Double)  // 0.0–1.0
    }

    static func encode(_ cgImage: CGImage, as format: OutputFormat) throws -> (data: Data, mimeType: String) {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        switch format {
        case .png:
            guard let data = rep.representation(using: .png, properties: [:]) else {
                throw CaptureError.encodingFailed
            }
            return (data, "image/png")
        case .jpeg(let quality):
            let props: [NSBitmapImageRep.PropertyKey: Any] = [
                .compressionFactor: max(0.0, min(1.0, quality))
            ]
            guard let data = rep.representation(using: .jpeg, properties: props) else {
                throw CaptureError.encodingFailed
            }
            return (data, "image/jpeg")
        }
    }

    /// Backward-compat shim — always PNG. New call sites should use `encode(_:as:)`.
    private static func pngData(from cgImage: CGImage) throws -> Data {
        try encode(cgImage, as: .png).data
    }

    private static func scaleFactor(for displayID: CGDirectDisplayID) -> CGFloat {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[key] as? NSNumber)?.uint32Value == displayID
        }?.backingScaleFactor ?? 2.0
    }

    private static func scaleForWindow(_ window: SCWindow) -> CGFloat? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(window.frame) }) else {
            return nil
        }
        return screen.backingScaleFactor
    }
}
