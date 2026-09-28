import SwiftUI

/// Write the note, set it, then see it: the editor is a text field, the
/// options that apply to the whole sticky, and the three Home Screen widgets
/// underneath, live. Nothing here is a mode — what you type is already in the
/// previews by the time you look down at them.
struct NoteEditorView: View {
    @Environment(NoteStore.self) private var store
    /// What the colour picker's choices are resolved against.
    @Environment(\.self) private var environment
    @Binding var selection: Note.ID?

    @State private var draft = ""
    @State private var color: StickyColor = .yellow
    /// The note's own text colour; `nil` means the paper's ink.
    @State private var ink: StickyInk?
    @State private var formatting = NoteFormatting.standard
    @State private var countdown = CountdownSettings()
    /// The body as it last was on disk. Anything else means unsaved edits.
    @State private var baseline = ""
    @State private var loadedID: Note.ID?
    /// Set when the file changed on disk while this editor had unsaved edits.
    @State private var conflictingBody: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isConfirmingDelete = false
    @FocusState private var editorFocused: Bool

    private var currentNote: Note? { store.note(id: selection) }

    private var inkColor: Color { ink?.color ?? color.ink }

    var body: some View {
        Group {
            if let note = currentNote {
                editor(for: note)
                    .navigationTitle(note.title)
                    .onChange(of: note) { _, updated in sync(with: updated) }
                    .onAppear { sync(with: note) }
                    .onDisappear { flushSave(for: loadedID) }
                    // Options save on the same debounce as typing: dragging a
                    // date picker shouldn't rewrite the file at every tick.
                    .onChange(of: formatting) { _, _ in scheduleSave() }
                    .onChange(of: countdown) { _, _ in scheduleSave() }
                    .onChange(of: color) { _, _ in scheduleSave() }
                    .onChange(of: ink) { _, _ in scheduleSave() }
                    .onChange(of: editorFocused) { _, focused in
                        if !focused { flushSave(for: loadedID) }
                    }
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

    private func editor(for note: Note) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let conflictingBody {
                    conflictBanner(theirs: conflictingBody)
                }
                input(for: note)
                options
                previews(for: note)
            }
            // A column, then centred in whatever's left: an editor the width
            // of a Mac window would put the previews an inch from the options.
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(18)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.primary.opacity(0.045))
    }

    // MARK: - Text input

    private func input(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Note")

            TextEditor(text: boundedDraft)
                .font(.system(size: 15))
                .foregroundStyle(inkColor)
                .tint(inkColor)
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .frame(minHeight: 190)
                .padding(10)
                .background {
                    // With no paper, the checkerboard stands in for whatever
                    // the widget will sit on, so the ink has something to be
                    // read against.
                    if color.isTransparent {
                        TransparencyCheckerboard(squareSize: 14)
                    } else {
                        StickyPaper(color: color)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(color.ink.opacity(editorFocused ? 0.35 : 0.12), lineWidth: 1)
                )

            markdownLegend

            footer(for: note)
        }
    }

    /// Emphasis is markdown's job, not a note-wide setting, so the syntax that
    /// works is spelled out right under the box you type it into.
    private var markdownLegend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(MarkdownHint.all) { hint in
                Text(hint.syntax)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .help(hint.name)
                    .accessibilityLabel(hint.name)
            }
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

    // MARK: - Options

