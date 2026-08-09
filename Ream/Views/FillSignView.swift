import SwiftUI
import SwiftData
import PDFKit
import PencilKit

/// Fill in a scanned form and sign it.
///
/// Deliberately **free placement**, not field detection. A scan of paper has no form fields
/// to fill — there is nothing there but pixels — so detecting where the blanks are is a
/// computer-vision problem that will be wrong some of the time. Tapping where you want the
/// text is never wrong, and it's what the fill-and-sign feature people pay Adobe for
/// actually does.
///
/// The editor positions markups against a rasterized preview; saving re-renders from the
/// untouched original so the invisible OCR layer survives. See `MarkupRenderer`.
struct FillSignView: View {
    let document: ScannedDocument

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var markups: [PageMarkup] = []
    @State private var pageIndex = 0
    @State private var pageCount = 1
    @State private var preview: UIImage?
    @State private var canvasSize: CGSize = .zero

    @State private var selectedID: UUID?
    @State private var editingID: UUID?
    @State private var draftText = ""
    @State private var showingSignature = false
    @State private var isDrawingMode = false
    @State private var drawCanvas = PKCanvasView()
    @State private var drawIsEmpty = true
    /// The current pen. Applies to new markups, and retints whatever is selected — signatures
    /// included, since they're captured as a template.
    @State private var ink: MarkupInk = .black
    @State private var isSaving = false
    /// Origin captured when a drag begins.
    ///
    /// `DragGesture.translation` is cumulative from the START of the gesture, so adding it to
    /// the markup's CURRENT origin each frame applies the whole offset again on top of an
    /// already-moved item. The result compounds every frame and the markup shoots off the
    /// page on the smallest movement.
    @State private var dragStartOrigin: CGPoint?
    @State private var draggingID: UUID?
    /// Set the instant a finger lands on a markup, before any movement. This is what the
    /// grab haptic fires on.
    @State private var grabbedID: UUID?
    /// Whether the item was already selected when this touch began, so a release without
    /// movement can tell "select it" from "open the editor".
    @State private var wasSelectedAtGrab = false

    /// Points of movement before a touch stops being a tap and becomes a drag.
    private static let dragThreshold: CGFloat = 4

    /// Size at the start of a pinch, so the scale factor is applied to a fixed base.
    /// `MagnifyGesture.magnification` is cumulative from the start of the gesture, the same
    /// trap `dragStartOrigin` exists for.
    @State private var resizeStartFont: CGFloat?
    @State private var resizeStartWidth: CGFloat?

    private static let fontRange: ClosedRange<CGFloat> = 0.008...0.10
    private static let widthRange: ClosedRange<CGFloat> = 0.05...0.95
    @State private var suggestions: [FieldSuggester.Suggestion] = []
    @State private var showSuggestions = true

    /// The pristine scan. Every render starts here, so re-saving can't compound: moving a
    /// signature twice must not leave a ghost of where it was first flattened.
    private var sourceURL: URL { MarkupStore.sourceURL(for: document.fileName) }

