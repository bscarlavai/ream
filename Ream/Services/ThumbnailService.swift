import Foundation
import PDFKit
import UIKit

/// Renders and caches first-page thumbnails for the document list.
///
/// Two layers, for two different failure modes. The **memory** cache keeps scrolling from
/// re-decoding a PDF that's already on screen; the **disk** cache keeps a relaunch from
/// re-rendering the whole library. Rendering a PDF page costs single-digit milliseconds,
/// which is fine once and ruinous on every `body` evaluation — and SwiftUI evaluates a lot.
///
/// Disk cache lives in `Caches/`, not `Documents/`, on purpose: these are derived data. If
/// the system purges them under storage pressure they regenerate silently, and they must
/// never inflate the user's iCloud backup.
actor ThumbnailService {
    static let shared = ThumbnailService()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL

    init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "Thumbnails", directoryHint: .isDirectory)
        memory.countLimit = 200
    }

    /// Point size of the rendered thumbnail. Rendered at 3x so it stays sharp on every
    /// device, then cached at that size — re-rendering per scale factor would triple the
    /// work for a difference nobody can see.
    static let size = CGSize(width: 54, height: 70)

    func thumbnail(for fileName: String) async -> UIImage? {
        let key = fileName as NSString
        if let cached = memory.object(forKey: key) { return cached }

        if let onDisk = loadFromDisk(fileName) {
            memory.setObject(onDisk, forKey: key)
            return onDisk
        }

        guard let rendered = render(fileName) else { return nil }
        memory.setObject(rendered, forKey: key)
        writeToDisk(rendered, fileName: fileName)
        return rendered
    }

    /// Called when a document is deleted, so the cache doesn't outlive its source.
    func invalidate(fileName: String) {
        memory.removeObject(forKey: fileName as NSString)
        try? FileManager.default.removeItem(at: diskURL(fileName))
    }

    func invalidateAll() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Private

    private func diskURL(_ fileName: String) -> URL {
        directory.appending(path: fileName + ".jpg")
    }

    /// Fixed render scale rather than the device's.
    ///
    /// `UIScreen.main` is deprecated and is main-actor isolated, which this actor cannot
    /// reach without a hop. Rendering at 3x covers every current iPhone; a 2x device wastes
    /// a little memory on a 54pt image, which is a better trade than a per-device cache key
    /// (the same file would render twice if the scale ever changed under it).
    private static let renderScale: CGFloat = 3

    private func render(_ fileName: String) -> UIImage? {
        let pdfURL = DocumentStore.shared.url(for: fileName)
        guard let document = PDFDocument(url: pdfURL),
              let page = document.page(at: 0) else { return nil }

        let pixelSize = CGSize(width: Self.size.width * Self.renderScale,
                               height: Self.size.height * Self.renderScale)

        // `thumbnail(of:for:)` fits the page inside the box preserving aspect, which is what
        // we want — a receipt should stay receipt-shaped rather than being squashed to Letter.
        let raw = page.thumbnail(of: pixelSize, for: .mediaBox)
        // `raw.cgImage ?? raw.cgImage!` was here, which is not a fallback — it crashes on
        // exactly the input it pretends to handle. A nil backing store means the page
        // couldn't rasterize; the row shows its blank-paper placeholder instead.
        guard let cgImage = raw.cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: Self.renderScale, orientation: .up)
    }

    private func loadFromDisk(_ fileName: String) -> UIImage? {
        guard let data = try? Data(contentsOf: diskURL(fileName)) else { return nil }
        return UIImage(data: data, scale: Self.renderScale)
    }

    private func writeToDisk(_ image: UIImage, fileName: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // JPEG rather than PNG: these are photographs of paper, and the size difference on a
        // large library is real. Quality 0.8 is indistinguishable at 54pt.
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        try? data.write(to: diskURL(fileName), options: .atomic)
    }
}
