import Foundation
import CoreGraphics
import Vision
import Testing
@testable import Ream

/// Heuristics for guessing where a form's blanks are.
///
/// These are guesses by design, so the tests pin the two things that matter: that obvious
/// labels ARE found, and that ordinary prose is NOT — a false target scattered across a
/// letter is worse than no suggestions at all.
struct FieldSuggesterTests {

    /// Builds a page of OCR lines. `y` is the TOP of the line in normalized page space;
    /// Vision reports bottom-left, so it's flipped on the way in.
    private func page(_ lines: [(text: String, x: CGFloat, y: CGFloat, width: CGFloat)]) -> PageOCR {
        let height: CGFloat = 0.03
        let recognized = lines.map { line in
            RecognizedLine(
                text: line.text,
                boundingBox: NormalizedRect(x: line.x,
                                            y: 1 - line.y - height,
                                            width: line.width,
                                            height: height),
                isTitle: false
            )
        }
        return PageOCR(lines: recognized, transcript: "", detectedTitle: nil)
    }

    @Test("A label ending in a colon suggests a field to its right")
    func colonLabelSuggestsField() {
        let result = FieldSuggester.suggestions(
            from: page([("Name:", 0.1, 0.2, 0.12)])
        )
        let suggestion = try? #require(result.first)
        #expect(result.count == 1)
        // Starts after the label, not on top of it.
        #expect((suggestion?.origin.x ?? 0) > 0.22)
        // Approximate: the rect is flipped bottom-left -> top-left on the way through, so an
        // exact match would be asserting that floating point is lossless.
        #expect(abs((suggestion?.origin.y ?? 0) - 0.2) < 0.0001)
    }

    @Test("A bare keyword label is recognized without a colon")
    func keywordLabelSuggestsField() {
        let result = FieldSuggester.suggestions(from: page([("Signature", 0.1, 0.5, 0.18)]))
        #expect(result.count == 1)
    }

    @Test("A run of underscores is itself the blank")
    func underscoreRunIsTheField() {
        let result = FieldSuggester.suggestions(from: page([("__________", 0.2, 0.4, 0.4)]))
        let suggestion = try? #require(result.first)
        // Fills in place rather than to the right — there is no label to sit after.
        #expect(abs((suggestion?.origin.x ?? 0) - 0.2) < 0.0001)
        #expect(abs((suggestion?.widthFraction ?? 0) - 0.4) < 0.0001)
    }

    @Test("Prose is not mistaken for a form label")
    func proseIsIgnored() {
        let result = FieldSuggester.suggestions(from: page([
            ("Please return this form to the address shown above", 0.1, 0.3, 0.7),
            ("we will confirm receipt by email", 0.1, 0.35, 0.6),
        ]))
        // The second line ends in "email", a keyword — but it's a sentence, not a label.
        #expect(result.isEmpty)
    }

    @Test("A label with no room to its right is skipped rather than cramped")
    func noRoomMeansNoSuggestion() {
        let result = FieldSuggester.suggestions(from: page([("Date:", 0.75, 0.2, 0.2)]))
        #expect(result.isEmpty)
    }

    @Test("Overlapping suggestions on one line collapse to the leftmost")
    func overlappingSuggestionsDedupe() {
        let result = FieldSuggester.suggestions(from: page([
            ("Name:", 0.05, 0.2, 0.10),
            ("Date:", 0.30, 0.2, 0.10),
        ]))
        // Both extend to the right margin, so they'd otherwise stack two targets on one line.
        #expect(result.count == 1)
    }

    @Test("An empty page yields nothing rather than failing")
    func emptyPageIsFine() {
        #expect(FieldSuggester.suggestions(from: page([])).isEmpty)
    }
}
