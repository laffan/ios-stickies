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
    /// The note's own text size. Kept apart from `scale` because it must not
    /// touch the margins: a note set in extra large still needs the same gap
    /// to the widget's rounded edge.
    var textScale: CGFloat = 1

    var scaledBase: CGFloat { (baseFontSize * scale * textScale).rounded() }
    var scaledTitle: CGFloat { (titleSize * scale * textScale).rounded() }
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

    /// The sizes `.fit` tries, largest first. The first one whose text fits
    /// the widget wins; if even the last is too big the note was never going
    /// to fit, and the bottom fade takes it from there.
    private static let fitScales: [CGFloat] = [4, 3.3, 2.8, 2.35, 2, 1.7, 1.42, 1.18, 0.95, 0.75]

    private var formatting: NoteFormatting { note.formatting }

    var body: some View {
        text
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: formatting.horizontal.frameAlignment)
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
            // Drawn last, and outside the fade, so the frame stays unbroken.
            .overlay { border }
    }

    /// Either the note at the size it asked for, or — for `.fit` — the largest
    /// of a ladder of sizes whose text still fits the space on offer.
    ///
    /// `ViewThatFits` measures each candidate's ideal height and takes the
    /// first that doesn't overflow, which is exactly the question "how big can
    /// this note be set and still be readable in full?".
    @ViewBuilder
    private var text: some View {
        if let scale = formatting.textSize.scale {
            stack(textScale: scale)
        } else {
            ViewThatFits(in: .vertical) {
                stack(textScale: Self.fitScales[0])
                stack(textScale: Self.fitScales[1])
                stack(textScale: Self.fitScales[2])
                stack(textScale: Self.fitScales[3])
                stack(textScale: Self.fitScales[4])
                stack(textScale: Self.fitScales[5])
                stack(textScale: Self.fitScales[6])
                stack(textScale: Self.fitScales[7])
                stack(textScale: Self.fitScales[8])
                stack(textScale: Self.fitScales[9])
            }
        }
    }

    private func stack(textScale: CGFloat) -> some View {
        let metrics = sized(textScale)
        return VStack(alignment: formatting.horizontal.stackAlignment, spacing: metrics.scaledBase * 0.4) {
            // Vertical centring is two spacers rather than a frame alignment,
            // so the footer can still sit on the bottom edge where it belongs.
            if formatting.vertical.padsAbove { Spacer(minLength: 0) }

            if showsTitle {
                MarkdownInline.text(
                    note.titleMarkdown,
                    size: metrics.scaledTitle,
                    weight: .semibold,
                    theme: markdownStyle(textScale)
                )
                .foregroundStyle(note.color.ink)
                // Two lines is a sensible cap for a title — except when the
                // note is being fitted, where a truncated title would make
                // "it fits" a lie and stop the ladder stepping down.
                .lineLimit(formatting.textSize == .fit ? nil : 2)
                .multilineTextAlignment(formatting.horizontal.textAlignment)
                .frame(maxWidth: .infinity, alignment: formatting.horizontal.frameAlignment)
                .fixedSize(horizontal: false, vertical: true)
            }

            if note.isEmpty {
                Text("Empty note")
                    .font(.system(size: metrics.scaledBase).italic())
                    .foregroundStyle(note.color.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: formatting.horizontal.frameAlignment)
            } else if !bodyMarkdown.isEmpty {
                MarkdownBodyView(markdown: bodyMarkdown, style: markdownStyle(textScale))
            }

            if formatting.vertical.padsBelow { Spacer(minLength: 0) }

            if presentation.showsFooter {
                Text(note.modified, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: max(8, metrics.scaledBase * 0.72), weight: .medium))
                    .foregroundStyle(note.color.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: formatting.horizontal.frameAlignment)
            }
        }
        .padding(metrics.scaledPadding)
    }

    /// The border follows the container rather than a shape of its own: inside
    /// a widget that's the widget's own rounding, and inside the app it's the
    /// radius `StickyCard` hands down with `.containerShape`. Nothing has to
    /// guess what the system rounds a widget to.
    @ViewBuilder
    private var border: some View {
        if let color = formatting.border.color {
            ContainerRelativeShape()
                .strokeBorder(
                    color.edge,
                    lineWidth: max(1, (formatting.border.width.points * presentation.scale).rounded())
                )
        }
    }

    /// The presentation with a text size folded in.
    private func sized(_ textScale: CGFloat) -> StickyPresentation {
        var adjusted = presentation
        adjusted.textScale = presentation.textScale * textScale
        return adjusted
    }

    private func markdownStyle(_ textScale: CGFloat) -> MarkdownStyle {
        MarkdownStyle.sticky(
            color: note.color,
            baseSize: presentation.baseFontSize,
            scale: presentation.scale * presentation.textScale * textScale,
            formatting: formatting
        )
    }

    /// A note that opens with a list has no title line of its own, so the
    /// heading row is given back to the content instead of repeating the file
    /// name above it.
    private var showsTitle: Bool {
        presentation.showsTitle && note.hasExplicitTitle
    }

    private var bodyMarkdown: String {
        showsTitle ? note.bodyBelowTitle : note.body
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
            // Hands the card's own radius to the border inside, which is drawn
            // as a `ContainerRelativeShape` so that in a widget it picks up
            // whatever the system rounds the widget to instead.
            .containerShape(RoundedRectangle(cornerRadius: presentation.cornerRadius, style: .continuous))
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
