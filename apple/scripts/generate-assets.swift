import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("App/Assets.xcassets")
let icon = assets.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: icon, withIntermediateDirectories: true)
let info: [String: Any] = ["version": 1, "author": "xcode"]
try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys]).write(to: assets.appendingPathComponent("Contents.json"))
var images: [[String: Any]] = []
let slots: [(String, Double, [Int])] = [
    ("iphone", 20, [2, 3]), ("iphone", 29, [1, 2, 3]), ("iphone", 40, [2, 3]), ("iphone", 60, [2, 3]),
    ("ipad", 20, [1, 2]), ("ipad", 29, [1, 2]), ("ipad", 40, [1, 2]), ("ipad", 76, [1, 2]), ("ipad", 83.5, [2]),
    ("ios-marketing", 1024, [1])
]
for (idiom, points, scales) in slots {
    for scale in scales {
        let pixels = Int(points * Double(scale))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let size = Double(pixels)
        NSColor(red: 0.80, green: 0.31, blue: 0.17, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        NSColor.white.setFill()
        // Three simple book spines retain clarity at the smallest icon sizes.
        for (x, y, width, height, rotation) in [(0.25, 0.27, 0.13, 0.46, 0.0), (0.42, 0.22, 0.14, 0.56, 0.0), (0.62, 0.28, 0.13, 0.46, 10.0)] {
            NSGraphicsContext.saveGraphicsState()
            let transform = AffineTransform(translationByX: x * size, byY: y * size)
            var tilted = transform
            tilted.rotate(byDegrees: rotation)
            (tilted as NSAffineTransform).concat()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width * size, height: height * size), xRadius: size * 0.022, yRadius: size * 0.022).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        let pointName = points == floor(points) ? String(Int(points)) : String(points)
        let filename = "Icon-\(idiom)-\(pointName)-\(scale)x.png"
        let opaque = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        opaque.draw(bitmap.cgImage!, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let png = NSBitmapImageRep(cgImage: opaque.makeImage()!)
        try png.representation(using: .png, properties: [:])!.write(to: icon.appendingPathComponent(filename))
        images.append(["idiom": idiom, "size": "\(pointName)x\(pointName)", "scale": "\(scale)x", "filename": filename])
    }
}
try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys]).write(to: icon.appendingPathComponent("Contents.json"))
