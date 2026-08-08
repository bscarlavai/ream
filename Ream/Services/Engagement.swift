import Foundation
import Observation

/// Decides what, if anything, to ask the user for after a scan completes.
///
/// One scheduler rather than three independent triggers, because the failure mode of
/// independent triggers is all of them firing on the same scan: a rating request, an app
/// recommendation and a supporter pitch stacked on the moment the user just wanted their PDF.
/// `nextPrompt(...)` returns **at most one**, and the priority order is explicit.
///
/// Everything is keyed on **completed scans**, never launches or elapsed time. A launch is
/// not evidence anyone got value; finishing a scan is a deliberate act that says the app did
/// its job.
@MainActor
@Observable
final class Engagement {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let scanCount = "engagement.completedScanCount"
        static let reviewRequestCount = "engagement.reviewRequestCount"
        static let lastReviewDate = "engagement.lastReviewDate"
        static let lastSupporterScanCount = "engagement.lastSupporterPromptScans"
        static let supporterPromptCount = "engagement.supporterPromptCount"
        static let lastSupporterDate = "engagement.lastSupporterPromptDate"
    }

    enum Prompt: Equatable {
        case review
        case supporter
    }

    // MARK: - Tuning

    /// Review milestones **escalate** rather than repeating every N.
    ///
    /// iOS caps `requestReview` at **3 prompts per 365 days** and silently ignores the rest,
    /// so a fixed "every 10 scans" cadence does not ask more often — it just spends the whole
    /// year's budget in the first month, on the user who has least experience of the app.
    /// Three well-spaced asks is exactly what the system will honour anyway.
    static let reviewMilestones = [10, 45, 130]
    /// Belt and braces on top of the system limit, so a heavy scanning week can't burn two.
    static let minimumDaysBetweenReviews = 45

    /// Scan counts at which the Supporter pitch appears, then every
    /// `supporterRepeatInterval` scans after the last one.
    ///
    /// **Escalating, not fixed.** A fixed cadence punishes exactly the wrong person: a heavy
    /// user crosses thresholds fastest, so "every 5 scans" is a modal every couple of days
    /// for the user who likes the app most. And the pitch has no leverage — everything is
    /// free — so its only currency is goodwill. People who tip do it in the first two or
    /// three asks; past that the asks convert almost nobody and buy "keeps asking me for
    /// money" in the reviews.
    ///
    /// Widening intervals mean heavy users are still asked more in absolute terms, while the
    /// asks thin out as evidence accumulates that this person isn't going to tip.
    ///
    /// The first ask is early **on purpose**: five scans is the point of peak goodwill, when
    /// the app has just proved itself and nothing has yet asked anything of the user. The
    /// long gap that follows is the trade — ask while they're delighted, then leave them
    /// alone rather than grinding away at someone who already said no.
    static let supporterMilestones = [5, 30, 60, 110]
    static let supporterRepeatInterval = 100
    /// A floor in days as well as scans, so a big filing session can't pitch twice.
    static let minimumDaysBetweenSupporterPrompts = 7

    // MARK: - State

    var completedScans: Int { defaults.integer(forKey: Key.scanCount) }

    private var reviewRequestCount: Int { defaults.integer(forKey: Key.reviewRequestCount) }

    private var lastReviewDate: Date? {
        defaults.object(forKey: Key.lastReviewDate) as? Date
    }

    private var lastSupporterDate: Date? {
        defaults.object(forKey: Key.lastSupporterDate) as? Date
    }

    private var lastSupporterScanCount: Int {
        defaults.integer(forKey: Key.lastSupporterScanCount)
    }

    private var supporterPromptCount: Int {
        defaults.integer(forKey: Key.supporterPromptCount)
    }

    /// Scan count at which the next pitch becomes due.
    var nextSupporterThreshold: Int {
        let shown = supporterPromptCount
        let milestones = Self.supporterMilestones
        guard shown >= milestones.count else { return milestones[shown] }
        let beyond = shown - milestones.count + 1
        return (milestones.last ?? 0) + Self.supporterRepeatInterval * beyond
    }

    func recordCompletedScan() {
        defaults.set(completedScans + 1, forKey: Key.scanCount)
    }

    // MARK: - The decision

    /// What to show now, or nil. Called once, when a scan finishes.
    ///
    /// Priority: **review before supporter**. The rating ask is rarer, strictly capped, and
    /// worth more to a free app with no marketing budget than one more chance at a $2.99 tip.
    /// The cross-promo sits below both and is checked by the caller only when this returns nil.
    func nextPrompt(isSupporter: Bool, now: Date = .now) -> Prompt? {
        if shouldRequestReview(now: now) { return .review }
        if shouldPitchSupporter(isSupporter: isSupporter, now: now) { return .supporter }
        return nil
    }

    private func shouldRequestReview(now: Date) -> Bool {
        let milestones = Self.reviewMilestones
        guard reviewRequestCount < milestones.count else { return false }
        guard completedScans >= milestones[reviewRequestCount] else { return false }

        if let last = lastReviewDate {
            let days = now.timeIntervalSince(last) / 86_400
            guard days >= Double(Self.minimumDaysBetweenReviews) else { return false }
        }
        return true
    }

    private func shouldPitchSupporter(isSupporter: Bool, now: Date) -> Bool {
        // The single most important line here. Once someone has paid, this never fires again.
        guard !isSupporter else { return false }
        guard completedScans >= nextSupporterThreshold else { return false }

        if let last = lastSupporterDate {
            let days = now.timeIntervalSince(last) / 86_400
            guard days >= Double(Self.minimumDaysBetweenSupporterPrompts) else { return false }
        }
        return true
    }

    // MARK: - Recording

    /// Called after the rating prompt is asked for, so it is never asked for twice at one
    /// milestone. Apple may decline to show it, which is indistinguishable from here — which
    /// is exactly why this must not retry. A retry loop against a silent rate limit is how an
    /// app ends up asking on every launch.
    func markReviewRequested(now: Date = .now) {
        defaults.set(reviewRequestCount + 1, forKey: Key.reviewRequestCount)
        defaults.set(now, forKey: Key.lastReviewDate)
    }

    func markSupporterPrompted(now: Date = .now) {
        defaults.set(supporterPromptCount + 1, forKey: Key.supporterPromptCount)
        defaults.set(completedScans, forKey: Key.lastSupporterScanCount)
        defaults.set(now, forKey: Key.lastSupporterDate)
    }

    #if DEBUG
    func resetForTesting() {
        for key in [Key.scanCount, Key.reviewRequestCount, Key.lastReviewDate,
                    Key.lastSupporterScanCount, Key.lastSupporterDate,
                    Key.supporterPromptCount] {
            defaults.removeObject(forKey: key)
        }
    }

    func setScanCountForTesting(_ count: Int) {
        defaults.set(count, forKey: Key.scanCount)
    }
    #endif
}
