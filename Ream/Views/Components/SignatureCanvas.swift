import SwiftUI
import PencilKit

/// Draw-your-signature pane.
///
/// A **short sheet, not a full screen**. Full height gave a tall empty canvas with a
/// signature line stranded at the very bottom, which reads as "sign down there" while the
/// space you'd naturally sign in does nothing. A wide, shallow pane is the shape of a
/// signature, so the whole area is obviously the place to sign.
///
/// PencilKit rather than a hand-rolled `Path` over touch points: it already handles stroke
/// smoothing, variable width and finger input, and a signature drawn from raw samples looks
/// like a child wrote it.
struct SignatureCanvas: View {
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()
    @State private var isEmpty = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                // The rule sits about two-thirds down the PANE rather than at the bottom of
                // the screen, so there is signing room above it and it reads as a line on a
                // form rather than a footer.
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 1)
                        .padding(.horizontal, 32)
                    Spacer().frame(height: 46)
                }
                .allowsHitTesting(false)

                CanvasRepresentable(canvas: canvas, isEmpty: $isEmpty)
            }
            .navigationTitle("Sign here")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        canvas.drawing = PKDrawing()
                        isEmpty = true
                    }
                    .disabled(isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Use Signature") { capture() }
                        .disabled(isEmpty)
                }
            }
        }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.hidden)
        // Without this, a downward stroke near the top of the pane competes with the sheet's
        // own drag-to-dismiss and the sheet slides away mid-signature.
        .interactiveDismissDisabled(true)
    }

    private func capture() {
        let drawing = canvas.drawing
        let bounds = drawing.bounds
        guard !bounds.isEmpty else { return }

        // Crop to the ink, not the canvas. Exporting the whole canvas would stamp a mostly
        // transparent rectangle whose visible signature is a small patch in the middle, and
        // sizing that on the page would be guesswork.
        let padded = bounds.insetBy(dx: -12, dy: -12)
        onCapture(drawing.image(from: padded, scale: 3))
        dismiss()
    }
}

private struct CanvasRepresentable: UIViewRepresentable {
    let canvas: PKCanvasView
    @Binding var isEmpty: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput          // finger as well as Pencil
        canvas.tool = PKInkingTool(.pen, color: .black, width: 6)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        // PencilKit inverts dark ink in dark mode, so this pen draws WHITE on a dark pane —
        // which is correct here: you have to see the stroke you're making.
        //
        // Pinning the canvas to `.light` was tried and is wrong: the pane behind it is still
        // `systemBackground`, which is black in dark mode, so it meant signing in black ink
        // on a black background.
        //
        // The captured colour doesn't matter either way. `MarkupRenderer.tinted(_:with:)`
        // rebuilds the stroke from its ALPHA channel, so the drawing is a pure shape and the
        // ink colour is chosen separately, on the page.
        return canvas
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isEmpty: $isEmpty)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let isEmpty: Binding<Bool>

        init(isEmpty: Binding<Bool>) { self.isEmpty = isEmpty }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            isEmpty.wrappedValue = canvasView.drawing.strokes.isEmpty
        }
    }
}
