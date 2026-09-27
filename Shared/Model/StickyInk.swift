import SwiftUI

/// A text colour chosen for one note, overriding its paper's own ink.
///
/// Stored in front matter as a quoted hex string — `ink: "#1F2A44"`. The quotes
/// matter: in YAML an unquoted `#` starts a comment, so other tools reading the
/// same file would otherwise see an empty value.
struct StickyInk: Hashable, Codable, Sendable {
    /// sRGB components, 0…1, held to the 8 bits a hex string keeps — so an
    /// ink read back from disk compares equal to the one that was written.
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.quantize(red)
        self.green = Self.quantize(green)
        self.blue = Self.quantize(blue)
    }

    /// Accepts `#RGB` or `#RRGGBB`, with or without the `#`.
    init?(hex raw: String) {
        var digits = raw.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16)
        else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// Whatever the colour picker hands back, flattened to sRGB. Wide-gamut
    /// picks land on the nearest sRGB colour, which is all a hex string holds.
    init(_ color: Color, in environment: EnvironmentValues) {
        let resolved = color.resolve(in: environment)
        self.init(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
    }

    /// `#RRGGBB`, upper-case.
    var hex: String {
        func byte(_ component: Double) -> String {
            String(format: "%02X", Int((component * 255).rounded()))
        }
        return "#" + byte(red) + byte(green) + byte(blue)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }

    private static func quantize(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (min(max(value, 0), 1) * 255).rounded() / 255
    }

    // A hex string in the widget snapshot too, so it reads the same as the file.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let ink = StickyInk(hex: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a hex colour: \(raw)")
        }
        self = ink
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

extension Note {
    /// The colour the note's text is drawn in: its own ink if it has one,
    /// otherwise the ink that goes with its paper.
    var inkColor: Color { ink?.color ?? color.ink }

    /// Muted ink for metadata, list bullets and rules.
    var secondaryInkColor: Color { inkColor.opacity(0.58) }
}