    private var options: some View {
        VStack(alignment: .leading, spacing: 16) {
            optionRow("Colour") { colorPicker }

            optionRow("Text Colour") { inkPicker }

            optionRow("Text Size") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker(selection: $formatting.textSize) {
                        ForEach(NoteTextSize.allCases) { size in
                            Text(size.shortName).tag(size)
                        }
                    } label: {
                        Text("Text Size")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if formatting.textSize == .fit {
                        Text("Set as large as it goes while every word still shows. Each widget size works it out for itself, so the small one lands smaller than the large one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            optionRow("Align") {
                Picker(selection: $formatting.horizontal) {
                    ForEach(NoteHorizontalAlignment.allCases) { option in
                        Image(systemName: option.systemImage)
                            .accessibilityLabel(option.displayName)
                            .tag(option)
                    }
                } label: {
                    Text("Align")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            optionRow("Vertical") {
                Picker(selection: $formatting.vertical) {
                    ForEach(NoteVerticalAlignment.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                } label: {
                    Text("Vertical")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            optionRow("Border") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        borderSwatch(nil)
                        ForEach(StickyColor.paperColors) { option in
                            borderSwatch(option)
                        }
                        Spacer(minLength: 0)
                    }

                    if formatting.border.isVisible {
                        Picker(selection: $formatting.border.width) {
                            ForEach(NoteBorderWidth.allCases) { width in
                                Text(width.displayName).tag(width)
                            }
                        } label: {
                            Text("Border Width")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }

            HStack {
                Spacer(minLength: 0)
                Button("Reset Formatting") { formatting = .standard }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(formatting.isStandard)
            }

            Divider()

            countdownOptions
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func optionRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(title)
            content()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var colorPicker: some View {
        HStack(spacing: 10) {
            ForEach(StickyColor.allCases) { option in
                Button {
                    color = option
                } label: {
                    swatch(for: option)
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
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

    @ViewBuilder
    private func swatch(for option: StickyColor) -> some View {
        if option.isTransparent {
            TransparencyCheckerboard(squareSize: 6)
        } else {
            LinearGradient(
                colors: [option.paperTop, option.paperBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// Text colour. Any note can have one; a transparent note usually wants
    /// one, since it's the only thing on the widget.
    private var inkPicker: some View {
        HStack(spacing: 10) {
            ColorPicker("Text Colour", selection: inkSelection, supportsOpacity: false)
                .labelsHidden()
            Text(ink?.hex ?? (color.isTransparent ? "Follows light and dark mode" : "Matches the paper"))
                .font(ink == nil ? .caption : .caption.monospaced())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Use Default") { ink = nil }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(ink == nil)
        }
    }

    /// The picker writes continuously while it's dragged; `onChange(of: ink)`
    /// puts its saves on the same debounce as typing.
    private var inkSelection: Binding<Color> {
        Binding(
            get: { inkColor },
            set: { picked in ink = StickyInk(picked, in: environment) }
        )
    }

    /// A ring in the border's own colour, or a dashed one for no border.
    private func borderSwatch(_ option: StickyColor?) -> some View {
        let isSelected = formatting.border.color == option
        let name = option?.displayName ?? "No border"

        return Button {
            formatting.border.color = option
        } label: {
            Circle()
                .strokeBorder(
                    option?.edge ?? Color.secondary.opacity(0.5),
                    style: StrokeStyle(
                        lineWidth: option == nil ? 1.5 : 5,
                        dash: option == nil ? [3, 2.5] : []
                    )
                )
                .frame(width: 22, height: 22)
                .padding(3)
                .overlay(
                    Circle().stroke(
                        isSelected ? Color.accentColor : .clear,
                        lineWidth: 2
                    )
                )
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Countdown

    private var countdownOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: countdownEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Countdown")
                    Text("Write \(NoteTags.countdownTagExample) in the note and it becomes the time left.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if countdown.isEnabled {
                DatePicker(
                    "Counts to",
                    selection: countdownTarget,
                    displayedComponents: [.date, .hourAndMinute]
                )

                optionRow("Show") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 86), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(CountdownUnit.allCases) { unit in
                            unitChip(unit)
                        }
                    }
                }

                optionRow("Reads As") {
                    Picker(selection: $countdown.style) {
                        ForEach(CountdownStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    } label: {
                        Text("Reads As")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                HStack(spacing: 10) {
                    Button {
                        insertCountdownTag()
                    } label: {
                        Label("Insert \(NoteTags.countdownTagExample)", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasRoomForCountdownTag)

                    Text(countdownSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func unitChip(_ unit: CountdownUnit) -> some View {
        let isOn = countdown.orderedUnits.contains(unit)
        return Button {
            countdown.toggle(unit)
        } label: {
            Text(unit.displayName)
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOn ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.07))
                )
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unit.displayName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Turning the countdown on needs a date to count to; a week out is a
    /// better guess than today, which would read as "0 days" straight away.
    private var countdownEnabled: Binding<Bool> {
        Binding(
            get: { countdown.isEnabled },
            set: { isOn in
                countdown.target = isOn ? (countdown.target ?? Self.defaultTarget()) : nil
            }
        )
    }

    private var countdownTarget: Binding<Date> {
        Binding(
            get: { countdown.target ?? Self.defaultTarget() },
            set: { countdown.target = $0 }
        )
    }

    private static func defaultTarget() -> Date {
        let week = Date().addingTimeInterval(7 * 24 * 60 * 60)
        return Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0, of: week
        ) ?? week
    }

    /// What the tag will read as right now — the fastest way to tell whether
    /// the chosen units say what you meant.
    private var countdownSummary: String {
        Countdown.text(for: countdown, at: Date()).map { "Now: \($0)" } ?? ""
    }

    private var hasRoomForCountdownTag: Bool {
        draft.count + NoteTags.countdownTagExample.count + 1 <= Note.characterLimit
    }

    /// SwiftUI's text editor doesn't hand out its selection, so the tag lands
    /// at the end of the note — which is where a "3 days to go" line usually
    /// belongs anyway.
    private func insertCountdownTag() {
        guard hasRoomForCountdownTag else { return }
        let needsSpace = !draft.isEmpty
            && !draft.hasSuffix(" ")
            && !draft.hasSuffix("\n")
        draft += (needsSpace ? " " : "") + NoteTags.countdownTagExample
        scheduleSave()
    }

    // MARK: - Previews

    private func previews(for note: Note) -> some View {
        let preview = previewNote(from: note)

        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Widget Previews")

            ForEach(StickyWidgetSize.allCases) { size in
                VStack(alignment: .leading, spacing: 6) {
                    Text(size.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    StickyWidgetPreview(note: preview, size: size)
                }
            }

            Text("The Lock Screen sticky drops colour and shrinks the text until it fits, so it isn't shown here.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The note as it stands right now, including unsaved keystrokes.
    private func previewNote(from note: Note) -> Note {
        var preview = note
        preview.body = draft
        preview.color = color
        preview.ink = ink
        preview.formatting = formatting
        preview.countdown = countdown
        return preview
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
            if editorFocused {
                Button("Done") { editorFocused = false }
            }
        }

        ToolbarItem {
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
            ink = note.ink
            formatting = note.formatting
            countdown = note.countdown
            conflictingBody = nil
            editorFocused = false
            return
        }

        guard note.body != baseline
            || note.color != color
            || note.ink != ink
            || note.formatting != formatting
            || note.countdown != countdown
        else {
            return
        }

        if draft == baseline {
            // No local edits — take the newer version silently.
            draft = note.body
            baseline = note.body
            color = note.color
            ink = note.ink
            formatting = note.formatting
            countdown = note.countdown
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
        guard draft != baseline
            || color != note.color
            || ink != note.ink
            || formatting != note.formatting
            || countdown != note.countdown
        else {
            return
        }
        guard let saved = store.save(
            note,
            body: draft,
            color: color,
            ink: ink,
            formatting: formatting,
            countdown: countdown
        ) else {
            return
        }
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

/// The markdown the sticky renderer understands, as shown under the editor.
private struct MarkdownHint: Identifiable {
    var syntax: String
    var name: String

    var id: String { syntax }

    static let all: [MarkdownHint] = [
        MarkdownHint(syntax: "**bold**", name: "Bold"),
        MarkdownHint(syntax: "*italic*", name: "Italic"),
        MarkdownHint(syntax: "<u>under</u>", name: "Underline"),
        MarkdownHint(syntax: "~~strike~~", name: "Strikethrough"),
        MarkdownHint(syntax: "`code`", name: "Code"),
        MarkdownHint(syntax: "# Heading", name: "Heading"),
        MarkdownHint(syntax: "- list", name: "Bulleted list"),
        MarkdownHint(syntax: "1. list", name: "Numbered list"),
        MarkdownHint(syntax: "- [ ] task", name: "Task"),
        MarkdownHint(syntax: "> quote", name: "Quote"),
        MarkdownHint(syntax: "[link](url)", name: "Link")
    ]
}
