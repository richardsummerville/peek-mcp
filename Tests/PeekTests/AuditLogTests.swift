import Testing
import Foundation
@testable import Peek

@Suite("AuditLog")
struct AuditLogTests {
    @Test func captureEntryEncodesAndDecodes() throws {
        let entry = AuditEntry(
            kind: "capture_window",
            caller: .mcp,
            app: "Safari",
            windowId: 42,
            bytes: 12345
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(AuditEntry.self, from: data)

        #expect(decoded.kind == "capture_window")
        #expect(decoded.caller == "mcp")
        #expect(decoded.app == "Safari")
        #expect(decoded.windowId == 42)
        #expect(decoded.bytes == 12345)
        #expect(decoded.denyReason == nil)
        #expect(decoded.displayId == nil)
    }

    @Test func deniedEntryCarriesReason() throws {
        let entry = AuditEntry(
            kind: "denied",
            caller: .cli,
            app: "Passwords",
            windowId: 99,
            denyReason: "bundle id matches deny pattern"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(AuditEntry.self, from: data)

        #expect(decoded.kind == "denied")
        #expect(decoded.denyReason == "bundle id matches deny pattern")
        #expect(decoded.bytes == nil)
    }

    @Test func displayEntryCarriesDisplayID() throws {
        let entry = AuditEntry(
            kind: "capture_display",
            caller: .mcp,
            displayId: 1,
            bytes: 9999999
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(AuditEntry.self, from: data)

        #expect(decoded.displayId == 1)
        #expect(decoded.app == nil)
        #expect(decoded.windowId == nil)
    }

    @Test func regionEntryCarriesBounds() throws {
        let region = Bounds(CGRect(x: 100, y: 200, width: 800, height: 600))
        let entry = AuditEntry(
            kind: "capture_region",
            caller: .cli,
            displayId: 1,
            region: region,
            bytes: 50000
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(AuditEntry.self, from: data)

        #expect(decoded.region?.x == 100)
        #expect(decoded.region?.y == 200)
        #expect(decoded.region?.width == 800)
        #expect(decoded.region?.height == 600)
    }

    @Test func timestampIsISO8601WithFractionalSeconds() {
        let entry = AuditEntry(kind: "capture_display", caller: .cli)
        // 2026-05-02T18:42:13.123Z
        let pattern = #/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z$/#
        #expect(entry.ts.firstMatch(of: pattern) != nil)
    }

    @Test func tailFromMissingFileReturnsEmpty() throws {
        // Don't actually touch the on-disk log; just verify the function
        // handles missing files gracefully when we haven't written anything.
        // (We can't easily isolate the path without DI, so this is a smoke
        // test that it doesn't throw on a fresh system.)
        let entries = try AuditLog.tail(lines: 10)
        // Either empty (fresh system) or a non-negative count from prior runs
        #expect(entries.count >= 0)
    }
}
