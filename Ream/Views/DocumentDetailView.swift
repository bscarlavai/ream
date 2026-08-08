import SwiftUI
import PDFKit

struct DocumentDetailView: View {
    @Bindable var document: ScannedDocument
    @Environment(\.modelContext) private var context

    @State private var isRenaming = false
    @State private var showingLabels = false
    @State private var showingFillSign = false
    @State private var draftTitle = ""

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

    var body: some View {
        PDFViewer(url: fileURL)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(document.title)
            .navigationSubtitle(labelSummary)
            // Large, so the title is LEFT-ALIGNED on its own row. An inline title is centred
            // and shares the bar with the buttons, which is what forced them into an overflow
            // menu and truncated long names. Given its own row, a long scan title has room
            // and all four actions stay visible.
            .navigationBarTitleDisplayMode(.large)
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

                    Button {
                        draftTitle = document.title
                        isRenaming = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Rename")
                }
            }
            .sheet(isPresented: $showingLabels) {
                LabelPickerView(document: document)
            }
            .fullScreenCover(isPresented: $showingFillSign) {
                FillSignView(document: document)
            }
            .alert("Rename scan", isPresented: $isRenaming) {
                TextField("Name", text: $draftTitle)
                Button("Cancel", role: .cancel) {}
                Button("Save") { rename() }
            }
    }

    private func rename() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // Guard the write so an unchanged name doesn't dirty the model and kick off
        // a pointless @Query re-evaluation.
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
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
