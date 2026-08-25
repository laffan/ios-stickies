import AppIntents
import Foundation

/// A sticky, as offered in the widget's "Choose Sticky" picker.
struct NoteEntity: AppEntity, Identifiable, Hashable {
    /// The note's file name — the same value `Note.id` uses.
    var id: String
    var title: String
    var colorName: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Sticky")
    }

    static var defaultQuery = NoteEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(colorName)"
        )
    }

    init(id: String, title: String, colorName: String) {
        self.id = id
        self.title = title
        self.colorName = colorName
    }

    init(note: Note) {
        self.init(id: note.id, title: note.title, colorName: note.color.displayName)
    }
}

/// Feeds the picker from the notes folder, falling back to the cached
/// snapshot so widget configuration still works when the folder is briefly
/// unreachable.
struct NoteEntityQuery: EntityStringQuery {
    func entities(for identifiers: [NoteEntity.ID]) async throws -> [NoteEntity] {
        let notes = StickyLibrary.current().notes
        return identifiers.compactMap { identifier in
            Note.match(id: identifier, in: notes).map(NoteEntity.init(note:))
        }
    }

    func entities(matching string: String) async throws -> [NoteEntity] {
        let notes = StickyLibrary.current().notes
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes.map(NoteEntity.init(note:)) }
        return notes
            .filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.body.localizedCaseInsensitiveContains(query)
            }
            .map(NoteEntity.init(note:))
    }

    func suggestedEntities() async throws -> [NoteEntity] {
        StickyLibrary.current().notes.map(NoteEntity.init(note:))
    }

    /// A brand-new widget shows the most relevant sticky instead of an empty
    /// box, which is a much better first impression than "Choose Sticky".
    func defaultResult() async -> NoteEntity? {
        StickyLibrary.current().notes.first.map(NoteEntity.init(note:))
    }
}
