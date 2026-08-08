import Foundation
import StoreKit

/// Ream is free. Every scanning, OCR, PDF and export feature is free permanently and
/// always will be. The Supporter unlock buys the accent finishes and nothing else.
///
/// **These are NON-CONSUMABLE on purpose, and must stay that way.** A consumable that
/// grants permanent functionality is a guideline 3.1.1 rejection, and with no accounts
/// and no cloud, an Apple ID restore is the only way someone who reinstalls gets their
/// finishes back. This is the same call already settled in PokeArtist.
///
/// The two tiers carry an **identical** entitlement — the second exists only so someone
/// who wants to give more can, and because non-consumables stack, they can buy the
/// second later without losing the first.
@MainActor
@Observable
final class SupporterService {
    /// Three tiers, **identical entitlement**. The top one's job is not to be bought — it
    /// anchors, so the middle reads as modest. With only two options most people take the
    /// lower; with three, more take the middle.
    ///
    /// They are separate non-consumables, so they **stack**: someone can tip $2.99 now and
    /// $9.99 later and keep both. That's also why entitlement is a plain `Bool` rather than a
    /// level — nothing here grants more than anything else, so there is no tier to demote
    /// anyone to when a second purchase lands.
    static let productIDs = [
        "com.lavailabs.ream.supporter",
        "com.lavailabs.ream.supporter.plus",
        "com.lavailabs.ream.supporter.max",
    ]

    private(set) var products: [Product] = []
    private(set) var isSupporter = false

    #if DEBUG
    /// Forces the entitlement on for development.
    ///
    /// `simctl launch` does not apply the scheme's StoreKit configuration, so in the
    /// Simulator there are no products to buy and the locked finishes are unreachable —
    /// this is the only way to see them without a device and a sandbox account.
    ///
    /// Gated by `#if DEBUG` rather than a hidden gesture or a runtime flag, so it cannot
    /// reach the App Store by accident. Same rule PokeArtist uses for its debug section.
    static let debugOverrideKey = "debugForceSupporter"

    var debugForceSupporter: Bool {
        get { UserDefaults.standard.bool(forKey: Self.debugOverrideKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.debugOverrideKey)
            Task { await refreshEntitlement() }
        }
    }
    #endif
    private(set) var isLoading = false
    private(set) var isRestoring = false
    /// Set after a successful purchase so the UI can say thank you once.
    var didJustSupport = false

    /// Kept only so the listener isn't discarded; nothing cancels it.
    ///
    /// There is no `deinit`. This service is held in `@State` by the app and lives for the
    /// whole process, so a cancel-on-deinit that can never run is ceremony — and reaching a
    /// main-actor property from a nonisolated `deinit` is exactly the thing Swift 6 objects
    /// to. (`nonisolated` cannot be applied to a mutable stored property at all;
    /// `nonisolated(unsafe)` compiles but warns that it has no effect, because `Task` is
    /// already Sendable.)
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        // StoreKit can deliver transactions that happen outside a purchase call —
        // Ask to Buy approvals, a purchase made on another device, an App Store refund.
        // Without this listener the entitlement would be stale until next launch.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self?.refreshEntitlement()
            }
        }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        await refreshEntitlement()

        guard products.isEmpty else { return }
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            // A failed load is not worth an alert — the sheet simply shows no tiers.
            // Nothing the user needs is behind this.
            products = []
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result,
               case .verified(let transaction) = verification {
                await transaction.finish()
                await refreshEntitlement()
                didJustSupport = true
            }
        } catch {
            // Cancelled or failed. Non-event: nothing is broken and nothing is owed.
        }
    }

    /// Required for non-consumables. Apple rejects apps that sell a permanent unlock
    /// with no way to restore it.
    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        #if DEBUG
        // Checked before StoreKit, so the override works with no products loaded at all.
        if UserDefaults.standard.bool(forKey: Self.debugOverrideKey) {
            isSupporter = true
            return
        }
        #endif

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if Self.productIDs.contains(transaction.productID) {
                isSupporter = true
                return
            }
        }
        isSupporter = false
    }
}