    private var pageMarkups: [PageMarkup] {
        markups.filter { $0.pageIndex == pageIndex }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvas
                if pageCount > 1 { pager }
            }
            .background(Theme.pageBackground)
            .navigationTitle("Fill & Sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingSignature) {
                SignatureCanvas { image in addSignature(image) }
            }
            .alert("Text", isPresented: Binding(
                get: { editingID != nil },
                set: { if !$0 { editingID = nil } }
            )) {
                TextField("Type here", text: $draftText)
                Button("Cancel", role: .cancel) { cancelEdit() }
                Button("Done") { commitEdit() }
            }
            .onChange(of: ink) { _, newInk in
                guard let selectedID,
                      let index = markups.firstIndex(where: { $0.id == selectedID })
                else { return }
                markups[index].ink = newInk
            }
            .task {
                // Restore whatever was applied last time, so this is an edit and not a
                // fresh start on a page that already has your text welded to it.
                if markups.isEmpty {
                    markups = MarkupStore.decode(document.markupData)
                }
                await loadPage()
            }
            .onChange(of: pageIndex) { _, _ in Task { await loadPage() } }
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geometry in
            ZStack {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .background(
                            GeometryReader { imageGeometry in
                                // The image is letterboxed inside the available space, so the
                                // markup coordinate system must be the IMAGE's frame, not the
                                // container's — otherwise every tap lands offset.
                                Color.clear.onAppear { canvasSize = imageGeometry.size }
                                    .onChange(of: imageGeometry.size) { _, new in
                                        canvasSize = new
                                    }
                            }
                        )
                        .overlay { suggestionLayer }
                        .overlay { markupLayer.allowsHitTesting(!isDrawingMode) }
                        .overlay { drawingLayer }
                        .contentShape(Rectangle())
                        // Pinch anywhere resizes the SELECTION. Requiring the pinch to land
                        // on the markup meant covering the thing you were trying to size with
                        // your own fingers, and small markups were nearly impossible to hit.
                        // Selection already says what you mean; the gesture needn't repeat it.
                        .simultaneousGesture(resizeGesture)
                        .onTapGesture { location in
                            // Tapping empty space deselects; it does not place anything.
                            // Placement is an explicit toolbar action, so a stray tap while
                            // reading can never scatter text across a form.
                            selectedID = nil
                            _ = location
                        }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Theme.Spacing.medium)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// Faint targets over the blanks Vision's text boxes imply. Tapping one drops a text
    /// markup exactly there, already sized to the line.
    @ViewBuilder
    private var suggestionLayer: some View {
        if showSuggestions, !suggestions.isEmpty {
            ZStack(alignment: .topLeading) {
                ForEach(suggestions) { suggestion in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.tint.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.tint.opacity(0.45),
                                              style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                        .frame(width: suggestion.widthFraction * canvasSize.width,
                               height: max(suggestion.fontFraction * canvasSize.height * 1.8, 22))
                        .offset(x: suggestion.origin.x * canvasSize.width,
                                y: suggestion.origin.y * canvasSize.height)
                        .onTapGesture { fill(suggestion) }
                        .accessibilityLabel("Fill field after \(suggestion.label)")
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        }
    }

    /// The freehand surface, exactly over the page.
    @ViewBuilder
    private var drawingLayer: some View {
        if isDrawingMode, canvasSize.width > 0 {
            PageDrawingCanvas(canvas: drawCanvas, ink: ink, isEmpty: $drawIsEmpty)
                .frame(width: canvasSize.width, height: canvasSize.height)
        }
    }

    private var markupLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach(pageMarkups) { markup in
                MarkupItem(markup: markup,
                           canvasSize: canvasSize,
                           isSelected: markup.id == selectedID,
                           isDragging: markup.id == draggingID,
                           isGrabbed: markup.id == grabbedID,
                           onAdjust: { resizeSelected(by: $0) })
                    // Placed by offset from the top-left rather than `.position`, which
                    // centres on a frame whose size changes with the padding — so the item
                    // drifted as its hit area grew.
                    .offset(x: markup.origin.x * canvasSize.width,
                            y: markup.origin.y * canvasSize.height)
                    .gesture(grabGesture(for: markup))
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        // Fires on GRAB, not on movement. Waiting for the drag to start meant the app felt
        // unresponsive for the moment between putting a finger down and it taking hold.
        .sensoryFeedback(.impact(weight: .light), trigger: grabbedID)
    }

    /// One gesture for touch-down, drag and tap.
    ///
    /// Previously a separate `.onTapGesture` and `DragGesture(minimumDistance: 4)` competed:
    /// the tap could only be recognised after the drag declined the touch, so nothing
    /// acknowledged the finger until it had already moved. `minimumDistance: 0` means this
    /// takes the touch immediately — the grab is felt at once, and a release that never
    /// travelled far is interpreted as a tap here rather than by a second recogniser.
    private func grabGesture(for markup: PageMarkup) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let index = markups.firstIndex(where: { $0.id == markup.id }) else { return }

                if grabbedID != markup.id {
                    wasSelectedAtGrab = selectedID == markup.id
                    grabbedID = markup.id
                    selectedID = markup.id
                    // Captured once, at touch-down. `translation` is cumulative from here, so
                    // anchoring to the CURRENT origin each frame would compound and fling the
                    // markup off the page.
                    dragStartOrigin = markup.origin
                }

                guard canvasSize.width > 0, canvasSize.height > 0 else { return }
                let distance = hypot(value.translation.width, value.translation.height)
                guard distance > Self.dragThreshold else { return }

                draggingID = markup.id
                let start = dragStartOrigin ?? markup.origin
                let dx = value.translation.width / canvasSize.width
                let dy = value.translation.height / canvasSize.height
                markups[index].origin = CGPoint(
                    x: min(max(start.x + dx, 0), 0.98),
                    y: min(max(start.y + dy, 0), 0.98)
                )
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if distance <= Self.dragThreshold {
                    // Never moved: this was a tap. First tap selects, a second opens the
                    // editor — so grabbing something to move it doesn't summon the keyboard.
                    if wasSelectedAtGrab, !markup.isDrawing {
                        draftText = markup.text
                        editingID = markup.id
                    }
                }
                grabbedID = nil
                draggingID = nil
                dragStartOrigin = nil
            }
    }

