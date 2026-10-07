// Builds a complete app icon from 1–4 hand-drawn SVG glyph layers and a house-style palette. No dependencies
// beyond macOS frameworks.
//
// Usage: xcrun swift -O build-icon.swift <appicon.json> [--house-style <house-style.json>] [--strict]
//
// Writes to the config's output folder:
//   AppIcon.icon/            Icon Composer document (macOS 26 / iOS 26 Liquid Glass icon)
//   AppIcon.appiconset/      legacy macOS icon, 16–512 pt at @1x and @2x
//   AppIcon-iOS.appiconset/  single-size 1024 iOS icon (opaque), when "iOS" is true
//   Renders/                 Apple's own Liquid Glass renders of AppIcon.icon (via Icon Composer's ictool)
//   preview.png              sizes on light and dark, zoomed small sizes, Liquid Glass variants, Dock rows (unless previewDock is false)
//   report.txt               lint results and legibility metrics
// Errors (raster input, SF Symbols, text, filters…) stop the build. Warnings are reported; --strict fails on them.
// See README.md for the config format and the design rules.

import AppKit
import ImageIO
import QuartzCore
import UniformTypeIdentifiers

// MARK: - Configuration

struct HouseStyle: Decodable {
    struct Glyph: Decodable {
        var safeInset: Double          // fraction of the 1024 canvas kept clear on every side
        var minExtent: Double          // the glyph's larger side should span at least this fraction of the canvas
        var minStroke32: Double        // thinnest acceptable feature, in pixels on the 32 px icon
        var maxThinFraction: Double    // warn when more than this fraction of the glyph is thinner than minStroke32
        var minContrast: Double        // WCAG contrast of each glyph color against the background gradient
    }
    struct Shadow: Decodable { var enabled: Bool; var offsetY: Double; var blur: Double; var opacity: Double }
    struct LegacyMac: Decodable { var margin: Double; var cornerRadius: Double; var continuousCorners: Bool; var shadow: Shadow }
    struct IconComposer: Decodable {
        var glass: Bool; var shadowKind: String; var shadowOpacity: Double; var translucency: Double; var specular: Bool
    }
    struct Palette: Decodable { var gradient: [String]; var colors: [String: String] }
    var glyph: Glyph
    var legacyMac: LegacyMac
    var iconComposer: IconComposer
    var palettes: [String: Palette]
}

struct AppConfig: Decodable {
    struct Layer: Decodable {
        var name: String?
        var svg: String
        var color: String?             // palette role ("primary", "secondary", "accent") or "#RRGGBB"; omit to keep SVG colors
        var opacity: Double?
        var glass: Bool?               // Icon Composer Liquid Glass for this layer (default: house style)
    }
    var name: String
    var houseStyle: String?            // path relative to this config; default is the kit's house-style.json
    var palette: String
    var gradient: [String]?            // overrides the palette's gradient (top color, bottom color)
    var layers: [Layer]                // back to front
    var scale: Double?                 // glyph scale around the canvas center (default 1)
    var offset: [Double]?              // glyph offset in canvas points, +y down (default [0, 0])
    var output: String?                // default "Output"
    var iOS: Bool?                     // also write AppIcon-iOS.appiconset (default true)
    var legacyShadow: Bool?            // overrides house style legacyMac.shadow.enabled
    var previewDock: Bool?             // draw the Dock rows on preview.png with this Mac's app icons (default true)
}

var arguments = Array(CommandLine.arguments.dropFirst())
let strict = arguments.contains("--strict"); arguments.removeAll { $0 == "--strict" }
var houseStyleArgument: String?
if let i = arguments.firstIndex(of: "--house-style"), i + 1 < arguments.count {
    houseStyleArgument = arguments[i + 1]; arguments.removeSubrange(i...(i + 1))
}
guard let configPath = arguments.first else {
    print("Usage: xcrun swift -O build-icon.swift <appicon.json> [--house-style <house-style.json>] [--strict]"); exit(2)
}

func fail(_ message: String) -> Never { FileHandle.standardError.write(("error: " + message + "\n").data(using: .utf8)!); exit(1) }
func decode<T: Decodable>(_ type: T.Type, _ url: URL) -> T {
    guard let data = try? Data(contentsOf: url) else { fail("cannot read \(url.path)") }
    do { return try JSONDecoder().decode(type, from: data) } catch { fail("\(url.lastPathComponent): \(error)") }
}

let configURL = URL(fileURLWithPath: configPath).standardizedFileURL
let configDir = configURL.deletingLastPathComponent()
let config = decode(AppConfig.self, configURL)
let houseURL: URL = {
    if let p = config.houseStyle { return URL(fileURLWithPath: p, relativeTo: configDir).standardizedFileURL }
    if let p = houseStyleArgument { return URL(fileURLWithPath: p).standardizedFileURL }
    fail("no house style: set \"houseStyle\" in the config or pass --house-style")
}()
let house = decode(HouseStyle.self, houseURL)
guard let palette = house.palettes[config.palette] else {
    fail("unknown palette \"\(config.palette)\"; available: \(house.palettes.keys.sorted().joined(separator: ", "))")
}
let outDir = URL(fileURLWithPath: config.output ?? "Output", relativeTo: configDir).standardizedFileURL

var errors: [String] = [], warnings: [String] = [], notes: [String] = []

