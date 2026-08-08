import SwiftUI
import UIKit

/// `UIActivityViewController` as a SwiftUI sheet.
///
/// `ShareLink` can't be used here because the archive doesn't exist until the button is
/// pressed — it has to be built first, then shared. This keeps the presentation inside
/// SwiftUI's own hierarchy instead of reaching through `UIApplication.connectedScenes` for
/// a root view controller, which only worked as long as the calling screen stayed a sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Identity wrapper so a freshly built file URL can drive `.sheet(item:)`.
///
/// A retroactive `Identifiable` conformance on `URL` would be visible to every file in the
/// module and to anything that later imports it — a wrapper keeps the conformance local.
struct ShareableFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
