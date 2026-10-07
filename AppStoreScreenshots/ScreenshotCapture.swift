import XCTest

// Reusable App Store screenshot capture for XCUITest (macOS and iOS).
// Add this file to the app's UI test target, then write one test that launches the app into each state and calls
// `captureScreenshot`. Captures are stored as named attachments in the test result bundle; `make-screenshots.sh`
// exports them by name and `compose.swift` turns them into App Store images.

/// The environment variable that enables screenshot tests. `make-screenshots.sh` sets it through xcodebuild's
/// `TEST_RUNNER_` prefix, so ordinary test runs skip the (slow) capture tests.
let appStoreScreenshotsEnabled = ProcessInfo.processInfo.environment["APPSTORE_SCREENSHOTS"] == "1"

extension XCTestCase {
    /// Skips the calling test unless screenshots were requested.
    func requireScreenshotRun() throws {
        try XCTSkipUnless(appStoreScreenshotsEnabled, "Run make-screenshots.sh to capture App Store screenshots.")
    }

    /// Launches the app with `arguments` and waits until `ready` exists (or the first window appears).
    @MainActor @discardableResult
    func launchForScreenshot(_ arguments: [String], ready: ((XCUIApplication) -> XCUIElement)? = nil, settle: TimeInterval = 1.5) -> XCUIApplication {
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        let marker = ready?(app) ?? app.windows.firstMatch
        var isReady = marker.waitForExistence(timeout: 15)
        #if os(macOS)
        if !isReady && !app.windows.firstMatch.exists {
            // A SwiftUI app occasionally comes up with no window at all (seen intermittently on fresh builds);
            // ask for one, as File ▸ New Window would.
            app.typeKey("n", modifierFlags: .command)
            isReady = marker.waitForExistence(timeout: 10)
        }
        #endif
        XCTAssertTrue(isReady, "Screenshot state never became ready")
        // Let icons, charts, and animations finish.
        Thread.sleep(forTimeInterval: settle)
        return app
    }

    /// Captures the app's frontmost window (macOS) or the screen (iOS) as a named, kept attachment.
    @MainActor
    func captureScreenshot(_ app: XCUIApplication, named name: String) {
        #if os(macOS)
        let screenshot = app.windows.firstMatch.screenshot()
        #else
        dismissNotificationBanners()
        let screenshot = XCUIScreen.main.screenshot()
        #endif
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    #if os(iOS)
    /// Swipes away notification banners, which would otherwise land in a whole-screen capture. A freshly booted
    /// simulator posts system notices ("Ready for Apple Intelligence" and the like) at unpredictable moments.
    @MainActor
    func dismissNotificationBanners() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.descendants(matching: .any).matching(identifier: "NotificationShortLookView").firstMatch
        for _ in 0..<5 where banner.exists {
            banner.swipeUp()
            _ = banner.waitForNonExistence(timeout: 2)
        }
        XCTAssertFalse(banner.exists, "A notification banner kept covering the screen")
    }
    #endif
}
