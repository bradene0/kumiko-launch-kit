# AppIconKit

Turns one hand-drawn vector glyph (1–4 SVG layers) and a house-style palette into a complete, validated app icon with
one command:

1. **`AppIcon.icon`**: an Icon Composer document for macOS 26 and iOS 26 (Liquid Glass). It opens in Icon Composer and
   compiles with `actool`.
2. **`AppIcon.appiconset`**: the legacy macOS icon (16, 32, 128, 256 and 512 pt at @1x and @2x, plus `Contents.json`)
   drawn on Apple's macOS 11–15 grid. **`AppIcon-iOS.appiconset`** is an opaque single-size 1024 iOS icon.
3. **`preview.png`**: the icon at 16–512 px on light and dark backgrounds, 16 and 32 px magnified ×8, Apple's Liquid
   Glass renders (default, dark, clear, tinted) and two simulated Dock rows, so you can judge it at small sizes.

The build stops on inputs that break the rules (raster art, SF Symbols, traced or AI-generated art, text, filters) and
warns about glyphs that won't read at 32 px. The wrapper then compiles everything with `actool` and checks every PNG
with `sips`. It uses Apple frameworks only (AppKit, Core Graphics, Core Animation, ImageIO) and runs with `xcrun swift`;
there are no other dependencies.

## Files

| File | Role | Per app? |
| --- | --- | --- |
| `make-icon.sh` | Builds, then validates with `actool` and `sips`. The one command to run | Shared |
| `build-icon.swift` | Lints the SVGs, writes the `.icon`, the appiconsets, the renders, `preview.png` and `report.txt` | Shared |
| `house-style.json` | Six palettes, glyph rules, legacy macOS geometry, Icon Composer defaults | Shared |
| `check-svg.swift` | Compares CoreSVG (NSImage) with WebKit for one SVG; use it on any glyph that looks wrong | Shared |
| `Tests/*.svg` | SVG fidelity fixtures for `check-svg.swift` | Shared |
| `appicon.json` + glyph SVGs | The app's palette choice, layers, colors, scale and offset | Per app |
| `Example/` | A complete example: `appicon.json`, `Glyph/*.svg` and the generated `Output/` | Reference |

## Commands

```bash
# Build and validate the example
AppIconKit/make-icon.sh AppIconKit/Example/appicon.json

# Any app: same command with its config; --strict also fails on design warnings
AppIconKit/make-icon.sh path/to/appicon.json --strict

# Re-validate an existing output, e.g. after adjusting AppIcon.icon in Icon Composer
SKIP_BUILD=1 AppIconKit/make-icon.sh path/to/appicon.json

# Check how faithfully NSImage renders an SVG (writes coresvg.png, webkit.png, diff.png)
xcrun swift AppIconKit/check-svg.swift path/to/glyph.svg /tmp/svg-check
```

Always use `xcrun swift`, not `swift`: if another Swift toolchain (for example one installed with swiftly) comes first on `PATH`, plain `swift` won't match Xcode's SDK. A build takes
about 10 seconds including validation.

## Adopting it for a new app (checklist for a person or an agent)

1. **Pick the idea, not the artwork.** One object or metaphor, with a silhouette you could recognize at 16 px. No
   words, no screenshots, no photos. Choose a palette from `house-style.json` that fits the app's category; the
   palette `about` text says what each one is for.
2. **Draw the glyph by hand in a vector editor** (Affinity, Illustrator, Figma or Sketch) on a **1024×1024 artboard** (the same artboard for every layer, so the
   layers line up). Keep it within the central 768×768 (the safe area: `safeInset` 0.125 = 128 pt per side) and
   make it fill at least ~42% of the canvas. Use 1–4 layers, back to front, for example "shape" and "accent".
   Keep strokes at **48 pt or thicker** on the 1024 canvas (1.2 px at 32 px). Use flat fills only; the colors in the
   file don't matter if the config sets `color`.
