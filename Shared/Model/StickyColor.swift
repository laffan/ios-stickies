import SwiftUI

/// The classic sticky-note palette.
///
/// Colours are hard-coded rather than pulled from an asset catalogue so the
/// app and the widget extension render identically without sharing resources.
/// Sticky paper keeps its colour in dark mode (that's what makes it read as a
/// sticky note); only the surrounding chrome adapts.
///
/// `clear` is the odd one out: no paper at all, just the text on whatever the
/// widget sits on. Its ink follows the system's light/dark appearance unless
/// the note carries an ink of its own.
enum StickyColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case yellow
    case pink
    case blue
    case green
    case orange
    case purple
    case clear

    /// The colours that are actually paper — what a new note or a file with
    /// no colour metadata is given. Transparency is only ever chosen.
    static let paperColors: [StickyColor] = allCases.filter { !$0.isTransparent }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yellow: return "Canary Yellow"
        case .pink: return "Neon Pink"
        case .blue: return "Cape Cod Blue"
        case .green: return "Limeade Green"
        case .orange: return "Electric Orange"
        case .purple: return "Iris Purple"
        case .clear: return "Transparent"
        }
    }

    /// Short name used in the file's front matter.
    var token: String { rawValue }

    var isTransparent: Bool { self == .clear }

    // MARK: - Paper

    /// Top-of-note paper colour.
    var paperTop: Color {
        switch self {
        case .yellow: return Color(red: 1.00, green: 0.95, blue: 0.62)
        case .pink: return Color(red: 1.00, green: 0.76, blue: 0.84)
        case .blue: return Color(red: 0.72, green: 0.90, blue: 0.98)
        case .green: return Color(red: 0.82, green: 0.94, blue: 0.66)
        case .orange: return Color(red: 1.00, green: 0.83, blue: 0.62)
        case .purple: return Color(red: 0.86, green: 0.82, blue: 0.98)
        case .clear: return .clear
        }
    }

    /// Bottom-of-note paper colour — very slightly deeper, which gives the
    /// note the faint "lit from above" look real sticky notes have.
    var paperBottom: Color {
        switch self {
        case .yellow: return Color(red: 0.99, green: 0.88, blue: 0.42)
        case .pink: return Color(red: 0.99, green: 0.63, blue: 0.74)
        case .blue: return Color(red: 0.58, green: 0.83, blue: 0.95)
        case .green: return Color(red: 0.72, green: 0.88, blue: 0.49)
        case .orange: return Color(red: 0.99, green: 0.72, blue: 0.44)
        case .purple: return Color(red: 0.78, green: 0.73, blue: 0.96)
        case .clear: return .clear
        }
    }

    /// The colour of the folded-over corner.
    var fold: Color {
        switch self {
        case .yellow: return Color(red: 0.93, green: 0.79, blue: 0.30)
        case .pink: return Color(red: 0.93, green: 0.52, blue: 0.64)
        case .blue: return Color(red: 0.45, green: 0.74, blue: 0.90)
        case .green: return Color(red: 0.61, green: 0.80, blue: 0.38)
        case .orange: return Color(red: 0.93, green: 0.61, blue: 0.32)
        case .purple: return Color(red: 0.68, green: 0.63, blue: 0.92)
        case .clear: return .clear
        }
    }

    // MARK: - Ink

    /// Primary text colour. Dark, slightly tinted toward the paper so it reads
    /// like pen on coloured card rather than pure black on colour.
    var ink: Color {
        switch self {
        case .yellow: return Color(red: 0.28, green: 0.22, blue: 0.05)
        case .pink: return Color(red: 0.32, green: 0.10, blue: 0.17)
        case .blue: return Color(red: 0.07, green: 0.20, blue: 0.29)
        case .green: return Color(red: 0.15, green: 0.25, blue: 0.06)
        case .orange: return Color(red: 0.31, green: 0.17, blue: 0.04)
        case .purple: return Color(red: 0.20, green: 0.15, blue: 0.36)
        // Nothing to tint toward, and no way to know what's behind it, so
        // follow the system: dark on light, light on dark.
        case .clear: return .primary
        }
    }

    /// Muted ink for metadata, list bullets and rules.
    var secondaryInk: Color { ink.opacity(0.58) }

    /// Deterministic fallback colour for a file that carries no colour
    /// metadata — stable across launches and across devices because it only
    /// depends on the file name.
    static func derived(from seed: String) -> StickyColor {
        var hash: UInt64 = 5381
        for byte in seed.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        let all = StickyColor.paperColors
        return all[Int(hash % UInt64(all.count))]
    }

    static func named(_ raw: String?) -> StickyColor? {
        guard let raw else { return nil }
        let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
        switch key {
        case "transparent", "none": return .clear
        default: return StickyColor(rawValue: key)
        }
    }
}
