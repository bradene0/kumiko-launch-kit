// Copies the named screenshot attachments exported by `xcresulttool export attachments` into a captures folder,
// one `<name>.png` per `captureScreenshot(_:named:)` call. No dependencies beyond Foundation.
//
// Usage: xcrun swift export-captures.swift <exported-attachments-dir> <captures-dir>
//
// xcresulttool names exported files by UUID; its manifest.json maps them to "<name>_<n>_<UUID>.png".
// XCTest's automatic attachments (UI snapshots, debug descriptions) are skipped.

import Foundation

struct Test: Decodable {
    struct Attachment: Decodable { var exportedFileName: String; var suggestedHumanReadableName: String }
    var testIdentifier: String?
    var attachments: [Attachment]
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { FileHandle.standardError.write(Data("usage: export-captures.swift <attachments-dir> <captures-dir>\n".utf8)); exit(64) }
let source = URL(fileURLWithPath: arguments[1]), target = URL(fileURLWithPath: arguments[2])
let fm = FileManager.default

do {
    let tests = try JSONDecoder().decode([Test].self, from: Data(contentsOf: source.appendingPathComponent("manifest.json")))
    try fm.createDirectory(at: target, withIntermediateDirectories: true)
    let suffix = try NSRegularExpression(pattern: #"_\d+_[0-9A-Fa-f-]{36}(\.png)?$"#)
    var written: [String: String] = [:]
    for test in tests {
        for item in test.attachments where item.exportedFileName.lowercased().hasSuffix(".png") {
            let raw = item.suggestedHumanReadableName
            let name = suffix.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
            guard !["App UI", "UI Snapshot", "Debug description"].contains(where: { name.hasPrefix($0) }) else { continue }
            if let previous = written[name] {
                FileHandle.standardError.write(Data("warning: capture \"\(name)\" was taken more than once (\(previous) and \(test.testIdentifier ?? "?")); keeping the last\n".utf8))
            }
            let destination = target.appendingPathComponent(name + ".png")
            try? fm.removeItem(at: destination)
            try fm.copyItem(at: source.appendingPathComponent(item.exportedFileName), to: destination)
            written[name] = test.testIdentifier ?? "?"
        }
    }
    guard !written.isEmpty else { FileHandle.standardError.write(Data("No named captures found. Check that the test ran (not skipped: TEST must name the capture test class) and calls captureScreenshot(_:named:).\n".utf8)); exit(1) }
    print("Exported \(written.count) captures to \(target.path): \(written.keys.sorted().joined(separator: ", "))")
} catch {
    FileHandle.standardError.write(Data("export-captures: \(error.localizedDescription)\n".utf8)); exit(1)
}