3. **Export each layer as SVG** (in Affinity: File ▸ Export ▸ SVG) with the **whole artboard** as the export area, not just the
   selection, so every file keeps the same `0 0 1024 1024` viewBox, and with nothing rasterized. Hide the other
   layers while exporting each one. Convert text to curves; expanding strokes is optional. Never start from SF Symbols, clip art, a traced bitmap or an
   AI-generated image. The build rejects the obvious cases, but the rule applies even when it can't tell.
4. **Write `appicon.json`** next to the glyphs (format below). Start from `Example/appicon.json`. Put it in a
   design folder, not in the app's source tree, for example `Design/AppIcon/appicon.json` with `"output": "Output"`.
5. **Run `make-icon.sh path/to/appicon.json`.** Fix every `error:`, then read the warnings and `preview.png`.
   Judge the 16 and 32 px icons and the Dock rows, not the 512 px one. If the glyph turns to mush at 32 px, simplify
   it; don't add detail.
6. **Iterate on the config, not on pixels.** Change `scale`/`offset`, swap palette roles, or redraw a layer and run
   it again. Nothing in `Output/` should be edited by hand, except optionally `AppIcon.icon` in Icon Composer
   (see below). Run `make-icon.sh --strict` before shipping.
7. **Add it to the app**, in Xcode 26 or later:
   - **Preferred:** drag `Output/AppIcon.icon` into the project navigator (next to, not inside, `Assets.xcassets`)
     and set the target's *App Icon* to `AppIcon`. Xcode's `actool` also generates the pre-macOS 26 and pre-iOS 26
     fallback from it; see `Output/Renders/actool-fallback-AppIcon.icns` for what older systems get.
   - **Legacy or flat look:** copy `Output/AppIcon.appiconset` into `Assets.xcassets` (replace the existing one).
     For iOS, copy `AppIcon-iOS.appiconset` into the asset catalog as `AppIcon.appiconset`.
   - Keep only one icon named `AppIcon` in a target (either the `.icon` or the appiconset), so it's clear which
     one Xcode uses.
8. **Keep the sources.** Commit the `.afdesign`, the exported SVGs and `appicon.json`. `Output/` can be regenerated.

## Config format

### `appicon.json` (per app)

```json
{
  "name": "Shoji (example)",
  "houseStyle": "../house-style.json",
  "palette": "ink",
  "layers": [
    { "name": "sun",   "svg": "Glyph/sun.svg",   "color": "accent" },
    { "name": "frame", "svg": "Glyph/frame.svg", "color": "primary", "opacity": 1.0, "glass": true }
  ],
  "scale": 1.0,
  "offset": [0, 0],
  "output": "Output",
  "iOS": true
}
```

| Key | Meaning |
| --- | --- |
| `name` | Shown on the preview sheet and in the report |
| `houseStyle` | Path to the house style, relative to this file. Optional: `make-icon.sh` falls back to the kit's own |
| `palette` | A palette name from the house style |
| `gradient` | Optional override: two colors `["#RRGGBB", "#RRGGBB"]`, top to bottom. The background gradient is always vertical, because Icon Composer ignores a direction on the background |
| `layers` | 1–4 layers, **back to front**. Each one is an SVG on the shared artboard |
| `layers[].color` | A palette role (`primary`, `secondary`, `accent`) or `#RRGGBB`. It replaces the SVG's colors in both the legacy icon and the `.icon` (as an Icon Composer solid fill). Omit it to keep the SVG's own colors |
| `layers[].opacity` | 0–1, default 1 |
| `layers[].glass` | Liquid Glass for this layer in Icon Composer (default from the house style: on) |
| `scale`, `offset` | Glyph transform around the canvas center; offset is in canvas points with +y down. Applied to every layer |
| `output` | Output folder, relative to this file. **It is deleted and recreated on every build** |
| `iOS` | Also write `AppIcon-iOS.appiconset` (default true) |
| `legacyShadow` | Override the house style's legacy drop shadow (true or false) |
| `previewDock` | Draw the two Dock rows on `preview.png` (default true). They use your Mac's own app icons as neighbors, so set it to false for a preview you plan to publish. The example sets it to false |

