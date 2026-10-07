# Kumiko Launch Kit

App Store screenshots, app icons and a submission checklist for Mac and iPhone apps. Free and MIT licensed.

Kumiko Solutions built these while shipping [App Archaeology](https://apps.apple.com/app/id6814937695) to the Mac App Store, then pulled them out of the app so any project can use them.

| Part | What it does |
| --- | --- |
| [`AppStoreScreenshots/`](AppStoreScreenshots/README.md) | A UI test captures the real app in a Debug-only demo mode, in light and dark. A compositor turns the captures into App Store screenshots for Mac and iPhone and checks them: accepted sizes, no alpha channel, no blurry captures, no headlines that wrap, no leftover files. Re-run one command when the UI changes |
| [`AppIconKit/`](AppIconKit/README.md) | One hand-drawn SVG glyph and a palette become an Icon Composer `.icon` for macOS 26 and iOS 26 (Liquid Glass), the legacy macOS and iOS appiconsets, and a preview sheet for judging the icon at 16 and 32 px. Validated with Apple's `actool` and `ictool`. Rejects raster art, SF Symbols, live text and traced artwork |
| [`CHECKLIST.md`](CHECKLIST.md) | A submission checklist from real App Review experience, including two rejections and how they were fixed |

Both tools use Apple frameworks only, run with `xcrun swift`, and have no other dependencies.

## Requirements

- A Mac with Xcode 26 or later. AppIconKit needs Xcode's `actool` and Icon Composer's `ictool` for the `.icon` format.
- For screenshots: a UI test target in your app, and a SwiftUI app for the drop-in demo mode (UIKit and AppKit work by hand; see the screenshots README).
- Run screenshot captures from a normal desktop Space, not a full-screen app.
- The example project has no signing team set. If Xcode asks for one when running its UI tests, pick yours under Signing & Capabilities, and change its bundle IDs if you like.

## Try it in two minutes

Both examples use **Shoji Notes**, a small fictional notes app included in the kit.

```bash
# Build and validate an app icon from the example glyph (about 15 seconds)
AppIconKit/make-icon.sh AppIconKit/Example/appicon.json

# Recompose the example's App Store screenshots from its saved captures (seconds, no build)
SKIP_CAPTURE=1 AppStoreScreenshots/Example/AppStore/make-screenshots.sh mac
SKIP_CAPTURE=1 AppStoreScreenshots/Example/AppStore/make-screenshots.sh iphone

# Full run: build the example app, capture it with a UI test, then compose (about a minute)
AppStoreScreenshots/Example/AppStore/make-screenshots.sh
```

Then follow the "Adopting it" checklist in each tool's README to use it in your own app.

## What's verified, and what isn't

- The icon build and both screenshot recompositions above were re-run from a clean copy of this repository before release.
- The screenshot pipeline has been run end to end on Mac and iPhone. iPad works the same way but has no example run.
- Apple changes App Store Connect and Icon Composer over time. If something here stops matching what Apple accepts, open an issue.

## Need a hand shipping?

Kumiko Solutions takes Mac and iPhone apps through App Review to approval for a fixed price, including screenshots, icons, store listing and rejection fixes.

build@kumikosolutions.com · [kumikosolutions.com](https://kumikosolutions.com)

## License

MIT. See [LICENSE](LICENSE).
