import Foundation
import CoreGraphics

/// Guesses where the blanks are on a scanned form.
///
/// **PARKED — not called by the app (decided 2026-08-08).** Kept, with its tests, because the
/// heuristics are sound and the next attempt shouldn't start from nothing.
///
/// Why it was pulled: on a real document it was wrong more often than right. A completed
/// receipt is full of labels — `Billing Address`, `Payment Term` — whose answers were printed
/// years ago, and every one drew a target. Clipping and an occupancy check fixed the worst of
/// it, but the underlying problem is unsolved: **telling a blank field from a filled one is
/// the hard part**, and text-presence only detects it when the answer happens to be text
/// Vision read on the same line. Ruled lines with handwriting in them, checkboxes, and
/// anything in a column defeat it.
///
/// A wrong suggestion is worse than none: the three manual tools are never wrong, and a bad
/// guess costs the user a deletion plus the doubt about whether the others are right too.
/// Reviving this needs actual blank-detection (ruled lines, boxes), not better text rules.
///
/// **No new computer vision.** This reads the line boxes Vision already produced when the
/// scan was OCR'd, and applies text heuristics to them. A line ending in `Name:` is a label
/// with a blank to its right; a run of underscores is a blank by itself. That is nearly all
/// of what a printed form looks like, and it costs nothing beyond an OCR pass we already run.
///
/// Everything here is a *suggestion*. Free placement stays available and unchanged — if the
/// heuristics find nothing, the editor behaves exactly as it did before. That's the whole
/// reason to do it this way rather than edge-detecting ruled lines: this degrades to the
/// existing behaviour instead of to a wrong answer.
enum FieldSuggester {

    struct Suggestion: Identifiable, Equatable {
        let id = UUID()
        /// The label that implied this field, for accessibility and debugging.
        let label: String
        /// Top-left, normalized to the page.
        let origin: CGPoint
        let widthFraction: CGFloat
        let fontFraction: CGFloat

        static func == (lhs: Suggestion, rhs: Suggestion) -> Bool { lhs.id == rhs.id }
    }

    /// Labels that imply a blank even without a trailing colon. Deliberately short: a longer
    /// list starts matching body text and scatters false targets over a letter.
    private static let labelWords: Set<String> = [
        "name", "date", "address", "signature", "signed", "phone", "email",
        "city", "state", "zip", "amount", "total", "account", "title", "company",
    ]

    /// Right-hand edge a suggested field may extend to. Stops short of the page edge because
    /// printed forms have margins and text written into one looks wrong flush to the trim.
    private static let rightMargin: CGFloat = 0.92

    static func suggestions(from page: PageOCR) -> [Suggestion] {
        var result: [Suggestion] = []

        // Every line's rect, so a candidate can be tested against what is ALREADY on the
        // page. Without this the heuristics fire on completed documents: a paid receipt is
        // full of "Billing Address" and "Payment Term" labels whose blanks were filled in
        // years ago, and every one of them looked like a field to offer.
        let occupied = page.lines.compactMap { line -> CGRect? in
            let rect = line.boundingBox.toImageCoordinates(CGSize(width: 1, height: 1),
                                                           origin: .upperLeft)
            return rect.width > 0 && rect.height > 0 ? rect : nil
        }

        for line in page.lines {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            // Vision reports bottom-left origin; ask for a top-left rect against a unit size
            // so the result is already normalized the way markups are stored.
            let rect = line.boundingBox.toImageCoordinates(CGSize(width: 1, height: 1),
                                                           origin: .upperLeft)
            guard rect.height > 0, rect.width > 0 else { continue }

            if isBlankRun(text) {
                // The blank IS the line: fill it in place.
                result.append(Suggestion(label: text,
                                         origin: CGPoint(x: rect.minX, y: rect.minY),
                                         widthFraction: rect.width,
                                         fontFraction: rect.height * 0.8))
                continue
            }

            guard endsWithLabel(text) else { continue }

            // The blank is to the RIGHT of the label, on the same line.
            let start = min(rect.maxX + 0.015, rightMargin - 0.05)

            // Stop at whatever comes next on this line rather than running to the margin.
            // Unclipped, a label at x=0.3 produced a box reaching 0.92 that swallowed every
            // other field beside it — which is why the targets overlapped into one another.
            let sameLine = occupied.filter { other in
                other.minX > rect.maxX && verticallyOverlaps(other, rect)
            }
            let limit = sameLine.map(\.minX).min() ?? rightMargin
            let end = min(limit - 0.01, rightMargin)
            let width = end - start

            // Too little room means the blank is already filled — there is text sitting where
            // the answer would go. Skipping is the whole point: a suggestion over existing
            // content is worse than no suggestion.
            guard width > 0.08 else { continue }

            result.append(Suggestion(label: text,
                                     origin: CGPoint(x: start, y: rect.minY),
                                     widthFraction: width,
                                     fontFraction: rect.height * 0.8))
        }

        return dedupe(result)
    }

    /// Two rects sit on the same visual line if their vertical spans mostly overlap.
    private static func verticallyOverlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap > min(a.height, b.height) * 0.5
    }

    // MARK: - Heuristics

    private static func endsWithLabel(_ text: String) -> Bool {
        if text.hasSuffix(":") { return true }

        // A trailing keyword with no colon, e.g. "Signature" over a printed rule. Only the
        // LAST word is considered — "name of the insured party" is prose, not a label.
        let words = text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        guard let last = words.last else { return false }
        // Long lines are prose that happens to end in a keyword, not form labels.
        guard words.count <= 4 else { return false }
        return labelWords.contains(last)
    }

    /// A run of underscores, dots or dashes: a printed blank with nothing written on it.
    private static func isBlankRun(_ text: String) -> Bool {
        let fillers = CharacterSet(charactersIn: "_-.·… ")
        guard text.count >= 4 else { return false }
        return text.unicodeScalars.allSatisfy { fillers.contains($0) }
    }

    /// Two labels on the same visual line (e.g. "Name:" and "Date:" side by side) produce
    /// overlapping targets; keep the leftmost and drop anything that starts inside it.
    private static func dedupe(_ suggestions: [Suggestion]) -> [Suggestion] {
        var kept: [Suggestion] = []
        for candidate in suggestions.sorted(by: { $0.origin.y < $1.origin.y }) {
            let overlaps = kept.contains { existing in
                abs(existing.origin.y - candidate.origin.y) < 0.01
                    && candidate.origin.x < existing.origin.x + existing.widthFraction
                    && existing.origin.x < candidate.origin.x + candidate.widthFraction
            }
            if !overlaps { kept.append(candidate) }
        }
        return kept
    }
}
