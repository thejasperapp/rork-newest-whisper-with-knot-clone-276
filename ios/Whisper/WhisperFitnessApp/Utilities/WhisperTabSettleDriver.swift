import UIKit

/// Display-synchronized settling keeps UIKit page transforms and selection handoff
/// on the same timeline; no SwiftUI animation completion can race the page layers.
@MainActor
final class WhisperTabSettleDriver: NSObject {
    private var link: CADisplayLink?
    private var started: CFTimeInterval = 0
    private var duration: Double = 0.3
    private var sample: ((CGFloat) -> Void)?
    private var completion: (() -> Void)?

    func start(duration: Double, sample: @escaping (CGFloat) -> Void, completion: @escaping () -> Void) {
        stop()
        self.duration = duration
        self.sample = sample
        self.completion = completion
        started = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        self.link = link
        link.add(to: .main, forMode: .common)
    }

    func stop() {
        link?.invalidate(); link = nil
        sample = nil; completion = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let t = min(1, max(0, (link.targetTimestamp - started) / duration))
        // Monotonic ease-out: no bounce, overshoot or backwards final frame.
        let eased = 1 - pow(1 - t, 3)
        sample?(CGFloat(eased))
        if t >= 1 {
            let finish = completion
            stop()
            finish?()
        }
    }
}
