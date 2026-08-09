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
        // Unprefixed. A "Sample ·" prefix protected a real device from confusing seeded
        // labels with real ones, but seeding is DEBUG-only and deliberate, and the prefix
        // showed up in App Store screenshots where the labels are the thing being sold.
        let sampleLabels: [(String, Int)] = [
            ("Household", 1), ("Medical", 3), ("Warranty", 4),
        ]

        let labels = sampleLabels.map { name, colorIndex in
            let label = ScanLabel(name: name, colorIndex: colorIndex)
            context.insert(label)
            return label
        }

        let sampleTitles = ["Northgate Property", "Central Veterinary",
                            "Appliance Warranty", "Service Authorization"]

        var pages: [UIImage] = documents.map { renderPage(lines: $0) }
        let form = renderForm()
        pages.append(form.image)

        for (index, page) in pages.enumerated() {
            await pipeline.process(pages: [page], into: context)

            // Attach to whatever the pipeline just inserted — it's the newest document.
            let descriptor = FetchDescriptor<ScannedDocument>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            guard let newest = try? context.fetch(descriptor).first else { continue }
            newest.labels = index == 0
                ? [labels[0], labels[2]]        // one document with two labels
                : [labels[index % labels.count]]
            // Titles are set explicitly rather than left to OCR title-detection. On these
            // synthetic pages the heading is the same weight as the body, so one of them
            // falls through to the "Scan <date>" fallback — accurate behaviour, but a
            // date-named row is not what the library looks like once a user has renamed
            // anything, and these seed the App Store screenshots.
            newest.title = sampleTitles[index]
        }
        try? context.save()

        // Give the newest document some markups, so the Fill & Sign editor has something to
        // show when it's opened by launch argument. Screenshots of an empty editor say
        // nothing about what the feature does.
        let newest = FetchDescriptor<ScannedDocument>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let document = try? context.fetch(newest).first {
            // A made-up name. Never a real person's, and least of all the developer's: this
            // ends up on a public App Store product page.
            var typed = PageMarkup(kind: .text("Dana Whitmore"),
                                   pageIndex: 0,
                                   origin: form.anchors["name"] ?? CGPoint(x: 0.2, y: 0.5),
                                   widthFraction: 0.4)
            typed.fontFraction = 0.019
            typed.ink = .blue

            var dated = PageMarkup(kind: .text("14 March 2026"),
                                   pageIndex: 0,
                                   origin: form.anchors["date"] ?? CGPoint(x: 0.2, y: 0.66),
                                   widthFraction: 0.3)
            dated.fontFraction = 0.019
            dated.ink = .blue

            var signed = PageMarkup(kind: .drawing(signatureMark()),
                                    pageIndex: 0,
                                    // A signature sits higher than typed text: the squiggle's
                                    // own bounding box is taller than the ink inside it.
                                    origin: (form.anchors["signature"]
                                             ?? CGPoint(x: 0.2, y: 0.58))
                                        .applying(.init(translationX: 0, y: -0.020)),
                                    widthFraction: 0.26)
            signed.ink = .blue

            document.markupData = MarkupStore.encode([typed, dated, signed])
        }

        try? context.save()
        // The pipeline rebuilt the manifest as each document landed — before these labels
        // were attached. Without this the sample library exports without its labels.
        LibraryManifest.rebuild(from: context)
    }

    /// A blank form with rules to fill in, and the normalized position of each rule.
    ///
    /// Anchors come out of the same layout loop that draws the page, so a markup placed at
    /// `anchors["signature"]` sits on the signature line by construction rather than by
    /// eyeballing a screenshot. Sample content is a warranty card elsewhere; you don't sign a
    /// warranty card, so Fill & Sign needs something that is actually signable.
    static func renderForm() -> (image: UIImage, anchors: [String: CGPoint]) {
        let width = 1275, height = 1650
        let lines: [(String, CGFloat, Bool, String?)] = [
            ("SERVICE AUTHORIZATION", 46, true, nil),
            ("", 18, false, nil),
            ("Northgate Property Management", 30, false, nil),
            ("Work Order 44719", 30, false, nil),
            ("", 22, false, nil),
            ("I authorize the work described above to be", 28, false, nil),
            ("completed at the address on file.", 28, false, nil),
            ("", 34, false, nil),
            ("Name  ______________________", 30, false, "name"),
            ("", 26, false, nil),
            ("Signature  ___________________", 30, false, "signature"),
            ("", 26, false, nil),
            ("Date  ______________________", 30, false, "date"),
        ]

        var anchors: [String: CGPoint] = [:]
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
                                            format: format).image { context in
            UIColor(red: 0.98, green: 0.975, blue: 0.965, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            var y: CGFloat = 150
            let left: CGFloat = 120
            for (text, size, isBold, anchor) in lines {
                if text.isEmpty { y += size; continue }
                let font = isBold ? UIFont.systemFont(ofSize: size, weight: .bold)
                                  : UIFont.systemFont(ofSize: size)
                (text as NSString).draw(at: CGPoint(x: left, y: y), withAttributes: [
                    .font: font,
                    .foregroundColor: UIColor(white: 0.09, alpha: 1),
                ])
                if let anchor {
                    // Just right of the label, sitting ON the rule.
                    //
                    // `y` is the TOP of the label text, but the rule is drawn at its
                    // baseline, and a markup's stored y is also its top. Writing at the
                    // label's top therefore lands a line low. Lifting by the ascent puts the
                    // written text on the rule instead of under it.
                    let labelWidth = (text.prefix(while: { $0 != "_" }) as NSString)
                        .size(withAttributes: [.font: font]).width
                    anchors[anchor] = CGPoint(x: (left + labelWidth) / CGFloat(width),
                                              y: (y - font.ascender * 0.55) / CGFloat(height))
                }
                y += font.lineHeight * 1.5
            }
        }
        return (image, anchors)
    }

    /// A handwriting-shaped squiggle, drawn rather than captured, so seeded data needs no
    /// PencilKit session.
    private static func signatureMark() -> UIImage {
        let size = CGSize(width: 300, height: 110)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 12, y: 78))
            path.addCurve(to: CGPoint(x: 78, y: 26),
                          controlPoint1: CGPoint(x: 24, y: 20),
                          controlPoint2: CGPoint(x: 52, y: 16))
            path.addCurve(to: CGPoint(x: 104, y: 82),
                          controlPoint1: CGPoint(x: 96, y: 36),
                          controlPoint2: CGPoint(x: 88, y: 84))
            path.addCurve(to: CGPoint(x: 168, y: 30),
                          controlPoint1: CGPoint(x: 126, y: 78),
                          controlPoint2: CGPoint(x: 140, y: 24))
            path.addCurve(to: CGPoint(x: 208, y: 80),
                          controlPoint1: CGPoint(x: 190, y: 34),
                          controlPoint2: CGPoint(x: 186, y: 82))
            path.addCurve(to: CGPoint(x: 288, y: 44),
                          controlPoint1: CGPoint(x: 240, y: 76),
                          controlPoint2: CGPoint(x: 262, y: 40))
            path.lineWidth = 7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.black.setStroke()
            path.stroke()
            _ = context
        }
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
