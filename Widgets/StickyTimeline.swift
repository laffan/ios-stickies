import Foundation
import WidgetKit

/// Why a widget might not be showing a note.
enum WidgetStatus: Hashable {
    case ready
    case noFolderChosen
    case folderEmpty
    case noteMissing

    var title: String {
        switch self {
        case .ready: return ""
        case .noFolderChosen: return "Choose a folder"
        case .folderEmpty: return "No stickies yet"
        case .noteMissing: return "Sticky not found"
        }
    }

    var message: String {
        switch self {
        case .ready:
            return ""
        case .noFolderChosen:
            return "Open Stickies and pick the folder your notes live in."
        case .folderEmpty:
            return "Write a sticky in the app and it'll show up here."
        case .noteMissing:
            return "Edit this widget to pick a sticky."
        }
    }

    var systemImage: String {
        switch self {
        case .ready: return "note.text"
        case .noFolderChosen: return "folder.badge.questionmark"
        case .folderEmpty: return "note.text.badge.plus"
        case .noteMissing: return "questionmark.folder"
        }
    }
}

struct SingleStickyEntry: TimelineEntry {
    var date: Date
    var note: Note?
    var status: WidgetStatus
    var showsTitle: Bool = true
    var showsFooter: Bool = false
}

struct DoubleStickyEntry: TimelineEntry {
    var date: Date
    var topNote: Note?
    var bottomNote: Note?
    var status: WidgetStatus
    var showsTitles: Bool = true
}

/// Turns a widget's stored note id into an actual note.
enum StickyResolver {
    /// How long before WidgetKit is asked to come back.
    ///
    /// The app reloads timelines the moment anything changes on this device,
    /// so this only has to cover edits made elsewhere.
    static let refreshInterval: TimeInterval = 15 * 60

    static func nextRefresh(from date: Date = Date()) -> Date {
        date.addingTimeInterval(refreshInterval)
    }

    /// The dates a widget showing these notes has to be drawn for.
    ///
    /// A widget extension isn't running when a countdown's value changes, so
    /// every value it will show has to be drawn in advance: one entry per tick
    /// of the finest unit on display, aligned to the target so the number
    /// turns over at the right moment rather than up to a tick late.
    ///
    /// Seconds are rendered but never ticked — WidgetKit won't wake an
    /// extension that often — so a note counting in seconds refreshes once a
    /// minute like everything else, and a Lock Screen or Home Screen sticky is
    /// simply not a stopwatch.
    static func entryDates(for notes: [Note], from now: Date = Date(), limit: Int = 60) -> [Date] {
        let ticking = notes.compactMap { note -> (interval: TimeInterval, target: Date)? in
            guard let interval = note.tickInterval, let target = note.countdown.target else { return nil }
            return (max(60, interval), target)
        }
        guard let finest = ticking.min(by: { $0.interval < $1.interval }) else { return [now] }

        var dates = [now]
        let untilBoundary = finest.target.timeIntervalSince(now)
            .truncatingRemainder(dividingBy: finest.interval)
        var next = now.addingTimeInterval(
            untilBoundary <= 0 ? untilBoundary + finest.interval : untilBoundary
        )
        while dates.count < max(1, limit) {
            dates.append(next)
            next = next.addingTimeInterval(finest.interval)
        }
        return dates
    }

    /// Resolve one selected note.
    ///
    /// Passing `nil` (a widget that was added but never configured) falls back
    /// to the first sticky, so the widget is useful straight away.
    static func resolve(id: String?, in state: LibraryState) -> (note: Note?, status: WidgetStatus) {
        guard state.isFolderConfigured else { return (nil, .noFolderChosen) }
        guard !state.notes.isEmpty else { return (nil, .folderEmpty) }

        guard let id else {
            return (state.notes.first, .ready)
        }
        guard let note = Note.match(id: id, in: state.notes) else {
            return (nil, .noteMissing)
        }
        return (note, .ready)
    }

    /// Resolve the stacked widget's pair, defaulting the second slot to the
    /// next sticky along rather than repeating the first.
    static func resolvePair(
        topID: String?,
        bottomID: String?,
        in state: LibraryState
    ) -> (top: Note?, bottom: Note?, status: WidgetStatus) {
        guard state.isFolderConfigured else { return (nil, nil, .noFolderChosen) }
        guard !state.notes.isEmpty else { return (nil, nil, .folderEmpty) }

        let top = topID.flatMap { Note.match(id: $0, in: state.notes) } ?? (topID == nil ? state.notes.first : nil)
        let fallbackBottom = state.notes.first { $0.id != top?.id } ?? state.notes.first
        let bottom = bottomID.flatMap { Note.match(id: $0, in: state.notes) } ?? (bottomID == nil ? fallbackBottom : nil)

        if top == nil && bottom == nil { return (nil, nil, .noteMissing) }
        return (top, bottom, .ready)
    }

    /// A believable note for the gallery and for redacted placeholders.
    static func sampleNote(color: StickyColor = .yellow, title: String = "Pick up keys") -> Note {
        Note(
            fileName: "\(title).md",
            body: "# \(title)\n- back door\n- **spare set** in the drawer",
            color: color,
            created: Date(),
            modified: Date()
        )
    }
}
