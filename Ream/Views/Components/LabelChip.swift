import SwiftUI

/// The one way a label is ever drawn. Every surface — row, detail, filter bar, picker —
/// goes through this so a palette or shape change lands everywhere at once.
struct LabelChip: View {
    let name: String
    let color: LabelColor
    /// Filter chips invert when active; content chips never do.
    var isSelected: Bool = false
    var showsCount: Int?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .lineLimit(1)
            if let showsCount {
                Text("\(showsCount)")
                    .monospacedDigit()
                    .opacity(0.7)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(isSelected ? Theme.cardBackground : resolved)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            isSelected ? AnyShapeStyle(resolved)
                       : AnyShapeStyle(resolved.opacity(LabelColor.tintOpacity)),
            in: Capsule()
        )
    }

    private var resolved: Color { color.color(for: scheme) }
}

/// Horizontally scrolling row of chips. Used for the filter bar and for a document's own
/// labels, which is why it takes content rather than a fixed model.
struct ChipRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.tight) {
                content
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.tight)
        }
        // Without this the scroll view swallows the whole width even when a single chip
        // would fit, and the row can't be tapped past its content.
        .scrollBounceBehavior(.basedOnSize)
    }
}
