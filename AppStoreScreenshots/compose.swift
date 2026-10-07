// Composes App Store marketing screenshots from raw app captures. No dependencies beyond macOS frameworks.
//
// Usage: xcrun swift compose.swift <config.json> <captures-dir> <output-dir> [--overview <file.png>] [--strict]
//
// Each shot draws a background gradient, a headline and subtitle, and one or more captured windows (rounded,
// shadowed, optionally running off the bottom edge). Output is opaque PNG (no alpha channel) at every configured size.
// Before drawing anything it checks that every capture exists; while drawing it warns about sizes App Store Connect
// rejects, text that wraps or collides with a window, and captures that would be upscaled (blurry).
// --overview writes a contact sheet of all shots for review. --strict fails on warnings.
// See README.md for the configuration format.

import AppKit
import ImageIO
import UniformTypeIdentifiers

struct Config: Decodable {
    struct Size: Decodable { var width: Int; var height: Int }
    struct Style: Decodable {
        var background: [String]?          // gradient colors, top-left to bottom-right (one color = flat)
        var textColor: String?
        var subtitleColor: String?
        var headlineSize: Double?          // fraction of canvas height
        var subtitleSize: Double?
        var padding: Double?               // fraction of canvas width (left/right text margin)
        var top: Double?                   // fraction of canvas height above the headline
        var align: String?                 // "left" (default) or "center"
        var subtitleWidth: Double?         // fraction of the text width the subtitle may use (default 0.62; 1 when centered)
        var windowTop: Double?             // fraction of canvas height where windows start
        var windowWidth: Double?           // fraction of canvas width
        var cornerRadius: Double?          // fraction of each window's drawn width
        var shadow: Bool?
    }
    struct Layer: Decodable {
        var capture: String                // capture name (file name without .png)
        var width: Double?                 // fraction of canvas width
        var x: Double?                     // left edge, fraction of canvas width (default: centered)
        var y: Double?                     // top edge, fraction of canvas height (default: style.windowTop)
    }
    struct Shot: Decodable {
        var output: String
        var headline: String
        var subtitle: String?
        var layers: [Layer]
        var style: Style?                  // per-shot overrides
    }
    var sizes: [Size]
    var style: Style
    var shots: [Shot]
}

extension Config.Style {
    func merged(with override: Config.Style?) -> Config.Style {
        guard let o = override else { return self }
        return Config.Style(background: o.background ?? background, textColor: o.textColor ?? textColor, subtitleColor: o.subtitleColor ?? subtitleColor,
                            headlineSize: o.headlineSize ?? headlineSize, subtitleSize: o.subtitleSize ?? subtitleSize, padding: o.padding ?? padding,
                            top: o.top ?? top, align: o.align ?? align, subtitleWidth: o.subtitleWidth ?? subtitleWidth,
                            windowTop: o.windowTop ?? windowTop, windowWidth: o.windowWidth ?? windowWidth,
                            cornerRadius: o.cornerRadius ?? cornerRadius, shadow: o.shadow ?? shadow)
    }
}

/// Pixel sizes App Store Connect accepts (developer.apple.com/help/app-store-connect/reference/screenshot-specifications).
let acceptedSizes: [String: [(Int, Int)]] = [
    "Mac": [(1280, 800), (1440, 900), (2560, 1600), (2880, 1800)],
    "iPhone 6.9\"": [(1260, 2736), (1290, 2796), (1320, 2868), (2736, 1260), (2796, 1290), (2868, 1320)],
    "iPhone 6.5\"": [(1284, 2778), (1242, 2688), (2778, 1284), (2688, 1242)],
    "iPad 13\"": [(2064, 2752), (2048, 2732), (2752, 2064), (2732, 2048)],
]

var warnings: [String] = []

