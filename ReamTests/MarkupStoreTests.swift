import Foundation
import CoreGraphics
import Testing
import UIKit
@testable import Ream

/// Markups must survive being saved, so that reopening Fill & Sign is an EDIT rather than a
/// fresh start on a page with your text already welded to it.
struct MarkupStoreTests {

    private func strokeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 20, height: 12), format: format).image {
            UIColor.black.setFill()
            $0.fill(CGRect(x: 4, y: 4, width: 12, height: 4))
        }
    }

    @Test("A text markup round-trips with every property intact")
    func textRoundTrips() throws {
        var markup = PageMarkup(kind: .text("Jane Q. Public"),
                                pageIndex: 2,
                                origin: CGPoint(x: 0.25, y: 0.6),
                                widthFraction: 0.4)
        markup.fontFraction = 0.031
        markup.ink = .red

        let restored = MarkupStore.decode(MarkupStore.encode([markup]))
        let result = try #require(restored.first)

        #expect(result.text == "Jane Q. Public")
        #expect(result.pageIndex == 2)
        #expect(result.ink == .red)
        #expect(abs(result.origin.x - 0.25) < 0.0001)
        #expect(abs(result.origin.y - 0.6) < 0.0001)
        #expect(abs(result.fontFraction - 0.031) < 0.0001)
    }

    @Test("A drawing round-trips, image and all")
    func drawingRoundTrips() throws {
        var markup = PageMarkup(kind: .drawing(strokeImage()),
                                pageIndex: 0,
                                origin: CGPoint(x: 0.1, y: 0.2),
                                widthFraction: 0.33)
        markup.ink = .blue

        let restored = MarkupStore.decode(MarkupStore.encode([markup]))
        let result = try #require(restored.first)

        #expect(result.isDrawing)
        #expect(result.image != nil)
        #expect(result.ink == .blue)
        #expect(abs(result.widthFraction - 0.33) < 0.0001)
    }

    @Test("Removing a drawing deletes its file rather than orphaning it")
    func removedDrawingsAreCleanedUp() throws {
        let markup = PageMarkup(kind: .drawing(strokeImage()),
                                pageIndex: 0,
                                origin: .zero,
                                widthFraction: 0.3)
        _ = MarkupStore.encode([markup])

        let file = MarkupStore.drawingsDirectory.appending(path: "\(markup.id.uuidString).png")
        #expect(FileManager.default.fileExists(atPath: file.path))

        // Saving without it must not leave the PNG behind forever.
        _ = MarkupStore.encode([])
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Decoding nothing yields nothing rather than failing")
    func emptyDecodeIsSafe() {
        #expect(MarkupStore.decode(nil).isEmpty)
        #expect(MarkupStore.decode(Data()).isEmpty)
    }

    @Test("A drawing whose file is missing is dropped, not resurrected blank")
    func missingImageIsDropped() throws {
        let markup = PageMarkup(kind: .drawing(strokeImage()),
                                pageIndex: 0,
                                origin: .zero,
                                widthFraction: 0.3)
        let data = try #require(MarkupStore.encode([markup]))
        try FileManager.default.removeItem(
            at: MarkupStore.drawingsDirectory.appending(path: "\(markup.id.uuidString).png"))

        // A markup with no image would render as an invisible, undeletable ghost.
        #expect(MarkupStore.decode(data).isEmpty)
    }
}