Every path is relative to the config file. Unknown keys produce a warning, except keys starting with `_`, which you
can use for comments (for example `"_note": "…"`). An SVG artboard that isn't square is centered on the canvas, with a warning.

### `house-style.json` (shared)

| Key | Meaning |
| --- | --- |
| `glyph.safeInset` | Fraction of the 1024 canvas to keep clear on each side (0.125 = 128 pt). A house choice, not an Apple number |
| `glyph.minExtent` | The glyph's larger side should span at least this fraction of the canvas |
| `glyph.minStroke32` | The thinnest acceptable feature, in pixels of the 32 px icon |
| `glyph.maxThinFraction` | Warn when more than this fraction of a layer is thinner than `minStroke32` |
| `glyph.minContrast` | Minimum WCAG contrast between each layer color and both gradient stops |
| `legacyMac.margin`, `cornerRadius`, `continuousCorners` | The macOS 11–15 body: 824×824 at a 100 pt margin, continuous corners with radius 185.4 |
| `legacyMac.shadow` | `enabled`, plus `offsetY`, `blur` and `opacity` on the 1024 grid (6, 36, 0.20) |
| `iconComposer` | Defaults for every group in the `.icon`: `glass`, `shadowKind` (`neutral` or `layer-color`), `shadowOpacity`, `translucency`, `specular` |
| `palettes.<name>` | `gradient` (exactly two colors, top to bottom), `colors` (named roles), `about` |

The six palettes: **tide** (daylight blue), **sage** (green), **ember** (orange-red), **plum** (violet), **ink** (deep
indigo, strong accents) and **paper** (light neutral with a dark glyph). Each has a gentle top-to-bottom gradient, the
way Apple's macOS 26 icons do: a lighter top, a slightly deeper bottom, and no more than two steps of hue. Add palettes
freely, but keep exactly two stops, because Icon Composer gradients have two.

## Design rules for an Apple-native, non-AI look

- **Vector shapes only.** Paths, circles and rectangles with flat fills. No raster input, no photos, no textures, no
  noise, no painted highlights, no inner shadows. Icon Composer (Liquid Glass) or the legacy squircle and shadow
  supply all of the depth.
- **2–3 colors in total:** one background gradient, a primary glyph color, and at most one accent. Use the palette
  roles; don't invent colors per app.
- **One idea, one silhouette.** The glyph must be recognizable as a solid blob at 16 px. Small details, thin lines and
  text vanish at that size; the report counts "specks" and "small holes" for this reason.
- **Strokes at 48 pt or thicker on the 1024 canvas** (≥ 1.2 px at 32 px). Prefer filled shapes over hairlines.
- **Geometric and deliberate.** Snap to a grid, use consistent corner radii (e.g. 24 or 96 pt), and center optically.
  Things that look AI-generated: uneven wobbly curves, hundreds of nodes, extra ornament, fake 3D, glossy highlights,
  rainbow gradients and centered "logo plus sparkles". The linter warns at more than 1500 path commands or 80 paths.
- **Layers mean depth.** In Icon Composer each layer is its own glass group, so put the element that should float
  in front last. Two layers is usually right; four is the maximum.
- **No SF Symbols, no Apple artwork, no fonts you don't have logo rights to.** Apple's SF Symbols license forbids
  their use in app icons and logos. Redraw your own glyph, even if it's similar in spirit.

## What the build enforces

**Errors (the build stops):** a raster layer file (`.png`, `.jpg`, `.heic`…); `<image>` elements or `data:image`;
SF Symbols markers (an "SF Symbols" generator or the weight/scale group IDs such as `Regular-M`); trace or AI
generator markers (potrace, Vectorizer, Image Trace, Firefly, Midjourney, DALL·E, Recraft and others); live
`<text>`; SVG `<filter>`; more than 4 layers; an unknown palette or color.

**Warnings (reported; `--strict` fails on them):**
- **Legibility, measured on the rendered glyph mapped to the 32 px legacy icon:** the share of each layer that is
  thinner than `minStroke32` (found by a morphological opening with a disk of that diameter), pieces and holes
  smaller than one pixel, the glyph's extent, coverage, and the safe area;
