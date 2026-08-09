import Foundation

/// Owns PDF files on disk. SwiftData holds metadata; the bytes live here.
///
/// Everything goes in the app's Documents directory, which `UIFileSharingEnabled`
/// exposes in Files.app. That's deliberate: a user should be able to get their
/// scans out of Ream without Ream's cooperation.
actor DocumentStore {
    static let shared = DocumentStore()

    private var directory: URL { AppPaths.scans }

    nonisolated func url(for fileName: String) -> URL {
        AppPaths.scan(fileName)
    }

    func write(_ data: Data, to fileName: String) throws -> URL {
        AppPaths.ensure(directory)
        let target = AppPaths.scan(fileName)
        // .atomic so a crash mid-write can't leave a truncated PDF that SwiftData
        // still has a row pointing at.
        try data.write(to: target, options: .atomic)
        return target
    }

    func delete(fileName: String) {
        try? FileManager.default.removeItem(at: AppPaths.scan(fileName))
    }

    func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: AppPaths.scan(fileName).path)
    }
}