    /// Pinch anywhere on the page to resize the selected markup.
    ///
    /// Chosen over a corner handle because a handle needs the item's measured on-screen size
    /// to know what it's resizing FROM — and a text markup is intrinsically sized, so that
    /// number doesn't exist without a measurement pass. A pinch reports a scale factor
    /// directly, which is all the maths needs.
    ///
    /// The toolbar's A- / A+ buttons cover the same ground one-handed, and for anyone who
    /// doesn't think to pinch.
    private var resizeGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // Drawing mode owns the canvas; a pinch there is not a resize.
                guard !isDrawingMode,
                      let selectedID,
                      let index = markups.firstIndex(where: { $0.id == selectedID })
                else { return }

                if resizeStartFont == nil {
                    resizeStartFont = markups[index].fontFraction
                    resizeStartWidth = markups[index].widthFraction
                }
                guard let startFont = resizeStartFont,
                      let startWidth = resizeStartWidth else { return }

                // `magnification` is cumulative from the start of the gesture, so it must be
                // applied to the size captured then — the same trap as `dragStartOrigin`.
                let scale = value.magnification
                if markups[index].isDrawing {
                    markups[index].widthFraction =
                        min(max(startWidth * scale, Self.widthRange.lowerBound),
                            Self.widthRange.upperBound)
                } else {
                    markups[index].fontFraction =
                        min(max(startFont * scale, Self.fontRange.lowerBound),
                            Self.fontRange.upperBound)
                }
            }
            .onEnded { _ in
                resizeStartFont = nil
                resizeStartWidth = nil
            }
    }

    /// Steps the selected markup's size.
    ///
    /// No longer has toolbar buttons — a pair of magnifying glasses in the bar never
    /// explained what they applied to, and the "pinch to resize" hint under the selection
    /// teaches the gesture instead. Kept because it backs the VoiceOver adjustable action,
    /// which is the one case that genuinely can't pinch.
    private func resizeSelected(by factor: CGFloat) {
        guard let selectedID,
              let index = markups.firstIndex(where: { $0.id == selectedID }) else { return }
        if markups[index].isDrawing {
            markups[index].widthFraction =
                min(max(markups[index].widthFraction * factor, Self.widthRange.lowerBound),
                    Self.widthRange.upperBound)
        } else {
            markups[index].fontFraction =
                min(max(markups[index].fontFraction * factor, Self.fontRange.lowerBound),
                    Self.fontRange.upperBound)
        }
    }

    // MARK: - Pager

    private var pager: some View {
        HStack {
            Button {
                pageIndex = max(0, pageIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(pageIndex == 0)

            Spacer()
            Text("Page \(pageIndex + 1) of \(pageCount)")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Spacer()

            Button {
                pageIndex = min(pageCount - 1, pageIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(pageIndex >= pageCount - 1)
        }
        .padding(.horizontal, Theme.Spacing.large)
        .frame(height: Theme.minTapTarget)
    }

    // MARK: - Toolbar

    // Split in two because `@ToolbarContentBuilder` tops out at 10 elements, and the bottom
    // bar alone now carries tools, a field toggle, ink, size and delete.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        topBarContent
        bottomBarContent
    }

    @ToolbarContentBuilder
    private var topBarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Save") { save() }
                // Enabled with zero markups on purpose: removing them all and saving is how
                // you get the clean scan back.
                .disabled(isSaving)
        }
    }

    @ToolbarContentBuilder
    private var bottomBarContent: some ToolbarContent {
        if isDrawingMode {
            drawingBarContent
        } else {
            editingBarContent
        }
    }

    /// A separate bar while drawing. Leaving the placement tools visible would offer actions
    /// that can't apply to strokes that don't exist as a markup yet.
    @ToolbarContentBuilder
    private var drawingBarContent: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Button("Cancel", role: .cancel) {
                drawCanvas.drawing = PKDrawing()
                drawIsEmpty = true
                isDrawingMode = false
            }
        }
        ToolbarSpacer(.fixed, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) { inkMenu }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button {
                withAnimation { commitDrawing() }
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .disabled(drawIsEmpty)
        }
    }

    // Split again for the same 10-element builder limit: tools on one side, options on the
    // other.
    @ToolbarContentBuilder
    private var editingBarContent: some ToolbarContent {
        toolsBarContent
        optionsBarContent
    }

    @ToolbarContentBuilder
    private var toolsBarContent: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Button {
                addText()
            } label: {
                Label("Text", systemImage: "textformat")
            }
        }
        ToolbarSpacer(.fixed, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button {
                showingSignature = true
            } label: {
                Label("Signature", systemImage: "signature")
            }
        }
        ToolbarSpacer(.fixed, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button {
                selectedID = nil
                withAnimation { isDrawingMode = true }
            } label: {
                Label("Draw", systemImage: "scribble")
            }
        }
    }

    @ToolbarContentBuilder
    private var optionsBarContent: some ToolbarContent {
        if !suggestions.isEmpty {
            ToolbarSpacer(.fixed, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button {
                    withAnimation { showSuggestions.toggle() }
                } label: {
                    Label("Fields", systemImage: showSuggestions
                          ? "rectangle.dashed" : "rectangle.dashed.and.paperclip")
                }
            }
        }
        ToolbarSpacer(.fixed, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) { inkMenu }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button(role: .destructive) {
                if let selectedID {
                    markups.removeAll { $0.id == selectedID }
                    self.selectedID = nil
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedID == nil)
        }
    }

    /// Shared by the editing bar and the drawing bar.
    private var inkMenu: some View {
        Menu {
            Picker("Ink", selection: $ink) {
                ForEach(MarkupInk.allCases, id: \.self) { option in
                    Label {
                        Text(option.displayName)
                    } icon: {
                        Image(uiImage: option.swatchImage)
                    }
                    .tag(option)
                }
            }
        } label: {
            // An ink drop, filled with the current colour.
            //
            // A bare circle was ambiguous — it read as decoration or a disabled control
            // rather than something to tap. A droplet says "ink" on its own, so the colour
            // can go back to being carried by the fill instead of by a text label.
            //
            // Layered fill + outline, always, so WHITE ink is still a visible button. That
            // was the failure that made the earlier tinted-glyph version unusable.
            ZStack {
                Image(systemName: "drop.fill")
                    .foregroundStyle(Color(ink.cgColor))
                Image(systemName: "drop")
                    .foregroundStyle(Color(.separator))
            }
            .font(.body)
        }
        .accessibilityLabel("Ink colour, currently \(ink.displayName)")
    }

    // MARK: - Actions

    private func loadPage() async {
        if let document = PDFDocument(url: sourceURL) {
            pageCount = max(document.pageCount, 1)
        }
        // Rendered at a fixed generous width; SwiftUI scales it to fit.
        preview = MarkupRenderer.pagePreview(pdfAt: sourceURL, pageIndex: pageIndex, width: 1200)
        await loadSuggestions()
    }

    /// Re-runs OCR for line boxes.
    ///
    /// The transcript is stored on the document but the per-line RECTANGLES are not, and
    /// positions are the entire point here. A page costs ~200ms, which is unnoticeable
    /// against opening an editor, and it avoids growing the schema for data used on one
    /// screen.
    private func loadSuggestions() async {
        suggestions = []
        guard let cgImage = preview?.cgImage,
              let page = try? await OCRService.recognize(image: cgImage) else { return }
        suggestions = FieldSuggester.suggestions(from: page)
    }

    private func fill(_ suggestion: FieldSuggester.Suggestion) {
        var markup = PageMarkup(kind: .text(""),
                                pageIndex: pageIndex,
                                origin: suggestion.origin,
                                widthFraction: suggestion.widthFraction)
        markup.fontFraction = suggestion.fontFraction
        markup.ink = ink
        markups.append(markup)
        selectedID = markup.id
        draftText = ""
        editingID = markup.id
    }

    private func addText() {
        // Placed at a consistent spot rather than at a tap: the user has to drag it into
        // position anyway, and "appears where you can see it" beats "appears where you last
        // touched", which is often under your own thumb.
        var markup = PageMarkup(kind: .text(""),
                                pageIndex: pageIndex,
                                origin: CGPoint(x: 0.15, y: 0.4),
                                widthFraction: 0.5)
        markup.fontFraction = 0.022
        markup.ink = ink
        markups.append(markup)
        selectedID = markup.id
        draftText = ""
        editingID = markup.id
    }

    /// Turns whatever was drawn into a markup and leaves drawing mode.
    ///
    /// Captured at the strokes' own bounds rather than the whole canvas: the bounds ARE the
    /// mark's position and size, so no separate placement step is needed — which is the point
    /// of drawing on the page instead of in a pane.
    private func commitDrawing() {
        defer {
            drawCanvas.drawing = PKDrawing()
            drawIsEmpty = true
            isDrawingMode = false
        }
        let drawing = drawCanvas.drawing
        let bounds = drawing.bounds
        guard !bounds.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return }

        let padded = bounds.insetBy(dx: -6, dy: -6)
        // Clamped so a mark can never land outside the page. An off-page markup is invisible
        // AND unselectable, so it can't even be deleted — the user just sees nothing and has
        // no way to find out why.
        let origin = CGPoint(
            x: min(max(padded.minX / canvasSize.width, 0), 0.95),
            y: min(max(padded.minY / canvasSize.height, 0), 0.95)
        )
        var markup = PageMarkup(kind: .drawing(drawing.image(from: padded, scale: 3)),
                                pageIndex: pageIndex,
                                origin: origin,
                                widthFraction: min(padded.width / canvasSize.width, 1))
        markup.ink = ink
        markups.append(markup)
        selectedID = markup.id
    }

    private func addSignature(_ image: UIImage) {
        var markup = PageMarkup(kind: .drawing(image),
                                pageIndex: pageIndex,
                                origin: CGPoint(x: 0.15, y: 0.6),
                                widthFraction: 0.35)
        markup.ink = ink
        markups.append(markup)
        selectedID = markup.id
    }

    private func commitEdit() {
        guard let editingID, let index = markups.firstIndex(where: { $0.id == editingID })
        else { return }
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // An empty text markup would render as nothing and be undeletable, since there'd
            // be no visible target to tap.
            markups.remove(at: index)
            selectedID = nil
        } else {
            markups[index].kind = .text(trimmed)
        }
        self.editingID = nil
    }

    private func cancelEdit() {
        if let editingID, let index = markups.firstIndex(where: { $0.id == editingID }),
           markups[index].text.isEmpty {
            markups.remove(at: index)
            selectedID = nil
        }
        self.editingID = nil
    }

    private func save() {
        isSaving = true
        // Take a copy of the untouched scan before the first flatten. After this the main
        // file is derived and the original is the source of record.
        MarkupStore.preserveOriginalIfNeeded(fileName: document.fileName)

        guard let data = MarkupRenderer.render(pdfAt: sourceURL, markups: markups) else {
            isSaving = false
            return
        }
        Task {
            do {
                _ = try await DocumentStore.shared.write(data, to: document.fileName)
                // The thumbnail is now a picture of the unfilled form.
                await ThumbnailService.shared.invalidate(fileName: document.fileName)
            } catch {
                isSaving = false
                return
            }
            await MainActor.run {
                document.markupData = MarkupStore.encode(markups)
                try? context.save()
                LibraryManifest.rebuild(from: context)
                isSaving = false
                dismiss()
            }
        }
    }
}
