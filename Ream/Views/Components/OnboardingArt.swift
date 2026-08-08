import SwiftUI

/// Illustrations for the onboarding cards.
///
/// A 64pt SF Symbol in a full-screen page is mostly empty space, and a glyph can only ever
/// gesture at the idea. These *show* it: the search card renders a page with a word actually
/// highlighted in it, which is the whole point being explained.
///
/// Drawn in SwiftUI rather than shipped as images so they follow the accent finish and both
/// color schemes for free, and cost nothing in the bundle.
enum OnboardingArt {

    // MARK: - Shared pieces

    /// Paper white, fixed in both schemes.
    ///
    /// **Not `systemBackground`.** That resolves to pure black in dark mode, so the sheet
    /// vanished into the page and the illustration became text lines floating in space. A
    /// sheet of paper is white whatever the phone's appearance setting is, which is also what
    /// the real thumbnails and the app icon show.
    static let paper = Color(hex: 0xFAFAF7)
    /// Ink on that paper. Fixed for the same reason: it sits on paper, not on the UI.
    static let paperInk = Color(hex: 0xB4B4AE)
    static let paperInkStrong = Color(hex: 0x8A8A83)

    /// A sheet of paper, matching the stack-of-pages metaphor in the app icon.
    private struct PaperSheet<Content: View>: View {
        var width: CGFloat = 200
        var height: CGFloat = 250
        @ViewBuilder var content: Content

        var body: some View {
            content
                .frame(width: width, height: height, alignment: .topLeading)
                .background(OnboardingArt.paper)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.subtleBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
        }
    }

    /// One line of "text" on a page. Width is a fraction of the sheet.
    private struct TextLine: View {
        var fraction: CGFloat
        var height: CGFloat = 7
        var color: Color = OnboardingArt.paperInk

        var body: some View {
            Capsule()
                .fill(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: height)
                .scaleEffect(x: fraction, y: 1, anchor: .leading)
        }
    }

    // MARK: - Card 1 — search finds words inside the page

    struct SearchInside: View {
        /// Foreground accent: for marks drawn ON the page.
        let accent: Color
        /// Fill accent: for shapes that carry a WHITE label. Light in dark mode, `accent`
        /// would be ~2:1 against white — the same trap that made the scan button illegible.
        let accentFill: Color

        var body: some View {
            ZStack(alignment: .bottomTrailing) {
                PaperSheet {
                    VStack(alignment: .leading, spacing: 11) {
                        TextLine(fraction: 0.55, height: 10, color: OnboardingArt.paperInkStrong)
                        Spacer().frame(height: 4)
                        TextLine(fraction: 0.95)
                        TextLine(fraction: 0.8)

                        // The line the search matched. This is the entire idea of the card,
                        // so it is the one element drawn in the accent.
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(accent.opacity(0.22))
                                .frame(width: 108, height: 20)
                            TextLine(fraction: 0.46, height: 7, color: accent)
                                .padding(.leading, 6)
                        }
                        .padding(.vertical, 1)

                        TextLine(fraction: 0.9)
                        TextLine(fraction: 0.65)
                        TextLine(fraction: 0.85)
                    }
                    .padding(20)
                }

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 70, height: 70)
                    .background(accentFill, in: Circle())
                    .overlay { Circle().strokeBorder(Theme.pageBackground, lineWidth: 4) }
                    .offset(x: 22, y: 14)
            }
        }
    }

    // MARK: - Card 2 — the document never leaves the device

    struct OnDevice: View {
        /// Foreground accent: for marks drawn ON the page.
        let accent: Color
        /// Fill accent: for shapes that carry a WHITE label. Light in dark mode, `accent`
        /// would be ~2:1 against white — the same trap that made the scan button illegible.
        let accentFill: Color

        var body: some View {
            ZStack(alignment: .top) {
                // Phone body, with a page tucked inside it.
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 2)
                    }
                    .frame(width: 196, height: 268)
                    .overlay(alignment: .center) {
                        PaperSheet(width: 146, height: 188) {
                            VStack(alignment: .leading, spacing: 9) {
                                TextLine(fraction: 0.6, height: 9, color: OnboardingArt.paperInkStrong)
                                Spacer().frame(height: 2)
                                TextLine(fraction: 0.95)
                                TextLine(fraction: 0.85)
                                TextLine(fraction: 0.9)
                                TextLine(fraction: 0.7)
                                TextLine(fraction: 0.5)
                            }
                            .padding(16)
                        }
                    }

                // Sits ON the boundary, because the claim is about the boundary.
                Image(systemName: "lock.fill")
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(accentFill, in: Circle())
                    .overlay { Circle().strokeBorder(Theme.pageBackground, lineWidth: 4) }
                    .offset(y: -22)
            }
        }
    }

    // MARK: - Card 3 — what the app doesn't do

    struct NoCatch: View {
        /// Foreground accent: for marks drawn ON the page.
        let accent: Color
        /// Fill accent: for shapes that carry a WHITE label. Light in dark mode, `accent`
        /// would be ~2:1 against white — the same trap that made the scan button illegible.
        let accentFill: Color

        private let absent = ["Subscription", "Ads", "Watermarks", "Account"]

        var body: some View {
            // A normal VStack element, not an overlay with an offset — the offset version
            // sat the badge directly on top of the last row.
            VStack(spacing: 14) {
                VStack(spacing: 10) {
                    ForEach(absent, id: \.self) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(.secondaryLabel))
                                .frame(width: 26, height: 26)
                                .background(Color(.tertiarySystemFill), in: Circle())

                            Text(item)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.secondaryText)
                                // Struck through because the point is their absence, not a
                                // list of features. Reads instantly without any label.
                                .strikethrough(true, color: Color(.tertiaryLabel))

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        // `systemBackground`, not `secondarySystemBackground`: the card sits
                        // on a GROUPED background, and in light mode the secondary variant is
                        // the same colour as it, so the rows vanished.
                        .background(Theme.cardBackground,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // The payoff row. Same shape as the four above so the list reads as one
                    // idea — "not this, not this, not this… but this" — rather than a list
                    // and then an unrelated badge. Taller and accent-filled so it's clearly
                    // the answer and not a fifth absence.
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(accentFill)
                            .frame(width: 30, height: 30)
                            .background(.white, in: Circle())

                        Text("Everything, free")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(accentFill,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 4)
                }
            }
            .frame(width: 256)
        }
    }
}