- **Color:** WCAG contrast of each layer against the gradient;
- **Style:** gradients, patterns or masks inside a glyph, non-square artboards, and node counts typical of tracing;
- **Format drift:** whether Apple's own render of the `.icon` still matches the palette (see below).

`report.txt` lists the metrics, for example "median stroke 1.9 px at 32 px".

The checks can't prove that art is hand-made: an SF Symbol or AI image that was re-traced and stripped of its metadata
passes. The rules still apply; the checklist above is the real control.

## How it works, and what was verified

**Legacy macOS geometry (measured, not guessed).** Apple's design templates put the macOS 11–15 icon body at
824×824 on the 1024 canvas, with a 100 pt margin and a ~185.4 pt corner radius on a continuous ("squircle") curve.
To confirm this, Apple's own pre-macOS 26 icon files on a Mac running macOS 26 (the `actool` fallback `.icns` in Activity
Monitor, Console, Keychain Access and Instruments, all identical) and a third-party app's 1024 px icns were rasterized and
fitted:
- the body is 824 px wide starting at 100 px;
- Core Animation's continuous corners fit at radius 185–190;
- the shadow fits 6 pt down, 36 pt blur, black at 20%, with a fit error of about 0.4/255 per sample.

The renderer draws the body mask with Core Animation (`CALayer.cornerCurve = .continuous`), which is the system's own
curve, at every size directly from vectors. 16 px is not a downscale of 1024.

