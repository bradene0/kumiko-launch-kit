import XCTest

/// Captures the raw window (macOS) or screen (iOS) images used for App Store screenshots. Skipped in normal test runs.
/// Run `AppStore/make-screenshots.sh mac` or `… iphone`; captures are composed with `AppStore/screenshots-<platform>.json`.
#if os(iOS)
private let isPhone = true
#else
private let isPhone = false
#endif

final class AppStoreScreenshots: XCTestCase {
    override func setUpWithError() throws {
        try requireScreenshotRun()
        continueAfterFailure = false
    }

    private struct Scene {
        let name: String
        let arguments: [String]
        let ready: String              // a text that is on screen once the scene is ready
    }

    private let scenes = [
        // On iPhone a selected note opens full screen, so the library scene selects nothing there.
        Scene(name: "library", arguments: isPhone ? [] : ["-UITestSelectNote", "Morning pages"], ready: "Morning pages"),
        Scene(name: "note", arguments: ["-UITestSelectNote", "Kumiko patterns", "-UITestCompactColumn", "detail"], ready: "asanoha"),
    ]

    @MainActor func testCaptureAppStoreScreenshots() throws {
        for appearance in ["light", "dark"] {
            for scene in scenes {
                let app = launchForScreenshot(["-UITestDemo", "-UITestAppearance", appearance, "-UITestWindowSize", "1280x800"] + scene.arguments,
                                              ready: { $0.staticTexts[scene.ready].firstMatch })
                captureScreenshot(app, named: "\(scene.name)-\(appearance)")
                app.terminate()
            }
        }
    }
}
