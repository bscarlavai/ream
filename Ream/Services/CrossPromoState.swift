import Foundation
import Observation

/// Tracks which sibling apps this user has already been shown.
///
/// A **set of keys**, not a single "seen" bool, so that adding a sibling in a later
/// release surfaces only the new one — everyone's existing dismissals survive.
@MainActor
@Observable
final class CrossPromoState {
    private static let seenKey = "crossPromoSeenApps"

    private(set) var seen: Set<String>

    init() {
        seen = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
    }

    /// Siblings to show right now, or empty.
    ///
    /// The scan count is passed in rather than tracked here — `Engagement` already owns
    /// that number for the review prompt, and two counters over the same event drift the
    /// moment one of them is incremented from a path the other doesn't see.
    ///
    /// Gated on completed scans, deliberately. Promoting another app to someone who has
    /// not yet gotten anything out of this one is how a utility app earns a one-star
    /// review — they came to scan a document, not to be sold to. Two scans in means the
    /// app worked and the moment is a good one.
    ///
    /// Sits below `Engagement.reviewAfterScans` (5) on purpose: the promo and the rating
    /// prompt must not land on the same scan.
    func pending(completedScans: Int) -> [SiblingApp] {
        guard completedScans >= 2 else { return [] }
        return SiblingApp.crossPromoTargets.filter { !seen.contains($0.key) }
    }

    /// Marked up front by the caller so a swipe-to-dismiss counts the same as tapping Done.
    func markSeen(_ siblings: [SiblingApp]) {
        for sibling in siblings { seen.insert(sibling.key) }
        UserDefaults.standard.set(Array(seen), forKey: Self.seenKey)
    }

    #if DEBUG
    func resetForTesting() {
        seen = []
        UserDefaults.standard.removeObject(forKey: Self.seenKey)
    }
    #endif
}
