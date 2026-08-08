import Foundation
import SwiftData

/// Versioned schema from commit one.
///
/// poke-rip's store is still unversioned, and retrofitting a `VersionedSchema` there is a
/// sequenced two-release migration that has already cost one user their collection. The cost
/// of doing this before shipping is twenty lines; the cost of doing it after is a migration
/// nobody can safely test.
enum ReamSchemaV1: VersionedSchema {
    // `let`, not `var` — a static mutable is nonisolated global shared state under Swift 6
    // strict concurrency and will not compile.
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [ScannedDocument.self, ScanLabel.self] }
}

enum ReamMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ReamSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// Opens the store, and refuses to destroy data in order to do it.
///
/// **The invariant: the app may fail to open your data, but it may never destroy it trying.**
/// Never `.modelContainer(for:)` — it `fatalError`s on a failed migration, which crash-loops
/// the app and leaves the user unable to even export. Here a failed open moves the store
/// aside intact and boots a recovery state.
///
/// Ream is in a better position than its siblings on this: the PDFs are the real artifacts
/// and they live as ordinary files, so losing the store costs titles, labels and transcripts
/// but never a document. `OrphanRecovery` rebuilds the rest.
@MainActor
enum StoreManager {

    enum BootResult {
        case ok(ModelContainer)
        /// The store could not be opened. The files are preserved at `quarantined`, and the
        /// app runs on a fresh container — `OrphanRecovery` then re-adopts every PDF on disk.
        case recovered(ModelContainer, quarantined: URL)
    }

    /// A dedicated directory, so "back up the store" means "copy one folder".
    static var storeDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Ream/Store", directoryHint: .isDirectory)
    }

    static var storeURL: URL { storeDirectory.appending(path: "Ream.store") }

    static var backupsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Ream/Backups", directoryHint: .isDirectory)
    }

    // MARK: - The shrink tripwire

    /// Rows present when the app last ran. Written after every successful open, so at the NEXT
    /// launch it describes exactly the bytes `snapshotBeforeOpen` is about to copy.
    private static let lastRowCountKey = "storeLastKnownRowCount"
    /// Set by delete-all, cleared on the next boot. The one caller allowed to collapse the
    /// store to zero on purpose.
    private static let intentionalWipeKey = "storeIntentionalWipe"

    static func recordRowCount(_ count: Int) {
        UserDefaults.standard.set(count, forKey: lastRowCountKey)
    }

    static func markIntentionalWipe() {
        UserDefaults.standard.set(true, forKey: intentionalWipeKey)
        UserDefaults.standard.set(0, forKey: lastRowCountKey)
    }

    // MARK: - Boot

    static func boot() -> BootResult {
        let fm = FileManager.default
        try? fm.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        snapshotBeforeOpen()

        let configuration = ModelConfiguration(url: storeURL)
        let schema = Schema(versionedSchema: ReamSchemaV1.self)

        do {
            let container = try ModelContainer(for: schema,
                                               migrationPlan: ReamMigrationPlan.self,
                                               configurations: configuration)
            return .ok(container)
        } catch {
            // Move aside, never delete. The broken files are the user's only copy of anything
            // the snapshots missed, and they may be recoverable by hand.
            let stamp = ISO8601DateFormatter().string(from: .now)
                .replacingOccurrences(of: ":", with: "-")
            let quarantine = storeDirectory.appending(path: "broken-\(stamp)",
                                                      directoryHint: .isDirectory)
            try? fm.createDirectory(at: quarantine, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: storeURL.path + suffix)
                guard fm.fileExists(atPath: source.path) else { continue }
                try? fm.moveItem(at: source,
                                 to: quarantine.appending(path: source.lastPathComponent))
            }
            // Second attempt against a now-empty location. If this also fails there is nothing
            // sensible left to do but crash — and by then the user's bytes are safely aside.
            let container = try! ModelContainer(for: schema,
                                                migrationPlan: ReamMigrationPlan.self,
                                                configurations: configuration)
            return .recovered(container, quarantined: quarantine)
        }
    }

    /// Copies the store directory BEFORE the container is constructed, so the files are
    /// quiescent and there is no WAL/live-SQLite hazard. ~7 daily snapshots, rotated.
    ///
    /// Never `isExcludedFromBackup` on any of this — device backups must include it.
    ///
    /// **The shrink tripwire lives here.** Without it the backup system is a liability rather
    /// than a safety net: a library emptied by accident — or by a bug — gets snapshotted as
    /// empty, and seven launches later every good snapshot has rotated out. A backup system
    /// that faithfully replicates a catastrophe has done the user harm.
    ///
    /// So a run that starts from zero rows does not get to write a snapshot while non-empty
    /// ones exist. It FREEZES. Delete-all is the single exempt caller.
    private static func snapshotBeforeOpen() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return }   // nothing to snapshot yet

        let defaults = UserDefaults.standard
        let wipedOnPurpose = defaults.bool(forKey: intentionalWipeKey)
        defaults.set(false, forKey: intentionalWipeKey)
        // `lastRowCountKey` describes the state these very bytes were left in.
        if !wipedOnPurpose, defaults.integer(forKey: lastRowCountKey) == 0, hasSnapshots {
            return
        }

        let day = String(ISO8601DateFormatter().string(from: .now).prefix(10))
        let destination = backupsDirectory.appending(path: day, directoryHint: .isDirectory)
        if fm.fileExists(atPath: destination.path) { return }        // one per day is enough
        try? fm.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        try? fm.copyItem(at: storeDirectory, to: destination)
        rotateSnapshots(keeping: 7)
    }

    static var hasSnapshots: Bool {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: backupsDirectory, includingPropertiesForKeys: nil)) ?? []
        return !entries.isEmpty
    }

    private static func rotateSnapshots(keeping count: Int) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: backupsDirectory,
                                                        includingPropertiesForKeys: nil) else { return }
        let sorted = entries.map(\.lastPathComponent).sorted()
        guard sorted.count > count else { return }
        for stale in sorted.prefix(sorted.count - count) {
            try? fm.removeItem(at: backupsDirectory.appending(path: stale))
        }
    }

    // MARK: - Purge

    /// Everything on disk that holds user rows, removed as one operation.
    ///
    /// Quarantined stores are included on purpose: a `broken-<date>` directory is a full copy
    /// of a library, so leaving one behind would mean "delete all scans" quietly kept the data.
    static func purgeAllLocalCopies() {
        let fm = FileManager.default
        try? fm.removeItem(at: backupsDirectory)
        let entries = (try? fm.contentsOfDirectory(at: storeDirectory,
                                                   includingPropertiesForKeys: nil)) ?? []
        for quarantine in entries where quarantine.lastPathComponent.hasPrefix("broken-") {
            try? fm.removeItem(at: quarantine)
        }
        markIntentionalWipe()
    }
}
