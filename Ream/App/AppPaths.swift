import Foundation

/// Every on-disk location the app uses, in one place.
///
/// These paths were previously rebuilt inline in five different files — `DocumentStore`,
/// `LibraryManifest`, `OrphanRecovery`, `MarkupStore` and `BackupArchive` each spelled out
/// `Documents/Scans` for itself. Six copies of a path is six chances for one of them to drift,
/// and the failure mode is silent: recovery scanning a folder nothing writes to, or an export
/// zipping a directory that isn't the one being filled.
enum AppPaths {

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// User-visible PDFs. Exposed in Files.app (`UIFileSharingEnabled`) so documents can be
    /// retrieved without the app's cooperation.
    static var scans: URL {
        documents.appending(path: "Scans", directoryHint: .isDirectory)
    }

    /// Pristine scans, kept once a document has been marked up. See `MarkupStore`.
    static var originals: URL {
        scans.appending(path: "originals", directoryHint: .isDirectory)
    }

    /// Signature and freehand images referenced by markup metadata.
    static var drawings: URL {
        scans.appending(path: "markups", directoryHint: .isDirectory)
    }

    /// Sidecar describing every scan. Lives INSIDE `scans` on purpose, so the export zip and
    /// Files.app both pick it up with no extra work.
    static var manifest: URL {
        scans.appending(path: "manifest.json")
    }

    static func scan(_ fileName: String) -> URL {
        scans.appending(path: fileName)
    }

    static func original(_ fileName: String) -> URL {
        originals.appending(path: fileName)
    }

    static func drawing(_ fileName: String) -> URL {
        drawings.appending(path: fileName)
    }

    static func ensure(_ directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

/// `@AppStorage` keys.
///
/// A raw string repeated across views is a rename waiting to break silently: change it in
/// four places and miss the fifth, and that view keeps reading a key nothing writes.
enum DefaultsKey {
    static let accentFinish = "accentFinish"
    static let appearanceMode = "appearanceMode"
    static let hasSeenOnboarding = "hasSeenOnboarding"
}

/// Where the app sends people. Centralised so a changed support address or a moved policy
/// page is one edit, not a search.
enum ExternalLink {
    /// Ream's App Store id.
    static let appStoreID = "6799583392"

    static let privacy = URL(string: "https://lavailabs.com/ream/privacy")!
    static let terms = URL(string: "https://lavailabs.com/ream/terms")!

    /// Opens the App Store review sheet directly.
    ///
    /// Used for the Settings row, NOT for the automatic milestone prompt. `requestReview` is
    /// capped by iOS at three prompts a year and silently ignores the rest — fine for a
    /// prompt the app chooses to show, useless for a button someone deliberately tapped,
    /// which would appear to do nothing.
    static let writeReview = URL(string:
        "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!

    static func support(version: String) -> URL {
        // Version in the subject so a bug report arrives already saying which build it's from.
        URL(string: "mailto:ream@lavailabs.com?subject=Ream%20\(version)")!
    }

    static func appStore(id: String) -> URL? {
        URL(string: "https://apps.apple.com/app/id\(id)")
    }
}

#if DEBUG
/// Launch arguments for states the Simulator can't otherwise reach — it has no camera and
/// cannot tap, so anything behind a gesture is unreachable from the command line.
enum LaunchArgument {
    static let seedSamples = "--seed-samples"
    static let showSettings = "--show-settings"
    static let showDetail = "--show-detail"
    static let onboardingPage = "--onboarding-page"
    /// Opens Fill & Sign on the newest document.
    static let showFillSign = "--show-fillsign"
    /// Pre-fills the search field, so a search-in-progress can be captured.
    static let search = "--search"
    /// Pre-selects a label filter by name, so a filtered library can be captured.
    static let filterLabel = "--filter-label"
    /// Forces the non-supporter state. Simulators accumulate StoreKit test transactions
    /// that RevenueCat syncs into a live entitlement, which makes the locked view of the
    /// finish picker unreachable — and that is the view a new user actually sees.
    static let forceLocked = "--locked"
    /// Opens Settings straight through to the finish picker.
    static let showFinishes = "--show-finishes"
    /// Hides debug-only chrome while keeping the other arguments working.
    ///
    /// Screenshots need a Debug build for the navigation arguments and seeded data, but must
    /// not show a "Sample" button that doesn't exist in the shipped app. Apple requires
    /// screenshots to be of the real UI.
    static let screenshotMode = "--screenshot"

    static func isPresent(_ argument: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    /// Reads `--flag <value>`.
    static func intValue(after argument: String) -> Int? {
        stringValue(after: argument).flatMap(Int.init)
    }

    static func stringValue(after argument: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: argument), args.count > index + 1 else { return nil }
        return args[index + 1]
    }
}
#endif

/// The app's own version, formatted for display and for support emails.
enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
