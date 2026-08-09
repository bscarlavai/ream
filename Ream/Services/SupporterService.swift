import Foundation
import RevenueCat

/// Ream is free. Every scanning, OCR, PDF and export feature is free permanently and always
/// will be. The Supporter unlock buys the accent finishes and nothing else.
///
/// **The products are NON-CONSUMABLE and must stay that way.** A consumable that grants
/// permanent functionality is a guideline 3.1.1 rejection, and with no accounts and no cloud
/// an Apple ID restore is the only way someone who reinstalls gets their finishes back. Same
/// call already settled in PokeArtist.
///
/// Three tiers, **identical entitlement**. The top one's job is not to be bought — it anchors,
/// so the middle reads as modest. Because they are separate non-consumables they **stack**:
/// someone can tip once now and again later and keep both. That is also why entitlement here
/// is a plain `Bool` and not a level — nothing grants more than anything else, so there is no
/// tier to demote anyone to when a second purchase lands.
///
/// The source of truth is RevenueCat's `CustomerInfo`, never local storage. A `UserDefaults`
/// flag is a plain value anyone can set with a backup edit.
@MainActor
@Observable
final class SupporterService {

    /// RevenueCat's **public** SDK key. Designed to ship in the binary — it is not a secret
    /// and grants no write access.
    ///
    /// Ream's own iOS key (RevenueCat → Project settings → API keys). If this is ever swapped
    /// for another project's key, offerings resolve empty and the tiers simply do not appear.
    private static let apiKey = "appl_rcLdfntrdWbCQycNUmbqIRjUmVx"

    /// The entitlement identifier configured in the RevenueCat dashboard. **Case-sensitive**,
    /// and compared as a plain string — if these two ever disagree, every supporter silently
    /// becomes a non-supporter.
    private static let entitlementID = "Supporter"

    /// Product identifiers, which must match App Store Connect and RevenueCat exactly. A
    /// mismatch yields an empty offering and no error anywhere.
    enum Tier: String, CaseIterable {
        case supporter = "com.lavailabs.ream.supporter"
        case generous = "com.lavailabs.ream.supporter.plus"
        case veryGenerous = "com.lavailabs.ream.supporter.max"
    }

    private(set) var packages: [Package] = []
    private(set) var isSupporter = false
    private(set) var isLoading = false
    private(set) var isRestoring = false
    /// Set after a successful purchase so the UI can say thank you once.
    var didJustSupport = false

    #if DEBUG
    /// Forces the entitlement on for development.
    ///
    /// The Simulator has no App Store session, so the tiers are unreachable and the locked
    /// finishes can't be seen without a device and a sandbox account. Gated by `#if DEBUG`
    /// rather than a hidden gesture, so it cannot reach the App Store by accident.
    static let debugOverrideKey = "debugForceSupporter"

    var debugForceSupporter: Bool {
        get { UserDefaults.standard.bool(forKey: Self.debugOverrideKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.debugOverrideKey)
            Task { await refreshEntitlement() }
        }
    }
    #endif

    init() {
        // Guarded because SwiftUI may construct this more than once (previews, scene
        // rebuilds) and configuring twice is a warning nobody would ever notice.
        if !Purchases.isConfigured {
            #if DEBUG
            Purchases.logLevel = .info
            #else
            Purchases.logLevel = .warn
            #endif
            Purchases.configure(withAPIKey: Self.apiKey)
        }
    }

    // MARK: - Loading

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        await refreshEntitlement()

        guard packages.isEmpty else { return }
        do {
            let offerings = try await Purchases.shared.offerings()
            // Sorted by price so the tiers always render smallest-first, whatever order the
            // dashboard returns them in.
            packages = (offerings.current?.availablePackages ?? [])
                .sorted { $0.storeProduct.price < $1.storeProduct.price }
        } catch {
            // A failed load is not worth an alert — the sheet simply shows no tiers. Nothing
            // the user needs is behind this.
            packages = []
        }
    }

    // MARK: - Buying

    func purchase(_ package: Package) async {
        do {
            let result = try await Purchases.shared.purchase(package: package)
            // Backing out is not an error and must not be reported as one.
            guard !result.userCancelled else { return }
            applyEntitlement(from: result.customerInfo)
            didJustSupport = isSupporter
        } catch {
            // Same reasoning as `load`: a failed tip is a non-event. Nothing is broken and
            // nothing is owed.
        }
    }

    /// Required for non-consumables. Apple rejects apps that sell a permanent unlock with no
    /// way to restore it.
    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        if let info = try? await Purchases.shared.restorePurchases() {
            applyEntitlement(from: info)
        }
    }

    // MARK: - Entitlement

    private func refreshEntitlement() async {
        #if DEBUG
        if LaunchArgument.isPresent(LaunchArgument.forceLocked) {
            isSupporter = false
            return
        }
        // Checked before RevenueCat, so the override works with no network and no offering.
        if UserDefaults.standard.bool(forKey: Self.debugOverrideKey) {
            isSupporter = true
            return
        }
        #endif

        guard let info = try? await Purchases.shared.customerInfo() else { return }
        applyEntitlement(from: info)
    }

    private func applyEntitlement(from info: CustomerInfo) {
        #if DEBUG
        if LaunchArgument.isPresent(LaunchArgument.forceLocked) {
            isSupporter = false
            return
        }
        if UserDefaults.standard.bool(forKey: Self.debugOverrideKey) {
            isSupporter = true
            return
        }
        #endif

        // The entitlement is checked first, then owned products as a fallback. That fallback
        // is not redundant: an entitlement that hasn't propagated yet would otherwise lock
        // out someone who has already paid.
        if info.entitlements[Self.entitlementID]?.isActive == true {
            isSupporter = true
            return
        }
        let owned = Set(info.nonSubscriptions.map(\.productIdentifier))
        isSupporter = Tier.allCases.contains { owned.contains($0.rawValue) }
    }
}