macOS 26 does not use any of this. It re-masks every conforming legacy icon with its own, rounder shape (continuous
radius ≈214.5 on the 824 body, measured from the system's renders), adds a glass rim, and draws its own shadow
(8 pt down, 32 pt blur, 25%). This was verified with a test app whose icns had a different corner shape. So the legacy
appiconset's corners and shadow only matter on macOS 11–15. What matters on macOS 26 is the `.icon`.

**SVG rendering: NSImage, which uses CoreSVG.** On macOS 26, `NSImage(contentsOf:)` loads SVG through
`_NSSVGImageRep`, which uses CoreSVG. This is the same framework Icon Composer bundles, so the legacy PNGs and the
`.icon` interpret the SVG the same way. `check-svg.swift` compares it with WebKit, which is spec-conformant:
- **Flat-fill features match WebKit to within anti-aliasing:** paths with cubic, quadratic and arc segments, rects
  with `rx`, circles, ellipses, polygons, even-odd fills, transforms (including `matrix`), stroked paths with caps and
  joins, opacity, CSS `<style>` classes, `style=""` attributes, `clip-path`, `<use>`, `currentColor`, viewBox-only
  documents, and Affinity's root `style`. For example `Tests/flat-features.svg` has a max difference of 8/255 and
  0.000% of pixels off.
- **Gradients don't match:** CoreSVG's SVG gradients differ from the spec by up to 29/255
  (`Tests/with-gradients.svg`). Glyphs should be flat anyway, so the build warns on gradients in a glyph. The
  background gradient is drawn by Core Graphics, not SVG.

So no WKWebView or custom SVG parser is needed, as long as glyphs follow the rules.

**The `.icon` format (generated directly, and validated three ways).** An `.icon` is a folder containing
`icon.json` and `Assets/*.svg`. The schema came from three sources: a sample made by Icon Composer, the key names in
Icon Composer's frameworks, and a reverse-engineered reference
([icon-composer-template](https://github.com/peterpoliwoda/icon-composer-template)). Each assumption was then checked
by rendering probe files with Icon Composer's own command-line renderer, `ictool`:
- `groups[0]` is the **frontmost** group;
- the background (`fill` at the top level) is a two-color `linear-gradient` drawn **top to bottom**. Icon Composer
  ignores an `orientation` there; its UI has no direction control for the background either. `orientation` works
  only on layer fills (unit coordinates, x right, y down), so the house style keeps every background vertical;
- an SVG with a 1024 viewBox and no `position` lands 1:1 on the canvas. So the build bakes `scale`/`offset` into each
  layer SVG instead of relying on `translation-in-points`, whose sign convention isn't documented;
- `fill: {"solid": …}` recolors a layer, and colors are written as `extended-srgb:r,g,b,a`.

The three validations:
1. `actool` compiles the `.icon` for macOS and iOS (`make-icon.sh`);
2. `ictool` renders it in default, dark, clear and tinted appearances (`Output/Renders/`, also shown on the preview);
   `ictool` rejects unknown fill keys;
3. the example opened in Icon Composer 27.0 with both groups, both layers and the gradient fill intact.

The build also compares Apple's render with the palette, a loose check that catches a fill Icon Composer silently
ignored. Glass lighting shifts colors by up to ~0.1, so small differences are expected.

`ictool` lives at `/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool`. Icon
Composer ships inside Xcode, not in `/Applications`. Set `ICTOOL=…` if it moves.

## Icon Composer: editing or importing by hand

Opening `Output/AppIcon.icon` in Icon Composer is the normal way to fine-tune glass, shadows, translucency or
per-appearance colors. Edits are saved into that `.icon`. Re-running the build overwrites it, so either copy the
tuned `.icon` out of `Output/` (and validate it with `SKIP_BUILD=1 make-icon.sh …` first), or move the setting into
`house-style.json`/`appicon.json`.

If a future Icon Composer changes the format and the generated `.icon` stops validating, build the document by hand
from the same normalized layers:

1. Open Icon Composer (it's inside Xcode: `open "/Applications/Xcode.app/Contents/Applications/Icon Composer.app"`)
   and create a new document.
2. Drag the layer SVGs from `Output/AppIcon.icon/Assets/` onto the canvas, **front layer first**. Each SVG already
   fills the 1024 canvas at the right position, so leave its position at 0, 0 and its scale at 100%. If a layer
   lands in a group with another layer, move it into its own group, as the generated file does.
3. Select the icon root ▸ Fill ▸ Gradient. Enter the palette's two colors from `report.txt`/`house-style.json`, top
   color first, with the direction top to bottom.
4. For each layer: Fill ▸ Solid, using the role color from the palette (skip this if the config keeps the SVG's colors),
   and Opacity if the config sets one. Turn Liquid Glass on or off per layer as configured.
5. For each group: Shadow Neutral 50%, Translucency 50%, Specular on (the house defaults).
6. Check the Default, Dark and Mono previews at the bottom right, then save it as `AppIcon.icon` and validate it with
   `SKIP_BUILD=1 make-icon.sh …`.

## Troubleshooting

- **"looks like an SF Symbols export":** the SVG contains SF Symbols markers. Redraw the glyph; renaming groups to
  get past the check doesn't make it licensable.
- **A layer looks wrong or shifted:** make sure every layer was exported from the same 1024×1024 artboard. Then run
  `check-svg.swift` on it and look at `diff.png`.
- **"thinner than 1.2 px at 32 px":** thicken those strokes to the number the warning gives (in points on the 1024
  canvas), or drop the detail.
- **No Liquid Glass renders on the preview:** `ictool` wasn't found; the build notes this. Set `ICTOOL`.
- **actool warnings fail validation:** that's intentional. The output is shown, and it's usually a PNG size mismatch.

## Limitations

- The rules catch markers and measurable problems, not intent: re-traced or cleaned-up AI or SF Symbols art passes
  the linter.
- Legibility metrics measure the union and each layer's shape, not contrast between overlapping layers. Judge the
  preview.
- Icon Composer features the config doesn't expose (per-appearance colors, dark-mode gradients, blend modes,
  `layer-color` shadows per group) need Icon Composer itself. The house style sets one value for every group.
- The `.icon` schema isn't publicly documented by Apple. The generator writes only keys verified with Icon Composer
  27.0 (`ictool` 27.0, design generation 27). Re-run the example after Xcode updates.
- The legacy macOS geometry targets macOS 11–15. macOS 10.15 and earlier used free-form icons.
- The Dock rows use your Mac's system app icons as neighbors. They show how the icon sits in context, not how the Dock
  renders pixel for pixel.
