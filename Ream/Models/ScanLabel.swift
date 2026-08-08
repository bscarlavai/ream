import SwiftUI
import SwiftData

/// A user-created category. A document can carry any number of them.
///
/// Named `ScanLabel`, not `Label`, because SwiftUI already owns that name and the collision
/// is silent and maddening — `Label("Taxes")` would resolve to the wrong type inside a view.
@Model
final class ScanLabel {
    var id: UUID = UUID()
    var name: String = ""
    /// Index into `LabelColor.allCases`. Stored as an Int rather than the enum so a future
    /// palette change can't fail to decode an existing row.
    var colorIndex: Int = 0
    var createdAt: Date = Date.now

    /// The inverse side of the many-to-many.
    ///
    /// **Delete rule is `.nullify`** — the SwiftData default for a to-many, and it must stay
    /// that way. `.cascade` here would mean deleting a label destroys every document filed
    /// under it, which is a data-loss bug wearing the costume of a tidy-up feature.
    @Relationship(deleteRule: .nullify, inverse: \ScannedDocument.labels)
    var documents: [ScannedDocument]?

    init(name: String, colorIndex: Int) {
        self.id = UUID()
        self.name = name
        self.colorIndex = colorIndex
        self.createdAt = .now
    }

    var color: LabelColor {
        LabelColor.allCases.indices.contains(colorIndex)
            ? LabelColor.allCases[colorIndex]
            : .slate
    }

    /// How many documents carry this label. `documents` is optional because SwiftData
    /// models every relationship as nullable for CloudKit compatibility.
    var documentCount: Int { documents?.count ?? 0 }
}

/// The label palette.
///
/// Chips render as the color's text on a 15% tint of itself over the card surface, so the
/// pair that matters is color-vs-its-own-tint, not color-vs-background. Every value below
/// clears 4.5:1 on that measure in both light and dark. Ratios in comments.
enum LabelColor: String, CaseIterable, Codable, Sendable {
    case slate, blue, teal, green, amber, orange, red, purple

    var displayName: String {
        switch self {
        case .slate: "Slate"
        case .blue: "Blue"
        case .teal: "Teal"
        case .green: "Green"
        case .amber: "Amber"
        case .orange: "Orange"
        case .red: "Red"
        case .purple: "Purple"
        }
    }

    func color(for scheme: ColorScheme) -> Color {
        let dark = scheme == .dark
        switch (self, dark) {
        case (.slate, false):  return Color(hex: 0x3F4750)  // 7.34
        case (.slate, true):   return Color(hex: 0xAEB7C2)  // 6.22
        case (.blue, false):   return Color(hex: 0x1B5A88)  // 5.80
        case (.blue, true):    return Color(hex: 0x74B6E4)  // 5.85
        case (.teal, false):   return Color(hex: 0x14625F)  // 5.65
        case (.teal, true):    return Color(hex: 0x63BFB8)  // 5.94
        case (.green, false):  return Color(hex: 0x2A6344)  // 5.66
        case (.green, true):   return Color(hex: 0x7BC49B)  // 6.18
        case (.amber, false):  return Color(hex: 0x7A5218)  // 5.50
        case (.amber, true):   return Color(hex: 0xE0AE5F)  // 6.26
        case (.orange, false): return Color(hex: 0x8A4318)  // 5.74
        case (.orange, true):  return Color(hex: 0xEA9A63)  // 5.73
        case (.red, false):    return Color(hex: 0x8F2B2B)  // 6.38
        case (.red, true):     return Color(hex: 0xE58585)  // 5.09
        case (.purple, false): return Color(hex: 0x5B3A80)  // 6.92
        case (.purple, true):  return Color(hex: 0xB794DF)  // 5.21
        }
    }

    /// Chip background. The 15% the contrast figures above were computed against —
    /// changing it invalidates every ratio in this file.
    static let tintOpacity: Double = 0.15
}
