import Foundation
import Observation
import WidgetKit

/// The app's live view of the folder.
///
/// The folder is the source of truth — this type never holds a note that isn't
/// on disk, and every external change to the folder is reflected here within
/// a few seconds (immediately, for local edits).
@MainActor
@Observable
final class NoteStore {
    private(set) var notes: [Note] = []
    private(set) var isReloading = false
    private(set) var hasLoadedOnce = false
    /// Set when the folder is configured but unreadable — folder deleted,
    /// iCloud signed out, permission revoked.
    private(set) var folderUnavailable = false
    var lastError: String?

    var searchText = ""

    // Not a `didSet` observer: `@Observable` rewrites stored properties into
    // computed ones, which property observers can't attach to.
    private(set) var sortOrder: NoteSortOrder = StickyLibrary.sortOrder

    func setSortOrder(_ newValue: NoteSortOrder) {
        guard newValue != sortOrder else { return }
        sortOrder = newValue
        StickyLibrary.sortOrder = newValue
        notes = newValue.sort(notes)
        publishToWidgets()
    }

    /// File names created in this session that still carry a placeholder name.
    /// They get renamed to match their title the first time the note has one,
    /// and are never touched again after that.
    private var awaitingAutoName: Set<String> = []

    private var watcher: FolderWatcher?
    private var reloadTask: Task<Void, Never>?

    // MARK: - Folder

    // Mirrored into stored properties rather than read straight from
    // `FolderAccess`: observation can only see stored state, and the whole UI
    // hinges on noticing the moment a folder is chosen.
    private(set) var isFolderConfigured = FolderAccess.hasFolder
    private(set) var folderName = FolderAccess.displayName
    private(set) var folderPath = FolderAccess.displayPath

    private func refreshFolderInfo() {
        isFolderConfigured = FolderAccess.hasFolder
        folderName = FolderAccess.displayName
        folderPath = FolderAccess.displayPath
    }

    init() {
        guard isFolderConfigured else { return }
        startWatching()
        reload()
    }

    /// Adopt the folder the user just picked in the file importer.
    func chooseFolder(_ url: URL) {
        do {
            try FolderAccess.store(url)
            refreshFolderInfo()
            awaitingAutoName.removeAll()
            folderUnavailable = false
            lastError = nil
            hasLoadedOnce = false
            notes = []
            WidgetSnapshotStore.clear()
            startWatching()
            watcher?.restart()
            reload()
        } catch {
            lastError = "Couldn't get permission for that folder. \(error.localizedDescription)"
        }
    }

    func forgetFolder() {
        watcher?.stop()
        watcher = nil
        FolderAccess.clear()
        WidgetSnapshotStore.clear()
        refreshFolderInfo()
        notes = []
        hasLoadedOnce = false
        folderUnavailable = false
        reloadWidgets()
    }

