// Ream tech spike — proves the risky part of the pipeline:
//   page image -> Vision OCR -> PDF with an INVISIBLE, correctly-positioned text layer
// Everything here is the same Vision/CoreGraphics code that runs on iOS.
//
//   swiftc -O main.swift -o ream-spike
//   ./ream-spike gen  page.png          # synthesize a realistic scanned page
//   ./ream-spike scan page.png out.pdf  # OCR it and emit a searchable PDF

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import Vision
import UniformTypeIdentifiers

// Core Text attribute keys — portable across macOS/iOS without pulling in AppKit/UIKit.
let kFont = kCTFontAttributeName as NSAttributedString.Key
let kColor = kCTForegroundColorAttributeName as NSAttributedString.Key

// MARK: - Sample page generation (stands in for a VisionKit-deskewed capture)

let sampleLines: [(String, CGFloat, Bool)] = [
    ("LAVAI LABS LLC", 58, true),
    ("1425 Foundry Street, Suite 200", 34, false),
    ("Austin, TX 78702", 34, false),
    ("", 20, false),
    ("INVOICE 2026-0814", 46, true),
    ("", 16, false),
    ("Bill To: Northgate Property Management", 34, false),
    ("Issue Date: August 8, 2026", 34, false),
    ("Terms: Net 30 — due September 7, 2026", 34, false),
    ("", 24, false),
    ("DESCRIPTION                        AMOUNT", 32, true),
    ("iOS application development         4,800.00", 30, false),
    ("Design and asset production         1,150.00", 30, false),
    ("App Store submission support          400.00", 30, false),
    ("Quarterly maintenance retainer        975.00", 30, false),
    ("", 20, false),
    ("Subtotal                            7,325.00", 30, false),
    ("Sales tax (8.25%)                     604.31", 30, false),
    ("TOTAL DUE                           7,929.31", 34, true),
    ("", 28, false),
    ("Remit payment by ACH to routing 021000021,", 28, false),
    ("account 4471903882. Reference the invoice", 28, false),
    ("number above so payment is applied correctly.", 28, false),
    ("", 24, false),
    ("Questions about this invoice should go to", 26, false),
    ("accounts@lavailabs.example within 10 days.", 26, false),
]

func generatePage(to url: URL) throws {
    let w = 1700, h = 2200  // 8.5x11 at 200dpi — typical phone-scan resolution
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "ream", code: 1)
    }
    // Slightly warm off-white, like a real scan rather than pure #FFF
    ctx.setFillColor(CGColor(red: 0.98, green: 0.975, blue: 0.965, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

    let regular = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
    let bold = CTFontCreateWithName("Helvetica-Bold" as CFString, 12, nil)
    var y = CGFloat(h) - 200
    let left: CGFloat = 150

    for (text, size, isBold) in sampleLines {
        if text.isEmpty { y -= size; continue }
        let base = isBold ? bold : regular
        let font = CTFontCreateCopyWithAttributes(base, size, nil, nil)
        let attr = NSAttributedString(string: text, attributes: [
            kFont: font,
            kColor: CGColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: left, y: y)
        CTLineDraw(line, ctx)
        y -= size * 1.55
    }

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "ream", code: 2) }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.lastPathComponent) — \(w)x\(h)")
}

// MARK: - OCR

struct OCRLine {
    let text: String
    let box: CGRect      // normalized, Vision space (origin bottom-left)
    let confidence: Float
}

func recognizeText(in image: CGImage) throws -> [OCRLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["en-US"]

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    return (request.results ?? []).compactMap { obs in
        guard let best = obs.topCandidates(1).first else { return nil }
        return OCRLine(text: best.string, box: obs.boundingBox, confidence: best.confidence)
    }
}

// MARK: - Searchable PDF

/// Re-encodes as JPEG so the PDF embeds a compressed image instead of raw bitmap data.
/// This is the difference between a 4 MB and a 400 KB 20-page scan.
func jpegCompressed(_ image: CGImage, quality: CGFloat) -> CGImage {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
    else { return image }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest),
          let src = CGImageSourceCreateWithData(data as CFData, nil),
          let out = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return image }
    return out
}

/// Draws each page image, then overlays that page's OCR lines as invisible text
/// positioned and scaled to their Vision bounding boxes.
func makeSearchablePDF(pages: [(image: CGImage, lines: [OCRLine])],
                       jpegQuality: CGFloat, to url: URL) throws {
    guard let first = pages.first else { throw NSError(domain: "ream", code: 5) }
    var mediaBox = CGRect(x: 0, y: 0, width: 612,
                          height: 612 * CGFloat(first.image.height) / CGFloat(first.image.width))
    guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        throw NSError(domain: "ream", code: 3)
    }
    for page in pages {
        try drawPage(page.image, lines: page.lines, jpegQuality: jpegQuality, in: ctx)
    }
    ctx.closePDF()
}

