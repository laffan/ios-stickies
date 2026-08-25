import SwiftUI
import WidgetKit

struct SingleStickyProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SingleStickyEntry {
        SingleStickyEntry(date: Date(), note: StickyResolver.sampleNote(), status: .ready)
    }

    func snapshot(for configuration: SelectStickyIntent, in context: Context) async -> SingleStickyEntry {
        // The widget gallery has no folder access of its own; show a sample
        // rather than an error card.
        if context.isPreview {
            return SingleStickyEntry(
                date: Date(),
                note: StickyResolver.sampleNote(),
                status: .ready,
                showsTitle: configuration.showsTitle,
                showsFooter: configuration.showsFooter
            )
        }
        return entry(for: configuration)
    }

    func timeline(for configuration: SelectStickyIntent, in context: Context) async -> Timeline<SingleStickyEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(StickyResolver.nextRefresh()))
    }

    private func entry(for configuration: SelectStickyIntent) -> SingleStickyEntry {
        let state = StickyLibrary.current()
        let resolved = StickyResolver.resolve(id: configuration.note?.id, in: state)
        return SingleStickyEntry(
            date: Date(),
            note: resolved.note,
            status: resolved.status,
            showsTitle: configuration.showsTitle,
            showsFooter: configuration.showsFooter
        )
    }
}

struct SingleStickyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SingleStickyEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                StickyPaper(color: entry.note?.color ?? .yellow)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let note = entry.note {
            StickyContent(note: note, presentation: presentation)
        } else {
            StickyPlaceholderView(
                title: entry.status.title,
                message: entry.status.message,
                systemImage: entry.status.systemImage,
                compact: family == .systemSmall
            )
        }
    }

    private var presentation: StickyPresentation {
        var presentation: StickyPresentation
        switch family {
        case .systemSmall:
            presentation = .widgetSmall
        case .systemLarge, .systemExtraLarge:
            presentation = .widgetLarge
        default:
            presentation = .widgetMedium
        }
        presentation.showsTitle = entry.showsTitle
        // There isn't room for a timestamp on a small widget without eating a
        // line of the note itself.
        presentation.showsFooter = entry.showsFooter && family != .systemSmall
        return presentation
    }
}

struct SingleStickyWidget: Widget {
    static let kind = "SingleStickyWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SelectStickyIntent.self,
            provider: SingleStickyProvider()
        ) { entry in
            SingleStickyWidgetView(entry: entry)
        }
        .configurationDisplayName("Sticky Note")
        .description("One sticky note, pinned where you'll see it.")
        .supportedFamilies(supportedFamilies)
        // The paper should run to the edges; the note's own padding does the
        // spacing work.
        .contentMarginsDisabled()
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(macOS)
        return [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        #else
        return [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}