    private func startWatching() {
        guard watcher == nil else { return }
        let watcher = FolderWatcher { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        watcher.start()
        self.watcher = watcher
    }

    // MARK: - Loading

    /// Re-read the folder. Cheap enough to call on every hint of a change:
    /// the UI is only touched when something actually differs.
    func reload() {
        reloadTask?.cancel()
        isReloading = true
        reloadTask = Task { [weak self] in
            guard let self else { return }
            let order = self.sortOrder
            let result = await Task.detached(priority: .userInitiated) { () -> [Note]? in
                FolderAccess.withFolder { folder in
                    order.sort(NoteFileIO.readAll(in: folder))
                }
            }.value

            guard !Task.isCancelled else { return }
            self.apply(result)
        }
    }

    private func apply(_ loaded: [Note]?) {
        isReloading = false
        hasLoadedOnce = true
        // Resolving a stale bookmark can move the folder's recorded path.
        refreshFolderInfo()

        guard let loaded else {
            folderUnavailable = isFolderConfigured
            return
        }
        folderUnavailable = false
        guard loaded != notes else { return }
        notes = loaded
        publishToWidgets()
    }

    private func publishToWidgets() {
        WidgetSnapshotStore.write(notes: notes)
        reloadWidgets()
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Querying

    var filteredNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }
        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(query)
                || note.body.localizedCaseInsensitiveContains(query)
                || note.fileName.localizedCaseInsensitiveContains(query)
        }
    }

    func note(id: Note.ID?) -> Note? {
        guard let id else { return nil }
        return notes.first { $0.id == id }
    }

    // MARK: - Editing

    /// Create an empty note on disk and return it.
    @discardableResult
    func createNote(color: StickyColor? = nil) -> Note? {
        guard let scope = FolderAccess.resolve() else {
            lastError = NoteFileIO.IOError.folderUnavailable.localizedDescription
            return nil
        }
        return withExtendedLifetime(scope) { () -> Note? in
            let folder = scope.url
            let existing = NoteFileIO.existingFileNames(in: folder)
            let fileName = NoteFile.fileName(forTitle: "Sticky", avoiding: existing)
            let now = Date()
            let note = Note(
                fileName: fileName,
                body: "",
                color: color ?? nextColor(),
                created: now,
                modified: now
            )
            do {
                try NoteFileIO.write(note, in: folder)
                awaitingAutoName.insert(fileName)
                notes = sortOrder.sort(notes + [note])
                publishToWidgets()
                return note
            } catch {
                lastError = error.localizedDescription
                return nil
            }
        }
    }

    /// Rotate through the palette so a new board doesn't come out all yellow.
    private func nextColor() -> StickyColor {
        let palette = StickyColor.allCases
        guard let mostRecent = notes.max(by: { $0.created < $1.created }),
              let index = palette.firstIndex(of: mostRecent.color)
        else {
            return .yellow
        }
        return palette[(index + 1) % palette.count]
    }

    /// Persist an edit. Returns the note as it now exists on disk, since the
    /// file may have been renamed to match a newly typed title.
    @discardableResult
    func save(_ note: Note, body: String, color: StickyColor) -> Note? {
        guard let scope = FolderAccess.resolve() else {
            lastError = NoteFileIO.IOError.folderUnavailable.localizedDescription
            return nil
        }
        return withExtendedLifetime(scope) { () -> Note? in
            let folder = scope.url
            var updated = note
            updated.body = body
            updated.color = color
            updated.modified = Date()

            do {
                // A brand-new note takes its file name from its first line,
                // once. After that the name is the user's to change.
                if awaitingAutoName.contains(note.fileName), !updated.isEmpty {
                    var existing = NoteFileIO.existingFileNames(in: folder)
                    existing.remove(note.fileName)
                    let desired = NoteFile.fileName(forTitle: updated.suggestedFileTitle, avoiding: existing)
                    if desired != note.fileName {
                        try NoteFileIO.rename(note, to: desired, in: folder)
                        updated.fileName = desired
                    }
                    awaitingAutoName.remove(note.fileName)
                }

                try NoteFileIO.write(updated, in: folder)
                replace(id: note.id, with: updated)
                return updated
            } catch {
                lastError = error.localizedDescription
                return nil
            }
        }
    }

    /// Rename the underlying file. Widgets pointing at the old name fall back
    /// to matching on the note's title, so most survive.
    @discardableResult
    func rename(_ note: Note, toFileName rawName: String) -> Note? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var newName = trimmed
        if (newName as NSString).pathExtension.isEmpty {
            newName += ".\(NoteFile.defaultExtension)"
        }
        guard newName != note.fileName else { return note }

        guard let scope = FolderAccess.resolve() else {
            lastError = NoteFileIO.IOError.folderUnavailable.localizedDescription
            return nil
        }
        return withExtendedLifetime(scope) { () -> Note? in
            do {
                try NoteFileIO.rename(note, to: newName, in: scope.url)
                var updated = note
                updated.fileName = newName
                awaitingAutoName.remove(note.fileName)
                replace(id: note.id, with: updated)
                return updated
            } catch {
                lastError = error.localizedDescription
                return nil
            }
        }
    }

    func delete(_ note: Note) {
        guard let scope = FolderAccess.resolve() else {
            lastError = NoteFileIO.IOError.folderUnavailable.localizedDescription
            return
        }
        withExtendedLifetime(scope) {
            do {
                try NoteFileIO.delete(note, in: scope.url)
                awaitingAutoName.remove(note.fileName)
                notes.removeAll { $0.id == note.id }
                publishToWidgets()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func setColor(_ color: StickyColor, for note: Note) {
        save(note, body: note.body, color: color)
    }

    private func replace(id: Note.ID, with note: Note) {
        if let index = notes.firstIndex(where: { $0.id == id }) {
            notes[index] = note
            notes = sortOrder.sort(notes)
        } else {
            notes = sortOrder.sort(notes + [note])
        }
        publishToWidgets()
    }
}
