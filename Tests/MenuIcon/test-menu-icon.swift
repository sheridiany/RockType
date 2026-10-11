import CoreGraphics
import Foundation

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("menu icon check failed: \(message)\n".utf8))
    exit(EXIT_FAILURE)
}
guard CommandLine.arguments.count == 2,
      let document = CGPDFDocument(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL),
      let page = document.page(at: 1) else { fail("expected an icon PDF") }
let box = page.getBoxRect(.mediaBox)
guard box.width == 22, box.height == 16 else { fail("expected system-safe 22 × 16 pt canvas, got \(box)") }
let scale = 15
let width = 22 * scale
let height = 16 * scale
guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("bitmap unavailable") }
context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
context.drawPDFPage(page)
guard let storage = context.data else { fail("no pixels") }
let pixels = storage.assumingMemoryBound(to: UInt8.self)
var left = width, right = -1, bottom = height, top = -1
var cutout = 0
for row in 0..<height {
    for column in 0..<width {
        let alpha = pixels[(row * width + column) * 4 + 3]
        if alpha > 16 {
            left = min(left, column); right = max(right, column)
            bottom = min(bottom, row); top = max(top, row)
        }
        if (7 * scale..<17 * scale).contains(column), (3 * scale..<13 * scale).contains(row), alpha < 5 {
            cutout += 1
        }
    }
}
guard abs(Double(right - left + 1) / Double(scale) - 22) < 0.15,
      abs(Double(top - bottom + 1) / Double(scale) - 16) < 0.15 else { fail("badge must visibly occupy 22 × 16 pt") }
guard abs(Double(left + right) / 2 - Double(width - 1) / 2) < 1,
      abs(Double(bottom + top) / 2 - Double(height - 1) / 2) < 1 else { fail("badge must remain centered") }
guard pixels[3] == 0, cutout > 1_000 else { fail("rounded outer margin or transparent letter is missing") }
print("PDF passed: full-bleed 22 × 16 pt. Run SystemRendererProbe and installed-menu acceptance separately.")
