import Foundation

/// One sticky note, backed by exactly one text file in the user's folder.
///
/// `id` is the file name (including extension). It is the same value the
/// widget configuration stores, which is why renaming a file in Finder /
/// Files re-points any widget that used it — see `Note.match(id:in:)` for the
/// fallbacks that soften that.
struct Note: Identifiable, Hashable, Codable, Sendable {
    /// The most a note may hold. Notes that arrive from outside the app can be
    /// longer; those are shown, flagged, and never silently truncated.
    static let characterLimit = 400

    var fileName: String
    var body: String
    var color: StickyColor
    /// A text colour of the note's own. `nil` means the paper's ink.
    var ink: StickyInk? = nil
    var created: Date
    var modified: Date
    /// Front-matter keys the app doesn't understand, preserved verbatim so
    /// other tools can annotate the same files without losing data.
    var passthroughFrontMatter: [String] = []

    var id: String { fileName }

    /// File name without its extension — what the user sees when metadata is
    /// absent and what search matches against.
    var stem: String {
        (fileName as NSString).deletingPathExtension
    }

    /// First meaningful line of the body, cleaned of markdown syntax.
    ///
    /// A note that opens with a list, a quote or a rule has no title line to
    /// take — promoting its first bullet would quietly remove that bullet from
    /// the note — so those fall back to the file name and keep their body
    /// whole.
    var title: String {
        guard let first = firstMeaningfulLine, !Note.isStructural(first.text) else { return stem }
        let plain = MarkdownPlainText.line(first.text)
        return plain.isEmpty ? stem : plain
    }

    /// The body minus its title line, so a widget showing the title doesn't
    /// print the first line twice.
    var bodyBelowTitle: String {
        guard let first = firstMeaningfulLine,
              !Note.isStructural(first.text),
              !MarkdownPlainText.line(first.text).isEmpty
        else {
            return body
        }
        var lines = body.components(separatedBy: "\n")
        lines.removeFirst(min(first.index + 1, lines.count))
        while let head = lines.first, head.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }

    /// Whether the body actually opens with a title line. When it doesn't,
    /// `title` is the file name — useful as a label in the app's list, but a
    /// widget is better off giving that row back to the note's content.
    var hasExplicitTitle: Bool {
        guard let first = firstMeaningfulLine, !Note.isStructural(first.text) else { return false }
        return !MarkdownPlainText.line(first.text).isEmpty
    }

    /// What to name this note's file: the first line's words, even when that
    /// line is a list item and so isn't shown as a title.
    var suggestedFileTitle: String {
        guard let first = firstMeaningfulLine else { return stem }
        let plain = MarkdownPlainText.line(first.text)
        return plain.isEmpty ? stem : plain
    }

    private var firstMeaningfulLine: (index: Int, text: String)? {
        for (index, raw) in body.components(separatedBy: "\n").enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return (index, trimmed) }
        }
        return nil
    }

    /// True for lines that are part of a block rather than a standalone
    /// sentence: list items, quotes, fences and rules.
    private static func isStructural(_ trimmed: String) -> Bool {
        for marker in ["- ", "* ", "+ ", "• "] where trimmed.hasPrefix(marker) {
            return true
        }
        if trimmed.hasPrefix(">") { return true }
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { return true }
        if trimmed.range(of: "^\\d{1,3}[.)] ", options: .regularExpression) != nil { return true }
        let compact = Set(trimmed.replacingOccurrences(of: " ", with: ""))
        if trimmed.count >= 3, compact.count == 1, let only = compact.first, "-*_".contains(only) {
            return true
        }
        return false
    }

    var characterCount: Int { body.count }
    var isOverLimit: Bool { characterCount > Note.characterLimit }

    var isEmpty: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Resolve a widget's stored note id against the current set of notes.
    ///
    /// Tries the exact file name first, then the name without extension, then
    /// the title — so a widget survives a note being renamed from `todo.md`
    /// to `todo.txt`, or the file being renamed to match its own heading.
    static func match(id: String, in notes: [Note]) -> Note? {
        if let exact = notes.first(where: { $0.fileName == id }) { return exact }
        let stem = (id as NSString).deletingPathExtension.lowercased()
        if let byStem = notes.first(where: { $0.stem.lowercased() == stem }) { return byStem }
        return notes.first(where: { $0.title.lowercased() == stem })
    }
}

/// How the sticky list is ordered. Persisted in the App Group so the ordering
/// the user picked in the app also drives the widget's note picker.
enum NoteSortOrder: String, CaseIterable, Codable, Sendable, Identifiable {
    case modifiedNewestFirst
    case createdNewestFirst
    case titleAToZ

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .modifiedNewestFirst: return "Last edited"
        case .createdNewestFirst: return "Date created"
        case .titleAToZ: return "Title"
        }
    }

    func sort(_ notes: [Note]) -> [Note] {
        switch self {
        case .modifiedNewestFirst:
            return notes.sorted { lhs, rhs in
                lhs.modified == rhs.modified ? lhs.fileName < rhs.fileName : lhs.modified > rhs.modified
            }
        case .createdNewestFirst:
            return notes.sorted { lhs, rhs in
                lhs.created == rhs.created ? lhs.fileName < rhs.fileName : lhs.created > rhs.created
            }
        case .titleAToZ:
            return notes.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }
}
