import SwiftUI
import WidgetKit

struct DoubleStickyProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DoubleStickyEntry {
        DoubleStickyEntry(
            date: Date(),
            topNote: StickyResolver.sampleNote(color: .yellow, title: "Pick up keys"),
            bottomNote: StickyResolver.sampleNote(color: .blue, title: "Call the vet"),
            status: .ready
        )
    }

    func snapshot(for configuration: SelectTwoStickiesIntent, in context: Context) async -> DoubleStickyEntry {
        if context.isPreview {
            var entry = placeholder(in: context)
            entry.showsTitles = configuration.showsTitles
            return entry
        }
        return entry(for: configuration)
    }

    func timeline(for configuration: SelectTwoStickiesIntent, in context: Context) async -> Timeline<DoubleStickyEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(StickyResolver.nextRefresh()))
    }

    private func entry(for configuration: SelectTwoStickiesIntent) -> DoubleStickyEntry {
        let state = StickyLibrary.current()
        let resolved = StickyResolver.resolvePair(
            topID: configuration.topNote?.id,
            bottomID: configuration.bottomNote?.id,
            in: state
        )
        return DoubleStickyEntry(
            date: Date(),
            topNote: resolved.top,
            bottomNote: resolved.bottom,
            status: resolved.status,
            showsTitles: configuration.showsTitles
        )
    }
}

struct DoubleStickyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: DoubleStickyEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { backdrop }
    }

    @ViewBuilder
    private var content: some View {
        if entry.topNote == nil && entry.bottomNote == nil {
            StickyPlaceholderView(
                title: entry.status.title,
                message: entry.status.message,
                systemImage: entry.status.systemImage,
                compact: family == .systemSmall
            )
        } else {
            VStack(spacing: gap) {
                half(entry.topNote)
                half(entry.bottomNote)
            }
            .padding(gap)
        }
    }

    @ViewBuilder
    private func half(_ note: Note?) -> some View {
        if let note {
            StickyCard(note: note, presentation: presentation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
                .overlay {
                    Text("Edit the widget to pick a second sticky")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The surface the two stickies sit on. The gap between two paper notes
    /// needs something behind it; when every note showing is transparent the
    /// widget is too, and each note's hairline outline does the separating.
    @ViewBuilder
    private var backdrop: some View {
        if isTransparent {
            Color.clear
        } else {
            let base = colorScheme == .dark
                ? Color(white: 0.11)
                : Color(white: 0.93)
            LinearGradient(
                colors: [base, base.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var isTransparent: Bool {
        let notes = [entry.topNote, entry.bottomNote].compactMap { $0 }
        return !notes.isEmpty && notes.allSatisfy { $0.color.isTransparent }
    }

    private var gap: CGFloat {
        switch family {
        case .systemSmall: return 6
        case .systemLarge, .systemExtraLarge: return 11
        default: return 9
        }
    }

    private var cornerRadius: CGFloat {
        switch family {
        case .systemSmall: return 8
        case .systemLarge, .systemExtraLarge: return 13
        default: return 10
        }
    }

    /// Two notes in the space of one, so the type comes down to match.
    private var textScale: CGFloat {
        switch family {
        case .systemSmall: return 0.76
        case .systemLarge, .systemExtraLarge: return 0.92
        default: return 0.84
        }
    }

    private var presentation: StickyPresentation {
        var presentation = StickyPresentation.stacked(scale: textScale, cornerRadius: cornerRadius)
        presentation.showsTitle = entry.showsTitles
        return presentation
    }
}

struct DoubleStickyWidget: Widget {
    static let kind = "DoubleStickyWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SelectTwoStickiesIntent.self,
            provider: DoubleStickyProvider()
        ) { entry in
            DoubleStickyWidgetView(entry: entry)
        }
        .configurationDisplayName("Two Stickies")
        .description("Two sticky notes stacked, at a smaller size.")
        .supportedFamilies(supportedFamilies)
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
