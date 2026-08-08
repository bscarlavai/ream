import Foundation
import SwiftData
import UIKit

/// Turns raw camera pages into a saved, searchable document.
///
/// Ordering matters here: the PDF is written to disk *before* the SwiftData row is
/// inserted. If we did it the other way and the write failed, the library would show
/// a document whose file doesn't exist.
@MainActor
@Observable
final class ScanPipeline {
    enum Phase: Equatable {
        case idle
        case recognizing(page: Int, of: Int)
        case buildingPDF
        case failed(String)

        var isWorking: Bool {
            switch self {
            case .recognizing, .buildingPDF: true
            case .idle, .failed: false
            }
        }
    }

    private(set) var phase: Phase = .idle

    /// Set by the shell so a finished scan can advance the review / cross-promo milestones.
    /// Optional so `ScanPipeline` stays usable without it (previews, tests).
    var engagement: Engagement?

    func process(pages: [UIImage], into context: ModelContext) async {
        guard !pages.isEmpty else { return }

        let cgPages = pages.compactMap(\.cgImage)
        guard cgPages.count == pages.count else {
            phase = .failed("Some pages couldn't be read from the camera.")
            return
        }

        // OCR, page by page, so the UI can show real progress on a long scan.
        var pageResults: [PageOCR] = []
        do {
            for (index, image) in cgPages.enumerated() {
                phase = .recognizing(page: index + 1, of: cgPages.count)
                pageResults.append(try await OCRService.recognize(image: image))
            }
        } catch {
            // A failed OCR pass shouldn't cost the user their scan — fall through with
            // empty text and still produce a (non-searchable) PDF.
            pageResults = cgPages.map { _ in
                PageOCR(lines: [], transcript: "", detectedTitle: nil)
            }
        }

        phase = .buildingPDF

        let builderPages = zip(cgPages, pageResults).map {
            PDFBuilder.Page(image: $0, lines: $1.lines)
        }
        let data = PDFBuilder.makeSearchablePDF(pages: builderPages)
        guard !data.isEmpty else {
            phase = .failed("Couldn't build the PDF.")
            return
        }

        let transcript = pageResults.map(\.transcript)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let document = ScannedDocument(
            title: Self.makeTitle(from: pageResults),
            pageCount: cgPages.count,
            transcript: transcript
        )

        do {
            _ = try await DocumentStore.shared.write(data, to: document.fileName)
        } catch {
            phase = .failed("Couldn't save the PDF: \(error.localizedDescription)")
            return
        }

        context.insert(document)
        // Explicit save — autosave has a delay, and a scan is user-created content
        // we can't regenerate if the app is killed before it flushes.
        try? context.save()

        // Recorded only on the success path: a scan that failed is not evidence the app
        // did its job, and must not count toward asking for a rating.
        // The manifest travels with the PDFs, so it has to be current the moment a new
        // one lands — an export taken before the next rebuild would omit this scan.
        LibraryManifest.rebuild(from: context)

        engagement?.recordCompletedScan()

        phase = .idle
    }

    /// Names the document from whatever Vision flagged as a heading, falling back to
    /// the date. Truncated because some scans "title" an entire paragraph.
    private static func makeTitle(from pages: [PageOCR]) -> String {
        let detected = pages.compactMap(\.detectedTitle)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard let detected else {
            return "Scan \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        }

        let cleaned = detected
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return cleaned.count > 60 ? String(cleaned.prefix(60)) + "…" : cleaned
    }
}
