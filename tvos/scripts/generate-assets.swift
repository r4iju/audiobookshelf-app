#!/usr/bin/env swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tvos/App/Assets.xcassets")
let manager = FileManager.default
let info: [String: Any] = ["author": "xcode", "version": 1]

func json(_ value: [String: Any], at directory: URL) throws {
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("Contents.json"))
}

func png(width: Int, height: Int, layer: String, to url: URL, shelf: Bool = false) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
    NSColor.clear.setFill(); bounds.fill()
    if layer == "Back" {
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.21, alpha: 1), ending: NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.07, alpha: 1))!
        gradient.draw(in: NSBezierPath(rect: bounds), angle: -30)
    } else {
        let unit = CGFloat(height) / 240
        let center = CGFloat(width) / 2
        let orange = NSColor(calibratedRed: 1, green: 0.57, blue: 0.18, alpha: 1)
        orange.setFill()
        let bookX = shelf ? center - 385 * unit : center - 76 * unit
        let baseY = CGFloat(height) * 0.3
        for (offset, bookHeight, bookWidth) in [(0.0, 90.0, 27.0), (35.0, 78.0, 31.0), (75.0, 104.0, 28.0), (111.0, 88.0, 26.0)] {
            let rect = NSRect(x: bookX + offset * unit, y: baseY, width: bookWidth * unit, height: bookHeight * unit)
            NSBezierPath(roundedRect: rect, xRadius: 4 * unit, yRadius: 4 * unit).fill()
        }
        NSColor(calibratedRed: 0.09, green: 0.1, blue: 0.13, alpha: 1).setFill()
        for y in [baseY + 20 * unit, baseY + 60 * unit] {
            NSBezierPath(roundedRect: NSRect(x: bookX + 43 * unit, y: y, width: 15 * unit, height: 4 * unit), xRadius: 2 * unit, yRadius: 2 * unit).fill()
        }
        if shelf {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            ("Audiobookshelf" as NSString).draw(at: NSPoint(x: center - 185 * unit, y: baseY + 36 * unit), withAttributes: [.font: NSFont.systemFont(ofSize: 51 * unit, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
            ("Your library. On the big screen." as NSString).draw(at: NSPoint(x: center - 182 * unit, y: baseY + 9 * unit), withAttributes: [.font: NSFont.systemFont(ofSize: 21 * unit, weight: .regular), .foregroundColor: NSColor.lightGray])
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

try json(["info": info], at: root)
let brand = root.appendingPathComponent("App Icon & Top Shelf Image.brandassets")
var assets: [[String: Any]] = []
for (name, width, height, scales) in [("App Icon", 400, 240, [1, 2]), ("App Store", 1280, 768, [1])] {
    let stack = brand.appendingPathComponent(name + ".imagestack")
    try json(["info": info, "layers": [["filename": "Front.imagestacklayer"], ["filename": "Back.imagestacklayer"]]], at: stack)
    for layer in ["Front", "Back"] {
        let directory = stack.appendingPathComponent(layer + ".imagestacklayer")
        try json(["info": info], at: directory)
        let content = directory.appendingPathComponent("Content.imageset")
        var images: [[String: Any]] = []
        try manager.createDirectory(at: content, withIntermediateDirectories: true)
        for scale in scales {
            let filename = "\(layer)-\(scale)x.png"
            var image: [String: Any] = ["filename": filename, "idiom": "tv"]
            if name == "App Icon" { image["scale"] = "\(scale)x" }
            images.append(image)
            try png(width: width * scale, height: height * scale, layer: layer, to: content.appendingPathComponent(filename))
        }
        try json(["info": info, "images": images], at: content)
    }
    assets.append(["filename": name + ".imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "\(width)x\(height)"])
}
for (name, width, role) in [("Top Shelf", 1920, "top-shelf-image"), ("Top Shelf Wide", 2320, "top-shelf-image-wide")] {
    let directory = brand.appendingPathComponent(name + ".imageset")
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    var images: [[String: Any]] = []
    for scale in [1, 2] {
        let filename = "shelf-\(scale)x.png"
        // Shelf graphics combine the same vector foreground and background.
        let background = directory.appendingPathComponent("background.png")
        let foreground = directory.appendingPathComponent("foreground.png")
        try png(width: width * scale, height: 720 * scale, layer: "Back", to: background, shelf: true)
        try png(width: width * scale, height: 720 * scale, layer: "Front", to: foreground, shelf: true)
        let bitmap = NSBitmapImageRep(data: try Data(contentsOf: background))!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSImage(contentsOf: foreground)!.draw(in: NSRect(x: 0, y: 0, width: width * scale, height: 720 * scale))
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
        try manager.removeItem(at: background); try manager.removeItem(at: foreground)
        images.append(["filename": filename, "idiom": "tv", "scale": "\(scale)x"])
    }
    try json(["info": info, "images": images], at: directory)
    assets.append(["filename": name + ".imageset", "idiom": "tv", "role": role, "size": "\(width)x720"])
}
try json(["info": info, "assets": assets], at: brand)
