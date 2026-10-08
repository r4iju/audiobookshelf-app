import AppKit
let root = URL(fileURLWithPath: "/tmp/231-covers")
for index in 0...1 {
    let size = NSSize(width: 800, height: index == 0 ? 800 : 1100)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor(calibratedRed: index == 0 ? 0.08 : 0.32, green: 0.19, blue: 0.24, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    NSColor(calibratedRed: 0.78, green: 0.46, blue: 0.22, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 190, y: 100, width: 850, height: 850)).fill()
    NSColor(calibratedRed: 0.23, green: 0.44, blue: 0.47, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: -180, y: -150, width: 610, height: 610)).fill()
    let title = index == 0 ? "STORIES FOR\nTOMORROW" : "THE QUIET\nEVENING"
    let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 65, weight: .bold), .foregroundColor: NSColor.white]
    (title as NSString).draw(in: NSRect(x: 65, y: size.height - 400, width: 670, height: 230), withAttributes: label)
    ("AUDIOBOOKSHELF QA" as NSString).draw(at: NSPoint(x: 65, y: 80), withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.white])
    ("SYNTHETIC EDITION" as NSString).draw(at: NSPoint(x: 65, y: size.height - 80), withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.white])
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: root.appendingPathComponent("\(index).jpg"))
}
let display = (0..<61).map { ["title": String(format: "Stories for Tomorrow %02d", $0 + 1), "author": "Audiobookshelf QA"] }
try JSONSerialization.data(withJSONObject: display).write(to: root.appendingPathComponent("display.json"))
