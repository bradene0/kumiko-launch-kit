import SwiftUI

struct ContentView: View {
    let library: Library
    @State private var selection: Note.ID?
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    init(library: Library) {
        self.library = library
        var selection: Note.ID? = nil
        var column = NavigationSplitViewColumn.sidebar
        #if DEBUG
        // Screenshot state: which note is open, and on iPhone whether the list or the note is showing.
        selection = ScreenshotDemo.value("SelectNote")
        if ScreenshotDemo.value("CompactColumn") == "detail" { column = .detail }
        #endif
        _selection = State(initialValue: selection)
        _compactColumn = State(initialValue: column)
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            List(selection: $selection) {
                ForEach(library.notebooks, id: \.self) { notebook in
                    Section(notebook) {
                        ForEach(library.notes(in: notebook)) { note in
                            NoteRow(note: note).tag(note.id)
                        }
                    }
                }
            }
            .navigationTitle("Shoji Notes")
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
            #endif
            .overlay {
                if library.notes.isEmpty {
                    ContentUnavailableView("No Notes", systemImage: "square.grid.2x2", description: Text("Notes you write appear here."))
                }
            }
        } detail: {
            if let note = library.notes.first(where: { $0.id == selection }) {
                NoteDetail(note: note)
            } else {
                ContentUnavailableView("Select a Note", systemImage: "note.text")
            }
        }
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title).font(.headline)
            Text(note.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            Text(note.edited, format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct NoteDetail: View {
    let note: Note

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.title).font(.largeTitle.bold())
                    Label {
                        Text("\(note.notebook) · edited \(note.edited.formatted(.dateTime.month(.wide).day().hour().minute()))")
                    } icon: {
                        Image(systemName: "book.closed")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(note.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.tint.opacity(0.15), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                }
                Text(note.body)
                    .font(.body)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                Divider()
                Text("\(note.wordCount) words").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if os(macOS)
        .navigationTitle(note.title)
        #endif
    }
}
