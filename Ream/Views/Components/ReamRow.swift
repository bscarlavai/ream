import SwiftUI

/// What sits at the trailing edge of a row.
///
/// An enum rather than a free-form view slot, so "what can appear on the right of a row"
/// is a closed, reviewable set. Every new accessory is a deliberate addition to this list
/// instead of a one-off `HStack` in some screen nobody looks at again.
enum RowAccessory {
    /// Performs an action in place. No indicator — nothing is being navigated to.
    case none
    /// Opens a sheet or pushes a screen.
    case chevron
    /// Static trailing text: a version number, a price.
    case value(String)
    /// Current selection in a picker.
    case checkmark(Color)
    /// Quiet trailing label, e.g. "Supporter" on a locked finish.
    case badge(String)
}

/// The one row idiom in Ream. Every list on every screen goes through this.
///
/// The point is not that a row is hard to write — it's that writing it eleven times
/// produced eleven different answers to "how tall is a row", and three rounds of spacing
/// bugs. Height, insets, dividers and press states now belong to `List`, and this only
/// decides what goes *in* the row.
///
/// **No `.frame(minHeight:)` here, deliberately.** A row inside a `List` already clears
/// 44pt from the system's own insets; adding a minimum on top stacks the two and yields a
/// ~66pt row that reads as mostly empty space. Only set an explicit minimum on controls
/// that are *not* inside a List.
struct ReamRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var iconTint: Color?
    /// Replaces the icon with a filled circle — used by the finish picker, where the
    /// color *is* the thing being chosen.
    var swatch: Color?
    var accessory: RowAccessory = .none
    var isDestructive = false

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            leading

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(isDestructive ? Color.red : Theme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            Spacer(minLength: Theme.Spacing.small)

            trailing
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leading: some View {
        if let swatch {
            Circle()
                .fill(swatch)
                .frame(width: 26, height: 26)
        } else if let systemImage {
            Image(systemName: systemImage)
                // Fixed width so titles align down the column regardless of glyph shape —
                // SF Symbols vary enough in width to make a ragged left edge otherwise.
                .frame(width: 26)
                .foregroundStyle(isDestructive ? Color.red : (iconTint ?? Theme.secondaryText))
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.tertiaryText)
        case .value(let text):
            Text(text)
                .foregroundStyle(Theme.secondaryText)
        case .checkmark(let color):
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
        case .badge(let text):
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.tertiaryText)
        }
    }
}
