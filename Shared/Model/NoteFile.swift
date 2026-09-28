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

    /// A countdown's target is a date a human is likely to type by hand, so it
    /// is written with the local offset — `2026-12-25T09:00:00+01:00` — and
    /// read back from any of the shapes below.
    private static let localDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let looseDateFormats = [
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
        "yyyy/MM/dd"
    ]

    /// Parse a date written in front matter, from strict ISO 8601 down to a
    /// bare `2026-12-25` typed into the file by hand.
    static func date(from raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let iso = dateFormatter.date(from: trimmed) { return iso }
        for format in looseDateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let parsed = formatter.date(from: trimmed) { return parsed }
        }
        return nil
    }

    /// The ways a file might say "no" to something that's off by default.
    private static func isNegative(_ raw: String) -> Bool {
        ["none", "no", "off", "false", ""].contains(
            raw.trimmingCharacters(in: .whitespaces).lowercased()
        )
    }

    struct Parsed {
        var body: String
        var color: StickyColor?
        var ink: StickyInk?
        var created: Date?
        var formatting: NoteFormatting
        var countdown: CountdownSettings
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
            return Parsed(
                body: trimTrailingNewlines(normalized),
                color: nil,
                ink: nil,
                created: nil,
                formatting: .standard,
                countdown: CountdownSettings(),
                passthrough: []
            )
        }

        var color: StickyColor?
        var ink: StickyInk?
        var created: Date?
        var formatting = NoteFormatting.standard
        var countdown = CountdownSettings()
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
            // A key we recognise but can't make sense of is kept verbatim
            // rather than dropped: the note keeps whatever another tool wrote,
            // and the app just carries on with its default.
            var understood = true
            switch key {
            case "color", "colour":
                color = StickyColor.named(unquoted(value))
            case "ink", "text-color", "text-colour":
                ink = StickyInk(hex: unquoted(value))
            case "created":
                created = dateFormatter.date(from: value)
            case "size", "text-size", "textsize", "font-size":
                if let size = NoteTextSize.named(value) { formatting.textSize = size }
                else { understood = false }
            case "align", "alignment", "text-align":
                if let aligned = NoteHorizontalAlignment.named(value) { formatting.horizontal = aligned }
                else { understood = false }
            case "valign", "vertical-align", "vertical-alignment":
                if let aligned = NoteVerticalAlignment.named(value) { formatting.vertical = aligned }
                else { understood = false }
            case "border", "border-color", "border-colour":
                // `none` names the transparent paper colour too, but a clear
                // border is no border, so it has to be checked first.
                if NoteFile.isNegative(value) || StickyColor.named(value)?.isTransparent == true {
                    formatting.border.color = nil
                } else if let edge = StickyColor.named(value) {
                    formatting.border.color = edge
                } else {
                    understood = false
                }
            case "border-width", "border-size":
                if let width = NoteBorderWidth.named(value) { formatting.border.width = width }
                else { understood = false }
            case "countdown", "countdown-to", "countdown-date":
                if let target = date(from: value) { countdown.target = target }
                else { understood = false }
            case "countdown-units", "countdown-fields":
                let units = value
                    .components(separatedBy: CharacterSet(charactersIn: ", \t"))
                    .compactMap { CountdownUnit.named($0) }
                if units.isEmpty { understood = false } else { countdown.units = units }
            case "countdown-style", "countdown-format":
                if let style = CountdownStyle.named(value) { countdown.style = style }
                else { understood = false }
            default:
                understood = false
            }
            if !understood { passthrough.append(trimmed) }
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
            formatting: formatting,
            countdown: countdown,
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
    ///
    /// Only settings that differ from the defaults are written, so a note
    /// nobody has restyled stays as plain on disk as it was before the app
    /// grew formatting at all.
    static func serialize(_ note: Note) -> String {
        var lines = [delimiter]
        lines.append("color: \(note.color.token)")
        if let ink = note.ink {
            lines.append("ink: \"\(ink.hex)\"")
        }
        lines.append("created: \(dateFormatter.string(from: note.created))")
        lines.append(contentsOf: note.formatting.frontMatterLines)
        lines.append(contentsOf: countdownLines(for: note.countdown))
        lines.append(contentsOf: note.passthroughFrontMatter)
        lines.append(delimiter)
        lines.append("")
        lines.append(note.body)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Nothing is written for a note with no countdown — the units on their
    /// own would be metadata about a clock that doesn't exist.
    private static func countdownLines(for countdown: CountdownSettings) -> [String] {
        guard let target = countdown.target else { return [] }
        var lines = ["countdown: \(localDateFormatter.string(from: target))"]
        if countdown.orderedUnits != CountdownSettings.defaultUnits {
            lines.append("countdown-units: \(countdown.orderedUnits.map(\.rawValue).joined(separator: ", "))")
        }
        if countdown.style != .full {
            lines.append("countdown-style: \(countdown.style.token)")
        }
        return lines
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
