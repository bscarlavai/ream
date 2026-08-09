import Foundation
import UIKit

/// Persists markups so they can be edited again later.
///
/// Before this, saving burned markups into the PDF and that was that: reopening the editor
/// showed a clean page with your text welded to it, and fixing a typo meant re-scanning.
///
/// The scheme keeps **two** files per marked-up document:
/// - `Scans/<id>.pdf` — flattened. Everything else in the app reads this and needs no
///   changes: the viewer, thumbnails, share, search, export.
/// - `Scans/originals/<id>.pdf` — the pristine scan, written once, the first time markups are
///   applied. Every save re-renders from THIS, so edits never compound: moving a signature
///   twice doesn't leave a ghost of the first position.
///
/// Both directories sit inside `Scans/`, so the export ZIP picks them up for free — as does
/// the manifest, which carries the markup metadata. A backup therefore restores editable
/// markups, not just a flattened page.
enum MarkupStore {

    /// Codable stand-in for `PageMarkup`, which holds a `UIImage` and can't be encoded.
    /// Drawings are written alongside as PNGs and referenced by filename.
    struct Stored: Codable {
        var id: UUID
        var text: String?
        var imageFile: String?
        var pageIndex: Int
        var originX: Double
        var originY: Double
        var widthFraction: Double
        var fontFraction: Double
        var ink: String
    }

    static var originalsDirectory: URL { AppPaths.originals }
    static var drawingsDirectory: URL { AppPaths.drawings }

    /// The file a fresh render should start from: the pristine scan if one exists, otherwise
    /// the document itself (which is still pristine, because nothing has been applied yet).
    static func sourceURL(for fileName: String) -> URL {
        let original = AppPaths.original(fileName)
        return FileManager.default.fileExists(atPath: original.path)
            ? original
            : DocumentStore.shared.url(for: fileName)
    }

    /// Called before the first flatten. After this the main file is derived and the original
    /// is the source of record.
    static func preserveOriginalIfNeeded(fileName: String) {
        let original = AppPaths.original(fileName)
        guard !FileManager.default.fileExists(atPath: original.path) else { return }
        AppPaths.ensure(AppPaths.originals)
        try? FileManager.default.copyItem(at: DocumentStore.shared.url(for: fileName),
                                          to: original)
    }

    // MARK: - Encoding

    static func encode(_ markups: [PageMarkup]) -> Data? {
        AppPaths.ensure(AppPaths.drawings)

        let stored: [Stored] = markups.map { markup in
            var imageFile: String?
            if let image = markup.image {
                // Named by the markup's id, so re-saving overwrites rather than accumulating
                // an orphan per edit.
                let name = "\(markup.id.uuidString).png"
                if let data = image.pngData() {
                    try? data.write(to: AppPaths.drawing(name), options: .atomic)
                }
                imageFile = name
            }
            return Stored(id: markup.id,
                          text: markup.isDrawing ? nil : markup.text,
                          imageFile: imageFile,
                          pageIndex: markup.pageIndex,
                          originX: markup.origin.x,
                          originY: markup.origin.y,
                          widthFraction: markup.widthFraction,
                          fontFraction: markup.fontFraction,
                          ink: markup.ink.rawValue)
        }

        // Drawings that no longer belong to any markup would otherwise linger forever.
        let live = Set(stored.compactMap(\.imageFile))
        let onDisk = (try? FileManager.default.contentsOfDirectory(
            at: AppPaths.drawings, includingPropertiesForKeys: nil)) ?? []
        for file in onDisk where file.pathExtension == "png" && !live.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }

        return try? JSONEncoder().encode(stored)
    }

    static func decode(_ data: Data?) -> [PageMarkup] {
        guard let data, let stored = try? JSONDecoder().decode([Stored].self, from: data) else {
            return []
        }
        return stored.compactMap { entry in
            let kind: PageMarkup.Kind
            if let file = entry.imageFile {
                guard let image = UIImage(contentsOfFile: AppPaths.drawing(file).path)
                else { return nil }
                kind = .drawing(image)
            } else {
                kind = .text(entry.text ?? "")
            }
            var markup = PageMarkup(kind: kind,
                                    pageIndex: entry.pageIndex,
                                    origin: CGPoint(x: entry.originX, y: entry.originY),
                                    widthFraction: entry.widthFraction)
            markup.fontFraction = entry.fontFraction
            markup.ink = MarkupInk(rawValue: entry.ink) ?? .black
            return markup
        }
    }

    /// Removes everything derived for a document. Called when it's deleted.
    static func purge(fileName: String, markupData: Data?) {
        try? FileManager.default.removeItem(at: AppPaths.original(fileName))
        for markup in decode(markupData) {
            try? FileManager.default.removeItem(
                at: AppPaths.drawing("\(markup.id.uuidString).png"))
        }
    }
}
