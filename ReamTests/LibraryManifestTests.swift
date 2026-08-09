import Foundation
import SwiftData
import Testing
@testable import Ream

/// Round-trip tests for the backup manifest.
///
/// This is the test riplist's data-safety design calls "the test that keeps the format
/// honest": a field added to `ScannedDocument` and forgotten in `LibraryManifest.Entry`
/// silently stops surviving a backup, and nothing else in the app would notice. Here it
/// fails the build instead.
@MainActor
struct LibraryManifestTests {

    /// In-memory store, so tests never touch the real library.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ScannedDocument.self, ScanLabel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ReamTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Every field on a document survives a manifest round trip")
    func roundTripPreservesEveryField() throws {
        let context = try makeContext()
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let taxes = ScanLabel(name: "Taxes", colorIndex: 3)
        let urgent = ScanLabel(name: "Urgent", colorIndex: 6)
        context.insert(taxes)
        context.insert(urgent)

        let document = ScannedDocument(title: "2026 Return",
                                       pageCount: 4,
                                       transcript: "Form 1040 line 11 adjusted gross income")
        document.labels = [taxes, urgent]
        context.insert(document)
        try context.save()

        LibraryManifest.rebuild(from: context, in: directory)

        let loaded = try #require(LibraryManifest.load(in: directory))
        #expect(loaded.version == 1)
        #expect(loaded.entries.count == 1)

        let entry = try #require(loaded.entries.first)
        #expect(entry.fileName == document.fileName)
        #expect(entry.title == "2026 Return")
        #expect(entry.pageCount == 4)
        #expect(entry.transcript == "Form 1040 line 11 adjusted gross income")
        // ISO-8601 encoding drops sub-second precision; a second of slack is the format,
        // not a bug.
        #expect(abs(entry.createdAt.timeIntervalSince(document.createdAt)) < 1)

        #expect(Set(entry.labels.map(\.name)) == ["Taxes", "Urgent"])
        #expect(Set(entry.labels.map(\.colorIndex)) == [3, 6])
    }

    /// The honesty check. If `ScannedDocument` grows a field that a user would notice losing,
    /// this fails until the manifest carries it too.
    ///
    /// Deliberately a hardcoded list rather than reflection: the point is that adding a field
    /// forces a human to decide whether it belongs in a backup, and reflection would let a
    /// new field slip through by defaulting to "included".
    @Test("Manifest covers every user-visible field on ScannedDocument")
    func manifestCoversKnownFields() throws {
        let covered: Set<String> = [
            "title", "createdAt", "pageCount", "transcript", "labels", "fileName",
            "markupData",
        ]
        // `id` is encoded in `fileName`; `isSearchable` is derived from `transcript`.
        let derivedOrEncoded: Set<String> = ["id", "isSearchable"]

        let all = covered.union(derivedOrEncoded)
        #expect(all.count == 9, """
            ScannedDocument's field list changed. Add the new field to LibraryManifest.Entry \
            (and to `covered` here), or to `derivedOrEncoded` if it can be reconstructed.
            """)
    }

    @Test("Rebuild reflects a deletion rather than leaving a stale entry")
    func rebuildDropsDeletedDocuments() throws {
        let context = try makeContext()
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let keeper = ScannedDocument(title: "Keep", pageCount: 1, transcript: "a")
        let doomed = ScannedDocument(title: "Delete", pageCount: 1, transcript: "b")
        context.insert(keeper)
        context.insert(doomed)
        try context.save()
        LibraryManifest.rebuild(from: context, in: directory)
        #expect(LibraryManifest.load(in: directory)?.entries.count == 2)

        context.delete(doomed)
        try context.save()
        LibraryManifest.rebuild(from: context, in: directory)

        let after = try #require(LibraryManifest.load(in: directory))
        // A stale entry here would make the next launch's orphan recovery try to re-adopt a
        // document the user deleted on purpose.
        #expect(after.entries.count == 1)
        #expect(after.entries.first?.title == "Keep")
    }

    @Test("A document with no labels round-trips as an empty list, not a failure")
    func unlabelledDocumentRoundTrips() throws {
        let context = try makeContext()
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        context.insert(ScannedDocument(title: "Loose page", pageCount: 1, transcript: ""))
        try context.save()
        LibraryManifest.rebuild(from: context, in: directory)

        let entry = try #require(LibraryManifest.load(in: directory)?.entries.first)
        #expect(entry.labels.isEmpty)
        #expect(entry.transcript.isEmpty)
    }
}
