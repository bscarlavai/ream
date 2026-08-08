import SwiftUI

/// Centralized design tokens. Semantic names only — no view should reference a raw
/// color, radius, or spacing value directly.
enum Theme {

    // MARK: - Color

    static let pageBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)

    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    /// Passes WCAG AA at body sizes, unlike `.tertiaryLabel`, which does not.
    static let tertiaryText = Color(.secondaryLabel).opacity(0.85)

    /// Form inputs need more contrast than decorative dividers — keep them distinct.
    static let fieldBorder = Color(.separator).opacity(0.12)
    static let subtleBorder = Color(.separator).opacity(0.08)

    // MARK: - Spacing

    enum Spacing {
        static let tight: CGFloat = 6
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let section: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        static let card: CGFloat = 14
        static let control: CGFloat = 10
    }

    /// Minimum tap target per Apple's HIG. Apply to anything small and interactive.
    static let minTapTarget: CGFloat = 44
}

/// The accent finishes. Blueprint is the default and the only one a non-supporter gets;
/// the rest come with the Supporter unlock.
///
/// Named as **desk materials**, never presented as a color picker — the same move that
/// works in PokeArtist. A "pick your favorite color" grid reads as a toy; a pencil, a
/// blueprint, a manila folder and a red correction pen read as a stationery drawer,
/// which is what a scanning app is about.
///
/// **Every value was computed, not eyeballed** — and the number that matters is not the
/// obvious one. `.glassProminent` composites the tint under a translucent glass veil, so
/// the label sits on a LIGHTER, hazier fill than the raw hex. Measuring the raw color
/// overstates contrast by roughly 40%: the first Manila (`#8A5A2B`) measured a
/// comfortable 5.87:1 against white and rendered at **3.98:1** — a real failure that
/// looked fine on paper. Every value here clears 4.5:1 *after* modelling an 18% veil,
/// against both canvases.
///
/// This also rules out the vivid blues. `#1268B0` pops hardest and lands at 4.05:1
/// glassed; `#17507A` is the deepest blue that still reads as blue and survives.
enum AccentFinish: String, CaseIterable, Codable, Sendable {
    case blueprint, graphite, manila, redPen, chalkboard

    var displayName: String {
        switch self {
        case .graphite: "Graphite"
        case .blueprint: "Blueprint"
        case .manila: "Manila"
        case .redPen: "Red Pen"
        case .chalkboard: "Chalkboard"
        }
    }

    /// What the material actually is, shown under the swatch.
    var materialNote: String {
        switch self {
        case .graphite: "No. 2 pencil"
        case .blueprint: "Cyanotype blue"
        case .manila: "Folder stock"
        case .redPen: "Correction ink"
        case .chalkboard: "Schoolroom green"
        }
    }

    /// Only Blueprint is free.
    var requiresSupporter: Bool { self != .blueprint }

    /// The ONE place a stored finish is resolved against entitlement.
    ///
    /// Every screen must go through this rather than reading `@AppStorage("accentFinish")`
    /// and trusting it. The guard originally lived only in `RootView`, so the app tint fell
    /// back correctly while Settings and the finish picker went on showing — and letting you
    /// re-select — a locked finish. Anyone who supported, chose Chalkboard, then refunded
    /// kept it on every screen except the one that mattered.
    static func resolved(rawValue: String, isSupporter: Bool) -> AccentFinish {
        let stored = AccentFinish(rawValue: rawValue) ?? .blueprint
        return (stored.requiresSupporter && !isSupporter) ? .blueprint : stored
    }

    /// The accent as a FILLED control background, with a white label on top.
    ///
    /// A second value is needed because the two roles pull opposite ways in dark mode, and
    /// the first version got this wrong. `color(for:)` goes light in dark mode so an icon
    /// reads against a near-black canvas — but a prominent button fills with the tint and
    /// puts a **white** label on it regardless of scheme. Light fill + white label measured
    /// ~2:1: the scan button was nearly illegible.
    ///
    /// (The original model assumed the system would pick a black label on a light fill in
    /// dark mode. It does not.)
    ///
    /// A fill has to satisfy two constraints at once:
    ///   - white label on it   >= 4.5:1
    ///   - pill against ~black >= 3:1  (WCAG 1.4.11, non-text UI component)
    /// which leaves a narrow window. Values below sit mid-window. Light mode reuses the
    /// foreground value, which was already dark enough to carry white.
    ///
    /// **Every filled/prominent button in the app uses this**, never `color(for:)` — see
    /// `View.reamProminent()`.
    func fillColor(for scheme: ColorScheme) -> Color {
        guard scheme == .dark else { return color(for: .light) }
        switch self {
        // white / vs-black
        case .blueprint:  return Color(hex: 0x2170A6)  // 5.34 / 3.93
        case .graphite:   return Color(hex: 0x5D6672)  // 5.82 / 3.61
        case .manila:     return Color(hex: 0x8F5D2C)  // 5.57 / 3.77
        case .redPen:     return Color(hex: 0xB33838)  // 5.93 / 3.54
        case .chalkboard: return Color(hex: 0x387C5C)  // 4.99 / 4.21
        }
    }

    func color(for scheme: ColorScheme) -> Color {
        let dark = scheme == .dark
        switch (self, dark) {
        // Ratios below are canvas / glassed-label — see the note above on why the
        // second number is the one that decides.
        case (.graphite, false):   return Color(hex: 0x23272E)  // 13.43 / 8.34
        case (.graphite, true):    return Color(hex: 0xB8C0CC)  // 11.45 / 7.70
        case (.blueprint, false):  return Color(hex: 0x17507A)  //  7.63 / 5.31
        case (.blueprint, true):   return Color(hex: 0x6FB4E3)  //  9.31 / 6.39
        case (.manila, false):     return Color(hex: 0x6B451F)  //  7.54 / 5.24
        case (.manila, true):      return Color(hex: 0xD9A867)  //  9.75 / 6.66
        case (.redPen, false):     return Color(hex: 0x8E2828)  //  7.58 / 5.57
        case (.redPen, true):      return Color(hex: 0xE38080)  //  7.67 / 5.31
        case (.chalkboard, false): return Color(hex: 0x275C43)  //  6.97 / 4.94
        case (.chalkboard, true):  return Color(hex: 0x77C09B)  //  9.80 / 6.65
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Light/dark override.
///
/// Following the system is the right default, but a scanning app gets used in bright rooms
/// and in bed, and "the document is a white rectangle either way" makes the surrounding
/// chrome a genuine preference rather than a cosmetic one.
enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// `nil` means "don't override", which is what `.preferredColorScheme` wants for System.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The one prominent-button treatment in the app.
///
/// Exists so "filled accent button" is a single decision rather than a per-screen one. It
/// reads the finish itself, so no call site has to remember that a FILL uses
/// `fillColor(for:)` and not `color(for:)` — getting that wrong is what made the dark-mode
/// scan button illegible.
private struct ReamProminent: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(SupporterService.self) private var supporter
    @AppStorage("accentFinish") private var finishRaw = AccentFinish.blueprint.rawValue

    var glass: Bool

    private var tint: Color {
        AccentFinish.resolved(rawValue: finishRaw, isSupporter: supporter.isSupporter)
            .fillColor(for: scheme)
    }

    func body(content: Content) -> some View {
        Group {
            if glass {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.borderedProminent)
            }
        }
        .tint(tint)
    }
}

extension View {
    /// Primary action styling. `glass: true` for toolbar pills (Liquid Glass), false for
    /// in-content buttons.
    func reamProminent(glass: Bool = false) -> some View {
        modifier(ReamProminent(glass: glass))
    }
}
