import Foundation

/// Reads and writes the on-disk representation of a note.
///
/// A note file is plain markdown. Everything the app adds lives in an optional
/// YAML-style front-matter block, so a file written by hand — or by any other
/// markdown editor pointed at the same folder — is a perfectly valid note:
///
/// ```
/// ---
/// color: yellow
/// ink: "#1F2A44"
/// created: 2026-08-25T09:41:00Z
/// ---
/// # Milk
/// - oat
/// - **not** skim
/// ```
enum NoteFile {
    static let delimiter = "---"
    /// A front-matter block longer than this is almost certainly a body that
    /// happens to start with a horizontal rule, so we stop looking.
    private static let maxFrontMatterLines = 24

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    struct Parsed {
        var body: String
        var color: StickyColor?
        var ink: StickyInk?
        var created: Date?
        var passthrough: [String]
    }

    // MARK: - Reading

    static func parse(_ contents: String) -> Parsed {
        let normalized = contents.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.components(separatedBy: "\n")

        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == delimiter,
              let closing = closingDelimiterIndex(in: lines)
        else {
            return Parsed(body: trimTrailingNewlines(normalized), color: nil, ink: nil, created: nil, passthrough: [])
        }

        var color: StickyColor?
        var ink: StickyInk?
        var created: Date?
        var passthrough: [String] = []

        for line in lines[1..<closing] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let separator = trimmed.firstIndex(of: ":") else {
                passthrough.append(trimmed)
                continue
            }
            let key = trimmed[trimmed.startIndex..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "color", "colour":
                color = StickyColor.named(unquoted(value))
            case "ink", "text-color", "text-colour":
                ink = StickyInk(hex: unquoted(value))
            case "created":
                created = dateFormatter.date(from: value)
            default:
                passthrough.append(trimmed)
            }
        }

        lines.removeSubrange(0...closing)
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        return Parsed(
            body: trimTrailingNewlines(lines.joined(separator: "\n")),
            color: color,
            ink: ink,
            created: created,
            passthrough: passthrough
        )
    }

    /// Front matter only counts when the block closes and every line inside it
    /// looks like metadata, which keeps a note that opens with `---` as a
    /// horizontal rule from being eaten.
    private static func closingDelimiterIndex(in lines: [String]) -> Int? {
        let upperBound = min(lines.count, maxFrontMatterLines)
        guard upperBound > 1 else { return nil }
        for index in 1..<upperBound where lines[index].trimmingCharacters(in: .whitespaces) == delimiter {
            let interior = lines[1..<index]
            let looksLikeMetadata = interior.allSatisfy { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty || trimmed.contains(":")
            }
            return looksLikeMetadata ? index : nil
        }
        return nil
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    private static func trimTrailingNewlines(_ text: String) -> String {
        var result = text
        while result.hasSuffix("\n") || result.hasSuffix(" ") {
            result.removeLast()
        }
        return result
    }

    // MARK: - Writing

    /// Serialize a note back to markdown, preserving unknown front-matter keys.
    static func serialize(_ note: Note) -> String {
        var lines = [delimiter]
        lines.append("color: \(note.color.token)")
        if let ink = note.ink {
            lines.append("ink: \"\(ink.hex)\"")
        }
        lines.append("created: \(dateFormatter.string(from: note.created))")
        lines.append(contentsOf: note.passthroughFrontMatter)
        lines.append(delimiter)
        lines.append("")
        lines.append(note.body)
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - File names

    /// Extensions the app treats as sticky notes.
    static let recognizedExtensions: Set<String> = ["md", "markdown", "txt", "text", "mdown"]
    static let defaultExtension = "md"

    static func isNoteFile(_ url: URL) -> Bool {
        guard !url.lastPathComponent.hasPrefix(".") else { return false }
        return recognizedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Turn a note's title into a friendly file name, then make it unique
    /// against what's already on disk.
    static func fileName(forTitle title: String, avoiding existing: Set<String>) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>\u{0}")
        var base = title
            .components(separatedBy: .newlines)
            .first?
            .components(separatedBy: illegal)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        base = base.replacingOccurrences(of: "  ", with: " ")
        if base.count > 48 { base = String(base.prefix(48)).trimmingCharacters(in: .whitespaces) }
        if base.isEmpty || base.hasPrefix(".") { base = "Sticky" }

        let lowercasedExisting = Set(existing.map { $0.lowercased() })
        var candidate = "\(base).\(defaultExtension)"
        var suffix = 2
        while lowercasedExisting.contains(candidate.lowercased()) {
            candidate = "\(base) \(suffix).\(defaultExtension)"
            suffix += 1
        }
        return candidate
    }
}
