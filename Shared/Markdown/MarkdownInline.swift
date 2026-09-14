import SwiftUI

/// The styling that applies to one run of inline text.
struct InlineStyle: Hashable {
    var bold = false
    var italic = false
    var code = false
    var strikethrough = false
    var underline = false
    var link: URL?
}

/// A stretch of text that shares one style.
struct InlineSpan: Hashable {
    var text: String
    var style: InlineStyle
}

/// Inline markdown, parsed by hand.
///
/// `AttributedString(markdown:)` can parse most of this, but its emphasis
/// arrives as presentation *intents* that only survive if nothing downstream
/// sets a font — and every sticky sets its own, at a size that depends on the
/// widget family. Resolving spans to concrete fonts ourselves means `**bold**`
/// renders as bold everywhere, and lets links and `<u>` carry an underline the
/// inline-only parser never produces.
enum MarkdownInline {
    /// Longest markers first, so `**` is never mistaken for two `*`.
    private static let emphasis: [(marker: [Character], bold: Bool, italic: Bool, strikethrough: Bool)] = [
        (Array("***"), true, true, false),
        (Array("___"), true, true, false),
        (Array("**"), true, false, false),
        (Array("__"), true, false, false),
        (Array("~~"), false, false, true),
        (Array("*"), false, true, false),
        (Array("_"), false, true, false)
    ]

    // MARK: - Rendering

    /// Build a `Text` whose runs each carry their own resolved font.
    ///
    /// Modifiers applied to the result — a colour, a strikethrough — still
    /// reach runs that don't set one themselves, so callers can tint a whole
    /// line without flattening its emphasis.
    static func text(
        _ source: String,
        size: CGFloat,
        weight: Font.Weight = .regular,
        italic: Bool = false,
        theme: MarkdownStyle
    ) -> Text {
        spans(source).reduce(Text(verbatim: "")) { partial, span in
            partial + rendered(span, size: size, weight: weight, italic: italic, theme: theme)
        }
    }

    private static func rendered(
        _ span: InlineSpan,
        size: CGFloat,
        weight: Font.Weight,
        italic: Bool,
        theme: MarkdownStyle
    ) -> Text {
        let inline = span.style
        // The note's own formatting is the floor: `**bold**` inside a note set
        // in bold is still bold, and a note set in italic italicises the runs
        // markdown left plain.
        let base = theme.emphasis
        let resolvedWeight: Font.Weight = (inline.bold || base.bold) ? .bold : weight
        var font: Font = inline.code
            ? .system(size: size * 0.92, weight: resolvedWeight, design: .monospaced)
            : .system(size: size, weight: resolvedWeight)
        if inline.italic || italic || base.italic {
            font = font.italic()
        }

        var text = Text(verbatim: span.text).font(font)
        if inline.strikethrough {
            text = text.strikethrough(true, color: theme.secondaryInk)
        }
        let isLink = inline.link != nil
        if inline.underline || base.underline || isLink {
            text = text.underline(true, color: isLink ? theme.linkInk : theme.ink)
        }
        if isLink {
            text = text.foregroundStyle(theme.linkInk)
        }
        return text
    }

    /// Plain text with the syntax removed — the Lock Screen's flat string.
    static func plain(_ source: String) -> String {
        spans(source).map(\.text).joined()
    }

    // MARK: - Parsing

    static func spans(_ source: String) -> [InlineSpan] {
        parse(Array(source), style: InlineStyle())
    }

    private static func parse(_ characters: [Character], style: InlineStyle) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        var buffer = ""
        var index = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            spans.append(InlineSpan(text: buffer, style: style))
            buffer = ""
        }

        while index < characters.count {
            let character = characters[index]

            if character == "\\", index + 1 < characters.count {
                buffer.append(characters[index + 1])
                index += 2
                continue
            }

            // Code spans win over everything, and never nest.
            if character == "`", let close = find(["`"], in: characters, from: index + 1) {
                flush()
                var code = style
                code.code = true
                spans.append(InlineSpan(text: String(characters[(index + 1)..<close]), style: code))
                index = close + 1
                continue
            }

            if character == "[",
               let bracket = find(["]"], in: characters, from: index + 1),
               bracket + 1 < characters.count, characters[bracket + 1] == "(",
               let paren = find([")"], in: characters, from: bracket + 2) {
                flush()
                var linked = style
                let destination = String(characters[(bracket + 2)..<paren])
                    .trimmingCharacters(in: .whitespaces)
                linked.link = URL(string: destination)
                spans.append(contentsOf: parse(Array(characters[(index + 1)..<bracket]), style: linked))
                index = paren + 1
                continue
            }

            // Markdown has no underline of its own, so honour the HTML tag
            // people reach for instead.
            if character == "<", matches(Array("<u>"), in: characters, at: index),
               let close = find(Array("</u>"), in: characters, from: index + 3) {
                flush()
                var underlined = style
                underlined.underline = true
                spans.append(contentsOf: parse(Array(characters[(index + 3)..<close]), style: underlined))
                index = close + 4
                continue
            }

            if let match = emphasisMatch(characters, at: index) {
                flush()
                var inner = style
                inner.bold = inner.bold || match.bold
                inner.italic = inner.italic || match.italic
                inner.strikethrough = inner.strikethrough || match.strikethrough
                spans.append(contentsOf: parse(Array(characters[match.content]), style: inner))
                index = match.end
                continue
            }

            buffer.append(character)
            index += 1
        }

        flush()
        return spans
    }

    private static func emphasisMatch(
        _ characters: [Character],
        at index: Int
    ) -> (content: Range<Int>, end: Int, bold: Bool, italic: Bool, strikethrough: Bool)? {
        for candidate in emphasis {
            let marker = candidate.marker
            guard matches(marker, in: characters, at: index) else { continue }

            // An opening marker has to be followed by content, not a space:
            // "2 * 3 * 4" is arithmetic, not emphasis.
            let start = index + marker.count
            guard start < characters.count, !characters[start].isWhitespace else { continue }

            // Underscores inside a word belong to the word — snake_case stays
            // snake_case.
            if marker[0] == "_", index > 0, isWordCharacter(characters[index - 1]) {
                continue
            }

            guard let close = find(marker, in: characters, from: start),
                  close > start,
                  !characters[close - 1].isWhitespace
            else {
                continue
            }

            if marker[0] == "_" {
                let after = close + marker.count
                if after < characters.count, isWordCharacter(characters[after]) { continue }
            }

            return (start..<close, close + marker.count, candidate.bold, candidate.italic, candidate.strikethrough)
        }
        return nil
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func matches(_ sequence: [Character], in characters: [Character], at index: Int) -> Bool {
        guard index >= 0, index + sequence.count <= characters.count else { return false }
        for offset in 0..<sequence.count where characters[index + offset] != sequence[offset] {
            return false
        }
        return true
    }

    /// The next unescaped occurrence of `sequence` at or after `from`.
    private static func find(_ sequence: [Character], in characters: [Character], from: Int) -> Int? {
        var index = from
        while index < characters.count {
            if characters[index] == "\\" {
                index += 2
                continue
            }
            if matches(sequence, in: characters, at: index) { return index }
            index += 1
        }
        return nil
    }
}
