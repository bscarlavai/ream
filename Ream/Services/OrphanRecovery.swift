import Foundation
import SwiftData

/// Re-adopts PDFs that exist on disk but have no row in the store.
///
/// **This is the recovery path Ream's siblings can't have.** In riplist and PokeArtist the
/// SwiftData store *is* the collection — lose it and only a snapshot or an archive brings it
/// back. Here the PDFs are the artifacts and they live as ordinary files named by UUID, so a
/// lost or quarantined store costs metadata, never a document. This walks the scans folder,
/// finds every PDF the store doesn't know about, and files it again.
///
/// It covers four separate failures with one mechanism:
/// - the store failed to open and was quarantined (`StoreManager.boot` → `.recovered`)
/// - a snapshot was restored that predates some scans
/// - the app was killed between writing a PDF and saving its row
/// - the user copied PDFs back in via Files.app after a reinstall
///
/// Metadata comes from `manifest.json` when it's there. When it isn't, the document is still
/// adopted — a scan with a placeholder title is recoverable, a scan you can't see is not.
enum OrphanRecovery {

    struct Result {
        var adopted: Int
        var withMetadata: Int
        var needsOCR: [UUID]
    }

    @MainActor
    @discardableResult
    static func run(in context: ModelContext) -> Result {
        var result = Result(adopted: 0, withMetadata: 0, needsOCR: [])

        let scansDirectory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "Scans", directoryHint: .isDirectory)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: scansDirectory, includingPropertiesForKeys: nil
        ) else { return result }

        let pdfs = files.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfs.isEmpty else { return result }

        // One fetch, then a Set — not a predicate per file. A library with a few hundred
        // scans would otherwise do a few hundred round trips to SQLite at launch.
        let known = Set(((try? context.fetch(FetchDescriptor<ScannedDocument>())) ?? [])
            .map(\.fileName))

        let manifest = LibraryManifest.load()
        let entries = Dictionary(
            (manifest?.entries ?? []).map { ($0.fileName, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Labels are shared across documents, so they're resolved once and reused. Creating
        // one per document would produce five copies of "Taxes" in the filter bar.
        var labelsByName: [String: ScanLabel] = [:]
        for label in ((try? context.fetch(FetchDescriptor<ScanLabel>())) ?? []) {
            labelsByName[label.name.lowercased()] = label
        }

        for pdf in pdfs {
            let fileName = pdf.lastPathComponent
            guard !known.contains(fileName) else { continue }

            // The filename stem is the document's UUID. If it isn't parseable this file didn't
            // come from Ream — adopt it anyway under a fresh id rather than skipping it.
            let id = UUID(uuidString: pdf.deletingPathExtension().lastPathComponent) ?? UUID()

            if let entry = entries[fileName] {
                let document = ScannedDocument(id: id,
                                               title: entry.title,
                                               pageCount: entry.pageCount,
                                               transcript: entry.transcript)
                document.createdAt = entry.createdAt
                // Markups come back editable, not just as whatever was flattened into the PDF.
                document.markupData = entry.markups.flatMap { try? JSONEncoder().encode($0) }
                document.labels = entry.labels.map { spec in
                    if let existing = labelsByName[spec.name.lowercased()] { return existing }
                    let created = ScanLabel(name: spec.name, colorIndex: spec.colorIndex)
                    context.insert(created)
                    labelsByName[spec.name.lowercased()] = created
                    return created
                }
                context.insert(document)
                result.withMetadata += 1
            } else {
                // No manifest entry. Adopt with an honest placeholder and queue it for OCR —
                // the caller re-reads the text so the document becomes searchable again.
                let document = ScannedDocument(id: id,
                                               title: "Recovered scan",
                                               pageCount: 1,
                                               transcript: "")
                context.insert(document)
                result.needsOCR.append(id)
            }
            result.adopted += 1
        }

        if result.adopted > 0 {
            try? context.save()
            // Fold the recovered documents back into the manifest immediately, so a second
            // failure doesn't have to rediscover them.
            LibraryManifest.rebuild(from: context)
        }
        return result
    }

    /// Re-reads text for documents adopted without a manifest entry.
    ///
    /// Separate from `run` and deliberately not awaited by it: adoption must be instant so the
    /// library is never empty on screen, where OCR over a large recovered folder can take a
    /// while. A document is visible and openable the whole time; it just isn't searchable yet.
    @MainActor
    static func restoreText(for ids: [UUID], in context: ModelContext) async {
        for id in ids {
            let descriptor = FetchDescriptor<ScannedDocument>(
                predicate: #Predicate { $0.id == id }
            )
            guard let document = try? context.fetch(descriptor).first else { continue }

            let url = DocumentStore.shared.url(for: document.fileName)
            guard let pages = try? BackupArchive.pageImages(fromPDF: url) else { continue }

            let cgPages = pages.compactMap(\.cgImage)
            guard let results = try? await OCRService.recognize(pages: cgPages) else { continue }

            document.pageCount = cgPages.count
            document.transcript = results.map(\.transcript)
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            document.isSearchable = !document.transcript.isEmpty
            if let detected = results.compactMap(\.detectedTitle).first,
               !detected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                document.title = String(detected.prefix(60))
            }
        }
        try? context.save()
        LibraryManifest.rebuild(from: context)
    }
}
