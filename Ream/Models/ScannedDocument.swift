import Foundation
import SwiftData

/// A single scanned document. The PDF itself lives on disk (see `DocumentStore`);
/// this model holds only metadata plus the OCR transcript.
///
/// Trade-off: storing the full transcript in SwiftData duplicates text that already
/// exists inside the PDF's invisible layer. We accept the duplication because it makes
/// in-app search a plain `@Query` predicate instead of parsing every PDF on each keystroke.
@Model
final class ScannedDocument {
    /// Stable identity, and also the on-disk filename stem (`<id>.pdf`).
    var id: UUID = UUID()

    /// User-facing name. Seeded from the first page's detected title, editable later.
    var title: String = ""

    var createdAt: Date = Date.now
    var pageCount: Int = 0

    /// Full recognized text, newline-joined. Backs in-app search.
    var transcript: String = ""

    /// Whether OCR actually produced text. A photo of a blank page or a failed
    /// recognition pass still yields a valid PDF — it just isn't searchable.
    var isSearchable: Bool = false

    /// Markups applied in Fill & Sign, encoded by `MarkupStore`.
    ///
    /// Held so the editor can restore them. Without it, saving welds markups into the page
    /// and a typo can only be fixed by re-scanning.
    var markupData: Data?

    /// Categories this document is filed under. Many-to-many; see `ScanLabel`.
    ///
    /// Optional and un-defaulted because SwiftData requires relationships to be nullable,
    /// and because that's what keeps a later CloudKit migration from being a schema break.
    var labels: [ScanLabel]?

    init(id: UUID = UUID(), title: String, pageCount: Int, transcript: String) {
        self.id = id
        self.title = title
        self.createdAt = .now
        self.pageCount = pageCount
        self.transcript = transcript
        self.isSearchable = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Filename on disk. Derived, never stored, so it can't drift from `id`.
    var fileName: String { "\(id.uuidString).pdf" }
}
