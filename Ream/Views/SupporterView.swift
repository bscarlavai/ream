import SwiftUI
import StoreKit

/// The finish picker and the Supporter unlock.
///
/// Locked finishes render at **full color** — never greyed out, never behind a padlock,
/// never wearing a "PRO" badge. You can see exactly what you'd get, and the app doesn't
/// nag. Same rule as PokeArtist.
struct SupporterView: View {
    @Environment(SupporterService.self) private var supporter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @AppStorage("accentFinish") private var finishRaw = AccentFinish.blueprint.rawValue

    private var selected: AccentFinish {
        AccentFinish.resolved(rawValue: finishRaw, isSupporter: supporter.isSupporter)
    }

    var body: some View {
        NavigationStack {
            List {
                finishes
                if !supporter.isSupporter { tiers }
            }
            .navigationTitle("Finishes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await supporter.load() }
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sections

    private var finishes: some View {
        Section {
            ForEach(AccentFinish.allCases, id: \.self) { finish in
                finishRow(finish)
            }
        } header: {
            Text("Finish")
        } footer: {
            Text(supporter.isSupporter
                 ? "All finishes are yours. Pick whichever suits the day."
                 : "Ream is free forever, and every scanning feature stays free. Supporting unlocks the other four finishes.")
        }
    }

    private func finishRow(_ finish: AccentFinish) -> some View {
        let locked = finish.requiresSupporter && !supporter.isSupporter
        let color = finish.color(for: scheme)

        return Button {
            guard !locked else { return }
            withAnimation { finishRaw = finish.rawValue }
        } label: {
            ReamRow(title: finish.displayName,
                    subtitle: finish.materialNote,
                    swatch: color,
                    accessory: finish == selected ? .checkmark(color)
                             : locked ? .badge("Supporter") : .none)
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    private var tiers: some View {
        Section {
            if supporter.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if supporter.products.isEmpty {
                Text("The App Store isn't reachable right now.")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(supporter.products, id: \.id) { product in
                    Button {
                        Task { await supporter.purchase(product) }
                    } label: {
                        // A tinted title is how a native list says "this row does something"
                        // — the same shape Settings uses for its own actions. The price sits
                        // trailing as a plain value rather than inside a button, so the whole
                        // row is the tap target.
                        ReamRow(title: product.displayName,
                                subtitle: product.description.isEmpty ? nil : product.description,
                                systemImage: "heart.fill",
                                iconTint: selected.fillColor(for: scheme),
                                accessory: .value(product.displayPrice))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task { await supporter.restore() }
                } label: {
                    ReamRow(title: supporter.isRestoring ? "Restoring…" : "Restore Purchase",
                            systemImage: "arrow.clockwise",
                            iconTint: selected.color(for: scheme))
                }
                .buttonStyle(.plain)
                .disabled(supporter.isRestoring)
            }
        } header: {
            Text("Support Ream")
        } footer: {
            Text("A one-time purchase, not a subscription. Every tier unlocks the same finishes and nothing else, so pick whatever feels right. No feature is ever gated behind this.")
        }
    }
}
