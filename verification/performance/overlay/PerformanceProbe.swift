#if DEBUG
import UIKit

/// Temporary measurement harness. Removed before distribution.
final class PerformanceProbe: NSObject {
    static let shared = PerformanceProbe()
    private var link: CADisplayLink?
    private var previous: CFTimeInterval?
    private var gaps: [Double] = []
    private var motion: Timer?
    private var step = 0
    private var distance: CGFloat = 0
    static func install() {
        guard CommandLine.arguments.contains("--profile-ui") else { return }
        for name in ["loft.performance.start", "loft.performance.stop"] {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, name, _, _ in
                DispatchQueue.main.async {
                    if name?.rawValue as String? == "loft.performance.start" { PerformanceProbe.shared.start() }
                    else { PerformanceProbe.shared.stop() }
                }
            }, name as CFString, nil, .deliverImmediately)
        }
    }
    private func start() {
        link?.invalidate(); previous = nil; gaps = []
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common); self.link = link
        #if os(iOS)
        motion?.invalidate(); step = 0; distance = 0
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        func scrolls(_ view: UIView) -> [UIScrollView] {
            ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrolls)
        }
        let candidates = windows.flatMap(scrolls).filter { $0.bounds.height > 200 && $0.contentSize.height > $0.bounds.height + 100 }
        guard let scroll = candidates.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else { return }
        print("[LOFT-PERF] native scroll content=\(scroll.contentSize) viewport=\(scroll.bounds.size)")
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self, weak scroll] timer in
            guard let self, let scroll, self.step < 16 else { timer.invalidate(); return }
            let direction: CGFloat = self.step < 8 ? 1 : -1
            let y = min(max(scroll.contentOffset.y + direction * scroll.bounds.height * 0.8, -scroll.adjustedContentInset.top), scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            self.distance += abs(y - scroll.contentOffset.y)
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: true)
            self.step += 1
        }
        RunLoop.main.add(timer, forMode: .common); motion = timer
        #endif
    }
    @objc private func frame(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if let previous { gaps.append((now - previous) * 1_000) }
        previous = now
    }
    private func stop() {
        link?.invalidate(); link = nil; motion?.invalidate(); motion = nil
        let sorted = gaps.sorted()
        guard !sorted.isEmpty else { return }
        let result: [String: Any] = ["scroll_steps": step, "scroll_distance": distance, "samples": sorted.count, "p95_ms": sorted[Int(Double(sorted.count - 1) * 0.95)], "p99_ms": sorted[Int(Double(sorted.count - 1) * 0.99)], "max_ms": sorted.last!, "over50ms": sorted.filter { $0 > 50 }.count]
        if let data = try? JSONSerialization.data(withJSONObject: result) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("loft-performance.json"))
            print("[LOFT-PERF] " + String(decoding: data, as: UTF8.self))
        }
    }
}
#endif
