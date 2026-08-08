import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    @Environment(SupporterService.self) private var supporter
    @Environment(\.requestReview) private var requestReview

    @Query private var documents: [ScannedDocument]
    @AppStorage("accentFinish") private var finishRaw = AccentFinish.blueprint.rawValue
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @State private var showingFinishes = false
    @State private var showingCrossPromo = false
    @State private var showingLabelManager = false
    @State private var showingImporter = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var shareFile: ShareableFile?

    let pipeline: ScanPipeline

    private var finish: AccentFinish {
        AccentFinish.resolved(rawValue: finishRaw, isSupporter: supporter.isSupporter)
    }

    private var accent: Color { finish.color(for: scheme) }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                appearance
                scans
                support
                about
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFinishes) { SupporterView() }
            .sheet(isPresented: $showingLabelManager) { LabelManagerView() }
            .sheet(item: $shareFile) { file in
                ShareSheet(url: file.url)
            }
            .sheet(isPresented: $showingCrossPromo) {
                CrossPromoView(siblings: SiblingApp.crossPromoTargets)
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.pdf],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .alert("Delete every scan?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Everything", role: .destructive) { deleteAll() }
            } message: {
                Text("This removes all \(documents.count) scans and their PDFs from this device. It cannot be undone, and there is no cloud copy.")
            }
            .alert("Something went wrong",
                   isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    private var appearance: some View {
        Section("Appearance") {
            // A menu picker rather than a segmented control: three options with icons read
            // better as a list, and it matches the Finish row directly beneath it.
            Picker(selection: appearanceBinding) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.symbol).tag(mode)
                }
            } label: {
                ReamRow(title: "Theme",
                        systemImage: appearanceBinding.wrappedValue.symbol,
                        iconTint: accent)
            }
            .pickerStyle(.menu)

            Button {
                showingFinishes = true
            } label: {
                ReamRow(title: "Finish",
                        subtitle: finish.displayName,
                        swatch: finish.color(for: scheme),
                        accessory: .chevron)
            }
            .buttonStyle(.plain)
        }
    }

    private var scans: some View {
        Section {
            // Export is the PDFs themselves, zipped — not a proprietary envelope. A backup
            // you can only open with the app that made it isn't a backup.
            Button {
                export()
            } label: {
                ReamRow(title: "Export All Scans", systemImage: "arrow.up.doc",
                        iconTint: accent, accessory: .value("ZIP"))
            }
            .buttonStyle(.plain)
            .disabled(documents.isEmpty)

            Button {
                showingLabelManager = true
            } label: {
                ReamRow(title: "Manage Labels", systemImage: "tag",
                        iconTint: accent, accessory: .chevron)
            }
            .buttonStyle(.plain)

            Button {
                showingImporter = true
            } label: {
                ReamRow(title: isImporting ? "Importing…" : "Import a PDF",
                        systemImage: "arrow.down.doc", iconTint: accent)
            }
            .buttonStyle(.plain)
            .disabled(isImporting)

            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                ReamRow(title: "Delete All Scans", systemImage: "trash",
                        isDestructive: true)
            }
            .buttonStyle(.plain)
            .disabled(documents.isEmpty)
        } header: {
            Text("Your Scans")
        } footer: {
            Text("Scans live only on this device. Ream has no account and no cloud, so an export is the only copy that survives losing your phone.")
        }
    }

    private var support: some View {
        Section {
            if !supporter.isSupporter {
                Button {
                    showingFinishes = true
                } label: {
                    ReamRow(title: "Support Ream", systemImage: "heart",
                            iconTint: accent, accessory: .chevron)
                }
                .buttonStyle(.plain)
            }

            Button {
                requestReview()
            } label: {
                ReamRow(title: "Rate Ream", systemImage: "star", iconTint: accent)
            }
            .buttonStyle(.plain)

            Link(destination: URL(string: "mailto:ream@lavailabs.com?subject=Ream%20\(appVersion)")!) {
                ReamRow(title: "Contact", systemImage: "envelope", iconTint: accent)
            }
            .buttonStyle(.plain)

            Button {
                showingCrossPromo = true
            } label: {
                ReamRow(title: "More from Lavai Labs", systemImage: "square.grid.2x2",
                        iconTint: accent, accessory: .chevron)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Support")
        }
    }

    private var about: some View {
        Section {
            ReamRow(title: "Version", systemImage: "info.circle",
                    iconTint: accent, accessory: .value(appVersion))

            Link(destination: URL(string: "https://lavailabs.com/ream/privacy")!) {
                ReamRow(title: "Privacy Policy", systemImage: "hand.raised",
                        iconTint: accent, accessory: .chevron)
            }
            .buttonStyle(.plain)

            Link(destination: URL(string: "https://lavailabs.com/ream/terms")!) {
                ReamRow(title: "Terms of Use", systemImage: "doc.text",
                        iconTint: accent, accessory: .chevron)
            }
            .buttonStyle(.plain)
        } header: {
            Text("About")
        } footer: {
            Text("Ream never uploads your documents. Scanning, text recognition and PDF creation all happen on this device, with no network access at all.")
        }
    }

    #if DEBUG
    /// Not shipped. `#if DEBUG` rather than a hidden gesture or a build flag, so it cannot
    /// reach the App Store by accident.
    private var debugSection: some View {
        @Bindable var supporter = supporter
        return Section {
            Toggle(isOn: $supporter.debugForceSupporter) {
                ReamRow(title: "Supporter Mode",
                        subtitle: supporter.isSupporter ? "Unlocked" : "Locked",
                        systemImage: "wrench.adjustable",
                        iconTint: accent)
            }

            Button {
                hasSeenOnboarding = false
                dismiss()
            } label: {
                ReamRow(title: "Replay Onboarding",
                        subtitle: "Takes effect on next launch",
                        systemImage: "arrow.counterclockwise",
                        iconTint: accent)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Debug")
        } footer: {
            Text("Forces the Supporter entitlement on. simctl doesn't apply the scheme's StoreKit configuration, so this is the only way to reach the locked finishes in the Simulator.")
        }
    }
    #endif

    // MARK: - Actions

    /// Builds the archive, then hands the URL to a SwiftUI sheet.
    ///
    /// The previous version reached through `UIApplication.shared.connectedScenes` for a root
    /// view controller and presented `UIActivityViewController` on whatever it found. That
    /// worked only because Settings happens to be presented as a sheet — any change to how
    /// this screen is shown would have broken it silently, with no compiler help.
    private func export() {
        // The manifest carries titles, labels and transcripts, and it lives inside the
        // scans folder — so rebuilding it here is what makes the zip a real backup rather
        // than a pile of anonymous PDFs.
        LibraryManifest.rebuild(from: context)
        do {
            shareFile = ShareableFile(url: try BackupArchive.exportAll())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                let pages = try BackupArchive.pageImages(fromPDF: url)
                await pipeline.process(pages: pages, into: context)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteAll() {
        let fileNames = documents.map(\.fileName)
        for document in documents { context.delete(document) }
        try? context.save()

        // Every local copy, as one operation. Snapshots and any quarantined store are full
        // copies of the library — leaving one behind would mean "delete all scans" quietly
        // kept the scans. This also stands the shrink tripwire down for the next boot, so
        // an intentional wipe isn't mistaken for a catastrophe.
        StoreManager.purgeAllLocalCopies()

        Task {
            for name in fileNames {
                await DocumentStore.shared.delete(fileName: name)
            }
            await ThumbnailService.shared.invalidateAll()
            // Manifest last: it must not describe documents that no longer exist, or the
            // next launch's orphan recovery would try to re-adopt them.
            await MainActor.run { LibraryManifest.rebuild(from: context) }
        }
    }
}
