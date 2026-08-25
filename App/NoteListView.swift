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

private struct NoteRow: View {
    let note: Note

    private var snippet: String {
        let plain = MarkdownPlainText.render(note.bodyBelowTitle)
            .replacingOccurrences(of: "\n", with: " · ")
        return plain.isEmpty ? note.fileName : plain
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            swatch
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if note.isOverLimit {
                    Label("\(note.characterCount) characters", systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var swatch: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(
                    colors: [note.color.paperTop, note.color.paperBottom],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            FoldedCorner(size: 9)
                .fill(note.color.fold)
        }
        .frame(width: 26, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(note.color.ink.opacity(0.12), lineWidth: 0.5)
        )
        .padding(.top, 1)
    }
}
