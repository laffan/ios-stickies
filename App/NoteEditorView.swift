import SwiftUI

struct NoteEditorView: View {
    @Environment(NoteStore.self) private var store
    @Binding var selection: Note.ID?

    @State private var draft = ""
    @State private var color: StickyColor = .yellow
    /// The body as it last was on disk. Anything else means unsaved edits.
    @State private var baseline = ""
    @State private var loadedID: Note.ID?
    /// Set when the file changed on disk while this editor had unsaved edits.
    @State private var conflictingBody: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isConfirmingDelete = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isWideLayout: Bool { horizontalSizeClass == .regular }
    #else
    private var isWideLayout: Bool { true }
    #endif

    private var currentNote: Note? { store.note(id: selection) }

    var body: some View {
        Group {
            if let note = currentNote {
                editor(for: note)
                    .navigationTitle(note.title)
                    .onChange(of: note) { _, updated in sync(with: updated) }
                    .onAppear { sync(with: note) }
                    .onDisappear { flushSave(for: loadedID) }
                    .toolbar { toolbar(for: note) }
                    .alert("Rename File", isPresented: $isRenaming) {
                        TextField("File name", text: $renameText)
                        Button("Rename") { commitRename(note) }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Widgets follow a renamed file when its title still matches, but it's safest to re-pick the sticky in any widget afterwards.")
                    }
                    .confirmationDialog(
                        "Delete “\(note.title)”?",
                        isPresented: $isConfirmingDelete,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Sticky", role: .destructive) {
                            saveTask?.cancel()
                            selection = nil
                            store.delete(note)
                        }
                        Button("Cancel", role: .cancel) { }
                    }
            } else {
                ContentUnavailableView(
                    "Sticky Not Found",
                    systemImage: "questionmark.folder",
                    description: Text("The file behind this sticky is no longer in your folder.")
                )
            }
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func editor(for note: Note) -> some View {
        if isWideLayout {
            HStack(alignment: .top, spacing: 0) {
                editorColumn(for: note)
                Divider()
                previewColumn(for: note)
                    .frame(width: 240)
            }
        } else {
            VStack(spacing: 0) {
                editorColumn(for: note)
                Divider()
                previewColumn(for: note)
                    .frame(height: 180)
            }
        }
    }

    private func editorColumn(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            colorPicker

            if let conflictingBody {
                conflictBanner(theirs: conflictingBody)
            }

            TextEditor(text: boundedDraft)
                .font(.system(size: 15))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.paperTop.opacity(0.22))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(color.fold.opacity(0.5), lineWidth: 1)
                )
                .frame(minHeight: 160)

            footer(for: note)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func previewColumn(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Widget preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            StickyCard(note: previewNote(from: note), presentation: .editorPreview)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Markdown is rendered the same way in widgets.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.035))
    }

    /// The note as it would look right now, including unsaved keystrokes.
    private func previewNote(from note: Note) -> Note {
        var preview = note
        preview.body = draft
        preview.color = color
        return preview
    }

    private var colorPicker: some View {
        HStack(spacing: 10) {
            ForEach(StickyColor.allCases) { option in
                Button {
                    color = option
                    flushSave(for: loadedID)
                } label: {
                    Circle()
                        .fill(LinearGradient(
                            colors: [option.paperTop, option.paperBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().stroke(
                                option == color ? option.ink.opacity(0.9) : Color.primary.opacity(0.12),
                                lineWidth: option == color ? 2.5 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .help(option.displayName)
                .accessibilityLabel(option.displayName)
            }
            Spacer()
        }
    }

    private func footer(for note: Note) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            characterCount

            Spacer()

            Text(note.fileName)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help("This file name is what widgets remember.")
        }
    }

    private var characterCount: some View {
        let count = draft.count
        let over = count - Note.characterLimit

        return Group {
            if over > 0 {
                Label("\(count) characters — \(over) over the limit", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Text("\(count) / \(Note.characterLimit)")
                    .foregroundStyle(count > Note.characterLimit - 40 ? .orange : .secondary)
                    .monospacedDigit()
            }
        }
        .font(.caption)
    }

    private func conflictBanner(theirs: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This file changed somewhere else", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
            Text("You have unsaved edits here, and the file on disk moved on — probably from another device.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Use the Other Version") {
                    draft = theirs
                    baseline = theirs
                    conflictingBody = nil
                }
                Button("Keep Mine") {
                    conflictingBody = nil
                    flushSave(for: loadedID)
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.caption)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.14))
        )
    }

    @ToolbarContentBuilder
    private func toolbar(for note: Note) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    renameText = note.fileName
                    isRenaming = true
                } label: {
                    Label("Rename File…", systemImage: "character.cursor.ibeam")
                }

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete Sticky", systemImage: "trash")
                }
            } label: {
                Label("Sticky Actions", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Editing plumbing

    /// Caps typing at the limit, while still letting an over-long note that
    /// arrived from elsewhere be shortened rather than being stuck.
    private var boundedDraft: Binding<String> {
        Binding(
            get: { draft },
            set: { proposed in
                let ceiling = max(Note.characterLimit, draft.count)
                if proposed.count <= ceiling {
                    draft = proposed
                } else {
                    draft = String(proposed.prefix(ceiling))
                }
                scheduleSave()
            }
        )
    }

    /// Reconcile with what the store now holds for this note.
    private func sync(with note: Note) {
        guard loadedID == note.id else {
            // Switching notes must not drop edits that were still inside the
            // save debounce — but a rename triggered by that last save must
            // not drag the selection back to the note we're leaving.
            flushSave(for: loadedID, followingRename: false)
            loadedID = note.id
            draft = note.body
            baseline = note.body
            color = note.color
            conflictingBody = nil
            return
        }

        guard note.body != baseline || note.color != color else { return }

        if draft == baseline {
            // No local edits — take the newer version silently.
            draft = note.body
            baseline = note.body
            color = note.color
            conflictingBody = nil
        } else if note.body != baseline {
            conflictingBody = note.body
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let id = loadedID
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            flushSave(for: id)
        }
    }

    /// Write the draft back to the note it belongs to. Takes the id rather
    /// than reading the selection so a save can still land after the user has
    /// moved on to another sticky.
    private func flushSave(for id: Note.ID?, followingRename: Bool = true) {
        saveTask?.cancel()
        saveTask = nil
        guard let id, let note = store.note(id: id) else { return }
        guard draft != baseline || color != note.color else { return }
        guard let saved = store.save(note, body: draft, color: color) else { return }
        baseline = saved.body
        // A first save can rename the file; follow it so the selection, and
        // this editor, stay pointed at the same note.
        if followingRename, saved.id != note.id, loadedID == note.id {
            loadedID = saved.id
            selection = saved.id
        }
    }

    private func commitRename(_ note: Note) {
        flushSave(for: loadedID)
        guard let renamed = store.rename(note, toFileName: renameText) else { return }
        loadedID = renamed.id
        selection = renamed.id
    }
}
