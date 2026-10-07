# App Store Screenshots

Generates App Store screenshots from the real app, reproducibly, in about a minute, for macOS and iOS:

1. **Capture:** an XCUITest launches the app into each screen you want to show, in light and dark, and captures the
   window (macOS) or the screen (iOS).
2. **Export:** `make-screenshots.sh` pulls those captures out of the test result bundle by name.
3. **Compose:** `compose.swift` draws each marketing image (background, headline, subtitle, and one or more framed
   windows) and checks the result.

When the UI changes, re-run one command. When only captions or styling change, recompose in seconds without
re-capturing. Everything uses Apple frameworks only and runs with Xcode's toolchain.

## Files

| File | Role | Per app? |
| --- | --- | --- |
| `ScreenshotCapture.swift` | XCTest helpers: `requireScreenshotRun()`, `launchForScreenshot(_:ready:)`, `captureScreenshot(_:named:)`, `dismissNotificationBanners()` (iOS) | Shared: add to the **UI test** target |
| `ScreenshotDemoSupport.swift` | Debug-only screenshot mode for SwiftUI apps: `ScreenshotDemo.isActive`, `ScreenshotDemo.value(_:)`, and the `.screenshotDemo()` modifier (appearance, plus window size and active Space on macOS) | Shared: add to the **app** target |
| `make-screenshots.sh` | Runs the capture test, exports the captures, composes, and checks the PNGs | Shared |
| `export-captures.swift` | Turns `xcresulttool`'s exported attachments into `Captures/<name>.png` | Shared |
| `compose.swift` | Renders the final PNGs from captures and a JSON config, with layout checks and an overview sheet | Shared |
| `screenshots.json` | Sizes, style, and the list of shots (headline, subtitle, which captures) | Per app |
| A capture test (e.g. `AppStoreScreenshots.swift`) | Launches each state and calls `captureScreenshot` | Per app |
| Demo data and state arguments | Fictional content and the app's own `-UITest…` state arguments, Debug only | Per app |
| A wrapper script (e.g. `AppStore/make-screenshots.sh`) | Sets `PROJECT`, `SCHEME`, `TEST`, `CONFIG`, `OUT`, `DESTINATION` | Per app |

`Example/` is a complete, working reference: **Shoji Notes**, a small multiplatform SwiftUI app with fictional demo
data. It has a capture test, Mac and iPhone configs, a wrapper script, and the generated captures and screenshots.
Its Xcode project uses the two shared Swift files by reference from this folder.

## Commands

```bash
# The example: Mac (2880×1800) and iPhone 6.9" (1320×2868)
AppStoreScreenshots/Example/AppStore/make-screenshots.sh            # or: mac | iphone

# Recompose only, after editing captions or style (seconds)
SKIP_CAPTURE=1 AppStoreScreenshots/Example/AppStore/make-screenshots.sh mac

# Generic form for any app
PROJECT=MyApp.xcodeproj SCHEME=MyApp TEST=MyAppUITests/AppStoreScreenshots \
CONFIG=AppStore/screenshots.json OUT=AppStore/Screenshots \
path/to/AppStoreScreenshots/make-screenshots.sh
```

Optional variables:
- `DESTINATION`: default `platform=macOS`; for iPhone use e.g. `platform=iOS Simulator,name=iPhone 17 Pro Max`.
- `WORKSPACE`: use instead of `PROJECT`.
- `CAPTURES`: where raw captures go; default `$OUT/../Captures`.
- `SKIP_CAPTURE=1`: recompose without capturing.
- `STATUS_BAR=0`: leave the simulator's status bar alone. By default it's set to 9:41 with full signal and battery for
  the capture, then cleared.
- `STRICT=1`: fail on compose warnings.

Each run writes the PNGs to `OUT`, plus `Screenshots-overview.png` next to it, a contact sheet for reviewing the set.
In testing, the example captured and composed both platforms in under a minute (builds were cached); a cold iPhone
run that boots the simulator took a little over a minute.

## Adopting it in another app (checklist for a person or an agent)