private func drawPage(_ image: CGImage, lines: [OCRLine],
                      jpegQuality: CGFloat, in ctx: CGContext) throws {
    // Fit to US Letter width at 72dpi in PDF points, preserving aspect.
    let pageW: CGFloat = 612
    let pageH = pageW * CGFloat(image.height) / CGFloat(image.width)
    var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)

    // Per-page media box: kCGPDFContextMediaBox takes CFData wrapping a CGRect,
    // which lets pages differ in size (mixed portrait/landscape scans).
    let boxData = withUnsafeBytes(of: &box) { Data($0) } as CFData
    ctx.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
    ctx.draw(jpegQuality < 1 ? jpegCompressed(image, quality: jpegQuality) : image, in: box)

    // PDF context origin is bottom-left, same as Vision's normalized space — no flip needed.
    // (On iOS, UIGraphicsPDFRenderer is top-left origin, so y must be flipped there.)
    let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    for line in lines where !line.text.isEmpty {
        let target = CGRect(x: line.box.minX * pageW,

                            y: line.box.minY * pageH,
                            width: line.box.width * pageW,
                            height: line.box.height * pageH)
        guard target.width > 0.5, target.height > 0.5 else { continue }

        // Measure at a reference size, then scale the font so the glyph run
        // spans the same width Vision reported. This is what makes selection
        // highlight land on the right words.
        let probe = NSAttributedString(string: line.text, attributes: [kFont: font])
        let probeWidth = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(probe), nil, nil, nil)
        guard probeWidth > 0 else { continue }
        let scaled = CTFontCreateCopyWithAttributes(font, 12 * target.width / CGFloat(probeWidth), nil, nil)

        let attr = NSAttributedString(string: line.text, attributes: [kFont: scaled])
        let ctLine = CTLineCreateWithAttributedString(attr)

        ctx.saveGState()
        ctx.setTextDrawingMode(.invisible)   // present in the text stream, never painted
        ctx.textPosition = CGPoint(x: target.minX, y: target.minY + target.height * 0.18)
        CTLineDraw(ctLine, ctx)
        ctx.restoreGState()
    }

    ctx.endPDFPage()
}

func loadImage(_ url: URL) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw NSError(domain: "ream", code: 4, userInfo: [NSLocalizedDescriptionKey: "cannot read \(url.path)"])
    }
    return img
}

// MARK: - Entry

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: ream-spike gen <out.png> | ream-spike scan <in.png> <out.pdf>")
    exit(2)
}

switch args[1] {
case "gen":
    try generatePage(to: URL(fileURLWithPath: args[2]))

case "scan":
    // ream-spike scan <quality> <out.pdf> <page1.png> [page2.png ...]
    guard args.count >= 5, let quality = Double(args[2]) else {
        print("usage: ream-spike scan <jpegQuality 0-1> <out.pdf> <page.png>...")
        exit(2)
    }
    let outURL = URL(fileURLWithPath: args[3])
    let inputs = args[4...].map { URL(fileURLWithPath: $0) }

    var pages: [(image: CGImage, lines: [OCRLine])] = []
    var totalOCRms = 0.0
    var allLines: [OCRLine] = []

    for input in inputs {
        let image = try loadImage(input)
        let t0 = Date()
        let lines = try recognizeText(in: image)
        totalOCRms += Date().timeIntervalSince(t0) * 1000
        allLines += lines
        pages.append((image, lines))
    }

    let t1 = Date()
    try makeSearchablePDF(pages: pages, jpegQuality: CGFloat(quality), to: outURL)
    let pdfMs = Date().timeIntervalSince(t1) * 1000

    let attrs = try FileManager.default.attributesOfItem(atPath: outURL.path)
    let bytes = (attrs[.size] as? Int) ?? 0
    let avgConf = allLines.isEmpty ? 0 : allLines.map(\.confidence).reduce(0, +) / Float(allLines.count)
    print("pages:      \(pages.count)  (jpeg q=\(quality))")
    print("OCR:        \(allLines.count) lines in \(String(format: "%.0f", totalOCRms)) ms " +
          "(\(String(format: "%.0f", totalOCRms / Double(pages.count))) ms/page)")
    print("PDF build:  \(String(format: "%.0f", pdfMs)) ms")
    print("avg conf:   \(String(format: "%.3f", avgConf))")
    print("size:       \(String(format: "%.0f", Double(bytes) / 1024)) KB " +
          "(\(String(format: "%.0f", Double(bytes) / 1024 / Double(pages.count))) KB/page)")

default:
    print("unknown mode \(args[1])"); exit(2)
}
