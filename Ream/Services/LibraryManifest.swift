import Foundation
import SwiftData

/// A plain-JSON sidecar describing every scan, written next to the PDFs themselves.
///
/// This exists because the export was a ZIP of PDFs and nothing else — so titles, labels
/// and transcripts did not survive losing the phone, while the Settings footer claimed an
/// export was "the only copy that survives". That was false, and this makes it true.
///
/// **Living in `Documents/Scans/` is the whole trick.** It means the manifest is picked up
/// by the export ZIP with no extra code, it is visible in Files.app beside the documents it
/// describes, and a user restoring by hand can copy the whole folder back and get their
/// labels with it. A metadata format stored somewhere else would have to be separately
/// exported, separately imported, and separately kept in sync.
struct LibraryManifest: Codable {
    struct Entry: Codable {
        var fileName: String
        var title: String
        var createdAt: Date
        var pageCount: Int
        var transcript: String
        var labels: [Label]

        struct Label: Codable {
            var name: String
            var colorIndex: Int
        }
    }

    var version = 1
    var entries: [Entry] = []

    static let fileName = "manifest.json"

    /// The live location. Tests pass an explicit directory instead — see `rebuild(from:in:)`.
    static var scansDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "Scans", directoryHint: .isDirectory)
    }

    static var url: URL { scansDirectory.appending(path: fileName) }

    // MARK: - IO

    static func load(in directory: URL? = nil) -> LibraryManifest? {
        let target = (directory ?? scansDirectory).appending(path: fileName)
        guard let data = try? Data(contentsOf: target) else { return nil }
        return try? JSONDecoder.manifest.decode(LibraryManifest.self, from: data)
    }

    /// Rewrites the manifest from the current store contents.
    ///
    /// Called after any mutation that changes what a scan *is* — created, renamed, relabelled,
    /// deleted. Cheap enough to do wholesale: it's a few hundred short records, and a
    /// wholesale rewrite cannot drift from the store the way incremental patching can.
    @MainActor
    static func rebuild(from context: ModelContext, in directory: URL? = nil) {
        let descriptor = FetchDescriptor<ScannedDocument>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let documents = try? context.fetch(descriptor) else { return }

        let manifest = LibraryManifest(entries: documents.map { document in
            Entry(fileName: document.fileName,
                  title: document.title,
                  createdAt: document.createdAt,
                  pageCount: document.pageCount,
                  transcript: document.transcript,
                  labels: (document.labels ?? []).map {
                      Entry.Label(name: $0.name, colorIndex: $0.colorIndex)
                  })
        })

        guard let data = try? JSONEncoder.manifest.encode(manifest) else { return }
        let target = (directory ?? scansDirectory)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        // .atomic so a crash mid-write can't leave a truncated manifest that parses as empty
        // and makes recovery think the library had no metadata.
        try? data.write(to: target.appending(path: fileName), options: .atomic)
    }
}

extension JSONEncoder {
    static var manifest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var manifest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