// Decodable ignores unknown keys, so a misspelled optional key ("ofset") would silently do nothing.
if let raw = try? JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any] {
    let known: Set<String> = ["name", "houseStyle", "palette", "gradient", "layers", "scale", "offset", "output", "iOS", "legacyShadow", "previewDock"]
    let knownLayer: Set<String> = ["name", "svg", "color", "opacity", "glass"]
    for key in raw.keys.sorted() where !known.contains(key) && !key.hasPrefix("_") { warnings.append("\(configURL.lastPathComponent): unknown key \"\(key)\" is ignored") }
    for (i, layer) in ((raw["layers"] as? [[String: Any]]) ?? []).enumerated() {
        for key in layer.keys.sorted() where !knownLayer.contains(key) && !key.hasPrefix("_") { warnings.append("layers[\(i)]: unknown key \"\(key)\" is ignored") }
    }
}

// MARK: - Colors

struct RGBA { var r, g, b, a: Double
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var iconComposer: String { String(format: "extended-srgb:%.5f,%.5f,%.5f,%.5f", r, g, b, a) }
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    func contrast(_ o: RGBA) -> Double { let (a, b) = (luminance, o.luminance); return (max(a, b) + 0.05) / (min(a, b) + 0.05) }
}
func hex(_ s: String) -> RGBA? {
    var h = s.trimmingCharacters(in: .whitespaces)
    guard h.hasPrefix("#") else { return nil }
    h.removeFirst()
    if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
    let hasAlpha = h.count == 8
    let c = { (shift: UInt64) in Double((v >> shift) & 0xFF) / 255 }
    return hasAlpha ? RGBA(r: c(24), g: c(16), b: c(8), a: c(0)) : RGBA(r: c(16), g: c(8), b: c(0), a: 1)
}
func resolveColor(_ s: String, _ context: String) -> RGBA {
    if let c = hex(s) { return c }
    if let role = palette.colors[s], let c = hex(role) { return c }
    fail("\(context): \"\(s)\" is neither #RRGGBB nor a color of palette \"\(config.palette)\" (\(palette.colors.keys.sorted().joined(separator: ", ")))")
}

let gradientHex = config.gradient ?? palette.gradient
guard gradientHex.count == 2 else { fail("the background gradient needs exactly 2 colors (Icon Composer gradients have two stops)") }
let gradient = gradientHex.map { resolveColor($0, "gradient") }
// Icon Composer always draws the background gradient top to bottom (it ignores "orientation" on the document fill;
// verified with ictool), so the legacy renderer does the same.
let direction = [[0.5, 0.0], [0.5, 1.0]]

// MARK: - Layer input checks (no raster, no SF Symbols, no AI or traced art, no text or effects)

struct Layer { var name: String; var source: URL; var color: RGBA?; var opacity: Double; var glass: Bool; var svg: XMLDocument }

guard (1...4).contains(config.layers.count) else { fail("use 1 to 4 glyph layers (Icon Composer shows at most 4 groups); found \(config.layers.count)") }

let rasterExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "tif", "tiff", "bmp", "psd", "afphoto"]
let sfSymbolMarkers = ["sf symbols", "sfsymbols", "sf-symbols", "com.apple.sfsymbols", "sfsymbolspreview", "sf pro"]
let generatorMarkers = ["potrace", "autotrace", "vectorizer", "vectormagic", "vector magic", "image trace", "imagetrace", "firefly",
                        "midjourney", "dall-e", "dall·e", "dalle", "stable diffusion", "stablediffusion", "recraft", "ideogram",
                        "leonardo.ai", "openai", "chatgpt", "gemini", "imagen", "svgai", "svg.io", "generated by ai", "ai-generated"]
