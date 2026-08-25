import Foundation

/// A block of markdown, ready to be laid out.
///
/// Inline syntax (`**bold**`, `*italic*`, `` `code` ``, `[links](…)`,
/// `~~strike~~`) is handled by Foundation's own markdown parser at render
/// time; this type only splits the document into blocks, which is the part
/// `AttributedString` can't do inside a widget-friendly layout.
enum MarkdownBlock: Hashable, Identifiable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(text: String, depth: Int)
    case numbered(number: Int, text: String, depth: Int)
    case task(text: String, isDone: Bool, depth: Int)
    case quote(String)
    case code(String)
    case rule

    var id: Int { hashValue }
}

enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var inCodeFence = false
        var orderedCounters: [Int: Int] = [:]

        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph.removeAll()
        }

        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if inCodeFence {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCodeFence = false
                } else {
                    flushParagraph()
                    inCodeFence = true
                }
                continue
            }
            if inCodeFence {
                codeLines.append(rawLine)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                orderedCounters.removeAll()
                continue
            }

            // Horizontal rule: three or more of - * _ and nothing else.
            let ruleCharacters = Set(trimmed.replacingOccurrences(of: " ", with: ""))
            if trimmed.count >= 3, ruleCharacters.count == 1,
               let only = ruleCharacters.first, "-*_".contains(only) {
                flushParagraph()
                blocks.append(.rule)
                continue
            }

            let depth = min(indentation(of: line) / 2, 3)

            if let heading = headingLevel(of: trimmed) {
                flushParagraph()
                let text = String(trimmed.dropFirst(heading))
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "#+$", with: "", options: .regularExpression)
                blocks.append(.heading(level: heading, text: text.trimmingCharacters(in: .whitespaces)))
                continue
            }

            if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)))
                continue
            }

            if let marker = bulletMarker(of: trimmed) {
                flushParagraph()
                let content = String(trimmed.dropFirst(marker)).trimmingCharacters(in: .whitespaces)
                if let checkbox = taskState(of: content) {
                    blocks.append(.task(text: checkbox.text, isDone: checkbox.isDone, depth: depth))
                } else {
                    blocks.append(.bullet(text: content, depth: depth))
                }
                continue
            }

            if let ordered = orderedMarker(of: trimmed) {
                flushParagraph()
                let next = (orderedCounters[depth] ?? ordered.number - 1) + 1
                orderedCounters[depth] = next
                blocks.append(.numbered(number: next, text: ordered.text, depth: depth))
                continue
            }

            paragraph.append(trimmed)
        }

        if inCodeFence, !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    // MARK: - Line classification

    private static func indentation(of line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " { count += 1 } else { break }
        }
        return count
    }

    private static func headingLevel(of trimmed: String) -> Int? {
        var level = 0
        for character in trimmed {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let remainder = trimmed.dropFirst(level)
        guard remainder.isEmpty || remainder.hasPrefix(" ") else { return nil }
        return level
    }

    /// Returns the length of the bullet marker, including its trailing space.
    private static func bulletMarker(of trimmed: String) -> Int? {
        for marker in ["- ", "* ", "+ ", "• "] where trimmed.hasPrefix(marker) {
            return marker.count
        }
        return nil
    }

    private static func orderedMarker(of trimmed: String) -> (number: Int, text: String)? {
        var digits = ""
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index].isNumber, digits.count < 3 {
            digits.append(trimmed[index])
            index = trimmed.index(after: index)
        }
        guard !digits.isEmpty, index < trimmed.endIndex else { return nil }
        guard trimmed[index] == "." || trimmed[index] == ")" else { return nil }
        index = trimmed.index(after: index)
        guard index < trimmed.endIndex, trimmed[index] == " " else { return nil }
        let text = String(trimmed[trimmed.index(after: index)...]).trimmingCharacters(in: .whitespaces)
        return (Int(digits) ?? 1, text)
    }

    private static func taskState(of content: String) -> (text: String, isDone: Bool)? {
        let lowered = content.lowercased()
        if lowered.hasPrefix("[ ] ") || lowered == "[ ]" {
            return (String(content.dropFirst(3)).trimmingCharacters(in: .whitespaces), false)
        }
        if lowered.hasPrefix("[x] ") || lowered == "[x]" {
            return (String(content.dropFirst(3)).trimmingCharacters(in: .whitespaces), true)
        }
        return nil
    }
}

/// Strips markdown down to readable plain text.
///
/// Used for note titles, for search, and for the lock-screen widget — where
/// the system renders a flat monochrome string and syntax characters would
/// just eat space.
enum MarkdownPlainText {
    /// Flatten a whole document to a single space-separated string.
    static func render(_ markdown: String) -> String {
        let blocks = MarkdownParser.parse(markdown)
        var pieces: [String] = []
        for block in blocks {
            switch block {
            case .heading(_, let text):
                pieces.append(line(text))
            case .paragraph(let text):
                pieces.append(line(text.replacingOccurrences(of: "\n", with: " ")))
            case .bullet(let text, _):
                pieces.append("• " + line(text))
            case .task(let text, let isDone, _):
                pieces.append((isDone ? "☑ " : "☐ ") + line(text))
            case .numbered(let number, let text, _):
                pieces.append("\(number). " + line(text))
            case .quote(let text):
                pieces.append("“" + line(text) + "”")
            case .code(let text):
                pieces.append(text.replacingOccurrences(of: "\n", with: " "))
            case .rule:
                continue
            }
        }
        return pieces
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip inline syntax from a single line.
    static func line(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)

        // Links and images: keep the label, drop the destination.
        result = result.replacingOccurrences(
            of: "!?\\[([^\\]]*)\\]\\([^)]*\\)",
            with: "$1",
            options: .regularExpression
        )
        // Leading block syntax.
        result = result.replacingOccurrences(
            of: "^\\s*(#{1,6}\\s+|>\\s*|[-*+•]\\s+|\\d{1,3}[.)]\\s+)",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "^\\[( |x|X)\\]\\s*",
            with: "",
            options: .regularExpression
        )
        // Emphasis markers, kept simple on purpose: these run over user text
        // in a widget, where a wrong-but-readable result beats a slow one.
        for marker in ["***", "___", "**", "__", "~~", "*", "_", "`"] {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