1. **Copy the shared files.** Put this folder in the new repo, e.g. `Tools/AppStoreScreenshots/`. Add
   `ScreenshotCapture.swift` to the app's UI test target. If there isn't one, create one: in Xcode, File ▸ New ▸
   Target ▸ UI Testing Bundle (`com.apple.product-type.bundle.ui-testing`, with `TEST_TARGET_NAME` set to the app),
   and include it in the shared scheme's Test action. For a SwiftUI app, also add `ScreenshotDemoSupport.swift` to
   the app target.
2. **Add a Debug-only demo state to the app.** Screenshots need attractive, deterministic data and no personal data:
   - Put `.screenshotDemo()` on the root view of the main window. It applies `-UITestAppearance light|dark` and, on
     macOS, `-UITestWindowSize 1280x800`, and pulls the window onto the active Space.
   - When `ScreenshotDemo.isActive` (the `-UITestDemo` argument), load fictional demo content instead of real data.
     Use fixed dates, invented names, and no other companies' names, icons or trademarks, which avoids App Review
     problems under Guideline 5.2. SF Symbols are fine inside the UI, never in the app icon.
   - Add the app's own state arguments: the selected item, tab, open sheet, expanded row or scroll position. Read
     them with `ScreenshotDemo.value("SelectNote")`, which reads `-UITestSelectNote <value>`. Set state through
     arguments, not by clicking: it's faster and deterministic.
   - Keep every use of `ScreenshotDemo` inside `#if DEBUG`. Release builds must contain none of it: after a Release
     build, `strings <binary> | grep UITest` must print nothing. The example passes this check.
   - Not using SwiftUI? Do the same by hand: on macOS, `NSApp.appearance = NSAppearance(named: .darkAqua)`, then
     `window.collectionBehavior.insert(.moveToActiveSpace); NSApp.activate()`; on iOS, set
     `overrideUserInterfaceStyle` on the window.
3. **Write the capture test.** Start with `try requireScreenshotRun()` so normal test runs skip it. For each scene
   and appearance: `launchForScreenshot(args, ready: { $0.staticTexts["Some text on that screen"] })`, then
   `captureScreenshot(app, named: "scene-appearance")`, then `app.terminate()`. Choose a `ready` text that only
   appears once the scene is fully set up. Copy `Example/ShojiNotesUITests/AppStoreScreenshots.swift`. Use
   `#if os(iOS)` where a scene must differ on iPhone; for example, a selected item opens full screen there.
4. **Write `screenshots.json`** (format below). Capture names are the names passed to `captureScreenshot`. Use
   one config per platform, because sizes and layout differ.
5. **Write the wrapper script** with `PROJECT` or `WORKSPACE`, `SCHEME`, `TEST` (`UITestTarget/TestClass`),
   `CONFIG`, `OUT` and `DESTINATION`. Copy `Example/AppStore/make-screenshots.sh`. Add the `Captures/` and
   `Screenshots/` folders and `Screenshots-overview.png` to `.gitignore`, unless you want them reviewed in git like
   the example.
6. **Run it** from a normal desktop Space, not a full-screen app. The first macOS run may ask once to let Xcode's
   test runner control the computer. Fix every warning, look at `Screenshots-overview.png`, then upload the PNGs
   from `OUT` to App Store Connect.

## Config format

```json
{
  "sizes": [{ "width": 2880, "height": 1800 }],
  "style": {
    "background": ["#F6F3EE", "#E4E9EE"],
    "textColor": "#1D1D1F", "subtitleColor": "#6E6E73",
    "headlineSize": 0.052, "subtitleSize": 0.022,
    "padding": 0.042, "top": 0.08, "align": "left",
    "windowTop": 0.30, "windowWidth": 0.84,
    "cornerRadius": 0.016, "shadow": true
  },
  "shots": [
    { "output": "01-hero", "headline": "Line one\nline two.", "subtitle": "One sentence.",
      "layers": [{ "capture": "home-dark" }] },
    { "output": "02-light-dark", "headline": "Light and dark.",
      "style": { "background": ["#2C2C30", "#0E0E10"], "textColor": "#FFFFFF" },
      "layers": [{ "capture": "home-light", "width": 0.6, "x": 0.05, "y": 0.27 },
                 { "capture": "home-dark", "width": 0.6, "x": 0.35, "y": 0.37 }] }
  ]
}
```

