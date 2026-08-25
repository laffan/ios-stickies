import AppIntents
import WidgetKit

/// Configuration for the single-sticky and Lock Screen widgets.
struct SelectStickyIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Sticky"
    static var description = IntentDescription("Pick which sticky note this widget shows.")

    @Parameter(title: "Sticky")
    var note: NoteEntity?

    @Parameter(title: "Show Title", default: true)
    var showsTitle: Bool

    @Parameter(title: "Show Last Edited", default: false)
    var showsFooter: Bool

    init() {}

    init(note: NoteEntity?, showsTitle: Bool = true, showsFooter: Bool = false) {
        self.note = note
        self.showsTitle = showsTitle
        self.showsFooter = showsFooter
    }
}

/// Configuration for the stacked two-sticky widget.
struct SelectTwoStickiesIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Two Stickies"
    static var description = IntentDescription("Pick the two sticky notes this widget stacks.")

    @Parameter(title: "Top Sticky")
    var topNote: NoteEntity?

    @Parameter(title: "Bottom Sticky")
    var bottomNote: NoteEntity?

    @Parameter(title: "Show Titles", default: true)
    var showsTitles: Bool

    init() {}

    init(topNote: NoteEntity?, bottomNote: NoteEntity?, showsTitles: Bool = true) {
        self.topNote = topNote
        self.bottomNote = bottomNote
        self.showsTitles = showsTitles
    }
}