let sfWeightIDs = try! NSRegularExpression(pattern: #"id="(Ultralight|Thin|Light|Regular|Medium|Semibold|Bold|Heavy|Black)-(S|M|L)""#)

func lint(_ layer: AppConfig.Layer, _ url: URL) -> XMLDocument? {
    let label = "layer \(layer.name ?? url.lastPathComponent)"
    let ext = url.pathExtension.lowercased()
    if rasterExtensions.contains(ext) { errors.append("\(label): \(url.lastPathComponent) is a raster image. Draw the glyph as vector paths and export SVG."); return nil }
    guard ext == "svg" else { errors.append("\(label): expected an .svg file, got \(url.lastPathComponent)"); return nil }
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { errors.append("\(label): cannot read \(url.path)"); return nil }
    let lower = text.lowercased()
    if let m = sfSymbolMarkers.first(where: lower.contains) ?? (sfWeightIDs.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil ? "SF Symbols weight/scale group ids" : nil) {
        errors.append("\(label): looks like an SF Symbols export (\(m)). Apple's license does not allow SF Symbols in app icons or logos; draw your own glyph.")
    }
    if let m = generatorMarkers.first(where: lower.contains) {
        errors.append("\(label): the file mentions \"\(m)\", which suggests auto-traced or AI-generated art. Redraw it by hand.")
    }
    if lower.contains("data:image") || lower.range(of: ##"href="[^"#]+\.(png|jpe?g|gif|webp|heic)""##, options: .regularExpression) != nil {
        errors.append("\(label): contains embedded or linked raster images. Use vector paths only.")
    }
    guard let doc = try? XMLDocument(data: Data(text.utf8), options: [.nodePreserveWhitespace]), let root = doc.rootElement(), root.localName == "svg" else {
        errors.append("\(label): not a valid SVG document"); return nil
    }
    var counts: [String: Int] = [:]
    var pathCommands = 0
    func walk(_ e: XMLElement) {
        counts[e.localName ?? "", default: 0] += 1
        if let d = e.attribute(forName: "d")?.stringValue { pathCommands += d.filter { "MLHVCSQTAZmlhvcsqtaz".contains($0) }.count }
        e.children?.compactMap { $0 as? XMLElement }.forEach(walk)
    }
    walk(root)
    if counts["image", default: 0] > 0 { errors.append("\(label): contains <image> elements (raster). Use vector paths only.") }
    if counts["text", default: 0] + counts["textPath", default: 0] + counts["tspan", default: 0] > 0 {
        errors.append("\(label): contains live text. Convert text to curves, and check the font's license allows logo use (SF fonts do not).")
    }
    if counts["foreignObject", default: 0] > 0 { errors.append("\(label): contains <foreignObject>, which icon renderers ignore.") }
    if counts["filter", default: 0] > 0 { errors.append("\(label): uses SVG filters (blur, shadow, lighting). Keep glyphs flat; Icon Composer supplies depth.") }
    if counts["pattern", default: 0] > 0 { warnings.append("\(label): uses a <pattern> fill, which reads as texture. Prefer flat fills.") }
    if counts["linearGradient", default: 0] + counts["radialGradient", default: 0] > 0 {
        warnings.append("\(label): has its own gradient. Glyphs should be flat; also, CoreSVG (used by NSImage and Icon Composer) interpolates SVG gradients differently from browsers.")
    }
    if counts["mask", default: 0] > 0 { warnings.append("\(label): uses <mask>; flatten it into plain paths for predictable results.") }
    if pathCommands > 1500 || counts["path", default: 0] > 80 {
        warnings.append("\(label): \(pathCommands) path commands in \(counts["path", default: 0]) paths. That is typical of traced artwork; hand-drawn icon glyphs usually need well under 300.")
    }
    return doc
}

var layers: [Layer] = []
for (i, l) in config.layers.enumerated() {
    let url = URL(fileURLWithPath: l.svg, relativeTo: configDir).standardizedFileURL
    let name = (l.name ?? url.deletingPathExtension().lastPathComponent).replacingOccurrences(of: "/", with: "-")
    guard let doc = lint(l, url) else { continue }
    if let o = l.opacity, !(0...1).contains(o) { fail("layer \(name): opacity must be between 0 and 1") }
    layers.append(Layer(name: layers.contains { $0.name == name } ? "\(name)-\(i + 1)" : name, source: url,
                        color: l.color.map { resolveColor($0, "layer \(name)") }, opacity: l.opacity ?? 1,
                        glass: l.glass ?? house.iconComposer.glass, svg: doc))
}
if !errors.isEmpty {
    errors.forEach { print("error: \($0)") }
    print("Build stopped: fix the errors above."); exit(1)
}

// MARK: - Normalize each layer onto the 1024 canvas (one coordinate system for Icon Composer and the renderer)

let canvas = 1024.0
let glyphScale = config.scale ?? 1
let glyphOffset = config.offset ?? [0, 0]

func number(_ s: String?) -> Double? { s.flatMap { Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "px", with: "")) } }

/// Wraps the SVG's content in a 1024×1024 document with one transform: viewBox fit (centered), then the app's
/// scale and offset. Root presentation attributes (Affinity puts fill-rule on the root) move onto the wrapper group.
func normalized(_ layer: Layer) -> Data {
    let root = layer.svg.rootElement()!
    var vb: [Double] = root.attribute(forName: "viewBox")?.stringValue?
        .split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) } ?? []
    if vb.count != 4 {
        guard let w = number(root.attribute(forName: "width")?.stringValue), let h = number(root.attribute(forName: "height")?.stringValue) else {
            fail("layer \(layer.name): the SVG has neither a viewBox nor width/height")
        }
        vb = [0, 0, w, h]
    }
    if abs(vb[2] - vb[3]) > 0.5 {
        warnings.append("layer \(layer.name): artboard is \(Int(vb[2]))×\(Int(vb[3])), not square; it is centered on the canvas. Use a 1024×1024 artboard for every layer so they line up.")
    }
    let fit = canvas / max(vb[2], vb[3])
    let tx0 = (canvas - vb[2] * fit) / 2 - vb[0] * fit, ty0 = (canvas - vb[3] * fit) / 2 - vb[1] * fit
    let s = fit * glyphScale
    let tx = canvas / 2 + glyphOffset[0] + glyphScale * (tx0 - canvas / 2)
    let ty = canvas / 2 + glyphOffset[1] + glyphScale * (ty0 - canvas / 2)

    let svg = XMLElement(name: "svg")
    for ns in root.namespaces ?? [] { svg.addNamespace(ns.copy() as! XMLNode) }
    if svg.namespace(forPrefix: "") == nil { svg.addNamespace(XMLNode.namespace(withName: "", stringValue: "http://www.w3.org/2000/svg") as! XMLNode) }
    svg.addAttribute(XMLNode.attribute(withName: "width", stringValue: "1024") as! XMLNode)
    svg.addAttribute(XMLNode.attribute(withName: "height", stringValue: "1024") as! XMLNode)
    svg.addAttribute(XMLNode.attribute(withName: "viewBox", stringValue: "0 0 1024 1024") as! XMLNode)
    let group = XMLElement(name: "g")
    group.addAttribute(XMLNode.attribute(withName: "transform", stringValue: String(format: "matrix(%.6f 0 0 %.6f %.4f %.4f)", s, s, tx, ty)) as! XMLNode)
    let skip: Set<String> = ["width", "height", "viewBox", "x", "y", "version", "id", "preserveAspectRatio", "xml:space", "enable-background"]
    for attr in root.attributes ?? [] where !skip.contains(attr.name ?? "") && !(attr.name ?? "").hasPrefix("xmlns") {
        group.addAttribute(attr.copy() as! XMLNode)
    }
    for child in root.children ?? [] {
        let copy = child.copy() as! XMLNode
        if let e = child as? XMLElement, ["defs", "style"].contains(e.localName ?? "") { svg.addChild(copy) } else { group.addChild(copy) }
    }
    svg.addChild(group)
    let doc = XMLDocument(rootElement: svg)
    doc.characterEncoding = "UTF-8"; doc.isStandalone = true
    return doc.xmlData(options: [.nodePrettyPrint])
}

