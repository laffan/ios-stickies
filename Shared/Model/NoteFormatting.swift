import SwiftUI

/// How one note is set: the things that apply to the sticky as a whole.
///
/// Emphasis is deliberately *not* here. Bold, italic, underline and the rest
/// belong to the words they're on, and markdown already says which words those
/// are — `**bold**`, `*italic*`, `<u>underline</u>`. What's left is the stuff
/// markdown has no syntax for: how big the type is, where it sits on the
/// paper, and whether the sticky is framed.
///
/// It travels in the note's own front matter, which is what lets a widget
/// render a sticky exactly the way the editor did: the widget reads the same
/// file (or the same snapshot) and gets the same numbers.
struct NoteFormatting: Hashable, Codable, Sendable {
    var textSize: NoteTextSize = .medium
    var horizontal: NoteHorizontalAlignment = .leading
    var vertical: NoteVerticalAlignment = .top
    var border = NoteBorder()

    static let standard = NoteFormatting()

    var isStandard: Bool { self == NoteFormatting.standard }

    init(
        textSize: NoteTextSize = .medium,
        horizontal: NoteHorizontalAlignment = .leading,
        vertical: NoteVerticalAlignment = .top,
        border: NoteBorder = NoteBorder()
    ) {
        self.textSize = textSize
        self.horizontal = horizontal
        self.vertical = vertical
        self.border = border
    }

    /// Decoded a key at a time so a snapshot written by an older build — one
    /// with no formatting in it at all — still loads instead of taking the
    /// widget down to its placeholder.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        textSize = try container.decodeIfPresent(NoteTextSize.self, forKey: .textSize) ?? .medium
        horizontal = try container.decodeIfPresent(NoteHorizontalAlignment.self, forKey: .horizontal) ?? .leading
        vertical = try container.decodeIfPresent(NoteVerticalAlignment.self, forKey: .vertical) ?? .top
        border = try container.decodeIfPresent(NoteBorder.self, forKey: .border) ?? NoteBorder()
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
    case huge
    /// No size of its own: the note is set as large as it can be while every
    /// word still fits the widget. See `StickyContent`.
    case fit

    var id: String { rawValue }

    /// Nil for `.fit`, which is decided at layout time rather than stored.
    var scale: CGFloat? {
        switch self {
        case .extraSmall: return 0.75
        case .small: return 0.88
        case .medium: return 1.0
        case .large: return 1.25
        case .extraLarge: return 1.6
        case .huge: return 2.2
        case .fit: return nil
        }
    }

    var displayName: String {
        switch self {
        case .extraSmall: return "Extra Small"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        case .huge: return "Huge"
        case .fit: return "Fit to Widget"
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
        case .huge: return "2XL"
        case .fit: return "Fit"
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
        case .huge: return "huge"
        case .fit: return "fit"
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
        case "x-large", "xlarge", "xl", "extra-large", "extralarge":
            return .extraLarge
        case "huge", "2xl", "xxl", "giant":
            return .huge
        case "fit", "auto", "fill":
            return .fit
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

// MARK: - Border

/// A frame around the sticky, in any of the palette's colours.
///
/// The border follows the *container's* corner radius rather than one of its
/// own, so it hugs the widget's rounding on the Home Screen and the card's in
/// the app — see `StickyContent`.
struct NoteBorder: Hashable, Codable, Sendable {
    /// Nil means no border, which is what a sticky has unless asked otherwise.
    var color: StickyColor?
    var width: NoteBorderWidth = .medium

    init(color: StickyColor? = nil, width: NoteBorderWidth = .medium) {
        self.color = color
        self.width = width
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(StickyColor.self, forKey: .color)
        width = try container.decodeIfPresent(NoteBorderWidth.self, forKey: .width) ?? .medium
    }

    var isVisible: Bool { color != nil }
}

enum NoteBorderWidth: String, CaseIterable, Codable, Sendable, Identifiable {
    case hairline
    case thin
    case medium
    case thick

    var id: String { rawValue }

    /// Points at a full-size widget; scaled down with everything else when the
    /// sticky is drawn smaller.
    var points: CGFloat {
        switch self {
        case .hairline: return 1.5
        case .thin: return 3
        case .medium: return 5
        case .thick: return 9
        }
    }

    var displayName: String {
        switch self {
        case .hairline: return "Hairline"
        case .thin: return "Thin"
        case .medium: return "Medium"
        case .thick: return "Thick"
        }
    }

    var token: String { rawValue }

    static func named(_ raw: String?) -> NoteBorderWidth? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "hairline", "hair", "xs": return .hairline
        case "thin", "s", "small": return .thin
        case "medium", "m", "regular": return .medium
        case "thick", "l", "large", "heavy": return .thick
        default: return nil
        }
    }
}

// MARK: - Front matter

extension NoteFormatting {
    /// The front-matter lines this formatting needs. A note left at the
    /// defaults writes nothing at all, so files stay as plain as they started.
    var frontMatterLines: [String] {
        var lines: [String] = []
        if textSize != .medium { lines.append("size: \(textSize.token)") }
        if horizontal != .leading { lines.append("align: \(horizontal.token)") }
        if vertical != .top { lines.append("valign: \(vertical.token)") }
        if let color = border.color {
            lines.append("border: \(color.token)")
            if border.width != .medium { lines.append("border-width: \(border.width.token)") }
        }
        return lines
    }
}
