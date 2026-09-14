import SwiftUI

/// The Home Screen widget sizes, as the app draws them for itself.
///
/// The numbers are the real thing's point sizes on an iPhone. Drawing a
/// preview at those dimensions and scaling the whole card down as one piece —
/// rather than squeezing the box and leaving the type where it was — is what
/// makes a preview worth looking at: the amount of the note that fits is the
/// amount that will fit.
enum StickyWidgetSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var referenceSize: CGSize {
        switch self {
        case .small: return CGSize(width: 158, height: 158)
        case .medium: return CGSize(width: 338, height: 158)
        case .large: return CGSize(width: 338, height: 354)
        }
    }

    /// What the system rounds a Home Screen widget to.
    var cornerRadius: CGFloat { 22 }

    /// The same presentation the widget extension uses, rounded off — and
    /// without the footer, which a widget only shows when its configuration
    /// asks for it.
    var presentation: StickyPresentation {
        var presentation: StickyPresentation
        switch self {
        case .small: presentation = .widgetSmall
        case .medium: presentation = .widgetMedium
        case .large: presentation = .widgetLarge
        }
        presentation.cornerRadius = cornerRadius
        presentation.showsFooter = false
        return presentation
    }
}

/// One sticky drawn the way a widget of that size will draw it.
///
/// Used for the previews under the editor and for the rows in the sidebar,
/// which are the same thing at different widths.
struct StickyWidgetPreview: View {
    let note: Note
    var size: StickyWidgetSize = .small
    /// How wide to draw it. Defaults to the widget's own size; the sidebar
    /// passes something smaller.
    var maxWidth: CGFloat?
    var shadow = true

    var body: some View {
        // A note with a live countdown redraws itself; everything else is
        // static, and shouldn't pay for a timeline it doesn't need.
        if let tick = note.tickInterval {
            TimelineView(.periodic(from: Date(), by: tick)) { context in
                fitted(at: context.date)
            }
        } else {
            fitted(at: Date())
        }
    }

    /// The largest of a few whole-card scalings that still fits the width on
    /// offer. Every candidate is laid out at the widget's real point size and
    /// then scaled as one piece, so the only thing that changes between them
    /// is how big the picture is — never how much of the note fits in it.
    private func fitted(at date: Date) -> some View {
        ViewThatFits(in: .horizontal) {
            scaled(1, at: date)
            scaled(0.86, at: date)
            scaled(0.72, at: date)
            scaled(0.58, at: date)
            scaled(0.44, at: date)
        }
    }

    private func scaled(_ step: CGFloat, at date: Date) -> some View {
        let reference = size.referenceSize
        let factor = ((maxWidth ?? reference.width) / reference.width) * step
        return StickyCard(
            note: note.resolved(at: date),
            presentation: size.presentation,
            shadow: shadow
        )
        .frame(width: reference.width, height: reference.height)
        // Scaling doesn't change the layout size, so the frame below is what
        // actually reserves the space. Both are centred on the same point,
        // which is why the anchor is left alone.
        .scaleEffect(factor)
        .frame(width: reference.width * factor, height: reference.height * factor)
    }
}
