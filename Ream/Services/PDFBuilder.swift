import Foundation
import CoreGraphics
import CoreText
import UIKit

/// Builds a searchable PDF: the scanned image is what you see, with the OCR'd text
/// drawn on top in invisible render mode so it stays selectable and searchable.
///
/// This is the one genuinely non-obvious part of Ream, and it was validated end-to-end
/// in `spike/main.swift` before any of this app existed.
enum PDFBuilder {

    /// Color handling for the embedded page images.
    ///
    /// Default is `.asCaptured` — pass through exactly what the scanner returned.
    /// `VNDocumentCameraViewController` already gives the user a Color / Grayscale /
    /// B&W / Photo selector in its own UI, so converting here would silently override
    /// a choice they just made on screen.
    ///
    /// `.forceGrayscale` stays available for a future "shrink file size" setting:
    /// measured on the same source, color lossless ran ~183 KB/page versus ~117 KB/page
    /// grayscale. Worth offering, not worth imposing.
    enum ColorMode: Sendable {
        case asCaptured
        case forceGrayscale
    }

    struct Page: Sendable {
        let image: CGImage
        let lines: [RecognizedLine]
    }

    /// Standard US Letter width in PDF points. Page height follows the image aspect,
    /// so a photo of a receipt stays a receipt instead of being stretched to Letter.
    private static let pageWidth: CGFloat = 612

    static func makeSearchablePDF(pages: [Page], colorMode: ColorMode = .asCaptured) -> Data {
        guard !pages.isEmpty else { return Data() }

        // Renderer bounds only seed the default page size; each page overrides it below.
        let firstSize = pageSize(for: pages[0].image)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: firstSize))

        return renderer.pdfData { context in
            for page in pages {
                let size = pageSize(for: page.image)
                context.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])

                let cg = context.cgContext
                let image = colorMode == .forceGrayscale ? grayscale(page.image) : page.image

                // UIKit's PDF context is top-left origin with y increasing downward.
                // Everything below — image draw and text placement — is easier in
                // CoreGraphics' native bottom-left space, which is also exactly the
                // space Vision reports bounding boxes in. So flip once, up front.
                cg.saveGState()
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)

                cg.draw(image, in: CGRect(origin: .zero, size: size))
                drawInvisibleTextLayer(page.lines, pageSize: size, in: cg)

                cg.restoreGState()
            }
        }
    }

    // MARK: - Text layer

    private static func drawInvisibleTextLayer(_ lines: [RecognizedLine],
                                               pageSize: CGSize,
                                               in cg: CGContext) {
        let baseFont = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let fontKey = kCTFontAttributeName as NSAttributedString.Key

        for line in lines where !line.text.isEmpty {
            // Vision hands back a NormalizedRect; ask it for page coordinates directly
            // rather than doing the multiply by hand. `.lowerLeft` matches the flipped
            // context established above.
            let target = line.boundingBox.toImageCoordinates(pageSize, origin: .lowerLeft)
            guard target.width > 0.5, target.height > 0.5 else { continue }

            // Measure at a reference size, then scale the font so the glyph run spans
            // the same width Vision reported. Without this, selection highlights drift
            // away from the words they're supposed to cover.
            let probe = NSAttributedString(string: line.text, attributes: [fontKey: baseFont])
            let probeWidth = CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(probe), nil, nil, nil
            )
            guard probeWidth > 0 else { continue }

            let scaledFont = CTFontCreateCopyWithAttributes(
                baseFont, 12 * target.width / CGFloat(probeWidth), nil, nil
            )
            let attributed = NSAttributedString(string: line.text, attributes: [fontKey: scaledFont])
            let ctLine = CTLineCreateWithAttributedString(attributed)

            cg.saveGState()
            // Render mode 3: glyphs are present in the content stream but never painted.
            // Preferred over clear-colored text, which some PDF tools strip as a no-op.
            cg.setTextDrawingMode(.invisible)
            // Nudge up off the box floor so the baseline sits inside the glyph box
            // rather than on its bottom edge.
            cg.textPosition = CGPoint(x: target.minX, y: target.minY + target.height * 0.18)
            CTLineDraw(ctLine, cg)
            cg.restoreGState()
        }
    }

    // MARK: - Helpers

    private static func pageSize(for image: CGImage) -> CGSize {
        CGSize(width: pageWidth,
               height: pageWidth * CGFloat(image.height) / CGFloat(image.width))
    }

    /// Redraws into a single-channel gray color space.
    ///
    /// Note we do *not* JPEG-compress: measured on a text page, JPEG q=0.7 produced a
    /// *larger* file than lossless (217 vs 183 KB/page) and q=0.4 visibly degraded the
    /// glyph edges. JPEG is tuned for photographs, not sharp black-on-white text.
    private static func grayscale(_ image: CGImage) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil,
                                  width: image.width,
                                  height: image.height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return image
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }
}
