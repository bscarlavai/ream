import Foundation
import CoreGraphics
import PencilKit
import Testing
import UIKit
@testable import Ream

/// Freehand capture: does a PencilKit drawing actually become a visible image?
///
/// Freehand marks kept vanishing while signatures worked, and the two share every downstream
/// step — persistence, tinting, rendering. The remaining difference is the capture itself, so
/// this pins it directly rather than by another round of inspection.
struct DrawingCaptureTests {

    private func makeDrawing(at origin: CGPoint = CGPoint(x: 40, y: 60)) -> PKDrawing {
        let ink = PKInk(.pen, color: .black)
        // A short run of points, since a single point may not produce a renderable path.
        let points = (0..<12).map { step in
            PKStrokePoint(location: CGPoint(x: origin.x + Double(step) * 6, y: origin.y),
                          timeOffset: Double(step) * 0.01,
                          size: CGSize(width: 6, height: 6),
                          opacity: 1,
                          force: 1,
                          azimuth: 0,
                          altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKDrawing(strokes: [PKStroke(ink: ink, path: path)])
    }

    private func hasInk(_ image: UIImage) throws -> Bool {
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Any pixel with meaningful alpha means something was drawn.
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 20 }
    }

    @Test("A stroke has non-empty bounds")
    func strokeHasBounds() {
        let drawing = makeDrawing()
        #expect(!drawing.bounds.isEmpty)
    }

    /// The direct suspect. A blank capture would explain both symptoms at once: the markup
    /// persists and is selectable, but there is nothing to see in the editor OR the document.
    @Test("Capturing the stroke's own bounds yields a visible image")
    func captureProducesInk() throws {
        let drawing = makeDrawing()
        let padded = drawing.bounds.insetBy(dx: -6, dy: -6)
        let image = drawing.image(from: padded, scale: 3)

        #expect(image.size.width > 0 && image.size.height > 0)
        #expect(try hasInk(image), "The captured drawing is blank — nothing was rendered.")
    }

    @Test("The captured image survives a PNG round trip")
    func captureSurvivesPNG() throws {
        let drawing = makeDrawing()
        let image = drawing.image(from: drawing.bounds.insetBy(dx: -6, dy: -6), scale: 3)

        // MarkupStore persists drawings as PNG; a capture that can't encode would be dropped
        // on the next decode and vanish silently.
        let data = try #require(image.pngData())
        let restored = try #require(UIImage(data: data))
        #expect(try hasInk(restored))
    }

    @Test("Tinting the capture keeps it visible")
    func tintedCaptureStaysVisible() throws {
        let drawing = makeDrawing()
        let image = drawing.image(from: drawing.bounds.insetBy(dx: -6, dy: -6), scale: 3)
        let tinted = try #require(MarkupRenderer.tinted(image, with: .blue))
        #expect(try hasInk(tinted))
    }
}
