import SwiftUI
#if os(macOS)
import AppKit
#endif

struct NoteListView: View {
    @Environment(NoteStore.self) private var store
    @Binding var selection: Note.ID?

    @State private var noteToDelete: Note?

    var body: some View {
        List(selection: $selection) {
            if store.folderUnavailable {
                folderUnavailableRow
            }
            ForEach(store.filteredNotes) { note in
                NoteRow(note: note)
                    .tag(note.id)
                    .contextMenu { menu(for: note) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            noteToDelete = note
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.filteredNotes.isEmpty, store.hasLoadedOnce, !store.folderUnavailable {
                emptyState
            }
        }
        .confirmationDialog(
            "Delete “\(noteToDelete?.title ?? "")”?",
            isPresented: Binding(
                get: { noteToDelete != nil },
                set: { if !$0 { noteToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Sticky", role: .destructive) {
                if let note = noteToDelete {
                    if selection == note.id { selection = nil }
                    store.delete(note)
                }
                noteToDelete = nil
            }
            Button("Cancel", role: .cancel) { noteToDelete = nil }
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteMessage: String {
        #if os(macOS)
        return "The file is moved to the Trash. Widgets showing it will go blank."
        #else
        return "This removes the file from your notes folder. Widgets showing it will go blank."
        #endif
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.searchText.isEmpty {
            ContentUnavailableView {
                Label("No Stickies Yet", systemImage: "note.text.badge.plus")
            } description: {
                Text("Your folder doesn't have any notes in it.")
            } actions: {
                Button("New Sticky") {
                    if let note = store.createNote() { selection = note.id }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView.search(text: store.searchText)
        }
    }

    private var folderUnavailableRow: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Folder unavailable").font(.subheadline.weight(.semibold))
                Text("“\(store.folderName ?? "Your folder")” can't be reached. It may be offline, or moved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func menu(for note: Note) -> some View {
        Menu("Colour") {
            ForEach(StickyColor.allCases) { color in
                Button {
                    store.setColor(color, for: note)
                } label: {
                    Label {
                        Text(color.displayName)
                    } icon: {
                        Image(systemName: note.color == color ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            }
        }

        Button {
            selection = note.id
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        #if os(macOS)
        Button {
            revealInFinder(note)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        #endif

        Divider()

        Button(role: .destructive) {
            noteToDelete = note
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    #if os(macOS)
    private func revealInFinder(_ note: Note) {
        _ = FolderAccess.withFolder { folder in
            let url = folder.appendingPathComponent(note.fileName)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    #endif
}

/// A row is the sticky's small widget, drawn the way the Home Screen will draw
/// it. A list of titles and snippets would be easier to skim, but it wouldn't
/// answer the question people actually have about a sticky — how much of it
/// fits, and what it looks like once it's up there.
private struct NoteRow: View {
    /// Close to a real small widget (158pt) while still leaving a sidebar
    /// narrow enough to be worth having.
    private static let width: CGFloat = 158

    let note: Note

    /// Read to the accessibility layer as one item: the card's own text is
    /// laid out for the eye, not for reading aloud a line at a time.
    private var spokenDescription: String {
        let plain = MarkdownPlainText.render(note.resolved(at: Date()).body)
            .replacingOccurrences(of: "\n", with: ", ")
        return plain.isEmpty ? note.fileName : plain
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            StickyWidgetPreview(note: note, size: .small, maxWidth: Self.width)

            if note.isOverLimit {
                Label("\(note.characterCount) characters", systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note.title)
        .accessibilityValue(spokenDescription)
    }
}
