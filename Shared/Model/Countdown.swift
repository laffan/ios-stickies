import Foundation

/// One field of a countdown. The declaration order is the order they're
/// rendered in, largest first.
enum CountdownUnit: String, CaseIterable, Codable, Sendable, Identifiable {
    case years
    case months
    case weeks
    case days
    case hours
    case minutes
    case seconds

    var id: String { rawValue }

    var component: Calendar.Component {
        switch self {
        case .years: return .year
        case .months: return .month
        case .weeks: return .weekOfYear
        case .days: return .day
        case .hours: return .hour
        case .minutes: return .minute
        case .seconds: return .second
        }
    }

    var displayName: String {
        switch self {
        case .years: return "Years"
        case .months: return "Months"
        case .weeks: return "Weeks"
        case .days: return "Days"
        case .hours: return "Hours"
        case .minutes: return "Minutes"
        case .seconds: return "Seconds"
        }
    }

    /// What a single one is called: "1 day", not "1 days".
    var singular: String {
        switch self {
        case .years: return "year"
        case .months: return "month"
        case .weeks: return "week"
        case .days: return "day"
        case .hours: return "hour"
        case .minutes: return "minute"
        case .seconds: return "second"
        }
    }

    var plural: String { rawValue }

    /// The compact suffix: `2mo 3d 4h`.
    var shortLabel: String {
        switch self {
        case .years: return "y"
        case .months: return "mo"
        case .weeks: return "w"
        case .days: return "d"
        case .hours: return "h"
        case .minutes: return "m"
        case .seconds: return "s"
        }
    }

    func label(for value: Int) -> String {
        abs(value) == 1 ? singular : plural
    }

    /// Roughly how often a countdown showing this as its smallest unit needs
    /// to be redrawn. Months and up don't need a schedule of their own — the
    /// ordinary widget refresh is far more frequent than they change.
    var refreshInterval: TimeInterval? {
        switch self {
        case .seconds: return 1
        case .minutes: return 60
        case .hours: return 3600
        case .days, .weeks, .months, .years: return nil
        }
    }

    static func named(_ raw: String?) -> CountdownUnit? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "year", "years", "y", "yr", "yrs": return .years
        case "month", "months", "mo", "mon", "mons": return .months
        case "week", "weeks", "w", "wk", "wks": return .weeks
        case "day", "days", "d": return .days
        case "hour", "hours", "h", "hr", "hrs": return .hours
        case "minute", "minutes", "min", "mins": return .minutes
        case "second", "seconds", "sec", "secs": return .seconds
        default: return nil
        }
    }
}

/// How the remaining time reads.
enum CountdownStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    /// `2 months, 14 days`
    case full
    /// `2mo 14d`
    case short
    /// `14:06:03`
    case digits

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full: return "Words"
        case .short: return "Compact"
        case .digits: return "Digits"
        }
    }

    var token: String { rawValue }

    static func named(_ raw: String?) -> CountdownStyle? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "full", "long", "words", "word": return .full
        case "short", "compact", "abbreviated", "abbrev": return .short
        case "digits", "digit", "clock", "timer": return .digits
        default: return nil
        }
    }

    func format(_ fields: [(unit: CountdownUnit, value: Int)], isPast: Bool) -> String {
        switch self {
        case .full:
            let body = fields
                .map { "\($0.value) \($0.unit.label(for: $0.value))" }
                .joined(separator: ", ")
            return isPast ? "\(body) ago" : body
        case .short:
            let body = fields
                .map { "\($0.value)\($0.unit.shortLabel)" }
                .joined(separator: " ")
            return isPast ? "\(body) ago" : body
        case .digits:
            let body = fields
                .enumerated()
                .map { index, field in
                    index == 0 ? "\(field.value)" : String(format: "%02d", field.value)
                }
                .joined(separator: ":")
            return isPast ? "-\(body)" : body
        }
    }
}

/// A note's countdown: what it counts to, and which fields it shows.
///
/// The value reaches the note through the `{{countdown}}` tag, so a sticky can
/// put it in a sentence — "Ship in {{countdown}}" — rather than being a clock
/// with a note attached.
struct CountdownSettings: Hashable, Codable, Sendable {
    /// Nil means the note has no countdown; a `{{countdown}}` tag then renders
    /// as a placeholder rather than disappearing.
    var target: Date?
    var units: [CountdownUnit]
    var style: CountdownStyle

    static let defaultUnits: [CountdownUnit] = [.days, .hours, .minutes]

    init(
        target: Date? = nil,
        units: [CountdownUnit] = CountdownSettings.defaultUnits,
        style: CountdownStyle = .full
    ) {
        self.target = target
        self.units = units
        self.style = style
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decodeIfPresent(Date.self, forKey: .target)
        units = try container.decodeIfPresent([CountdownUnit].self, forKey: .units)
            ?? CountdownSettings.defaultUnits
        style = try container.decodeIfPresent(CountdownStyle.self, forKey: .style) ?? .full
    }

    var isEnabled: Bool { target != nil }

