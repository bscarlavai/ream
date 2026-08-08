import SwiftUI

/// First page of a scan, drawn as a small sheet of paper.
///
/// Loads asynchronously and holds its frame from the first layout pass, so a list of these
/// doesn't reflow as thumbnails arrive — rows jumping while you scroll is worse than rows
/// that are briefly blank.
struct DocumentThumbnail: View {
    let fileName: String
    var pageCount: Int = 1

    @State private var image: UIImage?

    private static let size = ThumbnailService.size

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                // Not a spinner. A one-page render takes a few ms; a spinner that appears and
                // vanishes that fast is noise, where a blank sheet reads as the page itself.
                Rectangle().fill(Theme.pageBackground)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Theme.subtleBorder, lineWidth: 0.5)
        }
        // A whisper of a contact shadow, so the thumbnail reads as paper on a surface rather
        // than a flat swatch. Any heavier and a list of them looks embossed.
        .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
        .overlay(alignment: .bottomTrailing) {
            if pageCount > 1 {
                Text("\(pageCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(3)
            }
        }
        .task(id: fileName) {
            guard image == nil else { return }
            let loaded = await ThumbnailService.shared.thumbnail(for: fileName)
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        }
    }
}
