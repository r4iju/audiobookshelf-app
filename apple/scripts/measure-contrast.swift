// Measures text contrast inside one element of a simulator screenshot, as evidence for an accessibility audit finding.
//   swift apple/scripts/measure-contrast.swift <screenshot.png> <scale> <x> <y> <width> <height>
// The rectangle is in points, as XCUIElement.frame reports it. The background is the most common colour in the
// rectangle; the foreground is the darkest-or-lightest opposite colour, taken at the 90th percentile of contrast
// against the background so anti-aliased edges and single stray pixels do not decide the result. Prints both colours
// and the WCAG 2 contrast ratio.
import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments.dropFirst().map { $0 }
guard arguments.count == 6, let scale = Double(arguments[1]), let x = Double(arguments[2]), let y = Double(arguments[3]),
      let width = Double(arguments[4]), let height = Double(arguments[5]) else {
    FileHandle.standardError.write("usage: measure-contrast.swift <png> <scale> <x> <y> <width> <height>\n".data(using: .utf8)!)
    exit(2)
}
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[0]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { exit(2) }
let pixelWidth = image.width, pixelHeight = image.height
var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
let context = CGContext(data: &pixels, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

struct RGB: Hashable { let r: Int, g: Int, b: Int }
func luminance(_ c: RGB) -> Double {
    func channel(_ v: Int) -> Double { let s = Double(v) / 255; return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
}
func ratio(_ a: RGB, _ b: RGB) -> Double {
    let (l1, l2) = (luminance(a), luminance(b))
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
}
func hex(_ c: RGB) -> String { String(format: "#%02X%02X%02X", c.r, c.g, c.b) }

var counts: [RGB: Int] = [:]
var samples: [RGB] = []
let left = max(0, Int(x * scale)), top = max(0, Int(y * scale))
let right = min(pixelWidth, Int((x + width) * scale)), bottom = min(pixelHeight, Int((y + height) * scale))
for row in top..<bottom {
    for column in left..<right {
        let offset = (row * pixelWidth + column) * 4
        let color = RGB(r: Int(pixels[offset]), g: Int(pixels[offset + 1]), b: Int(pixels[offset + 2]))
        counts[color, default: 0] += 1
        samples.append(color)
    }
}
guard let background = counts.max(by: { $0.value < $1.value })?.key else { exit(2) }
let opposite = samples.filter { ratio($0, background) > 1.15 }.sorted { ratio($0, background) < ratio($1, background) }
guard !opposite.isEmpty else { print("background \(hex(background)); no text pixels found"); exit(0) }
let foreground = opposite[min(opposite.count - 1, Int(Double(opposite.count) * 0.9))]
print(String(format: "background %@ foreground %@ contrast %.2f:1 (%d text pixels of %d)", hex(background), hex(foreground), ratio(foreground, background), opposite.count, samples.count))
