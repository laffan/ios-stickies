import SwiftUI

/// How one note's text is set.
///
/// This travels in the note's own front matter, which is what lets a widget
/// render a sticky exactly the way the editor did: the widget reads the same
/// file (or the same snapshot) and gets the same numbers.
///
/// Markdown still does the fine-grained work — `**bold**` on one word — and
/// these are the note-wide settings that markdown has no syntax for.
struct NoteFormatting: Hashable, Codable, Sendable {
    var textSize: NoteTextSize = .medium
    var horizontal: NoteHorizontalAlignment = .leading
    var vertical: NoteVerticalAlignment = .top
    var bold = false
    var italic = false
    var underline = false

    static let standard = NoteFormatting()

    var isStandard: Bool { self == NoteFormatting.standard }

    /// Emphasis applied to every run of the note, on top of whatever the
    /// markdown itself asks for.
    var baseEmphasis: InlineStyle {
        InlineStyle(bold: bold, italic: italic, underline: underline)
    }

    init(
        textSize: NoteTextSize = .medium,
        horizontal: NoteHorizontalAlignment = .leading,
        vertical: NoteVerticalAlignment = .top,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false
    ) {
        self.textSize = textSize
        self.horizontal = horizontal
        self.vertical = vertical
        self.bold = bold
        self.italic = italic
        self.underline = underline
    }

    /// Decoded a key at a time so a snapshot written by an older build — one
    /// with no formatting in it at all — still loads instead of taking the
    /// widget down to its placeholder.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        textSize = try container.decodeIfPresent(NoteTextSize.self, forKey: .textSize) ?? .medium
        horizontal = try container.decodeIfPresent(NoteHorizontalAlignment.self, forKey: .horizontal) ?? .leading
        vertical = try container.decodeIfPresent(NoteVerticalAlignment.self, forKey: .vertical) ?? .top
        bold = try container.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try container.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        underline = try container.decodeIfPresent(Bool.self, forKey: .underline) ?? false
    }
}

// MARK: - Text size

/// Named sizes rather than points: the same note has to look right in a small
/// widget and in a large one, so what a note stores is a multiplier applied to
/// whatever size that context starts from.
enum NoteTextSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case extraSmall
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .extraSmall: return 0.78
        case .small: return 0.89
        case .medium: return 1.0
        case .large: return 1.18
        case .extraLarge: return 1.4
        }
    }

    var displayName: String {
        switch self {
        case .extraSmall: return "Extra Small"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    /// Short label for a segmented control, where "Extra Small" doesn't fit.
    var shortName: String {
        switch self {
        case .extraSmall: return "XS"
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        case .extraLarge: return "XL"
        }
    }

    /// What goes in the file.
    var token: String {
        switch self {
        case .extraSmall: return "x-small"
        case .small: return "small"
        case .medium: return "medium"
        case .large: return "large"
        case .extraLarge: return "x-large"
        }
    }

    static func named(_ raw: String?) -> NoteTextSize? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "x-small", "xsmall", "xs", "extra-small", "extrasmall", "tiny":
            return .extraSmall
        case "small", "s":
            return .small
        case "medium", "m", "regular", "normal", "default":
            return .medium
        case "large", "l", "big":
            return .large
        case "x-large", "xlarge", "xl", "extra-large", "extralarge", "huge":
            return .extraLarge
        default:
            return nil
        }
    }
}

// MARK: - Alignment

enum NoteHorizontalAlignment: String, CaseIterable, Codable, Sendable, Identifiable {
    case leading
    case center
    case trailing

    var id: String { rawValue }

    /// What goes in the file — `left`/`right` rather than the SwiftUI spelling,
    /// because a file written by hand is meant to be readable.
    var token: String {
        switch self {
        case .leading: return "left"
        case .center: return "center"
        case .trailing: return "right"
        }
    }

    var displayName: String {
        switch self {
        case .leading: return "Left"
        case .center: return "Centre"
        case .trailing: return "Right"
        }
    }

    var systemImage: String {
        switch self {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var stackAlignment: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    static func named(_ raw: String?) -> NoteHorizontalAlignment? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "left", "leading", "start": return .leading
        case "center", "centre", "middle", "centred", "centered": return .center
        case "right", "trailing", "end": return .trailing
        default: return nil
        }
    }
}

enum NoteVerticalAlignment: String, CaseIterable, Codable, Sendable, Identifiable {
    case top
    case middle
    case bottom

    var id: String { rawValue }

    var token: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return "Top"
        case .middle: return "Middle"
        case .bottom: return "Bottom"
        }
    }

    var systemImage: String {
        switch self {
        case .top: return "arrow.up.to.line"
        case .middle: return "arrow.up.and.down"
        case .bottom: return "arrow.down.to.line"
        }
    }

    /// Whether a spacer goes above the note's text, below it, or both.
    var padsAbove: Bool { self != .top }
    var padsBelow: Bool { self != .bottom }

    static func named(_ raw: String?) -> NoteVerticalAlignment? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "top", "start": return .top
        case "middle", "center", "centre", "centered", "centred": return .middle
        case "bottom", "end": return .bottom
        default: return nil
        }
    }
}

// MARK: - Front matter

extension NoteFormatting {
    /// Parse a `style:` value — any of `bold`, `italic`, `underline`, in any
    /// order, separated by commas or spaces.
    /// Returns false when the value held nothing we understand, so the caller
    /// can keep the line as written rather than dropping it.
    @discardableResult
    mutating func applyStyleList(_ raw: String) -> Bool {
        var parsed = NoteFormatting.standard
        var understood = false
        for token in raw.lowercased().components(separatedBy: CharacterSet(charactersIn: ", \t")) {
            switch token.trimmingCharacters(in: .whitespaces) {
            case "": continue
            case "bold", "b", "strong": parsed.bold = true
            case "italic", "i", "italics", "em": parsed.italic = true
            case "underline", "u", "underlined": parsed.underline = true
            case "none", "plain", "regular", "normal": break
            default: return false
            }
            understood = true
        }
        guard understood else { return false }
        bold = parsed.bold
        italic = parsed.italic
        underline = parsed.underline
        return true
    }

    var styleList: String {
        var tokens: [String] = []
        if bold { tokens.append("bold") }
        if italic { tokens.append("italic") }
        if underline { tokens.append("underline") }
        return tokens.joined(separator: ", ")
    }

    /// The front-matter lines this formatting needs. A note left at the
    /// defaults writes nothing at all, so files stay as plain as they started.
    var frontMatterLines: [String] {
        var lines: [String] = []
        if textSize != .medium { lines.append("size: \(textSize.token)") }
        if horizontal != .leading { lines.append("align: \(horizontal.token)") }
        if vertical != .top { lines.append("valign: \(vertical.token)") }
        if bold || italic || underline { lines.append("style: \(styleList)") }
        return lines
    }
}
