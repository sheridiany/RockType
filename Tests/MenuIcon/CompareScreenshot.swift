import CoreGraphics
import Foundation
import ImageIO

// Compare real menu pixels, not PDF metadata. Regions are x,y,width,height in image pixels.
// Usage: swift Tests/MenuIcon/CompareScreenshot.swift screenshot.png ax ay aw ah rx ry rw rh
let arguments = CommandLine.arguments
let lightBadge = arguments.last == "--light-badge"
precondition(arguments.count == (lightBadge ? 11 : 10), "expected screenshot and two four-number regions, optional --light-badge")
let url = URL(fileURLWithPath: arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("cannot read screenshot") }
func badge(at offset: Int) -> (Int, Int) {
    let values = arguments[offset..<(offset + 4)].map { Double($0)! }
    let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    guard let crop = image.cropping(to: rect),
          let context = CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8,
                                  bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("invalid region") }
    context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
    let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
    var left = crop.width, right = -1, top = crop.height, bottom = -1
    for row in 0..<crop.height {
        for column in 0..<crop.width {
            let index = (row * crop.width + column) * 4
            let matches = lightBadge
                ? min(pixels[index], pixels[index + 1], pixels[index + 2]) > 175
                : max(pixels[index], pixels[index + 1], pixels[index + 2]) < 75
            if pixels[index + 3] > 200, matches {
                left = min(left, column); right = max(right, column)
                top = min(top, row); bottom = max(bottom, row)
            }
        }
    }
    precondition(right >= left, "no badge found; check polarity and exclude text/checkmarks")
    return (right - left + 1, bottom - top + 1)
}
let abc = badge(at: 2), roarkt = badge(at: 6)
print("ABC: \(abc.0)×\(abc.1) px; R: \(roarkt.0)×\(roarkt.1) px")
guard abs(abc.0 - roarkt.0) <= 2, abs(abc.1 - roarkt.1) <= 2 else {
    print("FAIL: installed menu badge dimensions differ")
    exit(1)
}
print("PASS: actual ABC/R menu badges match within 2 pixels")
