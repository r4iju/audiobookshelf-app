import UIKit
import MediaPlayer
import AVFoundation

@MainActor final class ReaderVolume {
    private let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
    private var observation: NSKeyValueObservation?
    private var generation = UUID()
    private var original: Float?
    private var baseline: Float = 0.5
    private var resetTarget: Float?
    private var action: ((Bool) -> Void)?
    func attach(to parent: UIView, action: @escaping (Bool) -> Void) {
        parent.addSubview(view)
        self.action = action
    }
    func enabled(_ enabled: Bool) {
        guard enabled != (observation != nil) else { return }
        if !enabled { stopObserving(); return }
        let session = AVAudioSession.sharedInstance()
        original = session.outputVolume
        baseline = min(max(session.outputVolume, 0.05), 0.95)
        let id = UUID(); generation = id
        observation = session.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
            guard let old = change.oldValue, let new = change.newValue else { return }
            Task { @MainActor in self?.changed(old: old, new: new, generation: id) }
        }
        if baseline != original { reset(to: baseline) }
    }
    private func changed(old: Float, new: Float, generation: UUID) {
        guard self.generation == generation, observation != nil else { return }
        if let resetTarget, abs(new - resetTarget) < 0.001 { self.resetTarget = nil; return }
        guard UIApplication.shared.applicationState == .active else { return }
        let difference = abs(new - old)
        guard difference >= 0.04 && difference <= 0.07 else { return }
        reset(to: baseline)
        action?(new > old)
    }
    private func reset(to value: Float) {
        guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
        resetTarget = value
        slider.setValue(value, animated: false)
        slider.sendActions(for: .valueChanged)
    }
    private func stopObserving() {
        generation = UUID()
        observation?.invalidate(); observation = nil
        if let original { reset(to: original) }
        original = nil; resetTarget = nil
    }
    func detach() { stopObserving(); action = nil; view.removeFromSuperview() }
}
