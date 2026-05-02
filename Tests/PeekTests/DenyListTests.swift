import Testing
import Foundation
@testable import Peek

@Suite("DenyList")
struct DenyListTests {
    private func info(app: String, bundleID: String?) -> WindowInfo {
        WindowInfo(
            id: 1,
            title: "Test",
            app: app,
            bundleID: bundleID,
            bounds: Bounds(.zero),
            onScreen: true,
            layer: 0
        )
    }

    @Test func denies1PasswordByBundleID() {
        let reason = DenyList.defaults.denies(
            window: info(app: "1Password 8", bundleID: "com.1password.1password")
        )
        #expect(reason != nil)
    }

    @Test func deniesPasswordsAppByBundleID() {
        let reason = DenyList.defaults.denies(
            window: info(app: "Passwords", bundleID: "com.apple.Passwords")
        )
        #expect(reason != nil)
    }

    @Test func deniesKeychainAccessByBundleID() {
        let reason = DenyList.defaults.denies(
            window: info(app: "Keychain Access", bundleID: "com.apple.keychainaccess")
        )
        #expect(reason != nil)
    }

    @Test func deniesByAppNameWhenBundleIDMissing() {
        let reason = DenyList.defaults.denies(
            window: info(app: "1Password", bundleID: nil)
        )
        #expect(reason != nil)
    }

    @Test func bundleIDMatchIsCaseInsensitive() {
        let reason = DenyList.defaults.denies(
            window: info(app: "1Password", bundleID: "COM.1PASSWORD.1PASSWORD")
        )
        #expect(reason != nil)
    }

    @Test func allowsRegularApp() {
        let reason = DenyList.defaults.denies(
            window: info(app: "Safari", bundleID: "com.apple.Safari")
        )
        #expect(reason == nil)
    }

    @Test func allowsAppWithUnrelatedName() {
        let reason = DenyList.defaults.denies(
            window: info(app: "Calendar", bundleID: "com.apple.iCal")
        )
        #expect(reason == nil)
    }
}