let fm = FileManager.default
try? fm.removeItem(at: outDir)
let iconDir = outDir.appendingPathComponent("AppIcon.icon"), assetsDir = iconDir.appendingPathComponent("Assets")
try! fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

var glyphImages: [NSImage] = []
for layer in layers {
    let url = assetsDir.appendingPathComponent("\(layer.name).svg")
    try! normalized(layer).write(to: url)
    guard let image = NSImage(contentsOf: url), image.representations.contains(where: { String(describing: type(of: $0)).contains("SVG") }) else {
        fail("layer \(layer.name): CoreSVG could not load the normalized SVG (\(url.path))")
    }
    glyphImages.append(image)
}

// MARK: - Rendering

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func context(_ w: Int, _ h: Int, opaque: Bool = false) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
              bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func writePNG(_ image: CGImage, _ url: URL) {
    try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("could not write \(url.path)") }
}

func loadImage(_ url: URL) -> CGImage? {
    CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
}

func withAppKit(_ ctx: CGContext, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    body()
    NSGraphicsContext.restoreGraphicsState()
}

/// Background gradient plus glyph layers, with the 1024 glyph canvas mapped onto `rect`.
func drawArtwork(_ ctx: CGContext, in rect: CGRect) {
    let g = CGGradient(colorsSpace: sRGB, colors: gradient.map(\.cg) as CFArray, locations: [0, 1])!
    func point(_ p: [Double]) -> CGPoint { CGPoint(x: rect.minX + p[0] * rect.width, y: rect.maxY - p[1] * rect.height) }
    ctx.saveGState(); ctx.clip(to: rect)
    ctx.drawLinearGradient(g, start: point(direction[0]), end: point(direction[1]), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
    for (layer, image) in zip(layers, glyphImages) { drawGlyph(ctx, layer, image, in: rect) }
}

func drawGlyph(_ ctx: CGContext, _ layer: Layer, _ image: NSImage, in rect: CGRect, color override: RGBA? = nil) {
    ctx.saveGState()
    ctx.setAlpha(layer.opacity)
    ctx.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
    withAppKit(ctx) { image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1) }
    if let c = override ?? layer.color {
        ctx.setBlendMode(.sourceIn); ctx.setFillColor(c.cg); ctx.fill(rect)
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

/// Grayscale mask of the icon body; continuous corners come from Core Animation (the same curve the system uses).
func bodyMask(size: Int, rect: CGRect, radius: CGFloat, continuous: Bool) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let shape = CALayer()
    shape.frame = CGRect(origin: .zero, size: rect.size)
    shape.backgroundColor = CGColor(gray: 1, alpha: 1)
    shape.cornerRadius = radius
    shape.cornerCurve = continuous ? .continuous : .circular
    ctx.translateBy(x: rect.minX, y: rect.minY)
    shape.render(in: ctx)
    return ctx.makeImage()!
}

let legacy = house.legacyMac
let legacyShadow = config.legacyShadow ?? legacy.shadow.enabled
let bodyFraction = (canvas - 2 * legacy.margin) / canvas

func renderLegacy(_ px: Int) -> CGImage {
    let k = CGFloat(px) / CGFloat(canvas)
    let full = CGRect(x: 0, y: 0, width: px, height: px)
    let body = CGRect(x: legacy.margin * k, y: legacy.margin * k, width: (canvas - 2 * legacy.margin) * k, height: (canvas - 2 * legacy.margin) * k)
    let art = context(px, px)
    art.clip(to: full, mask: bodyMask(size: px, rect: body, radius: legacy.cornerRadius * k, continuous: legacy.continuousCorners))
    drawArtwork(art, in: body)
    let out = context(px, px)
    if legacyShadow {
        out.setShadow(offset: CGSize(width: 0, height: -legacy.shadow.offsetY * k), blur: legacy.shadow.blur * k,
                      color: CGColor(gray: 0, alpha: legacy.shadow.opacity))
    }
    out.draw(art.makeImage()!, in: full)
    return out.makeImage()!
}

func renderIOS() -> CGImage {
    let ctx = context(1024, 1024, opaque: true)
    drawArtwork(ctx, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    return ctx.makeImage()!
}

// MARK: - AppIcon.appiconset (macOS) and AppIcon-iOS.appiconset

let macSlots: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
let macSet = outDir.appendingPathComponent("AppIcon.appiconset")
var rendered: [Int: CGImage] = [:]
var macImages: [[String: String]] = []
for slot in macSlots {
    let px = slot.points * slot.scale
    let image = rendered[px] ?? renderLegacy(px); rendered[px] = image
    let file = "icon_\(slot.points)x\(slot.points)\(slot.scale == 2 ? "@2x" : "").png"
    writePNG(image, macSet.appendingPathComponent(file))
    macImages.append(["filename": file, "idiom": "mac", "scale": "\(slot.scale)x", "size": "\(slot.points)x\(slot.points)"])
}
func writeJSON(_ object: Any, _ url: URL) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try! (data + Data("\n".utf8)).write(to: url)
}
let xcodeInfo = ["author": "xcode", "version": 1] as [String: Any]
writeJSON(["images": macImages, "info": xcodeInfo], macSet.appendingPathComponent("Contents.json"))

if config.iOS ?? true {
    let iosSet = outDir.appendingPathComponent("AppIcon-iOS.appiconset")
    writePNG(renderIOS(), iosSet.appendingPathComponent("AppIcon-1024.png"))
    writeJSON(["images": [["filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]], "info": xcodeInfo],
              iosSet.appendingPathComponent("Contents.json"))
}

// MARK: - AppIcon.icon (Icon Composer)

var groups: [[String: Any]] = []
for layer in layers.reversed() {                       // icon.json lists groups front to back
    var l: [String: Any] = ["name": layer.name, "image-name": "\(layer.name).svg", "glass": layer.glass]
    if let c = layer.color { l["fill"] = ["solid": c.iconComposer] }
    if layer.opacity < 1 { l["opacity"] = layer.opacity }
    groups.append([
        "layers": [l],
        "shadow": ["kind": house.iconComposer.shadowKind, "opacity": house.iconComposer.shadowOpacity],
        "translucency": ["enabled": house.iconComposer.translucency > 0, "value": house.iconComposer.translucency],
        "specular": house.iconComposer.specular,
    ])
}
writeJSON([
    "fill": ["linear-gradient": gradient.map(\.iconComposer)],
    "groups": groups,
    "supported-platforms": ["circles": ["watchOS"], "squares": "shared"],
], iconDir.appendingPathComponent("icon.json"))

// Apple's own Liquid Glass renders, using Icon Composer's command-line renderer.
func findICTool() -> URL? {
    var candidates = [ProcessInfo.processInfo.environment["ICTOOL"]].compactMap { $0 }
    candidates.append("/Applications/Icon Composer.app/Contents/Executables/ictool")
    let xs = Process(); let pipe = Pipe()
    xs.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select"); xs.arguments = ["-p"]; xs.standardOutput = pipe
    if (try? xs.run()) != nil {
        xs.waitUntilExit()
        let dev = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        candidates.append(URL(fileURLWithPath: dev).deletingLastPathComponent().appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool").path)
    }
    return candidates.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
}
let rendersDir = outDir.appendingPathComponent("Renders")
var glass: [String: CGImage] = [:]                  // "<rendition>-<px>"
if let ictool = findICTool() {
    let jobs: [(String, Int)] = [("Default", 32), ("Default", 64), ("Default", 256), ("Dark", 64), ("Dark", 256),
                                 ("TintedDark", 256), ("ClearLight", 256), ("ClearDark", 256)]
    for (rendition, px) in jobs {
        let file = rendersDir.appendingPathComponent("macOS-\(rendition)-\(px).png")
        try! fm.createDirectory(at: rendersDir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = ictool
        p.arguments = [iconDir.path, "--export-image", "--output-file", file.path, "--platform", "macOS", "--rendition", rendition,
                       "--width", "\(px)", "--height", "\(px)", "--scale", "1"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        if p.terminationStatus == 0, let image = loadImage(file) { glass["\(rendition)-\(px)"] = image }
        else { warnings.append("Icon Composer's ictool could not render AppIcon.icon (\(rendition), \(px) px). Open it in Icon Composer to check.") }
    }
} else {
    notes.append("Icon Composer's ictool was not found, so the preview has no Liquid Glass renders. Set ICTOOL=/path/to/ictool.")
}

// MARK: - Legibility analysis (on the glyph canvas, measured in pixels of the 32 px icon)

let A = 512                                         // analysis resolution for the 1024 canvas
let px32 = Double(A) / (32 * bodyFraction)          // analysis pixels per pixel of the 32 px icon

func mask(_ images: [NSImage]) -> [Bool] {
    let ctx = context(A, A)
    for image in images { withAppKit(ctx) { image.draw(in: NSRect(x: 0, y: 0, width: A, height: A), from: .zero, operation: .sourceOver, fraction: 1) } }
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self), row = ctx.bytesPerRow
    return (0..<(A * A)).map { i in data[(i / A) * row + (i % A) * 4 + 3] >= 128 }  // row 0 = top
}

/// Euclidean distance from each pixel to the nearest pixel where `inside` is false (Felzenszwalb & Huttenlocher).
func distance(_ inside: [Bool]) -> [Double] {
    let big = 1e12
    var f = inside.map { $0 ? big : 0 }
    func pass(_ get: (Int) -> Int) {
        var d = [Double](repeating: 0, count: A), v = [Int](repeating: 0, count: A), z = [Double](repeating: 0, count: A + 1)
        let g = (0..<A).map { f[get($0)] }
        var k = 0; v[0] = 0; z[0] = -big; z[1] = big
        for q in 1..<A {
            var s = ((g[q] + Double(q * q)) - (g[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
            while s <= z[k] { k -= 1; s = ((g[q] + Double(q * q)) - (g[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k]) }
            k += 1; v[k] = q; z[k] = s; z[k + 1] = big
        }
        k = 0
        for q in 0..<A { while z[k + 1] < Double(q) { k += 1 }; d[q] = Double((q - v[k]) * (q - v[k])) + g[v[k]] }
        for q in 0..<A { f[get(q)] = d[q] }
    }
    for x in 0..<A { pass { $0 * A + x } }
    for y in 0..<A { pass { y * A + $0 } }
    return f.map { $0.squareRoot() }
}

func components(_ m: [Bool], _ value: Bool) -> [(area: Int, touchesEdge: Bool)] {
    var seen = [Bool](repeating: false, count: A * A), result: [(Int, Bool)] = []
    for start in 0..<(A * A) where m[start] == value && !seen[start] {
        var stack = [start], area = 0, edge = false; seen[start] = true
        while let i = stack.popLast() {
            area += 1
            let x = i % A, y = i / A
            if x == 0 || y == 0 || x == A - 1 || y == A - 1 { edge = true }
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < A && ny < A {
                let j = ny * A + nx
                if m[j] == value && !seen[j] { seen[j] = true; stack.append(j) }
            }
        }
        result.append((area, edge))
    }
    return result
}

struct Legibility { var coverage: Double; var bounds: CGRect; var thinFraction: Double; var medianStroke32: Double; var specks: Int; var smallHoles: Int }

func analyze(_ m: [Bool]) -> Legibility? {
    let count = m.filter { $0 }.count
    guard count > 0 else { return nil }
    var minX = A, minY = A, maxX = 0, maxY = 0
    for i in 0..<(A * A) where m[i] { let x = i % A, y = i / A; minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
    let d = distance(m)
    let r = house.glyph.minStroke32 / 2 * px32
    let core = d.map { $0 > r }                       // morphological opening with a disk of radius r:
    let near = distance(core.map { !$0 })             // parts the disk cannot reach are thinner than minStroke32
    let thin = (0..<(A * A)).filter { m[$0] && near[$0] > r }.count
    var ridge: [Double] = []                          // local maxima of the distance map ≈ half stroke widths
    for y in 1..<(A - 1) { for x in 1..<(A - 1) {
        let i = y * A + x, v = d[i]
        if v >= 2 && v >= d[i - 1] && v >= d[i + 1] && v >= d[i - A] && v >= d[i + A] { ridge.append(v) }
    } }
    ridge.sort()
    let speck = px32 * px32
    return Legibility(coverage: Double(count) / Double(A * A),
                      bounds: CGRect(x: Double(minX) / Double(A), y: Double(minY) / Double(A), width: Double(maxX - minX + 1) / Double(A), height: Double(maxY - minY + 1) / Double(A)),
                      thinFraction: Double(thin) / Double(count),
                      medianStroke32: ridge.isEmpty ? 0 : 2 * ridge[ridge.count / 2] / px32,
                      specks: components(m, true).filter { Double($0.area) < speck }.count,
                      smallHoles: components(m, false).filter { !$0.touchesEdge && Double($0.area) < speck }.count)
}

var metrics: [String] = []
let union = mask(glyphImages)
guard let all = analyze(union) else { fail("the glyph layers render empty") }
let g = house.glyph
metrics.append(String(format: "Glyph: covers %.0f%% of the canvas, spans %.0f%% × %.0f%%, median stroke %.1f px at 32 px",
                      all.coverage * 100, all.bounds.width * 100, all.bounds.height * 100, all.medianStroke32))
if max(all.bounds.width, all.bounds.height) < g.minExtent {
    warnings.append(String(format: "The glyph spans only %.0f%% of the canvas (house minimum %.0f%%). Scale it up; it will be tiny at 16 and 32 px.", max(all.bounds.width, all.bounds.height) * 100, g.minExtent * 100))
}
let inset = g.safeInset
if all.bounds.minX < inset - 0.002 || all.bounds.minY < inset - 0.002 || all.bounds.maxX > 1 - inset + 0.002 || all.bounds.maxY > 1 - inset + 0.002 {
    warnings.append(String(format: "The glyph extends outside the safe area (%.0f pt inset on the 1024 canvas). Edges near the icon shape get clipped or crowded.", inset * canvas))
}
if all.coverage < 0.06 { warnings.append(String(format: "The glyph covers only %.1f%% of the canvas; it will read as a faint mark at 32 px. Use bolder shapes.", all.coverage * 100)) }
for (layer, image) in zip(layers, glyphImages) {
    guard let m = analyze(mask([image])) else { warnings.append("layer \(layer.name): renders empty"); continue }
    metrics.append(String(format: "Layer %@: coverage %.1f%%, %.0f%% thinner than %.1f px at 32 px, median stroke %.1f px, %d specks, %d small holes",
                          layer.name, m.coverage * 100, m.thinFraction * 100, g.minStroke32, m.medianStroke32, m.specks, m.smallHoles))
    if m.thinFraction > g.maxThinFraction {
        warnings.append(String(format: "layer %@: %.0f%% of it is thinner than %.1f px at 32 px and will blur or vanish. Thicken strokes to about %.0f pt on the 1024 canvas.",
                               layer.name, m.thinFraction * 100, g.minStroke32, g.minStroke32 * canvas / (32 * bodyFraction)))
    }
    if m.specks > 0 { warnings.append("layer \(layer.name): \(m.specks) separate piece(s) smaller than one pixel at 32 px. Remove or merge small details.") }
    if m.smallHoles > 0 { warnings.append("layer \(layer.name): \(m.smallHoles) hole(s) smaller than one pixel at 32 px will fill in. Open them up or remove them.") }
    if let c = layer.color {
        let contrast = gradient.map { c.contrast($0) }.min()!
        if contrast < g.minContrast {
            warnings.append(String(format: "layer %@: contrast against the background is %.1f:1 (house minimum %.1f:1).", layer.name, contrast, g.minContrast))
        }
    }
}
// Format guard: actool ignores unknown icon.json keys, so check that Apple's render really uses the palette. Its glass
// lighting shifts colors by up to ~0.1, so this only catches gross mismatches (a fill Icon Composer did not understand).
if let render = glass["Default-256"] {
    let ctx = context(256, 256); ctx.draw(render, in: CGRect(x: 0, y: 0, width: 256, height: 256))
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let d0 = direction[0], d1 = direction[1]
    let dx = d1[0] - d0[0], dy = d1[1] - d0[1], len2 = max(dx * dx + dy * dy, 1e-9)
    var worst = 0.0, sampled = 0
    for (u, v) in [(0.5, 0.1), (0.5, 0.9), (0.1, 0.5), (0.9, 0.5), (0.25, 0.25), (0.75, 0.75)] {
        let ax = Int(u * Double(A)), ay = Int(v * Double(A))
        let clear = (-12...12).allSatisfy { oy in (-12...12).allSatisfy { ox in !union[(ay + oy) * A + ax + ox] } }
        guard clear else { continue }
        let t = min(max(((u - d0[0]) * dx + (v - d0[1]) * dy) / len2, 0), 1)
        let expected = [gradient[0].r + (gradient[1].r - gradient[0].r) * t, gradient[0].g + (gradient[1].g - gradient[0].g) * t,
                        gradient[0].b + (gradient[1].b - gradient[0].b) * t]
        let i = Int(v * 255) * ctx.bytesPerRow + Int(u * 255) * 4
        let alpha = Double(data[i + 3]) / 255
        guard alpha > 0.9 else { continue }
        for c in 0..<3 { worst = max(worst, abs(Double(data[i + c]) / 255 / alpha - expected[c])) }
        sampled += 1
    }
    if sampled == 0 { notes.append("Could not compare Apple's render with the palette: the glyph covers every sample point.") }
    else if worst > 0.2 {
        warnings.append(String(format: "Apple's render of AppIcon.icon differs from the palette by %.2f (sRGB). Icon Composer may not have understood icon.json; open it in Icon Composer and check the background.", worst))
    } else { metrics.append(String(format: "Icon Composer render matches the palette background (max deviation %.2f, glass lighting included).", worst)) }
}
if layers.allSatisfy({ $0.color == nil }) { notes.append("No layer sets a color, so Icon Composer keeps the SVG colors and its tinted/clear modes cannot recolor them.") }

// MARK: - Preview sheet

final class Sheet {
    let w: Int, h: Int, ctx: CGContext
    init(_ w: Int, _ h: Int) { self.w = w; self.h = h; ctx = context(w, h) }
    func r(_ x: Double, _ top: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x: x, y: Double(self.h) - top - h, width: w, height: h) }
    func fill(_ rect: CGRect, _ color: CGColor, radius: Double = 0) {
        ctx.setFillColor(color); ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.fillPath()
    }
    func image(_ image: CGImage, _ rect: CGRect, nearest: Bool = false) {
        ctx.saveGState(); ctx.interpolationQuality = nearest ? .none : .high; ctx.draw(image, in: rect); ctx.restoreGState()
    }
    func text(_ s: String, _ x: Double, _ top: Double, size: Double = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor, center: Double? = nil) {
        let attributed = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        let width = attributed.size().width
        withAppKit(ctx) { attributed.draw(at: NSPoint(x: center.map { $0 - width / 2 } ?? x, y: Double(h) - top - size * 1.25)) }
    }
}

let sizes = [16, 32, 64, 128, 256, 512]
for px in [64] where rendered[px] == nil { rendered[px] = renderLegacy(px) }
let margin = 40.0, gap = 36.0
let rowWidth = Double(sizes.reduce(0, +)) + gap * Double(sizes.count + 1)
let W = Int(rowWidth + 2 * margin)
let ink = NSColor(white: 0.12, alpha: 1), soft = NSColor(white: 0.45, alpha: 1)
let dockApps = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.Notes", "com.apple.iCal", "com.apple.Music",
                "com.apple.systempreferences"].compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.resolvingSymlinksInPath().path }
let hasGlass = !glass.isEmpty
let glassHeight: Int = hasGlass ? 330 : 0
let showDock = config.previewDock ?? true
let dockHeight: Int = showDock ? (glass["Default-64"] == nil ? 1 : 2) * 150 : 0
let H: Int = 80 + 2 * (512 + 70) + 330 + glassHeight + dockHeight + 40
let sheet = Sheet(W, H)
sheet.fill(CGRect(x: 0, y: 0, width: W, height: H), CGColor(gray: 1, alpha: 1))
var top = 32.0
sheet.text("\(config.name) — app icon preview", margin, top, size: 22, weight: .semibold, color: ink)
sheet.text("Palette \(config.palette) · \(layers.count) layer(s) · \(warnings.count) warning(s) · all icons at actual pixel size (1x)", margin, top + 30, size: 13, color: soft)
top += 80

for (label, bg, fg) in [("Legacy macOS icon (AppIcon.appiconset) on a light background", CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1), NSColor(white: 0.4, alpha: 1)),
                        ("…and on a dark background", CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1), NSColor(white: 0.7, alpha: 1))] {
    sheet.text(label, margin, top, size: 13, weight: .medium, color: ink)
    let panel = sheet.r(margin, top + 22, rowWidth, 512 + 40)
    sheet.fill(panel, bg, radius: 14)
    var x = margin + gap
    for px in sizes {
        let image = rendered[px] ?? loadImage(macSet.appendingPathComponent(px == 1024 ? "icon_512x512@2x.png" : "icon_\(px)x\(px).png")) ?? renderLegacy(px)
        let baseline = top + 22 + 20 + 512
        sheet.image(image, sheet.r(x, baseline - Double(px), Double(px), Double(px)))
        sheet.text("\(px)", x, baseline + 2, size: 11, color: fg, center: x + Double(px) / 2)
        x += Double(px) + gap
    }
    top += 512 + 70
}

// Zoomed small sizes: exact pixels, nearest-neighbor ×8.
sheet.text("Small sizes magnified ×8 (nearest neighbor): what the pixels really are", margin, top, size: 13, weight: .medium, color: ink)
var zx = margin
for (px, src) in [(16, rendered[16]!), (32, rendered[32]!)] + (glass["Default-32"].map { [(32, $0)] } ?? []) {
    let side = Double(px * 8)
    let tile = sheet.r(zx, top + 24, side, side)
    sheet.fill(tile, CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1))
    sheet.image(src, tile, nearest: true)
    sheet.text(src === glass["Default-32"] ? "32 px · Liquid Glass" : "\(px) px · legacy", zx, top + 24 + side + 4, size: 11, color: soft)
    zx += side + gap
}
top += 330

if hasGlass {
    sheet.text("Icon Composer render (AppIcon.icon via ictool, macOS 26 Liquid Glass): Default · Dark · Clear light · Clear dark · Tinted dark", margin, top, size: 13, weight: .medium, color: ink)
    let renditions: [(String, Double)] = [("Default", 0.96), ("Dark", 0.11), ("ClearLight", 0.80), ("ClearDark", 0.11), ("TintedDark", 0.11)]
    let side = ((rowWidth - Double(renditions.count - 1) * 16) / Double(renditions.count) - 32).rounded(.down)
    var gx = margin
    for (rendition, bg) in renditions {
        let panel = sheet.r(gx, top + 24, side + 32, side + 32)
        sheet.fill(panel, CGColor(gray: bg, alpha: 1), radius: 14)
        if let image = glass["\(rendition)-256"] { sheet.image(image, panel.insetBy(dx: 16, dy: 16)) }
        gx += side + 32 + 16
    }
    top += 330
}

// Dock rows: 64 px tiles between real system apps. macOS 26 draws icons in the same 824/1024 body with its own shadow
// (measured: 8 pt down, 32 pt blur, 25% black), so the Liquid Glass render is placed the same way.
func dockRow(_ title: String, _ icon: (CGRect) -> Void, wallpaper: [CGColor]) {
    sheet.text(title, margin, top, size: 13, weight: .medium, color: ink)
    let wall = sheet.r(margin, top + 22, rowWidth, 112)
    sheet.ctx.saveGState(); sheet.ctx.addPath(CGPath(roundedRect: wall, cornerWidth: 14, cornerHeight: 14, transform: nil)); sheet.ctx.clip()
    sheet.ctx.drawLinearGradient(CGGradient(colorsSpace: sRGB, colors: wallpaper as CFArray, locations: [0, 1])!,
                                 start: CGPoint(x: wall.minX, y: wall.maxY), end: CGPoint(x: wall.maxX, y: wall.minY), options: [])
    sheet.ctx.restoreGState()
    let count = dockApps.count + 1, tile = 64.0, spacing = 6.0
    let dockWidth = Double(count) * tile + Double(count - 1) * spacing + 20
    let dockX: Double = margin + (rowWidth - dockWidth) / 2
    let dockTop: Double = top + 40
    let dock = sheet.r(dockX, dockTop, dockWidth, tile + 12)
    sheet.fill(dock, CGColor(gray: 1, alpha: 0.35), radius: 22)
    sheet.ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.55)); sheet.ctx.setLineWidth(1)
    sheet.ctx.addPath(CGPath(roundedRect: dock.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 22, cornerHeight: 22, transform: nil)); sheet.ctx.strokePath()
    var x = dock.minX + 10
    let mid = dockApps.count / 2
    for i in 0..<count {
        let rect = CGRect(x: x, y: dock.minY + 6, width: tile, height: tile)
        if i == mid { icon(rect) } else {
            let app = dockApps[i < mid ? i : i - 1]
            withAppKit(sheet.ctx) { NSWorkspace.shared.icon(forFile: app).draw(in: rect) }
        }
        x += tile + spacing
    }
    top += 150
}
let wallpaper = [CGColor(srgbRed: 0.55, green: 0.68, blue: 0.86, alpha: 1), CGColor(srgbRed: 0.93, green: 0.80, blue: 0.72, alpha: 1)]
if showDock, let g64 = glass["Default-64"] {
    dockRow("Dock, macOS 26 (Liquid Glass from AppIcon.icon)", { rect in
        let k = rect.width / CGFloat(canvas), body = rect.insetBy(dx: 100 * k, dy: 100 * k)
        sheet.ctx.saveGState()
        sheet.ctx.setShadow(offset: CGSize(width: 0, height: -8 * k), blur: 32 * k, color: CGColor(gray: 0, alpha: 0.25))
        sheet.image(g64, body)
        sheet.ctx.restoreGState()
    }, wallpaper: wallpaper)
}
if showDock {
    dockRow("Dock, macOS 11–15 (legacy AppIcon.appiconset)", { rect in sheet.image(rendered[64]!, rect) }, wallpaper: wallpaper)
}
writePNG(sheet.ctx.makeImage()!, outDir.appendingPathComponent("preview.png"))

// MARK: - Report

var report = ["\(config.name): icon build report", "",
              "Inputs: palette \(config.palette), layers (back to front): " + layers.map { "\($0.name) ← \($0.source.lastPathComponent)" }.joined(separator: ", "), ""]
report += metrics + [""]
report += warnings.isEmpty ? ["No warnings."] : warnings.map { "warning: \($0)" }
report += notes.map { "note: \($0)" }
try! (report.joined(separator: "\n") + "\n").write(to: outDir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
print(report.joined(separator: "\n"))
print("\nWrote \(outDir.path)/{AppIcon.icon, AppIcon.appiconset\(config.iOS ?? true ? ", AppIcon-iOS.appiconset" : ""), Renders, preview.png, report.txt}")
if strict && !warnings.isEmpty { print("Failing because of --strict."); exit(1) }