- **Units:** fractions of the canvas, so one config renders at any size. `width`, `padding` and `x` are fractions of
  the canvas width; `top`, `windowTop`, `y` and the text sizes are fractions of its height. `cornerRadius` is a
  fraction of each window's drawn width.
- **Text:** `align` is `left` (the default, typical on Mac) or `center` (typical on iPhone). `subtitleWidth` is the
  fraction of the text width the subtitle may use: 0.62 when left-aligned, 1 when centered. Write headline line
  breaks yourself with `\n`. A headline that wraps on its own produces a warning.
- **Windows:** centered by default, and they may run off the bottom edge, which is intentional. Layers draw in
  order, so later ones sit on top. On iPhone, use a large `cornerRadius` (about 0.115) to echo the screen's corners;
  see `Example/AppStore/screenshots-iphone.json`.
- **Per-shot overrides:** a shot's `style` overrides any global style key for that shot.
- **Sizes:** list several in `sizes` to get one file per size. App Store Connect accepts:
  - **Mac:** 1280×800, 1440×900, 2560×1600 or 2880×1800 (16:10); one size is enough.
  - **iPhone 6.9":** 1320×2868, 1290×2796 or 1260×2736. Provide this or 6.5" (1284×2778, 1242×2688).
  - **iPad 13":** 2064×2752 or 2048×2732, if the app runs on iPad.

  Other sizes produce a warning.
- **Output:** opaque PNGs (no alpha channel), which App Store Connect requires. The script verifies this with `sips`.
- **Compatibility:** the format is a superset of the original App Archaeology `compose.swift`. That config renders
  pixel-identical output with this compositor (verified on all six of its shots).

### What compose checks

Before drawing, it checks that every capture the config names exists, and lists all the missing ones at once along with
what is available. While drawing, it warns about:
- sizes App Store Connect rejects;
- captures drawn more than 1.15× their pixel size (blurry; capture on a Retina display or draw smaller);
- windows running off the left or right edge;
- headlines that wrap on their own;
- text that runs into the highest window;
- PNGs left in `OUT` from an earlier config, which would otherwise be uploaded too.

After composing, `make-screenshots.sh` checks every PNG's size against the config and that it has no alpha channel.

## Gotchas

- **Run from a normal desktop Space.** XCUITest can't see windows on other Spaces. `.screenshotDemo()` moves the
  window to the active Space, but the run still has to start from one.
- **A macOS app with no window:** in testing, a freshly built SwiftUI app occasionally launched with no window at
  all. It was intermittent and not tied to the arguments. If the scene isn't ready and there's no window,
  `launchForScreenshot` presses ⌘N (File ▸ New Window) once before giving up.
- **iOS notification banners:** a freshly booted simulator posts system notices (for example "Ready for Apple
  Intelligence") at unpredictable moments, and one landed in a capture during testing. `captureScreenshot` swipes
  banners away first, and fails the test if one won't go. This was verified with banners firing every few seconds.
- **On iPhone, a selected item opens full screen** in a `NavigationSplitView`. A scene that should show a list must
  not select anything there.
- Don't pass `-ApplePersistenceIgnoreState YES` to a SwiftUI `Window` scene app; it can suppress the window.
- If a capture shows clipped text, fix the app, not the compositor. App Review rejects cut-off text (Guideline 4).
- **Mismatched toolchain errors from `swift`:** the scripts use `xcrun swift`, so they run Xcode's toolchain even
  when another Swift install comes first on `PATH`.
- **"No named captures found":** the test didn't run (check `TEST`; it must name the capture test class), or it never
  called `captureScreenshot(_:named:)`.

## Limitations

- Only iPhone and Mac were exercised end to end. iPad works the same way (an iPad simulator destination, an iPad
  size and layout in the config), but the example doesn't include an iPad run.
- The compositor draws plain rounded windows and screens, not device frames. App Store Connect doesn't require frames.
- Headline and subtitle text is drawn in the system font; there is no localization loop. To localize, run the
  compositor once per language with one config each, and capture with `-AppleLanguages (xx)` added to the launch
  arguments.
