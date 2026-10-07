import Foundation

struct Note: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var notebook: String
    var edited: Date
    var tags: [String]
    var body: String

    var wordCount: Int { body.split(whereSeparator: \.isWhitespace).count }
}

struct Library {
    var notes: [Note]

    var notebooks: [String] {
        var seen: [String] = []
        for note in notes where !seen.contains(note.notebook) { seen.append(note.notebook) }
        return seen
    }

    func notes(in notebook: String) -> [Note] {
        notes.filter { $0.notebook == notebook }.sorted { $0.edited > $1.edited }
    }
}
