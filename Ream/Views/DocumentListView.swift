import SwiftUI
import SwiftData

struct DocumentListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScannedDocument.createdAt, order: .reverse)
    private var documents: [ScannedDocument]
    @Query(sort: \ScanLabel.name) private var labels: [ScanLabel]

    @Environment(Engagement.self) private var engagement
    @Environment(CrossPromoState.self) private var crossPromo
    @Environment(SupporterService.self) private var supporter
    @Environment(\.requestReview) private var requestReview

    @State private var pipeline = ScanPipeline()
    @State private var isScanning = false
    @State private var showingSettings = false
    @State private var promoPayload: CrossPromoPayload?
    @State private var showingSupporterPitch = false
    @State private var importError: String?
    /// Explicit navigation path so a detail screen can be pushed programmatically.
    /// Rows still use `NavigationLink(value:)`, so the chevron and press behaviour are
    /// unchanged — this only adds a second way in, for launch arguments.
    @State private var path = NavigationPath()
    @State private var searchText = ""
    /// Label filter. Multi-select and treated as OR — picking Taxes and Medical shows
    /// anything in either, which is what "show me these piles" means. AND would return
    /// almost nothing, since documents rarely carry two specific labels at once.
    @State private var activeLabelIDs: Set<UUID> = []

    /// Cached result, recomputed only when an input actually changes.
    ///
    /// This used to be a computed property. Substring-searching every transcript and building
    /// a Set per document is fine at three scans and quietly awful at five hundred — and a
    /// computed property runs on EVERY body evaluation, not just when you type. SwiftUI
    /// evaluates a lot.
    @State private var filtered: [ScannedDocument] = []

    private static func applyFilters(documents: [ScannedDocument],
                                     searchText: String,
                                     activeLabelIDs: Set<UUID>) -> [ScannedDocument] {
        var result = documents

        if !activeLabelIDs.isEmpty {
            result = result.filter { document in
                let ids = Set((document.labels ?? []).map(\.id))
                return !ids.isDisjoint(with: activeLabelIDs)
            }
        }

        guard !searchText.isEmpty else { return result }
        // Searches the OCR transcript, not just the title — the whole point of the
        // invisible text layer is that you can find a document by its contents.
        return result.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.transcript.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func refreshFilter() {
        filtered = Self.applyFilters(documents: documents,
                                     searchText: searchText,
                                     activeLabelIDs: activeLabelIDs)
    }

    /// Nav-bar title. Information, not branding.
    ///
    /// The bar has to exist anyway — it carries the gear and the back button from detail —
    /// and with no title it was a lone icon floating in an empty strip. A count fills it
    /// with something that earns the space, and it doubles as the only indication that a
    /// label filter is narrowing the list.
    private var navTitle: Text {
        if activeLabelIDs.isEmpty {
            return Text("^[\(documents.count) Scan](inflect: true)")
        }
        return Text("\(filtered.count) of \(documents.count)")
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if documents.isEmpty {
                    emptyState
                } else {
                    documentList
                }
            }
            // Inline, and never the app name — a user who opened Ream knows what Ream is.
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search scans")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                #if DEBUG
                // The Simulator has no camera, so this is the only way to get scans
                // into the app while working on UI.
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sample") {
                        Task { await SampleScans.generate(into: context, pipeline: pipeline) }
                    }
                }
                #endif

                // iOS 26 bottom bar: the system search field and the primary action share
                // one row. `DefaultToolbarItem` is what lets the search field be *placed*
                // rather than float on its own, and `ToolbarSpacer` splits the Liquid Glass
                // into two groups so Scan reads as its own pill instead of a search accessory.
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        isScanning = true
                    } label: {
                        Label("Scan", systemImage: "doc.viewfinder")
                    }
                    // Prominent glass fills the pill with the accent color, marking Scan
                    // as the primary action. A plain glass button renders as a tinted
                    // icon that reads as a peer of the search field, not the main thing.
                    .reamProminent(glass: true)
                    .disabled(pipeline.phase.isWorking)
                    .accessibilityLabel("Scan document")
                }
            }
            .fullScreenCover(isPresented: $isScanning) {
                DocumentCameraView(
                    onFinish: { pages in
                        guard !pages.isEmpty else { return }
                        Task { await pipeline.process(pages: pages, into: context) }
                    },
                    onFailure: { _ in }
                )
                .ignoresSafeArea()
            }
            .navigationDestination(for: ScannedDocument.self) { document in
                DocumentDetailView(document: document)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(pipeline: pipeline)
            }
            .sheet(isPresented: $showingSupporterPitch) {
                SupporterView()
            }
            .sheet(item: $promoPayload) { payload in
                CrossPromoView(siblings: payload.siblings)
            }
            .overlay {
                if pipeline.phase.isWorking {
                    processingOverlay
                }
            }
            // Share sheet, "Open in…", Files, Mail, Safari downloads. Handled here rather
            // than at the app root so an inbound document drives the SAME pipeline as a
            // camera scan and therefore shows the same progress overlay.
            .onOpenURL { url in
                Task { await importInbound(url) }
            }
            .alert("Couldn't import", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .onAppear {
                pipeline.engagement = engagement
                refreshFilter()
            }
            // Explicit recompute on each input. Cheaper than a computed property because it
            // runs when something CHANGES rather than whenever SwiftUI re-evaluates the body.
            .onChange(of: searchText) { _, _ in refreshFilter() }
            .onChange(of: activeLabelIDs) { _, _ in refreshFilter() }
            .onChange(of: documents) { _, _ in refreshFilter() }
            // Both milestones are checked when the pipeline goes idle — i.e. right after a
            // scan lands, not on launch. They are mutually exclusive by threshold (promo at
            // 2 scans, review at 5) so a user never gets both at once.
            .onChange(of: pipeline.phase) { _, phase in
                guard phase == .idle else { return }
                showPromptIfDue()
            }
            #if DEBUG
            // Launch arguments for reaching states the Simulator otherwise can't:
            //   --seed-samples   populate the library (there is no camera here)
            //   --show-settings  open Settings directly
            //   --show-detail    push the newest document's detail screen
            .task {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("--seed-samples"), documents.isEmpty {
                    await SampleScans.generate(into: context, pipeline: pipeline)
                }
                if args.contains("--show-settings") {
                    showingSettings = true
                }
                if args.contains("--show-detail"), let first = documents.first {
                    path.append(first)
                }
            }
            #endif
        }
    }

    // MARK: - Pieces

    private var documentList: some View {
        List {
            ForEach(filtered) { document in
                NavigationLink(value: document) {
                    DocumentRow(document: document)
                }
            }
            .onDelete(perform: delete)

            if filtered.isEmpty {
                // A filter that hides everything must say so. Otherwise it reads as an
                // empty library and the user goes looking for scans they still have.
                ContentUnavailableView {
                    Label("Nothing matches", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No scans carry the labels you picked.")
                } actions: {
                    Button("Clear Filter") { withAnimation { activeLabelIDs = [] } }
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !labels.isEmpty { filterBar }
        }
    }

    /// Only shown once labels exist — an empty filter bar is chrome that teaches nothing.
    private var filterBar: some View {
        ChipRow {
            ForEach(labels) { label in
                Button {
                    withAnimation {
                        if activeLabelIDs.contains(label.id) {
                            activeLabelIDs.remove(label.id)
                        } else {
                            activeLabelIDs.insert(label.id)
                        }
                    }
                } label: {
                    LabelChip(name: label.name,
                              color: label.color,
                              isSelected: activeLabelIDs.contains(label.id),
                              showsCount: label.documentCount)
                        .frame(minHeight: Theme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.bar)
    }

    /// The bottom-bar pill is the right *persistent* affordance, but it's a weak first
    /// impression on an empty library. The empty state carries the prominent CTA instead,
    /// which is exactly what `ContentUnavailableView`'s actions slot is for.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No scans yet", systemImage: "doc.viewfinder")
        } description: {
            Text("Scan a document and Ream turns it into a searchable PDF. Free, on your device, no account.")
        } actions: {
            Button {
                isScanning = true
            } label: {
                Text("Scan Document")
                    // Inset from the capsule's own curve — without it the label sits flush
                    // against the rounded ends and the button reads as too tight.
                    .padding(.horizontal, Theme.Spacing.large)
                    .frame(minHeight: Theme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .reamProminent()
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.medium) {
                ProgressView()
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(Theme.Spacing.large)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    private var statusText: String {
        switch pipeline.phase {
        case .recognizing(let page, let total): "Reading page \(page) of \(total)…"
        case .buildingPDF: "Building PDF…"
        default: ""
        }
    }

    /// At most ONE ask per completed scan, in a fixed priority order.
    ///
    /// `Engagement` owns the review-vs-supporter decision; the cross-promo is checked only
    /// when neither fired, so a single scan can never stack a rating request, a paywall and
    /// an app recommendation on top of each other.
    private func showPromptIfDue() {
        switch engagement.nextPrompt(isSupporter: supporter.isSupporter) {
        case .review:
            requestReview()
            engagement.markReviewRequested()
        case .supporter:
            engagement.markSupporterPrompted()
            showingSupporterPitch = true
        case nil:
            let unseen = crossPromo.pending(completedScans: engagement.completedScans)
            guard !unseen.isEmpty else { return }
            // Marked up front so a swipe-dismiss counts the same as tapping Done.
            crossPromo.markSeen(unseen)
            promoPayload = CrossPromoPayload(siblings: unseen)
        }
    }

    private func importInbound(_ url: URL) async {
        guard InboundDocument.canHandle(url) else {
            importError = "Ream can open PDFs and images."
            return
        }
        do {
            let pages = try InboundDocument.pageImages(from: url)
            await pipeline.process(pages: pages, into: context)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        let targets = offsets.map { filtered[$0] }
        withAnimation {
            for document in targets {
                let fileName = document.fileName
                context.delete(document)
                Task {
                    await DocumentStore.shared.delete(fileName: fileName)
                    await ThumbnailService.shared.invalidate(fileName: fileName)
                }
            }
        }
        try? context.save()
        LibraryManifest.rebuild(from: context)
        refreshFilter()
    }
}

private struct DocumentRow: View {
    let document: ScannedDocument

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.medium) {
            // The thumbnail leads. You recognize a document by what it looks like long
            // before you read its title — especially when the title is an auto-detected
            // heading that got it wrong, or a fallback date.
            DocumentThumbnail(fileName: document.fileName, pageCount: document.pageCount)

            // Tight, natural height, vertically centred against the thumbnail. An earlier
            // version top-aligned this and used a Spacer to push the meta line down to the
            // thumbnail's baseline, which spread three short lines across 70pt and read as
            // a mostly-empty row.
            VStack(alignment: .leading, spacing: 5) {
                Text(document.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)

                if let labels = document.labels, !labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(labels.sorted { $0.name < $1.name }.prefix(3)) { label in
                            LabelChip(name: label.name, color: label.color)
                        }
                        // A row that silently drops labels is worse than one that admits it.
                        if labels.count > 3 {
                            Text("+\(labels.count - 3)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                }

                HStack(spacing: Theme.Spacing.tight) {
                    Text(document.createdAt.formatted(date: .abbreviated, time: .omitted))
                    if !document.isSearchable {
                        Text("·")
                        // Only stated when it is FALSE. "Searchable" on every row is a label
                        // that carries no information; its absence is the exception worth
                        // flagging, because it means search will not find this document.
                        Text("Not searchable")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
