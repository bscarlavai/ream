import SwiftUI
import PDFKit

struct DocumentDetailView: View {
    @Bindable var document: ScannedDocument
    @Environment(\.modelContext) private var context

    @State private var isRenaming = false
    @State private var draftTitle = ""
    @State private var showingLabels = false
    @State private var showingFillSign = false
    /// Bumped when the file on disk changes, to force `PDFView` to re-read it.
    @State private var revision = 0

    private var fileURL: URL {
        DocumentStore.shared.url(for: document.fileName)
    }

    /// Labels as a comma-joined subtitle rather than a row of chips.
    ///
    /// The chip bar cost a full row of vertical space to show one or two short words, and
    /// on a phone that row competes with the document itself. `navigationSubtitle` (iOS 26)
    /// puts the same information in space the nav bar already reserves.
    private var labelSummary: String {
        (document.labels ?? [])
            .sorted { $0.name < $1.name }
            .map(\.name)
            .joined(separator: " · ")
    }

    /// Title and labels, with the rename affordance attached to the title itself.
    ///
    /// A pencil alone in the toolbar never said WHAT it edited — the document's name or its
    /// contents. Sitting against the title, it can only mean one thing.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                draftTitle = document.title
                isRenaming = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    // No icon, deliberately.
                    //
                    // `navigationTitle($binding)` — the system's own editable document title
                    // — was rendered side by side with this to check what it draws, and the
                    // answer is NOTHING: plain title text, visually identical to a title you
                    // can't edit. The affordance is simply that tapping works, the same as
                    // renaming in Files or Pages.
                    //
                    // A pencil was tried at two weights and a chevron after it; all fought
                    // the bold title and were wide enough to wrap onto a line of their own.
                    // Matching the system costs nothing and adds no chrome. The binding API
                    // itself is unusable here only because it hands the toolbar to a system
                    // menu and collapses the actions into an overflow.
                    Text(document.title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename \(document.title)")

            if !labelSummary.isEmpty {
                Text(labelSummary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.bottom, Theme.Spacing.small)
        .background(.bar)
    }

    var body: some View {
        PDFViewer(url: fileURL, revision: revision)
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            // The title is drawn in `header`, not by the navigation bar.
            //
            // `.navigationTitle($document.title)` looked ideal — a tappable title with a
            // native Rename menu — but on iOS it takes the toolbar over for its own menu and
            // collapses the trailing buttons into a "…" overflow, which is precisely what
            // this screen was changed to avoid. Owning the header keeps both: a left-aligned
            // title that visibly invites a tap, and the actions on show.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Share sits in its own glass group; the three document actions form a
                // second. Splitting them is what keeps the icons concentric — three or four
                // packed into ONE capsule press against its rounded ends.
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: fileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingFillSign = true
                    } label: {
                        Image(systemName: "signature")
                    }
                    .accessibilityLabel("Fill and sign")

                    Button {
                        showingLabels = true
                    } label: {
                        Image(systemName: "tag")
                    }
                    .accessibilityLabel("Labels")

                }
            }
            .sheet(isPresented: $showingLabels) {
                LabelPickerView(document: document)
            }
            .fullScreenCover(isPresented: $showingFillSign) {
                FillSignView(document: document)
            }
            #if DEBUG
            .task {
                if LaunchArgument.isPresent(LaunchArgument.showFillSign) {
                    showingFillSign = true
                }
            }
            #endif
            // `PDFView` caches by URL, and saving markups rewrites the SAME path — so
            // without an explicit nudge the viewer kept showing the pre-markup document
            // until the screen was left and re-entered.
            .onChange(of: showingFillSign) { _, isShowing in
                if !isShowing { revision += 1 }
            }
            // The title binding writes straight through to the model, so persistence and the
            // manifest have to be driven from the change rather than from a Save button.
            .alert("Rename scan", isPresented: $isRenaming) {
                TextField("Name", text: $draftTitle)
                Button("Cancel", role: .cancel) {}
                Button("Save") { rename() }
            }
    }

    private func rename() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // Guard the write so an unchanged name doesn't dirty the model and kick off a
        // pointless @Query re-evaluation everywhere the title appears.
        guard !trimmed.isEmpty, trimmed != document.title else { return }
        document.title = trimmed
        try? context.save()
        LibraryManifest.rebuild(from: context)
    }
}

/// Thin PDFKit wrapper. PDFView gives us selection, search and Quick Look parity
/// with the rest of iOS — all of which depend on the invisible text layer being right.
private struct PDFViewer: UIViewRepresentable {
    let url: URL
    /// Changes when the file at `url` has been rewritten in place.
    let revision: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        // PDFView defaults to a black surround, which in dark mode reads as a void the page
        // floats in rather than a surface it rests on.
        //
        // `.systemGroupedBackground` looks like the obvious choice and is WRONG here: in
        // dark mode it resolves to pure black, so it changes nothing. `.secondarySystemBackground`
        // is #1C1C1E dark / #F2F2F7 light — lifted enough to separate the page from the
        // chrome in both schemes.
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        // Comparing URLs is not enough: markups are saved over the same path, so the URL is
        // unchanged while the bytes are not. `revision` is what says "re-read it".
        if view.document?.documentURL != url || context.coordinator.revision != revision {
            context.coordinator.revision = revision
            view.document = PDFDocument(url: url)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var revision = -1
    }
}
