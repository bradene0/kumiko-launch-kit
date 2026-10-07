#if DEBUG
import Foundation

/// Fictional content for screenshots: no personal data, no real people, no third-party names or trademarks.
enum DemoData {
    /// A fixed "now", so dates in screenshots never change between runs.
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)
    private static func ago(hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

    static let library = Library(notes: [
        Note(title: "Kumiko patterns", notebook: "Workshop", edited: ago(hours: 2), tags: ["joinery", "asanoha", "sketch"],
             body: """
             The asa-no-ha (hemp leaf) pattern starts from a square grid of jigumi. Each cell is split with diagonals, \
             then three tsuke-ko pieces lock into every triangle.

             Cut the kumiko strips to 2.4 mm. Keep the angle jig at 45° for the diagonals and 67.5° for the leaf pieces; \
             a test triangle in scrap hinoki first saves a whole panel.

             Next: try a sakura variation for the small lantern.
             """),
        Note(title: "Lantern frame", notebook: "Workshop", edited: ago(hours: 30), tags: ["project"],
             body: "Frame 180 × 180 × 320 mm. Mortises 6 mm. Paper: washi, double layer on the side facing the room."),
        Note(title: "Sharpening schedule", notebook: "Workshop", edited: ago(hours: 75), tags: ["tools"],
             body: "Chisels every Friday: 1000, 6000, then strop. Plane iron after every two panels."),
        Note(title: "Morning pages", notebook: "Journal", edited: ago(hours: 5), tags: ["daily"],
             body: "Quiet start. Light through the shoji in the studio looked like folded paper. Write down the angle of the sun at 8:10."),
        Note(title: "Tea ceremony notes", notebook: "Journal", edited: ago(hours: 50), tags: ["class", "tea"],
             body: "Whisk in an M shape, not circles. Turn the bowl twice before drinking; the front faces the host."),
        Note(title: "Moss garden", notebook: "Garden", edited: ago(hours: 20), tags: ["outside"],
             body: "Mist twice a day in August. Replace the stepping stone by the maple; it rocks."),
        Note(title: "Seed list", notebook: "Garden", edited: ago(hours: 120), tags: ["spring"],
             body: "Shiso (green and red), mizuna, edamame, and two kinds of morning glory for the fence."),
    ])
}
#endif
