import Foundation

/// The read-only view of the sticky collection, shared by the app's widgets
/// and anything else that needs notes without owning the editing state.
struct LibraryState: Sendable {
    var notes: [Note]
    /// The user has chosen a folder at some point.
    var isFolderConfigured: Bool
    /// These notes came from the folder just now, rather than from the cache.
    var isLive: Bool
    var folderName: String?

    static let empty = LibraryState(notes: [], isFolderConfigured: false, isLive: false, folderName: nil)
}

enum StickyLibrary {
    private static let sortKey = "stickies.sortOrder"

    static var sortOrder: NoteSortOrder {
        get {
            NoteSortOrder(rawValue: AppGroup.defaults.string(forKey: sortKey) ?? "") ?? .modifiedNewestFirst
        }
        set {
            AppGroup.defaults.set(newValue.rawValue, forKey: sortKey)
        }
    }

    /// Load the current notes, preferring the folder and falling back to the
    /// snapshot the app left behind.
    static func current() -> LibraryState {
        let configured = FolderAccess.hasFolder

        if let notes = FolderAccess.withFolder({ folder -> [Note] in
            NoteFileIO.readAll(in: folder)
        }) {
            let sorted = sortOrder.sort(notes)
            // Reading succeeded, so refresh the cache for next time. An empty
            // folder is a legitimate result and must be cached as such.
            WidgetSnapshotStore.write(notes: sorted)
            return LibraryState(
                notes: sorted,
                isFolderConfigured: configured,
                isLive: true,
                folderName: FolderAccess.displayName
            )
        }

        guard let snapshot = WidgetSnapshotStore.read() else {
            return LibraryState(
                notes: [],
                isFolderConfigured: configured,
                isLive: false,
                folderName: FolderAccess.displayName
            )
        }
        return LibraryState(
            notes: sortOrder.sort(snapshot.notes),
            isFolderConfigured: configured,
            isLive: false,
            folderName: snapshot.folderName ?? FolderAccess.displayName
        )
    }
}
