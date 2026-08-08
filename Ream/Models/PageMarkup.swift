import Foundation
import UIKit

/// Pen colour, shared by typed text and signatures.
///
/// Four, matching what people actually sign and fill forms with, plus white. A full colour
/// picker would be a worse answer: text has to stay legible on paper, and most of a picker's
/// range is not.
///
/// **White is invisible on white paper, and that is not a bug.** It's there for the cases
/// where the page isn't white: writing on a photo, a dark scan, or covering something that
/// is. The selection outline in the editor stays visible regardless, so a white markup can
/// always be found and moved even when it can't be seen.
enum MarkupInk: String, CaseIterable, Codable, Sendable {
    case black, blue, red, white

    var displayName: String {
        switch self {
        case .black: "Black"
        case .blue: "Blue"
        case .red: "Red"
        case .white: "White"
        }
    }

    /// Whether the swatch needs an outline to be visible against a light background.
    var needsOutline: Bool { self == .white }

    /// Deliberately not pure `#000`/`#00F`. These are ink colours — a real pen on paper is
    /// never fully saturated, and a document filled in with #FF0000 looks like clip art.
    var cgColor: CGColor {
        switch self {
        case .black: CGColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        case .blue:  CGColor(red: 0.10, green: 0.22, blue: 0.55, alpha: 1)
        case .red:   CGColor(red: 0.60, green: 0.11, blue: 0.13, alpha: 1)
        // Near-white rather than #FFF: this is usually covering something, and a hairline of
        // difference from the paper is what keeps it from looking like a rendering error.
        case .white: CGColor(red: 0.99, green: 0.99, blue: 0.98, alpha: 1)
        }
    }

    var uiColor: UIColor { UIColor(cgColor: cgColor) }
}

/// Something the user placed on a page: typed text, or a drawn signature.
///
/// Positions are **normalized to the page** (0...1, origin top-left) rather than stored in
/// points. The editor works against a rasterized preview whose size depends on the device,
/// while the save path renders against the real page box — normalized coordinates are the
/// only thing that means the same in both.
struct PageMarkup: Identifiable, Equatable {
    enum Kind: Equatable {
        case text(String)
        /// Ink: a signature captured in the signing pane, or a freehand mark drawn straight
        /// onto the page. Identical data and identical treatment — only the surface it was
        /// captured on differs — so they share one case rather than duplicating the pipeline.
        /// Compared by identity, not by pixels.
        case drawing(UIImage)

        static func == (lhs: Kind, rhs: Kind) -> Bool {
            switch (lhs, rhs) {
            case (.text(let a), .text(let b)): a == b
            case (.drawing(let a), .drawing(let b)): a === b
            default: false
            }
        }
    }

    let id = UUID()
    var kind: Kind
    var pageIndex: Int
    /// Top-left of the markup, normalized to the page.
    var origin: CGPoint
    /// Width as a fraction of page width. Height follows from the content.
    var widthFraction: CGFloat
    /// Text height as a fraction of page height. Ignored for signatures.
    var fontFraction: CGFloat = 0.022
    /// Applies to both kinds. Signatures are captured as a black-on-transparent TEMPLATE and
    /// tinted at draw time, so changing the colour after signing works.
    var ink: MarkupInk = .black

    var isDrawing: Bool {
        if case .drawing = kind { return true }
        return false
    }

    var text: String {
        if case .text(let value) = kind { return value }
        return ""
    }

    var image: UIImage? {
        if case .drawing(let value) = kind { return value }
        return nil
    }
}
