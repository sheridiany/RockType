import AppKit
import CoreText

// The system menu keeps image widths up to 22 pt, but squeezes wider images to 16 pt.
// A 24 pt page therefore made the R narrower. Use a full-bleed 22×16 pt page.
// SystemRendererProbe exercises that actual transform without changing any input source.
// Keep the native 16 pt HEIGHT: the earlier square 24 pt canvas sat too low in IMK.
guard CommandLine.arguments.count == 2 else { fatalError("usage: generate-menu-icon.swift output.pdf") }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
var page = CGRect(x: 0, y: 0, width: 22, height: 16)
guard let context = CGContext(output as CFURL, mediaBox: &page, nil) else { fatalError("cannot create PDF") }
// Match ABC's 12 pt semibold system lettering, including its width/optical axes.
// These are public font-descriptor attributes; no private framework is used here.
let descriptor = NSFont.systemFont(ofSize: 12, weight: .semibold).fontDescriptor
  .addingAttributes([.variation: [0x77647468: 110.0, 0x6f70737a: 16.0]]) // wdth, opsz
guard let face = NSFont(descriptor: descriptor, size: 12) else { fatalError("Missing system font") }
let font = face as CTFont
var character: UniChar = 82 // R, in the system font rather than the old small custom silhouette.
var glyph: CGGlyph = 0
guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
      let letter = CTFontCreatePathForGlyph(font, glyph, nil) else { fatalError("missing system R glyph") }
let bounds = letter.boundingBoxOfPath
var placement = CGAffineTransform(translationX: 11 - bounds.midX, y: 8 - bounds.midY)
guard let centered = letter.copy(using: &placement) else { fatalError("cannot center glyph") }
context.beginPDFPage(nil)
context.setFillColor(CGColor(gray: 0, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 22, height: 16),
                       cornerWidth: 4.5, cornerHeight: 4.5, transform: nil))
context.addPath(centered)
// Transparent letter and counter, allowing AppKit to tint the template in both appearances.
context.drawPath(using: .eoFill)
context.endPDFPage()
context.closePDF()
