import Foundation
import CoreGraphics
import Vision

/// One recognized line of text plus where it sits on the page.
///
/// `boundingBox` is kept in Vision's normalized space (0...1, origin lower-left)
/// so `PDFBuilder` can map it into whatever page size it ends up using.
struct RecognizedLine: Sendable {
    let text: String
    let boundingBox: NormalizedRect
    /// Vision's own guess that this line is a heading. Used to auto-name documents.
    let isTitle: Bool
}

struct PageOCR: Sendable {
    let lines: [RecognizedLine]
    /// Reading-order text for this page, as Vision reconstructed it.
    let transcript: String
    /// First line Vision flagged as a title, if any.
    let detectedTitle: String?
}

/// Wraps Vision's document recognizer.
///
/// Uses `RecognizeDocumentsRequest` (iOS 26+) rather than the older
/// `VNRecognizeTextRequest`. The older API returns unordered line fragments — a
/// two-column invoice comes back interleaved, and tables lose their structure.
/// `RecognizeDocumentsRequest` resolves reading order and keeps tables as tables,
/// which is what makes the transcript usable for search and future export.
enum OCRService {

    static func recognize(image: CGImage) async throws -> PageOCR {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = true

        let observations = try await request.perform(on: image)

        guard let container = observations.first?.document else {
            return PageOCR(lines: [], transcript: "", detectedTitle: nil)
        }

        let lines = container.text.lines.map { line in
            RecognizedLine(
                text: line.transcript,
                boundingBox: line.boundingBox,
                isTitle: line.isTitle
            )
        }

        return PageOCR(
            lines: lines,
            transcript: container.text.transcript,
            detectedTitle: container.title?.transcript ?? lines.first(where: \.isTitle)?.text
        )
    }

    /// Recognizes every page. Pages are processed sequentially rather than
    /// concurrently: Vision already saturates the Neural Engine on a single
    /// request, so fanning out mostly adds memory pressure on a 20-page scan.
    static func recognize(pages: [CGImage]) async throws -> [PageOCR] {
        var results: [PageOCR] = []
        results.reserveCapacity(pages.count)
        for page in pages {
            results.append(try await recognize(image: page))
        }
        return results
    }
}