    /// The selected units, largest first, de-duplicated, and never empty —
    /// a countdown that shows nothing at all would just be a blank sticky.
    var orderedUnits: [CountdownUnit] {
        let chosen = Set(units)
        let ordered = CountdownUnit.allCases.filter(chosen.contains)
        return ordered.isEmpty ? [.days] : ordered
    }

    /// The smallest unit on show — the one that decides how often the value
    /// changes, and so how often a widget has to be redrawn.
    var finestUnit: CountdownUnit? { orderedUnits.last }

    mutating func toggle(_ unit: CountdownUnit) {
        if units.contains(unit) {
            // Never let the last one go: an empty countdown has nothing to say.
            guard units.count > 1 else { return }
            units.removeAll { $0 == unit }
        } else {
            units.append(unit)
        }
        units = orderedUnits
    }
}

/// Renders a countdown, and expands the tags that put one inside a note.
enum Countdown {
    /// Shown where a `{{countdown}}` tag has no date behind it yet.
    static let placeholder = "—"

    /// The time between `now` and the target, in the units the note asked for.
    ///
    /// Leading zero fields are dropped — "0 months, 3 days" reads badly — but
    /// the smallest unit always survives, so a finished countdown still shows
    /// something rather than an empty string.
    static func text(
        for settings: CountdownSettings,
        at now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        guard let target = settings.target else { return nil }
        let units = settings.orderedUnits
        let isPast = target < now
        let components = calendar.dateComponents(
            Set(units.map(\.component)),
            from: isPast ? target : now,
            to: isPast ? now : target
        )

        var fields = units.map { unit in
            (unit: unit, value: max(0, components.value(for: unit.component) ?? 0))
        }
        if let firstMeaningful = fields.firstIndex(where: { $0.value != 0 }) {
            fields.removeFirst(firstMeaningful)
        } else if let smallest = fields.last {
            fields = [smallest]
        }
        return settings.style.format(fields, isPast: isPast)
    }
}

/// The `{{…}}` tags a note body may contain.
///
/// Only `{{countdown}}` exists today. Anything else is left exactly as typed,
/// so a note that happens to contain braces isn't quietly rewritten.
enum NoteTags {
    static let countdownName = "countdown"
    /// The tag as the app writes it, and as it appears in the editor.
    static let countdownTagExample = "{{countdown}}"

    private static let opening = "{{"
    private static let closing = "}}"

    static func containsCountdown(_ body: String) -> Bool {
        guard body.contains(opening) else { return false }
        var remainder = body[...]
        while let open = remainder.range(of: opening),
              let close = remainder.range(of: closing, range: open.upperBound..<remainder.endIndex) {
            if arguments(in: remainder[open.upperBound..<close.lowerBound]) != nil { return true }
            remainder = remainder[close.upperBound...]
        }
        return false
    }

    /// Replace every countdown tag with its value at `date`.
    static func expand(_ body: String, countdown settings: CountdownSettings, at date: Date) -> String {
        rewrite(body) { arguments in
            value(for: arguments, settings: settings, at: date)
        }
    }

    /// The body with its countdown tags taken out.
    ///
    /// Used where the value of a particular moment would be the wrong thing to
    /// keep — naming the file after a first line that reads "{{countdown}} to
    /// go" should give "to go", not "3 days to go" frozen forever.
    static func stripped(_ body: String) -> String {
        rewrite(body) { _ in "" }
    }

    private static func rewrite(_ body: String, replacing: ([String]) -> String) -> String {
        guard body.contains(opening) else { return body }

        var result = ""
        var remainder = body[...]
        while let open = remainder.range(of: opening),
              let close = remainder.range(of: closing, range: open.upperBound..<remainder.endIndex) {
            result += String(remainder[remainder.startIndex..<open.lowerBound])
            let inner = remainder[open.upperBound..<close.lowerBound]
            if let arguments = arguments(in: inner) {
                result += replacing(arguments)
            } else {
                result += String(remainder[open.lowerBound..<close.upperBound])
            }
            remainder = remainder[close.upperBound...]
        }
        return result + String(remainder)
    }

    /// The words inside a countdown tag, or nil if this isn't one.
    ///
    /// `{{countdown}}` takes the note's own settings; `{{countdown: days,
    /// hours}}` or `{{countdown short}}` overrides them for that one tag,
    /// which is how a note can show both "14 days" and "14d 6h 2m".
    private static func arguments(in raw: Substring) -> [String]? {
        let pieces = raw
            .lowercased()
            .components(separatedBy: CharacterSet(charactersIn: ":,| \t"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard pieces.first == countdownName else { return nil }
        return Array(pieces.dropFirst())
    }

    private static func value(
        for arguments: [String],
        settings: CountdownSettings,
        at date: Date
    ) -> String {
        var resolved = settings
        var units: [CountdownUnit] = []
        for argument in arguments {
            if let unit = CountdownUnit.named(argument) {
                units.append(unit)
            } else if let style = CountdownStyle.named(argument) {
                resolved.style = style
            }
        }
        if !units.isEmpty { resolved.units = units }
        return Countdown.text(for: resolved, at: date) ?? Countdown.placeholder
    }
}
