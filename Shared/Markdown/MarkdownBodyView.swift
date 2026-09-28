import SwiftUI

/// Type sizes, spacing and ink for rendered markdown.
///
/// Widgets pass a `scale` below 1 — that's how the stacked two-sticky widget
/// gets its smaller text without a second set of views.
struct MarkdownStyle: Equatable {
    var baseSize: CGFloat
    var lineSpacing: CGFloat
    var blockSpacing: CGFloat
    var ink: Color
    var secondaryInk: Color
    var linkInk: Color
    var alignment: TextAlignment = .leading

    /// `scale` already carries the note's text size — the caller resolves it,
    /// because `.fit` has no size until the layout picks one.
    static func sticky(
        for note: Note,
        baseSize: CGFloat,
        scale: CGFloat = 1,
        formatting: NoteFormatting = .standard
    ) -> MarkdownStyle {
        let resolved = (baseSize * scale).rounded()
        return MarkdownStyle(
            baseSize: resolved,
            lineSpacing: (resolved * 0.18).rounded(),
            blockSpacing: max(2, (resolved * 0.42).rounded()),
            ink: note.inkColor,
            secondaryInk: note.secondaryInkColor,
            linkInk: linkInk(for: note),
            alignment: formatting.horizontal.textAlignment
        )
    }

    /// One deep navy across the whole palette: dark enough to read on every
    /// paper colour, and it survives the Lock Screen's flattening because
    /// links are underlined too. A note with its own ink, or no paper, can't
    /// promise navy will read, so its links keep the ink and rely on the
    /// underline alone.
    private static func linkInk(for note: Note) -> Color {
        guard note.ink == nil, !note.color.isTransparent else { return note.inkColor }
        return Color(red: 0.15, green: 0.25, blue: 0.62)
    }

    var frameAlignment: Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var stackAlignment: HorizontalAlignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    /// Left-aligned rows fill the width so their text wraps against the
    /// margin; centred and right-aligned ones shrink to their content, which
    /// is what puts a bullet next to its own words rather than out at the edge.
    var rowsFillWidth: Bool { alignment == .leading }

    /// Heading sizes, largest first. Deliberately restrained: inside a small
    /// widget an `# H1` at 2× swallows the whole note.
    func headingSize(level: Int) -> CGFloat {
        let multipliers: [CGFloat] = [1.42, 1.26, 1.14, 1.06, 1.0, 1.0]
        let index = min(max(level - 1, 0), multipliers.count - 1)
        return (baseSize * multipliers[index]).rounded()
    }

    func indent(depth: Int) -> CGFloat {
        CGFloat(depth) * baseSize * 0.85
    }
}

/// Renders markdown blocks as SwiftUI text. Safe to use inside a widget: no
/// scroll views, no lazy stacks, no async work.
struct MarkdownBodyView: View {
    let markdown: String
    let style: MarkdownStyle

    private var blocks: [MarkdownBlock] { MarkdownParser.parse(markdown) }

    var body: some View {
        VStack(alignment: style.stackAlignment, spacing: style.blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .lineSpacing(style.lineSpacing)
        .foregroundStyle(style.ink)
        .multilineTextAlignment(style.alignment)
        .frame(maxWidth: .infinity, alignment: style.frameAlignment)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            MarkdownInline.text(
                text,
                size: style.headingSize(level: level),
                weight: level <= 2 ? .bold : .semibold,
                theme: style
            )
            .frame(maxWidth: .infinity, alignment: style.frameAlignment)

        case .paragraph(let text):
            MarkdownInline.text(text, size: style.baseSize, theme: style)
                .frame(maxWidth: .infinity, alignment: style.frameAlignment)

        case .bullet(let text, let depth):
            listRow(
                marker: Text(verbatim: "•").font(.system(size: style.baseSize, weight: .bold)),
                text: text,
                depth: depth
            )

        case .numbered(let number, let text, let depth):
            listRow(
                marker: Text(verbatim: "\(number).").font(.system(size: style.baseSize * 0.92, weight: .semibold)),
                text: text,
                depth: depth
            )

        case .task(let text, let isDone, let depth):
            listRow(
                marker: Text(Image(systemName: isDone ? "checkmark.square.fill" : "square"))
                    .font(.system(size: style.baseSize * 0.92)),
                text: text,
                depth: depth,
                strikethrough: isDone
            )

        case .quote(let text):
            HStack(alignment: .top, spacing: style.baseSize * 0.45) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(style.secondaryInk.opacity(0.55))
                    .frame(width: max(2, style.baseSize * 0.14))
                MarkdownInline.text(text, size: style.baseSize, italic: true, theme: style)
                    .foregroundStyle(style.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: style.frameAlignment)
            .fixedSize(horizontal: false, vertical: true)

        case .code(let text):
            Text(verbatim: text)
                .font(.system(size: style.baseSize * 0.88, design: .monospaced))
                .padding(.horizontal, style.baseSize * 0.4)
                .padding(.vertical, style.baseSize * 0.28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: style.baseSize * 0.35, style: .continuous)
                        .fill(style.ink.opacity(0.08))
                )

        case .rule:
            Rectangle()
                .fill(style.secondaryInk.opacity(0.35))
                .frame(height: 1)
                .padding(.vertical, style.blockSpacing * 0.25)
        }
    }

    private func listRow(marker: Text, text: String, depth: Int, strikethrough: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: style.baseSize * 0.35) {
            marker.foregroundStyle(style.secondaryInk)
            MarkdownInline.text(text, size: style.baseSize, theme: style)
                .strikethrough(strikethrough, color: style.secondaryInk)
                .foregroundStyle(strikethrough ? style.secondaryInk : style.ink)
                .frame(maxWidth: style.rowsFillWidth ? CGFloat.infinity : nil, alignment: .leading)
        }
        .padding(.leading, style.indent(depth: depth))
        .frame(maxWidth: .infinity, alignment: style.frameAlignment)
        .fixedSize(horizontal: false, vertical: true)
    }
}
