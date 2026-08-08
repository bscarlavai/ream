import SwiftUI

/// First-run explainer. Three cards, skippable, shown once.
///
/// It exists for exactly one reason: **searching inside a scan is invisible.** It's the most
/// valuable thing Ream does and nobody expects it, because no free scanner does it — a user
/// types a word, gets nothing (because they searched before scanning), and concludes search
/// only matches filenames. The other two cards ride along because a first-run sheet is the
/// one moment anyone reads anything.
///
/// Deliberately not a tour: no "tap here", no coach marks, no permission priming. Three
/// facts and a way out.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(SupporterService.self) private var supporter
    @AppStorage("accentFinish") private var finishRaw = AccentFinish.blueprint.rawValue

    @State private var page = 0

    #if DEBUG
    /// `--onboarding-page N` jumps straight to a card. The Simulator can't swipe a TabView
    /// from the command line, so without this only the first card is ever reachable.
    private static var debugStartPage: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--onboarding-page"),
              args.count > index + 1, let page = Int(args[index + 1]) else { return 0 }
        return page
    }
    #endif

    private var finish: AccentFinish {
        AccentFinish.resolved(rawValue: finishRaw, isSupporter: supporter.isSupporter)
    }

    private var accent: Color { finish.color(for: scheme) }
    private var accentFill: Color { finish.fillColor(for: scheme) }

    private struct Card: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    private let cards = [
        Card(title: "Search inside your scans",
             body: "Ream reads the words on every page. Search for “dishwasher” and it finds the receipt, not just documents you happened to name well."),
        Card(title: "Nothing leaves your phone",
             body: "Scanning, text recognition and PDF creation all happen on this device. There's no account, no cloud, and no network access at all."),
        Card(title: "Free, with no catch",
             body: "No subscription, no ads, no watermarks, and nothing locked behind a paywall. If it saves you from a $200-a-year scanner app, you can tip."),
    ]

    /// Art is matched to the card by index rather than stored on `Card`, because each one is
    /// a different view type and a heterogeneous list would need type erasure for no gain.
    @ViewBuilder
    private func art(for index: Int) -> some View {
        switch index {
        case 0: OnboardingArt.SearchInside(accent: accent, accentFill: accentFill)
        case 1: OnboardingArt.OnDevice(accent: accent, accentFill: accentFill)
        default: OnboardingArt.NoCatch(accent: accent, accentFill: accentFill)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    cardView(card, index: index).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if page < cards.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(page < cards.count - 1 ? "Next" : "Start Scanning")
                    .font(.headline)
                    .padding(.horizontal, Theme.Spacing.large)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .reamProminent()
            .padding(.horizontal, Theme.Spacing.large)
            .padding(.bottom, Theme.Spacing.small)

            Button("Skip") { dismiss() }
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .frame(minHeight: Theme.minTapTarget)
                // Always available, on every card. An onboarding you can't leave is an ad.
                .opacity(page < cards.count - 1 ? 1 : 0)
        }
        .background(Theme.pageBackground)
        .interactiveDismissDisabled(false)
        #if DEBUG
        .onAppear { page = Self.debugStartPage }
        #endif
    }

    private func cardView(_ card: Card, index: Int) -> some View {
        VStack(spacing: Theme.Spacing.large) {
            Spacer(minLength: Theme.Spacing.medium)

            // Fixed height so the three illustrations don't shift the copy up and down as
            // you page between them.
            art(for: index)
                .frame(height: 296)

            // Fixed, not a Spacer: the art and the copy are one unit, and three expanding
            // spacers spread them to opposite ends of the screen.
            Spacer().frame(height: Theme.Spacing.section)

            VStack(spacing: Theme.Spacing.medium) {
                Text(card.title)
                    .font(.title.bold())
                    .foregroundStyle(Theme.primaryText)
                    .multilineTextAlignment(.center)

                Text(card.body)
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.large)
        }
        .padding(.horizontal, Theme.Spacing.section)
    }
}
