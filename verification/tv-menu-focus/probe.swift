import UIKit

@MainActor final class MenuFocusProbe: NSObject {
    static let shared = MenuFocusProbe()
    private var link: CADisplayLink?
    private var records: [[String: Any]] = []
    private var lastWrite = 0.0
    static func install() {
        guard ProcessInfo.processInfo.arguments.contains("--probe-menu") else { return }
        shared.link = CADisplayLink(target: shared, selector: #selector(shared.sample))
        shared.link?.add(to: .main, forMode: .common)
    }
    @objc private func sample(_ link: CADisplayLink) {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where !window.isHidden {
                guard let view = UIFocusSystem.focusSystem(for: window)?.focusedItem as? UIView else { continue }
                var ancestors: [String] = []; var current: UIView? = view
                while let item = current { ancestors.append(String(describing: type(of: item))); current = item.superview }
                let record: [String: Any] = ["time": link.timestamp, "id": String(describing: ObjectIdentifier(view)), "classes": ancestors, "label": view.accessibilityLabel ?? "", "animations": view.layer.animationKeys() ?? [], "opacity": view.layer.presentation()?.opacity ?? view.layer.opacity]
                records.append(record)
            }
        }
        if link.timestamp - lastWrite > 0.5 {
            lastWrite = link.timestamp
            if let data = try? JSONSerialization.data(withJSONObject: records) { try? data.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("menu-focus.json"), options: .atomic) }
        }
    }
}
