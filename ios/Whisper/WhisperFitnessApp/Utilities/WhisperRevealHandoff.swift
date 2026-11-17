import UIKit

/// Holds the committed predecessor until it is attached and has crossed two
/// display/layout boundaries. The deadline only recovers refused navigation.
@MainActor
final class WhisperRevealHandoff: NSObject {
    private let cover: UIView
    private let touchShield: UIView
    private let earliestFinish: CFTimeInterval = CACurrentMediaTime() + 0.25
    private weak var departure: UIView?
    private weak var destination: UIView?
    private let local: Bool
    private let generation: UUID
    private let deadline: CFTimeInterval = CACurrentMediaTime() + 0.8
    private var readyFrames: Int = 0
    private var link: CADisplayLink?

    init(cover: UIView, touchShield: UIView, departure: UIView?, destination: UIView?, local: Bool, generation: UUID) {
        self.cover = cover; self.touchShield = touchShield; self.departure = departure; self.destination = destination
        self.local = local; self.generation = generation
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        self.link = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        guard cover.window != nil, generation == AccountStorage.generation,
              UIApplication.shared.applicationState == .active, CACurrentMediaTime() < deadline else { finish(); return }
        // A cached predecessor image is a render source, not the live destination.
        // Once the departure is detached, the window itself is the readiness boundary.
        let target = local ? departure : ((destination is UIImageView && destination?.window == nil) ? cover.window : destination)
        if (local || departure?.window == nil), let target, target.window === cover.window,
           target.bounds.width > 0, target.bounds.height > 0 {
            target.setNeedsLayout(); target.layoutIfNeeded()
            readyFrames += 1
            if readyFrames >= 2, CACurrentMediaTime() >= earliestFinish { finish() }
        } else { readyFrames = 0 }
    }

    private func finish() {
        link?.invalidate(); link = nil
        cover.removeFromSuperview()
        touchShield.removeFromSuperview()
    }
}
