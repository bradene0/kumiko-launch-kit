import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// Reusable, Debug-only screenshot mode for SwiftUI apps (macOS and iOS). Add this file to the APP target.
//
// Launch arguments it understands (all optional, set by the capture test):
//   -UITestDemo                  turn screenshot mode on; the app should load fictional demo data
//   -UITestAppearance light|dark force the appearance
//   -UITestWindowSize 1280x800   macOS: content size of the main window (points), centered
// Per-app state arguments use the same form, e.g. `-UITestSelectNote "Tea ceremony"`; read them with
// `ScreenshotDemo.value("SelectNote")`.
//
// Everything that reads the arguments is compiled only in Debug builds. In Release, `screenshotDemo()` returns the
// view unchanged, and `strings <binary> | grep UITest` prints nothing.

#if DEBUG
enum ScreenshotDemo {
    /// True when the app was launched for screenshots (`-UITestDemo`).
    static let isActive = ProcessInfo.processInfo.arguments.contains("-UITestDemo")

    /// The value of `-UITest<name> <value>`, or nil outside screenshot mode. Launch arguments of the form
    /// `-Key value` land in UserDefaults' argument domain, so no parsing is needed.
    static func value(_ name: String) -> String? {
        isActive ? UserDefaults.standard.string(forKey: "UITest" + name) : nil
    }

    static var colorScheme: ColorScheme? {
        switch value("Appearance") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    #if os(macOS)
    /// Forces the appearance app-wide (sheets and menus too), sizes the main window, and pulls it onto the active
    /// Space: XCUITest cannot see windows on other Spaces, and a Dock "Assign To" desktop can put it elsewhere.
    @MainActor static func prepareWindow() {
        guard isActive else { return }
        switch value("Appearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        window.collectionBehavior.insert(.moveToActiveSpace)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        if let size = value("WindowSize"), case let parts = size.split(separator: "x").compactMap({ Double($0) }), parts.count == 2 {
            window.setContentSize(NSSize(width: parts[0], height: parts[1]))
            window.center()
        }
    }
    #endif
}
#endif

extension View {
    /// Applies screenshot mode (appearance, and on macOS window size and Space) in Debug builds. A no-op in Release.
    /// Attach it to the root view of the main window.
    func screenshotDemo() -> some View {
        #if DEBUG
        return self
            .preferredColorScheme(ScreenshotDemo.colorScheme)
            .onAppear {
                #if os(macOS)
                // The window exists but may not be ordered in yet when the root view first appears.
                Task { @MainActor in ScreenshotDemo.prepareWindow() }
                #endif
            }
        #else
        return self
        #endif
    }
}
