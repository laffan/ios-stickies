#if os(iOS)
import SwiftUI
import WidgetKit

/// Lock Screen sticky.
///
/// Two shapes: the inline strip that sits directly above the clock, and the
/// rectangular slot below it. Both are rendered by the system in a single
/// tint, so sticky colour is deliberately not used here — all the space goes
/// to text instead.
struct LockScreenStickyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SingleStickyEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            // Inline supports a single line of text and nothing else.
            Text(inlineText)
        default:
            rectangular
        }
    }

    // MARK: - Rectangular

    /// Steps down the type size until the note fits, and only truncates when
    /// even the smallest size can't hold it.
    private var rectangular: some View {
        ViewThatFits(in: .vertical) {
            candidate(size: 13)
            candidate(size: 12)
            candidate(size: 11)
            candidate(size: 10)
            candidate(size: 9)
            candidate(size: 8, lineLimit: 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func candidate(size: CGFloat, lineLimit: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if showsTitle, !titleText.isEmpty {
                Text(titleText)
                    .font(.system(size: size + 1, weight: .semibold))
                    .lineLimit(1)
                    .widgetAccentable()
            }
            if !bodyText.isEmpty {
                Text(bodyText)
                    .font(.system(size: size))
                    .lineLimit(lineLimit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Text

    /// Same rule as the Home Screen sticky: only show a title row when the
    /// note actually starts with one.
    private var showsTitle: Bool {
        entry.showsTitle && (entry.note?.hasExplicitTitle ?? true)
    }

    private var titleText: String {
        entry.note?.title ?? entry.status.title
    }

    private var bodyText: String {
        guard let note = entry.note else { return entry.status.message }
        let source = showsTitle ? note.bodyBelowTitle : note.body
        return MarkdownPlainText.render(source)
    }

    private var inlineText: String {
        guard entry.note != nil else { return entry.status.title }
        let flattened = bodyText
            .replacingOccurrences(of: "\n", with: " · ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if flattened.isEmpty { return titleText }
        return showsTitle ? "\(titleText) — \(flattened)" : flattened
    }
}

struct LockScreenStickyWidget: Widget {
    static let kind = "LockScreenStickyWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SelectStickyIntent.self,
            provider: SingleStickyProvider()
        ) { entry in
            LockScreenStickyView(entry: entry)
        }
        .configurationDisplayName("Sticky on the Lock Screen")
        .description("Fits as much of one sticky as the Lock Screen allows.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular])
    }
}
#endif
