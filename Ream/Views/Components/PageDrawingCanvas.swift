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
