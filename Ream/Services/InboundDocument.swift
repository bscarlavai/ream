import Foundation
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// Handles a document handed to Ream from outside: the share sheet, "Open in…", Files, Mail,
/// a Safari download.
///
/// Deliberately reuses the existing import path rather than inventing a second one — an
/// inbound PDF becomes page images and goes through the same OCR and PDF build as a camera
/// scan, so a shared document ends up searchable exactly like everything else.
enum InboundDocument {

    /// True if this is a file Ream can actually take. iOS will hand us anything the user
    /// picks, including things our declared types don't cover.
    static func canHandle(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .pdf) || type.conforms(to: .image)
    }

    /// Converts an inbound file to page images.
    ///
    /// Files arriving from another app live outside our container and are security-scoped;
    /// without `startAccessingSecurityScopedResource` the read silently returns nothing.
    /// `BackupArchive.pageImages` already does that for PDFs, so only the image path needs it
    /// handled here.
    static func pageImages(from url: URL) throws -> [UIImage] {
        if url.pathExtension.lowercased() == "pdf" {
            return try BackupArchive.pageImages(fromPDF: url)
        }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            throw BackupArchive.ArchiveError.unreadablePDF
        }
        return [image]
    }
}
