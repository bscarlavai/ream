import SwiftUI
import VisionKit

/// SwiftUI wrapper around Apple's document camera — the same scanner Notes uses.
///
/// Edge detection, perspective correction, multi-page capture and the color/grayscale/
/// B&W filters all come from the system. There is no third-party scanning SDK here and
/// there doesn't need to be.
///
/// Known limits of `VNDocumentCameraViewController`, all of which we handle ourselves
/// after the fact rather than fighting the controller: no page cap, no post-capture
/// reorder/rotate, no custom UI strings.
struct DocumentCameraView: UIViewControllerRepresentable {
    /// Called with the captured pages, in scan order. Empty if the user cancelled.
    let onFinish: ([UIImage]) -> Void
    /// Called if the scanner itself fails (hardware unavailable, permission revoked mid-scan).
    let onFailure: (Error) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onFailure: onFailure, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: ([UIImage]) -> Void
        private let onFailure: (Error) -> Void
        private let dismiss: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void,
             onFailure: @escaping (Error) -> Void,
             dismiss: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onFailure = onFailure
            self.dismiss = dismiss
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            // `scan` is only valid for the lifetime of this callback, so pull every
            // page out now rather than holding the scan object.
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            dismiss()
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            dismiss()
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            dismiss()
            onFailure(error)
        }
    }
}
