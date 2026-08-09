import SwiftUI

/// One placed markup, drawn over the page preview.
///
/// Sized for the finger, not for the glyphs. A one-word text markup is a few points tall,
/// and hit-testing only the drawn text made it almost impossible to grab — so the whole
/// padded box is the target, with a 44pt floor.
struct MarkupItem: View {
    let markup: PageMarkup
    let canvasSize: CGSize
    let isSelected: Bool
    let isDragging: Bool
    let isGrabbed: Bool
    /// VoiceOver's adjustable action. Pinching is not available to everyone, and removing the
    /// toolbar steppers must not remove the only non-gestural way to resize.
    let onAdjust: (CGFloat) -> Void

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minWidth: Theme.minTapTarget,
                   minHeight: Theme.minTapTarget,
                   alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.tint.opacity(isSelected ? 0.10 : 0.001))
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.tint, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            // The whole box, including the transparent padding, is grabbable.
            .contentShape(Rectangle())
            // Lifts under the finger so a grab is felt as well as seen.
            // Responds to the GRAB, not just to movement — a finger down on the item should
            // visibly take hold at the same moment the haptic says it did.
            .scaleEffect(isGrabbed ? 1.06 : 1)
            .shadow(color: .black.opacity(isGrabbed ? 0.28 : 0), radius: 8, y: 4)
            .animation(.interactiveSpring(duration: 0.18), value: isGrabbed)
            // `.overlay` does NOT grow the frame, so the hint sits below the markup without
            // enlarging its hit area or shifting its position.
            .overlay(alignment: .bottom) {
                if isSelected, !isDragging {
                    Text("Pinch to resize")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: Capsule())
                        .fixedSize()
                        // Clear of the dashed selection outline, not touching it.
                        .offset(y: 32)
                        // Hidden while dragging: it would trail the item around and obscure
                        // exactly the area being positioned.
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .accessibilityElement(children: .combine)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onAdjust(1.15)
                case .decrement: onAdjust(1 / 1.15)
                @unknown default: break
                }
            }
    }

    private var width: CGFloat { markup.widthFraction * canvasSize.width }
    private var height: CGFloat {
        guard let image = markup.image else { return 0 }
        return width * (image.size.height / max(image.size.width, 1))
    }

    @ViewBuilder
    private var content: some View {
        if let image = markup.image {
            // `.template` so the captured black strokes take the chosen ink, matching what
            // `MarkupRenderer` does when it clips to the alpha and fills.
            Image(uiImage: image.withRenderingMode(.alwaysTemplate))
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(markup.ink.cgColor))
                .frame(width: width, height: height)
        } else {
            Text(markup.text.isEmpty ? "Tap to type" : markup.text)
                .font(.system(size: max(markup.fontFraction * canvasSize.height, 9)))
                .foregroundStyle(markup.text.isEmpty
                                 ? Color.secondary : Color(markup.ink.cgColor))
                .lineLimit(1)
                .fixedSize()
        }
    }
}