func color(_ hex: String) -> CGColor {
    var value: UInt64 = 0
    Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
    let hasAlpha = hex.count > 7
    let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255, g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
    let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255, a = hasAlpha ? Double(value & 0xFF) / 255 : 1
    return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func loadImage(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func render(_ shot: Config.Shot, style: Config.Style, width: Int, height: Int, captures: [String: CGImage]) throws -> CGImage {
    let W = CGFloat(width), H = CGFloat(height)
    let label = "\(shot.output) (\(width)×\(height))"
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw NSError(domain: "compose", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create a \(width)x\(height) context"])
    }
    // Background
    let stops = (style.background ?? ["#F5F3EF", "#E6EAEE"]).map(color)
    if stops.count > 1, let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops as CFArray, locations: nil) {
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
    } else {
        context.setFillColor(stops.first ?? color("#FFFFFF")); context.fill(CGRect(x: 0, y: 0, width: W, height: H))
    }
    // Windows
    let defaultWidth = style.windowWidth ?? 0.84, windowTop = style.windowTop ?? 0.30
    var highestWindowTop = H                           // distance from the top of the canvas to the highest window
    for layer in shot.layers {
        let image = captures[layer.capture]!
        let drawnWidth = W * CGFloat(layer.width ?? defaultWidth)
        let drawnHeight = drawnWidth * CGFloat(image.height) / CGFloat(image.width)
        let x = layer.x.map { W * CGFloat($0) } ?? (W - drawnWidth) / 2
        let top = H * CGFloat(layer.y ?? windowTop)
        highestWindowTop = min(highestWindowTop, top)
        let upscale = drawnWidth / CGFloat(image.width)
        if upscale > 1.15 {
            warnings.append(String(format: "%@: capture \"%@\" is %d px wide but drawn %.0f px wide (×%.1f, blurry). Capture on a Retina display or draw it smaller.",
                                   label, layer.capture, image.width, drawnWidth, upscale))
        }
        if x < -1 || x + drawnWidth > W + 1 { warnings.append("\(label): window \"\(layer.capture)\" runs off the left or right edge.") }
        let rect = CGRect(x: x, y: H - top - drawnHeight, width: drawnWidth, height: drawnHeight)
        let radius = drawnWidth * CGFloat(style.cornerRadius ?? 0.016)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if style.shadow ?? true {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -H * 0.012), blur: H * 0.05, color: CGColor(gray: 0, alpha: 0.35))
            context.addPath(path); context.setFillColor(CGColor(gray: 0.5, alpha: 1)); context.fillPath()
            context.restoreGState()
        }
        context.saveGState()
        context.addPath(path); context.clip()
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        context.restoreGState()
        context.addPath(path); context.setStrokeColor(CGColor(gray: 0.5, alpha: 0.35)); context.setLineWidth(max(1, W / 2880)); context.strokePath()
    }
    // Text
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
    let centered = style.align == "center"
    let padding = W * CGFloat(style.padding ?? 0.042)
    let textWidth = W - padding * 2
    var cursor = H - H * CGFloat(style.top ?? 0.075)
    let paragraph = NSMutableParagraphStyle(); paragraph.lineHeightMultiple = 0.95
    paragraph.alignment = centered ? .center : .left
    let headlineFont = NSFont.systemFont(ofSize: H * CGFloat(style.headlineSize ?? 0.052), weight: .bold)
    let headline = NSAttributedString(string: shot.headline, attributes: [
        .font: headlineFont, .foregroundColor: NSColor(cgColor: color(style.textColor ?? "#1D1D1F")) ?? .black, .paragraphStyle: paragraph, .kern: -0.5
    ])
    let headlineBounds = headline.boundingRect(with: NSSize(width: textWidth, height: H), options: [.usesLineFragmentOrigin, .usesFontLeading])
    // More lines than the headline's own line breaks means the text wrapped by itself.
    let explicitLines = shot.headline.split(separator: "\n", omittingEmptySubsequences: false).count
    let lineHeight = headlineFont.ascender - headlineFont.descender + headlineFont.leading
    if headlineBounds.height > lineHeight * 0.95 * CGFloat(explicitLines) * 1.25 {
        warnings.append("\(label): the headline wraps on its own. Shorten it or add explicit line breaks (\\n).")
    }
    cursor -= ceil(headlineBounds.height)
    headline.draw(with: NSRect(x: padding, y: cursor, width: textWidth, height: ceil(headlineBounds.height)), options: [.usesLineFragmentOrigin, .usesFontLeading])
    if let subtitleText = shot.subtitle {
        let subtitleWidth = textWidth * CGFloat(style.subtitleWidth ?? (centered ? 1 : 0.62))
        let subtitleParagraph = NSMutableParagraphStyle(); subtitleParagraph.alignment = paragraph.alignment
        let subtitle = NSAttributedString(string: subtitleText, attributes: [
            .font: NSFont.systemFont(ofSize: H * CGFloat(style.subtitleSize ?? 0.022), weight: .regular),
            .foregroundColor: NSColor(cgColor: color(style.subtitleColor ?? "#6E6E73")) ?? .gray, .paragraphStyle: subtitleParagraph
        ])
        let bounds = subtitle.boundingRect(with: NSSize(width: subtitleWidth, height: H), options: [.usesLineFragmentOrigin, .usesFontLeading])
        cursor -= ceil(bounds.height) + H * 0.012
        let x = centered ? (W - subtitleWidth) / 2 : padding
        subtitle.draw(with: NSRect(x: x, y: cursor, width: subtitleWidth, height: ceil(bounds.height)), options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
    NSGraphicsContext.restoreGraphicsState()
    // `cursor` is the bottom of the text block (from the bottom of the canvas); windows start at highestWindowTop.
    if !shot.layers.isEmpty && H - cursor > highestWindowTop - H * 0.01 {
        warnings.append("\(label): the text runs into the window. Raise windowTop/y or shorten the text.")
    }
    guard let result = context.makeImage() else { throw NSError(domain: "compose", code: 3) }
    return result
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "compose", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot write \(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "compose", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot write \(url.path)"]) }
}

/// A contact sheet of every composed image (first size only), for reviewing the set at a glance.
func overview(_ images: [(String, CGImage)]) -> CGImage? {
    guard let first = images.first?.1 else { return nil }
    let columns = min(3, images.count), rows = (images.count + columns - 1) / columns
    let cellWidth = 640.0, cellHeight = cellWidth * Double(first.height) / Double(first.width), gap = 32.0, label = 28.0
    let width = Int(gap + Double(columns) * (cellWidth + gap)), height = Int(gap + Double(rows) * (cellHeight + label + gap))
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(gray: 0.93, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    for (i, (name, image)) in images.enumerated() {
        let x = gap + Double(i % columns) * (cellWidth + gap)
        let top = gap + Double(i / columns) * (cellHeight + label + gap)
        let h = cellWidth * Double(image.height) / Double(image.width)
        let rect = CGRect(x: x, y: Double(height) - top - h, width: cellWidth, height: h)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
        NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor(white: 0.25, alpha: 1)])
            .draw(at: NSPoint(x: x, y: rect.minY - 24))
    }
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()
}

var arguments = Array(CommandLine.arguments.dropFirst())
let strict = arguments.contains("--strict"); arguments.removeAll { $0 == "--strict" }
var overviewPath: String?
if let i = arguments.firstIndex(of: "--overview"), i + 1 < arguments.count { overviewPath = arguments[i + 1]; arguments.removeSubrange(i...(i + 1)) }
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: compose.swift <config.json> <captures-dir> <output-dir> [--overview <file.png>] [--strict]\n".utf8)); exit(64)
}
do {
    let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[0])))
    let capturesDir = URL(fileURLWithPath: arguments[1]), output = URL(fileURLWithPath: arguments[2])

    // Check every capture up front, so one run lists everything that is missing.
    var captures: [String: CGImage] = [:], missing: [String] = []
    for name in Set(config.shots.flatMap { $0.layers.map(\.capture) }).sorted() {
        if let image = loadImage(capturesDir.appendingPathComponent(name + ".png")) { captures[name] = image } else { missing.append(name) }
    }
    if !missing.isEmpty {
        let available = ((try? FileManager.default.contentsOfDirectory(atPath: capturesDir.path)) ?? []).filter { $0.hasSuffix(".png") }.sorted()
        throw NSError(domain: "compose", code: 2, userInfo: [NSLocalizedDescriptionKey:
            "missing captures in \(capturesDir.path): \(missing.joined(separator: ", ")). Available: \(available.isEmpty ? "none" : available.joined(separator: ", "))"])
    }
    for size in config.sizes where !acceptedSizes.values.contains(where: { $0.contains { $0 == (size.width, size.height) } }) {
        warnings.append("\(size.width)×\(size.height) is not a size App Store Connect accepts (Mac: 2880×1800, 2560×1600, 1440×900, 1280×800; iPhone 6.9\": 1320×2868; iPad 13\": 2064×2752).")
    }

    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    var written: Set<String> = [], sheet: [(String, CGImage)] = []
    for shot in config.shots {
        for (index, size) in config.sizes.enumerated() {
            let image = try render(shot, style: config.style.merged(with: shot.style), width: size.width, height: size.height, captures: captures)
            let suffix = config.sizes.count > 1 ? "-\(size.width)x\(size.height)" : ""
            let file = output.appendingPathComponent("\(shot.output)\(suffix).png")
            try writePNG(image, to: file)
            written.insert(file.lastPathComponent)
            if index == 0 { sheet.append((file.lastPathComponent, image)) }
            print("wrote \(file.path)")
        }
    }
    // Files from an earlier config would otherwise be uploaded along with the new set.
    let stale = ((try? FileManager.default.contentsOfDirectory(atPath: output.path)) ?? []).filter { $0.hasSuffix(".png") && !written.contains($0) }.sorted()
    if !stale.isEmpty { warnings.append("\(output.path) also contains \(stale.joined(separator: ", ")), which this config did not produce. Delete them before uploading.") }
    if let overviewPath, let image = overview(sheet) {
        try writePNG(image, to: URL(fileURLWithPath: overviewPath))
        print("wrote \(overviewPath)")
    }
    for warning in warnings { print("warning: \(warning)") }
    if strict && !warnings.isEmpty { print("Failing because of --strict."); exit(1) }
} catch {
    FileHandle.standardError.write(Data("compose: \(error.localizedDescription)\n".utf8)); exit(1)
}
