import SwiftUI

/// Everything that varies between a sticky on a small widget, a sticky in a
/// stacked pair, and the live preview in the editor.
struct StickyPresentation: Equatable {
    var baseFontSize: CGFloat
    var titleSize: CGFloat
    var padding: CGFloat
    var cornerRadius: CGFloat
    var showsTitle: Bool = true
    var showsFooter: Bool = false
    var showsFold: Bool = true
    /// Multiplies every size. This is the single knob the stacked widget
    /// turns to get its smaller text.
    var scale: CGFloat = 1

    var scaledBase: CGFloat { (baseFontSize * scale).rounded() }
    var scaledTitle: CGFloat { (titleSize * scale).rounded() }
    var scaledPadding: CGFloat { (padding * scale).rounded() }

    /// The folded corner is sized from the type rather than the padding, so
    /// widening the margins doesn't inflate the fold along with them.
    var scaledFold: CGFloat { max(9, (baseFontSize * scale * 1.45).rounded()) }

    // Widget margins are generous on purpose: the system rounds widget corners
    // hard (more so since iOS 26), and text set tight to the edge gets clipped
    // by the arc. These are the numbers to turn if a size feels off.
    static let widgetSmall = StickyPresentation(
        baseFontSize: 12, titleSize: 14, padding: 22, cornerRadius: 0
    )
    static let widgetMedium = StickyPresentation(
        baseFontSize: 13, titleSize: 16, padding: 28, cornerRadius: 0, showsFooter: true
    )
    static let widgetLarge = StickyPresentation(
        baseFontSize: 14, titleSize: 19, padding: 32, cornerRadius: 0, showsFooter: true
    )

    /// One half of the stacked widget: same layout, smaller everything, and
    /// rounded because it's a card floating on the widget's backdrop.
    static func stacked(scale: CGFloat, cornerRadius: CGFloat) -> StickyPresentation {
        StickyPresentation(
            baseFontSize: 12,
            titleSize: 13,
            padding: 18,
            cornerRadius: cornerRadius,
            showsTitle: true,
            showsFooter: false,
            showsFold: true,
            scale: scale
        )
    }

    /// The surface the note is written on. Mirrors a large widget so what you
    /// type is laid out the way the widget will lay it out.
    static let editing = StickyPresentation(
        baseFontSize: 15, titleSize: 20, padding: 30, cornerRadius: 18, showsFooter: true
    )

    /// Small decorative stickies — the ones on the welcome screen.
    static let sample = StickyPresentation(
        baseFontSize: 9, titleSize: 11, padding: 12, cornerRadius: 10
    )
}

/// The paper itself: a soft top-to-bottom gradient, which is what stops a
/// sticky from reading as a flat coloured rectangle.
struct StickyPaper: View {
    let color: StickyColor

    var body: some View {
        LinearGradient(
            colors: [color.paperTop, color.paperBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 26)
        }
    }
}

/// The folded-over bottom corner, paper and all.
struct StickyFold: View {
    let color: StickyColor
    let size: CGFloat

    var body: some View {
        FoldedCorner(size: size)
            .fill(color.fold)
            .overlay(
                FoldedCorner(size: size)
                    .stroke(color.ink.opacity(0.08), lineWidth: 0.5)
            )
            .allowsHitTesting(false)
    }
}

/// The triangle itself.
struct FoldedCorner: Shape {
    var size: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX - size, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - size))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The text of a sticky, with no background of its own.
///
/// Widgets put this on top of `.containerBackground`, which is what lets the
/// paper run edge to edge the way the system expects.
struct StickyContent: View {
    let note: Note
    var presentation: StickyPresentation

    /// A note that opens with a list has no title line of its own, so the
    /// heading row is given back to the content instead of repeating the file
    /// name above it.
    private var showsTitle: Bool {
        presentation.showsTitle && note.hasExplicitTitle
    }

    private var bodyMarkdown: String {
        showsTitle ? note.bodyBelowTitle : note.body
    }

    private var markdownStyle: MarkdownStyle {
        MarkdownStyle.sticky(
            color: note.color,
            baseSize: presentation.baseFontSize,
            scale: presentation.scale
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: presentation.scaledBase * 0.4) {
            if showsTitle {
                Text(note.title)
                    .font(.system(size: presentation.scaledTitle, weight: .semibold))
                    .foregroundStyle(note.color.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if note.isEmpty {
                Text("Empty note")
                    .font(.system(size: presentation.scaledBase).italic())
                    .foregroundStyle(note.color.secondaryInk)
            } else if !bodyMarkdown.isEmpty {
                MarkdownBodyView(markdown: bodyMarkdown, style: markdownStyle)
            }

            Spacer(minLength: 0)

            if presentation.showsFooter {
                Text(note.modified, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: max(8, presentation.scaledBase * 0.72), weight: .medium))
                    .foregroundStyle(note.color.secondaryInk)
            }
        }
        .padding(presentation.scaledPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Long notes simply run out of room; fading the last few points is
        // kinder than a hard cut mid-letter.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.92),
                    .init(color: .black.opacity(0.15), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay {
            if presentation.showsFold {
                StickyFold(color: note.color, size: presentation.scaledFold)
            }
        }
    }
}

/// A complete sticky: paper, text and fold, clipped to a rounded rectangle.
struct StickyCard: View {
    let note: Note
    var presentation: StickyPresentation
    var shadow: Bool = true

    var body: some View {
        StickyContent(note: note, presentation: presentation)
            .background(StickyPaper(color: note.color))
            .clipShape(RoundedRectangle(cornerRadius: presentation.cornerRadius, style: .continuous))
            .shadow(
                color: shadow ? Color.black.opacity(0.16) : .clear,
                radius: shadow ? 3 : 0,
                x: 0,
                y: shadow ? 1.5 : 0
            )
    }
}

/// Shown when a widget has nothing to display yet.
struct StickyPlaceholderView: View {
    var title: String
    var message: String
    var systemImage: String = "note.text"
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 15 : 20, weight: .medium))
                .foregroundStyle(StickyColor.yellow.ink.opacity(0.65))
            Text(title)
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .foregroundStyle(StickyColor.yellow.ink)
            Text(message)
                .font(.system(size: compact ? 10 : 12))
                .foregroundStyle(StickyColor.yellow.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .padding(compact ? 10 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
