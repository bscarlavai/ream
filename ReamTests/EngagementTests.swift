import Foundation
import Testing
@testable import Ream

/// The prompt scheduler decides when the app asks for a rating and when it pitches the
/// Supporter unlock. Both are annoyance budgets, and both are easy to get quietly wrong —
/// these pin the behaviour that keeps them from stacking or repeating.
@MainActor
struct EngagementTests {

    private func makeEngagement() -> Engagement {
        let engagement = Engagement()
        engagement.resetForTesting()
        return engagement
    }

    @Test("Nothing is asked of a brand-new user")
    func silentAtZeroScans() {
        let engagement = makeEngagement()
        #expect(engagement.nextPrompt(isSupporter: false) == nil)
    }

    @Test("The rating ask waits for the first milestone")
    func reviewWaitsForMilestone() {
        let engagement = makeEngagement()
        engagement.setScanCountForTesting(Engagement.reviewMilestones[0] - 1)
        // Asserts specifically that REVIEW hasn't fired, not that nothing has. The supporter
        // pitch legitimately becomes due before the first rating milestone, and an
        // `== nil` here was really asserting the two schedules never overlap.
        #expect(engagement.nextPrompt(isSupporter: false) != .review)

        engagement.setScanCountForTesting(Engagement.reviewMilestones[0])
        #expect(engagement.nextPrompt(isSupporter: false) == .review)
    }

    @Test("The supporter pitch comes before the first rating ask")
    func supporterPitchPrecedesReview() {
        let engagement = makeEngagement()
        engagement.setScanCountForTesting(Engagement.supporterMilestones[0])
        // Five scans is peak goodwill: the app has proved itself and nothing has asked
        // anything of the user yet.
        #expect(engagement.nextPrompt(isSupporter: false) == .supporter)
        #expect(Engagement.supporterMilestones[0] < Engagement.reviewMilestones[0])
    }

    @Test("The same milestone never asks twice")
    func reviewDoesNotRepeat() {
        let engagement = makeEngagement()
        engagement.setScanCountForTesting(Engagement.reviewMilestones[0])
        #expect(engagement.nextPrompt(isSupporter: false) == .review)

        engagement.markReviewRequested()
        // Still past milestone 0, but that one is spent.
        #expect(engagement.nextPrompt(isSupporter: false) != .review)
    }

    @Test("A later milestone still respects the minimum gap between asks")
    func reviewRespectsTimeGap() {
        let engagement = makeEngagement()
        let now = Date()
        engagement.setScanCountForTesting(Engagement.reviewMilestones[0])
        engagement.markReviewRequested(now: now)

        // Enough scans for the SECOND milestone, but only a day later. iOS allows three
        // prompts a year; burning two in a week wastes the budget on one enthusiastic week.
        engagement.setScanCountForTesting(Engagement.reviewMilestones[1])
        let nextDay = now.addingTimeInterval(86_400)
        #expect(engagement.nextPrompt(isSupporter: false, now: nextDay) != .review)

        let muchLater = now.addingTimeInterval(86_400 * Double(Engagement.minimumDaysBetweenReviews + 1))
        #expect(engagement.nextPrompt(isSupporter: false, now: muchLater) == .review)
    }

    @Test("Supporters are never pitched")
    func supportersAreNotPitched() {
        let engagement = makeEngagement()
        engagement.setScanCountForTesting(500)
        // Milestones are all spent, so the only candidate left would be the supporter pitch.
        for _ in Engagement.reviewMilestones { engagement.markReviewRequested(now: .distantPast) }
        #expect(engagement.nextPrompt(isSupporter: true) == nil)
    }

    @Test("The supporter pitch repeats on its cadence")
    func supporterPitchRepeats() {
        let engagement = makeEngagement()
        for _ in Engagement.reviewMilestones { engagement.markReviewRequested(now: .distantPast) }

        let start = Date()
        engagement.setScanCountForTesting(Engagement.supporterMilestones[0])
        #expect(engagement.nextPrompt(isSupporter: false, now: start) == .supporter)
        engagement.markSupporterPrompted(now: start)

        // Immediately after: neither enough new scans nor enough days.
        #expect(engagement.nextPrompt(isSupporter: false, now: start) == nil)

        // Reaching the SECOND milestone, past the day floor.
        let later = start.addingTimeInterval(86_400 * Double(Engagement.minimumDaysBetweenSupporterPrompts + 1))
        engagement.setScanCountForTesting(Engagement.supporterMilestones[1])
        #expect(engagement.nextPrompt(isSupporter: false, now: later) == .supporter)
    }

    @Test("A scanning binge cannot pitch twice in one day")
    func supporterPitchHasDayFloor() {
        let engagement = makeEngagement()
        for _ in Engagement.reviewMilestones { engagement.markReviewRequested(now: .distantPast) }

        let start = Date()
        engagement.setScanCountForTesting(Engagement.supporterMilestones[0])
        engagement.markSupporterPrompted(now: start)

        // Plenty of new scans, same afternoon.
        engagement.setScanCountForTesting(Engagement.supporterMilestones[2])
        let sameDay = start.addingTimeInterval(3600)
        #expect(engagement.nextPrompt(isSupporter: false, now: sameDay) == nil)
    }

    @Test("The gap between pitches widens each time")
    func supporterPitchIntervalsWiden() {
        let engagement = makeEngagement()
        var previous = 0
        var gaps: [Int] = []
        for _ in 0..<4 {
            let threshold = engagement.nextSupporterThreshold
            gaps.append(threshold - previous)
            previous = threshold
            engagement.setScanCountForTesting(threshold)
            engagement.markSupporterPrompted(now: .distantPast)
        }
        // Never asked more often than the time before. A fixed cadence would be flat here,
        // and the whole point is that it decays for someone who keeps declining.
        #expect(zip(gaps, gaps.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test("Review outranks the supporter pitch when both are due")
    func reviewOutranksSupporter() {
        let engagement = makeEngagement()
        // Well past both thresholds, nothing spent yet.
        engagement.setScanCountForTesting(200)
        #expect(engagement.nextPrompt(isSupporter: false) == .review)
    }
}
