import SwiftUI
import PencilKit

/// A PencilKit surface laid exactly over the page preview, for drawing straight onto it.
///
/// Sized and positioned to match the preview so canvas points and page points are the same
/// coordinate space — the capture then converts to normalized page coordinates with a plain
/// division rather than a transform nobody can check.
struct PageDrawingCanvas: UIViewRepresentable {
    let canvas: PKCanvasView
    let ink: MarkupInk
    @Binding var isEmpty: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        // **Forced light, unlike the signature pane.** This canvas sits directly on the page
        // preview, which is a scan — white paper. In dark mode PencilKit would invert the ink
        // to white and draw invisibly on it. The signing pane can stay adaptive because its
        // background follows the appearance; this one never does.
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: ink.uiColor, width: 5)

        // **`PKCanvasView` is a `UIScrollView`, and `drawing.bounds` is in CONTENT
        // coordinates.** Left scrollable, the content origin drifts from the view origin and
        // every stroke's computed position is wrong by that offset — which put freehand marks
        // off the page entirely, while signatures were unaffected because their position is
        // fixed rather than derived from the drawing.
        //
        // Pinning scroll and zoom makes content coordinates identical to view coordinates, so
        // dividing by the canvas size is a valid conversion to page space.
        canvas.isScrollEnabled = false
        canvas.bounces = false
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.contentInset = .zero
        return canvas
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        // Live colour change: the stroke you're drawing is the colour it will be, because
        // here the surface underneath is the actual page.
        view.tool = PKInkingTool(.pen, color: ink.uiColor, width: 5)
    }

    func makeCoordinator() -> Coordinator { Coordinator(isEmpty: $isEmpty) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let isEmpty: Binding<Bool>
        init(isEmpty: Binding<Bool>) { self.isEmpty = isEmpty }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            isEmpty.wrappedValue = canvasView.drawing.strokes.isEmpty
        }
    }
}
