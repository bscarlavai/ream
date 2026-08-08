#if DEBUG
import SwiftUI
import SwiftData
import UIKit

/// Debug-only scan generator.
///
/// `VNDocumentCameraViewController` cannot run in the Simulator, so without this there
/// is no way to exercise the list, detail, or search UI outside a physical device.
/// It renders a synthetic page and feeds it through the *real* `ScanPipeline`, so it
/// also serves as an end-to-end check of OCR → searchable PDF.
enum SampleScans {

    private static let documents: [[String]] = [
        [
            "NORTHGATE PROPERTY",
            "Monthly Statement",
            "Account 4471-9038",
            "Period: July 2026",
            "Rent                 1,850.00",
            "Utilities              124.50",
            "Parking                 75.00",
            "TOTAL DUE            2,049.50",
            "Due by August 1, 2026",
        ],
        [
            "CENTRAL VETERINARY",
            "Visit Summary",
            "Patient: Biscuit",
            "Date: June 14, 2026",
            "Vaccinations current",
            "Weight 62 lbs, stable",
            "Recheck in six months",
            "Dr. Alvarez, DVM",
        ],
        [
            "APPLIANCE WARRANTY",
            "Model DW-4400",
            "Serial 88213947",
            "Purchased March 2, 2026",
            "Coverage: 3 years parts",
            "Coverage: 1 year labor",
            "Keep this document",
        ],
    ]

    /// `@MainActor` because `ModelContext` is not Sendable and `ScanPipeline` is
    /// main-actor bound. The expensive work (OCR) still hops off the main thread
    /// inside Vision.
    @MainActor
    static func generate(into context: ModelContext, pipeline: ScanPipeline) async {
        // Declared locally rather than as a static: an array of tuples isn't inferred
        // Sendable, so as global state Swift 6 isolates it and the access fails to compile.
        // Prefixed so a Debug build run on a real device can never be mistaken for, or
        // tangled up with, labels the user actually created.
        let sampleLabels: [(String, Int)] = [
            ("Sample · Household", 1), ("Sample · Medical", 3), ("Sample · Warranty", 4),
        ]

        let labels = sampleLabels.map { name, colorIndex in
            let label = ScanLabel(name: name, colorIndex: colorIndex)
            context.insert(label)
            return label
        }

        for (index, lines) in documents.enumerated() {
            let page = renderPage(lines: lines)
            await pipeline.process(pages: [page], into: context)

            // Attach to whatever the pipeline just inserted — it's the newest document.
            let descriptor = FetchDescriptor<ScannedDocument>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            guard let newest = try? context.fetch(descriptor).first else { continue }
            newest.labels = index == 0
                ? [labels[0], labels[2]]        // one document with two labels
                : [labels[index % labels.count]]
        }
        try? context.save()
        // The pipeline rebuilt the manifest as each document landed — before these labels
        // were attached. Without this the sample library exports without its labels.
        LibraryManifest.rebuild(from: context)
    }

    /// Draws a plausible scanned page: warm off-white stock, dark ink, ragged left margin.
    private static func renderPage(lines: [String]) -> UIImage {
        let size = CGSize(width: 1275, height: 1650)  // 8.5x11 at 150dpi
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            UIColor(red: 0.98, green: 0.975, blue: 0.965, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            var y: CGFloat = 160
            for (index, line) in lines.enumerated() {
                let isHeading = index == 0
                let font = UIFont.systemFont(ofSize: isHeading ? 46 : 30,
                                             weight: isHeading ? .bold : .regular)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor(white: 0.09, alpha: 1),
                ]
                (line as NSString).draw(at: CGPoint(x: 120, y: y), withAttributes: attributes)
                y += font.lineHeight * 1.6
            }
        }
    }
}
#endif
