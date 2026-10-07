import SwiftUI

@main
struct ShojiNotesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(library: Self.initialLibrary)
                .screenshotDemo()
                #if os(macOS)
                .frame(minWidth: 820, minHeight: 520)
                #endif
        }
    }

    /// Real data would load from disk here. Screenshot mode swaps in fictional demo content (Debug builds only).
    static var initialLibrary: Library {
        #if DEBUG
        if ScreenshotDemo.isActive { return DemoData.library }
        #endif
        return Library(notes: [])
    }
}
