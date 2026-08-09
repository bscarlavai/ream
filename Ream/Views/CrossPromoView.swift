import SwiftUI

/// A sister app we'd like to promote.
///
/// Mirrors the `SiblingApp` shape used across the -rip family so the two families
/// stay recognizably the same pattern. `key` is the identity used in the seen-set —
/// **renaming it re-shows the app to everyone who already dismissed it.**
struct SiblingApp: Identifiable {
    let key: String
    let name: String
    let tagline: String
    /// Asset in Assets.xcassets; falls back to `fallbackSymbol` if missing.
    let iconAsset: String?
    let fallbackSymbol: String
    let appStoreID: String

    var id: String { key }
    var appStoreURL: URL? { ExternalLink.appStore(id: appStoreID) }
}

extension SiblingApp {
    static let perennial = SiblingApp(
        key: "perennial",
        name: "Perennial",
        tagline: "Birthday, anniversary and memorial reminders.",
        iconAsset: "PerennialIcon",
        fallbackSymbol: "calendar.badge.clock",
        appStoreID: "6760379132"
    )

    static let unfrozen = SiblingApp(
        key: "unfrozen",
        name: "Unfrozen",
        tagline: "A cleaning coach for hard days.",
        iconAsset: "UnfrozenIcon",
        fallbackSymbol: "sparkles",
        appStoreID: "6759630431"
    )

    static let deckOfPain = SiblingApp(
        key: "deckofpain",
        name: "Deck of Pain",
        tagline: "Every card is an exercise.",
        iconAsset: "DeckOfPainIcon",
        fallbackSymbol: "figure.strengthtraining.functional",
        appStoreID: "6760635489"
    )

    /// Who Ream promotes, in priority order.
    ///
    /// **Deliberately not everything Lavai Labs makes.** The -rip family cross-promotes
    /// well because it's the same activity in a different game — a PokeRip user has
    /// demonstrably revealed they enjoy ripping packs. These apps share no such affinity,
    /// so the list is curated by *adjacency of problem*: Ream, Perennial and Unfrozen are
    /// all "don't drop the ball on life admin" tools, and someone scanning their documents
    /// plausibly has that shelf. Deck of Pain is a fitness app on a different axis — it's
    /// available above if that call ever changes, but shipping it here would be house
    /// advertising rather than a recommendation.
    static let crossPromoTargets: [SiblingApp] = [.perennial, .unfrozen]
}

/// Wrapper so the promo can be presented with `.sheet(item:)`.
///
/// **Not cosmetic.** With `.sheet(isPresented:)` the content closure captured the sibling
/// array before the same-update assignment landed, and the sheet rendered its header over
/// an empty list. Binding the data to the presentation makes that unrepresentable.
struct CrossPromoPayload: Identifiable {
    let id = UUID()
    let siblings: [SiblingApp]
}

/// "More from Lavai Labs" — shown once per batch of unseen siblings.
///
/// Adding a new sibling to `crossPromoTargets` in a later release surfaces just that one
/// on the next trigger, because its key isn't in the seen-set yet. Existing dismissals
/// are preserved.
struct CrossPromoView: View {
    let siblings: [SiblingApp]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(siblings) { sibling in
                        SiblingRow(sibling: sibling)
                    }
                } header: {
                    Text("More from Lavai Labs")
                } footer: {
                    // Says nothing about how the other apps are priced.
                    //
                    // This read "same deal: no subscriptions, no ads", which is a claim about
                    // apps this one doesn't control — and a false one: Unfrozen runs AI and
                    // charges a subscription for it. Ream's own terms are stated in Ream,
                    // where they're true.
                    Text("Small, focused apps. Tap one to open it on the App Store.")
                }
            }
            .navigationTitle("More Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .presentationDragIndicator(.visible)
        }
    }
}

private struct SiblingRow: View {
    let sibling: SiblingApp

    var body: some View {
        Group {
            if let url = sibling.appStoreURL {
                // Tapping opens the App Store but does NOT dismiss — coming back should
                // leave the list up so the other apps are still reachable.
                Link(destination: url) { content }
            } else {
                content
            }
        }
    }

    /// Custom content, native container. The App Store's own "you might also like" row is
    /// icon + name + tagline + Get, and copying that shape is why this one reads as an app
    /// recommendation rather than an ad. `List` still owns the height, insets and dividers.
    private var content: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Group {
                if let asset = sibling.iconAsset, UIImage(named: asset) != nil {
                    Image(asset).resizable().interpolation(.high)
                } else {
                    Image(systemName: sibling.fallbackSymbol)
                        .resizable()
                        .scaledToFit()
                        .symbolRenderingMode(.hierarchical)
                        .padding(12)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(sibling.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(sibling.tagline)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    // Balanced wrapping splits a two-line tagline evenly instead of
                    // leaving one orphaned word on the second line.
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: Theme.Spacing.tight)

            Text("GET")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.tint, in: Capsule())
                .foregroundStyle(Theme.cardBackground)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
