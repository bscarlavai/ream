import Foundation

/// Owns PDF files on disk. SwiftData holds metadata; the bytes live here.
///
/// Everything goes in the app's Documents directory, which `UIFileSharingEnabled`
/// exposes in Files.app. That's deliberate: a user should be able to get their
/// scans out of Ream without Ream's cooperation.
actor DocumentStore {
    static let shared = DocumentStore()

    private let directory: URL

    init() {
        directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "Scans", directoryHint: .isDirectory)
    }

    private func ensureDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    nonisolated func url(for fileName: String) -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "Scans", directoryHint: .isDirectory)
            .appending(path: fileName)
    }

    func write(_ data: Data, to fileName: String) throws -> URL {
        try ensureDirectory()
        let target = directory.appending(path: fileName)
        // .atomic so a crash mid-write can't leave a truncated PDF that SwiftData
        // still has a row pointing at.
        try data.write(to: target, options: .atomic)
        return target
    }

    func delete(fileName: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: fileName))
    }

    func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: fileName).path)
    }
}
