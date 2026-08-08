import SwiftUI
import SwiftData

@main
struct ReamApp: App {
    /// Local-only store. No CloudKit container, no account — a scan exists on exactly one
    /// device unless the user exports it themselves.
    ///
    /// Opened through `StoreManager`, never `.modelContainer(for:)`. The convenience modifier
    /// `fatalError`s on a failed migration, which crash-loops the app and leaves the user
    /// unable to even export their documents.
    private let boot: StoreManager.BootResult
    private let container: ModelContainer

    @State private var supporter = SupporterService()
    @State private var engagement = Engagement()
    @State private var crossPromo = CrossPromoState()

    init() {
        let result = StoreManager.boot()
        boot = result
        switch result {
        case .ok(let container), .recovered(let container, _):
            self.container = container
        }
    }

    private var quarantinedStore: URL? {
        if case .recovered(_, let url) = boot { return url }
        return nil
    }

    var body: some Scene {
        WindowGroup {
            RootView(quarantinedStore: quarantinedStore)
                .environment(supporter)
                .environment(engagement)
                .environment(crossPromo)
        }
        .modelContainer(container)
    }
}

/// Resolves the accent, and owns launch-time recovery.
///
/// The finish has a different value in light and dark mode, and `@Environment(\.colorScheme)`
/// is only readable from a View — not from a `Scene` — so the tint is applied here.
private struct RootView: View {
    let quarantinedStore: URL?

    @Environment(\.modelContext) private var context
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue

    @Query private var documents: [ScannedDocument]
    @State private var recoveryNotice: String?
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showingOnboarding = false

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        // The tint is resolved in a CHILD view, not here. `.preferredColorScheme` takes
        // effect for the subtree BELOW it — reading `\.colorScheme` in the same view that
        // sets it returns the previous value, so the accent would lag one toggle behind.
        TintedRoot()
            .preferredColorScheme(appearance.colorScheme)
            // Marked seen when it's PRESENTED, not when dismissed. A user who force-quits
            // mid-onboarding has still seen it, and showing it again reads as a bug.
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView()
            }
            .task {
                if !hasSeenOnboarding {
                    hasSeenOnboarding = true
                    showingOnboarding = true
                }
                await recoverIfNeeded()
            }
            .alert("Scans recovered", isPresented: .constant(recoveryNotice != nil)) {
                Button("OK") { recoveryNotice = nil }
            } message: {
                Text(recoveryNotice ?? "")
            }
    }

    /// Runs on every launch, not only after a quarantine.
    ///
    /// A PDF with no row can also come from the app being killed between writing the file and
    /// saving the row, from a restored snapshot that predates a scan, or from a user copying
    /// documents back in via Files.app. Checking always costs one directory listing.
    private func recoverIfNeeded() async {
        let result = OrphanRecovery.run(in: context)

        if result.adopted > 0 {
            recoveryNotice = quarantinedStore == nil
                ? "\(result.adopted) document(s) on this device weren't in your library and have been added back."
                : "Ream couldn't open your library, so it was set aside and rebuilt from the documents on this device. \(result.adopted) recovered."
        }

        // Text restoration runs after the notice so the library is never empty on screen
        // while OCR grinds through a large recovered folder.
        if !result.needsOCR.isEmpty {
            await OrphanRecovery.restoreText(for: result.needsOCR, in: context)
        }

        // Feeds the shrink tripwire: at the NEXT launch this number describes the state the
        // store files were left in, which is how a snapshot knows not to overwrite good
        // copies with an empty one.
        StoreManager.recordRowCount(documents.count)
    }
}

/// Resolves the accent against the *effective* color scheme, whatever produced it —
/// the system setting or the user's override.
private struct TintedRoot: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(SupporterService.self) private var supporter
    @AppStorage("accentFinish") private var finishRaw = AccentFinish.blueprint.rawValue

    private var finish: AccentFinish {
        AccentFinish.resolved(rawValue: finishRaw, isSupporter: supporter.isSupporter)
    }

    var body: some View {
        DocumentListView()
            .tint(finish.color(for: scheme))
    }
}
