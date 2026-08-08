import Foundation
import CoreGraphics
import CoreText
import PDFKit
import UIKit

/// Burns markups into a PDF, permanently.
///
/// **The critical decision here is how the original page gets carried across.** The obvious
/// implementation — rasterize each page to an image, draw on top, re-encode — would destroy
/// the invisible OCR text layer that makes every scan searchable. That layer is the whole
/// point of the app, and losing it on "fill in a form" would be a silent, unrecoverable
/// regression.
///
/// So the original page is drawn with `PDFPage.draw(with:to:)` into a **PDF** context. That
/// copies the page's operators rather than its pixels: vector content stays vector, and the
/// invisible text survives intact. Filled text is drawn as real text for the same reason —
/// it ends up selectable and searchable too, not a picture of words.
enum MarkupRenderer {

    /// Applies markups and returns the new document's bytes.
    /// Returns nil if the source can't be opened, so the caller can leave the original alone.
    static func render(pdfAt url: URL, markups: [PageMarkup]) -> Data? {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return nil }

        let byPage = Dictionary(grouping: markups, by: \.pageIndex)
        let data = NSMutableData()

        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { return nil }

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            var box = page.bounds(for: .mediaBox)

            let boxData = withUnsafeBytes(of: &box) { Data($0) } as CFData
            context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)

            // Vector copy of the original, invisible text layer and all.
            context.saveGState()
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()

            for markup in byPage[index] ?? [] {
                draw(markup, in: context, pageBox: box)
            }

            context.endPDFPage()
        }

        context.closePDF()
        return data as Data
    }

    // MARK: - Drawing

    private static func draw(_ markup: PageMarkup, in context: CGContext, pageBox: CGRect) {
        // Markups are stored top-left origin (screen convention); PDF is bottom-left.
        let x = pageBox.minX + markup.origin.x * pageBox.width
        let topY = pageBox.minY + markup.origin.y * pageBox.height

        switch markup.kind {
        case .text(let string):
            guard !string.isEmpty else { return }
            let fontSize = markup.fontFraction * pageBox.height
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attributed = NSAttributedString(string: string, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: markup.ink.cgColor,
            ])
            let line = CTLineCreateWithAttributedString(attributed)

            context.saveGState()
            // Visible text, drawn as TEXT — so a filled form stays selectable and searchable
            // rather than becoming a picture of words.
            context.setTextDrawingMode(.fill)
            // The stored y is the TOP of the text; a baseline sits one ascent below it.
            let ascent = CTFontGetAscent(font)
            context.textPosition = CGPoint(x: x, y: pageBox.maxY - (topY - pageBox.minY) - ascent)
            CTLineDraw(line, context)
            context.restoreGState()

        case .drawing(let image):
            guard let cgImage = image.cgImage else { return }
            let width = markup.widthFraction * pageBox.width
            let height = width * (image.size.height / max(image.size.width, 1))
            let rect = CGRect(x: x,
                              y: pageBox.maxY - (topY - pageBox.minY) - height,
                              width: width,
                              height: height)
            context.saveGState()
            // Recoloured through its alpha before drawing. `CGContext.clip(to:mask:)` looks
            // like the direct route but is documented to want a DeviceGray image with no
            // alpha — a PencilKit export is RGBA, so its behaviour there is not something to
            // rely on.
            let stroke = Self.tinted(image, with: markup.ink)?.cgImage ?? cgImage
            context.draw(stroke, in: rect)
            context.restoreGState()
        }
    }

    /// Recolours a signature using only its alpha channel.
    ///
    /// The stroke colour PencilKit captured is discarded on purpose. It varies with the
    /// appearance the user signed in — dark mode yields white ink, light mode black — and
    /// treating the drawing as a pure SHAPE means the pen colour is a decision made on the
    /// page afterwards, not one accidentally inherited from the phone's theme.
    static func tinted(_ image: UIImage, with ink: MarkupInk) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = image.scale

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            ink.uiColor.setFill()
            context.fill(rect)
            // `.destinationIn` keeps the fill only where the drawing has alpha, which is
            // exactly the stroke — whatever colour it happened to be drawn in.
            image.draw(in: rect, blendMode: .destinationIn, alpha: 1)
        }
    }

    /// Rasterizes one page for the editor's canvas.
    ///
    /// The editor works on a picture on purpose: it only needs something to position markups
    /// against, and the save path re-renders from the untouched original either way.
    static func pagePreview(pdfAt url: URL, pageIndex: Int, width: CGFloat) -> UIImage? {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale = width / bounds.width
        return page.thumbnail(of: CGSize(width: bounds.width * scale,
                                         height: bounds.height * scale),
                              for: .mediaBox)
    }
}
