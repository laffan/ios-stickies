import Foundation

/// What the widgets read when they can't reach the folder themselves.
struct StickySnapshot: Codable, Sendable {
    var notes: [Note]
    var folderName: String?
    var capturedAt: Date
}

/// A copy of the sticky list kept in the App Group container.
///
/// Widgets always try the real folder first. This exists for the cases where
/// that can't work: the folder is an iCloud path that hasn't materialised in
/// the extension yet, the bookmark won't resolve out-of-process, or the note
/// files simply aren't downloaded. Without it a widget renders empty; with it
/// it renders the last thing the user actually saw.
enum WidgetSnapshotStore {
    private static let fileName = "stickies-snapshot.json"

    private static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(fileName)
    }

    static func write(notes: [Note]) {
        guard let fileURL else { return }
        let snapshot = StickySnapshot(
            notes: notes,
            folderName: FolderAccess.displayName,
            capturedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func read() -> StickySnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StickySnapshot.self, from: data)
    }

    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
