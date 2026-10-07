// Checks that CoreSVG (NSImage, which build-icon.swift uses and which Icon Composer also uses) renders an SVG the same
// way WebKit does. WebKit's SVG renderer is the reference: it follows the SVG spec. No dependencies beyond macOS.
//
// Usage: xcrun swift check-svg.swift <file.svg> [output-dir]
//
// Writes coresvg.png, webkit.png and diff.png (differences ×8) to output-dir (default: a temp folder) and prints
// the per-pixel difference. Both renders sit on mid-gray so white and black glyphs both show. Anti-aliasing alone gives a max difference around 15–30 on edges with a mean below 0.5.
// Exits 1 when more than 0.5% of pixels differ by more than 8/255.

import AppKit
import WebKit

guard CommandLine.arguments.count >= 2 else { print("Usage: xcrun swift check-svg.swift <file.svg> [output-dir]"); exit(2) }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : NSTemporaryDirectory() + "check-svg")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let N = 1024

func bitmap() -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: N, pixelsHigh: N, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}
func draw(_ rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: N, height: N).fill(); body()
    NSGraphicsContext.restoreGraphicsState()
}
func save(_ rep: NSBitmapImageRep, _ name: String) { try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name)) }

// CoreSVG via NSImage.
guard let svgImage = NSImage(contentsOf: url) else { print("NSImage could not load \(url.path)"); exit(1) }
let core = bitmap()
draw(core) { svgImage.draw(in: NSRect(x: 0, y: 0, width: N, height: N)) }
save(core, "coresvg.png")

// WebKit, from an inline data URL (file URLs are sandboxed away from WKWebView).
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: N, height: N))
let window = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = web
final class Loader: NSObject, WKNavigationDelegate { var done = false; func webView(_ w: WKWebView, didFinish n: WKNavigation!) { done = true } }
let loader = Loader(); web.navigationDelegate = loader
let b64 = try! Data(contentsOf: url).base64EncodedString()
web.loadHTMLString("<html><body style='margin:0;background:#808080'><img src='data:image/svg+xml;base64,\(b64)' style='width:\(N)px;height:\(N)px;display:block'></body></html>", baseURL: nil)
while !loader.done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
var snapshot: NSImage?
web.takeSnapshot(with: nil) { image, error in snapshot = image; if let error { print("WebKit snapshot failed: \(error)"); exit(1) } }
while snapshot == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
let reference = bitmap()
draw(reference) { snapshot!.draw(in: NSRect(x: 0, y: 0, width: N, height: N)) }
save(reference, "webkit.png")

// Difference.
let diff = bitmap()
let a = core.bitmapData!, b = reference.bitmapData!, d = diff.bitmapData!
var maxDiff = 0, sum = 0.0, over = 0
for i in 0..<(N * N) {
    var m = 0
    for c in 0..<3 { m = max(m, abs(Int(a[i * 4 + c]) - Int(b[i * 4 + c]))) }
    maxDiff = max(maxDiff, m); sum += Double(m); if m > 8 { over += 1 }
    let v = UInt8(min(255, m * 8)); d[i * 4] = v; d[i * 4 + 1] = v; d[i * 4 + 2] = v; d[i * 4 + 3] = 255
}
save(diff, "diff.png")
let share = Double(over) / Double(N * N) * 100
print(String(format: "%@: max difference %d/255, mean %.2f, %.3f%% of pixels differ by more than 8", url.lastPathComponent, maxDiff, sum / Double(N * N), share))
print("Images: \(outDir.path)/{coresvg,webkit,diff}.png")
if share > 0.5 { print("CoreSVG and WebKit disagree. Look at diff.png; gradients inside glyphs are the usual cause."); exit(1) }
print("CoreSVG matches WebKit.")
