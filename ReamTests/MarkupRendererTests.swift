import Foundation
import CoreGraphics
import CoreText
import PDFKit
import Testing
import UIKit
@testable import Ream

/// Tests for burning markups into a PDF.
///
/// The one that matters is `preservesExistingTextLayer`. The obvious way to implement
/// fill-and-sign — rasterize the page, draw on the bitmap, re-encode — silently destroys the
/// invisible OCR layer that makes every scan searchable. It would look perfect and quietly
/// undo the app's whole point, on exactly the documents people care most about.
struct MarkupRendererTests {

    /// Builds a one-page PDF containing `text`, standing in for a scan whose invisible layer
    /// has already been written.
    private func makePDF(text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "markup-\(UUID().uuidString).pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)

        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)

        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
        ])
        context.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)

        context.endPDFPage()
        context.closePDF()
        return url
    }

    private func extractedText(from data: Data) throws -> String {
        let document = try #require(PDFDocument(data: data))
        return document.string ?? ""
    }

    @Test("Filled text lands in the document")
    func addsMarkupText() throws {
        let url = try makePDF(text: "ORIGINAL CONTENT")
        defer { try? FileManager.default.removeItem(at: url) }

        let markup = PageMarkup(kind: .text("Jane Q. Public"),
                                pageIndex: 0,
                                origin: CGPoint(x: 0.2, y: 0.5),
                                widthFraction: 0.4)

        let data = try #require(MarkupRenderer.render(pdfAt: url, markups: [markup]))
        #expect(try extractedText(from: data).contains("Jane Q. Public"))
    }

    /// The regression this whole design exists to prevent.
    @Test("Filling a form preserves the existing (searchable) text layer")
    func preservesExistingTextLayer() throws {
        let url = try makePDF(text: "POLICY NUMBER 44719038")
        defer { try? FileManager.default.removeItem(at: url) }

        let markup = PageMarkup(kind: .text("filled in"),
                                pageIndex: 0,
                                origin: CGPoint(x: 0.2, y: 0.5),
                                widthFraction: 0.4)

        let data = try #require(MarkupRenderer.render(pdfAt: url, markups: [markup]))
        let text = try extractedText(from: data)

        // If the page were rasterized instead of drawn as PDF operators, this is the
        // assertion that would fail — and nothing in the UI would look wrong.
        #expect(text.contains("POLICY NUMBER 44719038"),
                "The original text layer was destroyed. Did the renderer start rasterizing pages?")
        #expect(text.contains("filled in"))
    }

    @Test("Page count and page size are unchanged")
    func preservesGeometry() throws {
        let url = try makePDF(text: "A")
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try #require(MarkupRenderer.render(pdfAt: url, markups: []))
        let result = try #require(PDFDocument(data: data))
        #expect(result.pageCount == 1)

        let page = try #require(result.page(at: 0))
        let box = page.bounds(for: .mediaBox)
        #expect(abs(box.width - 612) < 1)
        #expect(abs(box.height - 792) < 1)
    }

    @Test("A markup aimed at a page that doesn't exist is ignored, not a crash")
    func ignoresOutOfRangePages() throws {
        let url = try makePDF(text: "ONLY PAGE")
        defer { try? FileManager.default.removeItem(at: url) }

        let markup = PageMarkup(kind: .text("ghost"),
                                pageIndex: 7,
                                origin: .zero,
                                widthFraction: 0.3)

        let data = try #require(MarkupRenderer.render(pdfAt: url, markups: [markup]))
        let text = try extractedText(from: data)
        #expect(text.contains("ONLY PAGE"))
        #expect(!text.contains("ghost"))
    }

    @Test("Ink colour reaches the rendered text")
    func inkColourIsApplied() throws {
        let url = try makePDF(text: "FORM")
        defer { try? FileManager.default.removeItem(at: url) }

        var markup = PageMarkup(kind: .text("in red"),
                                pageIndex: 0,
                                origin: CGPoint(x: 0.2, y: 0.5),
                                widthFraction: 0.4)
        markup.ink = .red

        // The text must still be TEXT, not a coloured picture of words — colouring it must
        // not quietly switch the renderer to a raster path.
        let data = try #require(MarkupRenderer.render(pdfAt: url, markups: [markup]))
        let text = try extractedText(from: data)
        #expect(text.contains("in red"))
        #expect(text.contains("FORM"))
    }

    @Test("Ink colours are distinct and none is pure black")
    func inkColoursAreInkLike() {
        let components = MarkupInk.allCases.compactMap { $0.cgColor.components }
        #expect(Set(components.map(\.description)).count == MarkupInk.allCases.count)
        // A real pen is never fully saturated; #000 / #F00 read as clip art on a scan.
        for parts in components {
            #expect(parts.prefix(3).contains { $0 > 0.05 })
        }
    }

    /// Builds a stroke image: an opaque square of `color` in the middle, transparent around.
    private func strokeImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 30, height: 30)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 10, y: 10, width: 10, height: 10))
        }
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let cgImage = try #require(image.cgImage)
        var data = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: -x, y: -(cgImage.height - 1 - y),
                                         width: cgImage.width, height: cgImage.height))
        return (data[0], data[1], data[2], data[3])
    }

    /// The claim the signature feature rests on: the captured stroke COLOUR is discarded and
    /// only its shape survives. PencilKit hands back white ink in dark mode and black in
    /// light, so if the capture colour leaked through, a signature's colour would depend on
    /// the phone's theme at the moment it was drawn.
    @Test("Signature tinting uses alpha only, whatever colour it was captured in",
          arguments: [UIColor.white, UIColor.black, UIColor.green])
    func tintingIgnoresCapturedColour(captured: UIColor) throws {
        let source = strokeImage(color: captured)
        let tinted = try #require(MarkupRenderer.tinted(source, with: .red))

        let inside = try pixel(tinted, x: 15, y: 15)
        let outside = try pixel(tinted, x: 2, y: 2)

        // Where the stroke was, the ink colour — regardless of what was drawn there.
        #expect(inside.a > 200)
        #expect(inside.r > inside.g && inside.r > inside.b)
        // Where it wasn't, still nothing: tinting must not fill the whole bounding box.
        #expect(outside.a < 40)
    }

    @Test("Every ink produces a distinguishable tint")
    func everyInkTintsDifferently() throws {
        let source = strokeImage(color: .black)
        var seen: Set<String> = []
        for ink in MarkupInk.allCases {
            let tinted = try #require(MarkupRenderer.tinted(source, with: ink))
            let inside = try pixel(tinted, x: 15, y: 15)
            seen.insert("\(inside.r),\(inside.g),\(inside.b)")
        }
        #expect(seen.count == MarkupInk.allCases.count)
    }

    /// Renders a page of the result and reports the pixel at a normalized position.
    private func renderedPixel(_ data: Data, atX x: Double, y: Double) throws
        -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        let box = page.bounds(for: .mediaBox)
        let image = page.thumbnail(of: box.size, for: .mediaBox)
        let cgImage = try #require(image.cgImage)

        let px = Int(Double(cgImage.width) * x)
        let py = Int(Double(cgImage.height) * y)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: -px, y: -(cgImage.height - 1 - py),
                                         width: cgImage.width, height: cgImage.height))
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    /// A drawing markup has to actually land on the page, in its ink, where it was placed.
    /// Freehand marks once vanished entirely, and nothing in the render path would have said
    /// so — the PDF was valid, just empty where the mark should have been.
    @Test("A drawing renders at its position, in its ink")
    func drawingRendersWhereItIsPlaced() throws {
        let url = try makePDF(text: "FORM")
        defer { try? FileManager.default.removeItem(at: url) }

        // A solid block, so a hit is unambiguous.
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let block = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40),
                                            format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }

        var markup = PageMarkup(kind: .drawing(block),
                                pageIndex: 0,
                                origin: CGPoint(x: 0.3, y: 0.3),
                                widthFraction: 0.4)
        markup.ink = .red

        let data = try #require(MarkupRenderer.render(pdfAt: url, markups: [markup]))

        // Inside the block: red ink.
        let inside = try renderedPixel(data, atX: 0.45, y: 0.4)
        #expect(inside.r > inside.g && inside.r > inside.b,
                "The drawing did not render, or rendered in the wrong colour.")

        // Well away from it: untouched page.
        let outside = try renderedPixel(data, atX: 0.9, y: 0.9)
        #expect(outside.r > 200 && outside.g > 200 && outside.b > 200,
                "The drawing bled outside its rect.")
    }

    @Test("An unreadable source returns nil rather than an empty document")
    func returnsNilForBadSource() {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "does-not-exist-\(UUID().uuidString).pdf")
        // Nil matters: the caller leaves the original file alone. Returning empty Data would
        // overwrite a real document with a blank one.
        #expect(MarkupRenderer.render(pdfAt: missing, markups: []) == nil)
    }
}
