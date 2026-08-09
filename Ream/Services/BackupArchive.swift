import Foundation
import PDFKit
import UIKit

/// Getting scans out of Ream, and other people's PDFs in.
///
/// Deliberately **asymmetric**, and the asymmetry is the point. Export is a zip of the
/// PDFs themselves — not a proprietary envelope — because a backup you can only open with
/// the app that made it is a hostage, not a backup. Import re-derives everything by running
/// the PDF back through the real OCR pipeline, so a restored document is indistinguishable
/// from a freshly scanned one and no metadata format has to stay in sync across versions.
///
/// It also means Import doubles as "bring in a PDF someone emailed me", which is a feature
/// on its own rather than a restore-only path.
enum BackupArchive {

    enum ArchiveError: LocalizedError {
        case nothingToExport
        case zipFailed
        case unreadablePDF

        var errorDescription: String? {
            switch self {
            case .nothingToExport: "There are no scans to export yet."
            case .zipFailed: "Couldn't build the archive."
            case .unreadablePDF: "That file couldn't be read as a PDF."
            }
        }
    }

    /// Zips the scans folder and returns a temp URL suitable for `ShareLink`.
    ///
    /// Uses `NSFileCoordinator`'s `.forUploading` option, which is the only zip facility in
    /// the SDK that doesn't require a third-party archiver. The URL it hands back is valid
    /// **only inside the coordination block**, so the file is copied out before returning.
    static func exportAll() throws -> URL {
        let source = AppPaths.scans
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: source.path),
              !contents.isEmpty else {
            throw ArchiveError.nothingToExport
        }

        var coordinationError: NSError?
        var exported: URL?

        NSFileCoordinator().coordinate(readingItemAt: source,
                                       options: .forUploading,
                                       error: &coordinationError) { temporaryZip in
            let destination = FileManager.default.temporaryDirectory
                .appending(path: "Ream Scans.zip")
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.copyItem(at: temporaryZip, to: destination)
                exported = destination
            } catch {
                exported = nil
            }
        }

        guard coordinationError == nil, let exported else { throw ArchiveError.zipFailed }
        return exported
    }

    /// Renders every page of a PDF to an image so it can go back through OCR.
    ///
    /// Rasterizes at 200 dpi — the same density a phone scan lands at, and enough for Vision
    /// to read reliably. Rendering at the PDF's native 72 dpi produces text too small to
    /// recognize; going much higher costs memory on a long document for no accuracy gain.
    static func pageImages(fromPDF url: URL) throws -> [UIImage] {
        // A security-scoped resource is what the file importer hands back for a document
        // outside the app's container. Without this the open silently returns nil.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url) else { throw ArchiveError.unreadablePDF }

        let dpiScale: CGFloat = 200.0 / 72.0
        var images: [UIImage] = []

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let size = CGSize(width: bounds.width * dpiScale, height: bounds.height * dpiScale)

            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                // PDF pages draw in a bottom-left origin space; flip into UIKit's.
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: dpiScale, y: -dpiScale)
                page.draw(with: .mediaBox, to: context.cgContext)
            }
            images.append(image)
        }

        guard !images.isEmpty else { throw ArchiveError.unreadablePDF }
        return images
    }
}
