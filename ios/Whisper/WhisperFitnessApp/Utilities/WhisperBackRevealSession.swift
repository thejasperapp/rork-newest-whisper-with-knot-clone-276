import UIKit

/// Presentation-local snapshots keep the previous screen visible without popping early or restarting its work.
@MainActor
final class WhisperBackRevealSession {
    private let overlay: UIView
    private let card = UIView()
    private let foreground: UIView
    private let scrim = UIView()
    private let back = UIImageView()
    private let topInset: CGFloat
    private let localTransition: Bool
    private let vertical: Bool
    private var extent: CGFloat { vertical ? overlay.bounds.height : overlay.bounds.width }
    private weak var departure: UIView?
    private weak var destination: UIView?
    private var animator: UIViewPropertyAnimator?
    private var finished: Bool = false
    private var leaving: Bool = false
    private var onFinish: ((Bool) -> Void)?
    private let generation = AccountStorage.generation

    init?(surface: UIView, predecessor: UIView, departure: UIView? = nil, localTransition: Bool = false, scope: CGRect? = nil, vertical: Bool = false) {
        guard surface.bounds.width > 0, surface.bounds.height > 0,
              predecessor.bounds.width > 0, predecessor.bounds.height > 0 else { return nil }
        guard let predecessorImage = (predecessor as? UIImageView)?.image
            ?? WhisperNavigationSnapshots.shared.image(for: predecessor)
            ?? WhisperNavigationSnapshots.captureAttached(predecessor) else { return nil }
        self.departure = departure ?? surface
        self.destination = predecessor
        self.localTransition = localTransition
        self.vertical = vertical
        let frame = scope ?? surface.bounds
        foreground = surface.resizableSnapshotView(from: frame, afterScreenUpdates: false, withCapInsets: .zero) ?? UIImageView(image: WhisperNavigationSnapshots.render(surface, rect: frame))
        overlay = WhisperTransitionCover(frame: frame)
        topInset = surface.window?.safeAreaInsets.top ?? surface.safeAreaInsets.top
        // Never load an unrelated controller or snapshot another window/account.
        back.image = predecessorImage
        back.frame = overlay.bounds; back.contentMode = .scaleToFill
        back.clipsToBounds = true
        overlay.backgroundColor = predecessor.backgroundColor ?? .systemBackground
        overlay.clipsToBounds = true
        overlay.isUserInteractionEnabled = true
        overlay.accessibilityElementsHidden = true
        overlay.addSubview(back)
        scrim.frame = overlay.bounds; scrim.backgroundColor = .black
        overlay.addSubview(scrim)
        card.frame = overlay.bounds
        foreground.frame = card.bounds
        foreground.layer.cornerCurve = .continuous
        foreground.clipsToBounds = true
        card.addSubview(foreground)
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowRadius = 28; card.layer.shadowOffset = CGSize(width: -10, height: 0)
        overlay.addSubview(card)
        surface.addSubview(overlay)
        update(translation: 0)
    }

    func update(translation: CGFloat) {
        guard !finished, generation == AccountStorage.generation else { remove(); return }
        let p = WhisperBackRevealStyle.progress(translation: translation, width: extent)
        card.transform = CGAffineTransform(translationX: vertical ? 0 : extent * p, y: vertical ? extent * p : 0)
        back.transform = CGAffineTransform(translationX: UIAccessibility.isReduceMotionEnabled ? 0 : WhisperBackRevealStyle.predecessorOffset(width: overlay.bounds.width, progress: p), y: 0)
        foreground.layer.cornerRadius = WhisperBackRevealStyle.radius(topInset: topInset, progress: p)
        card.layer.shadowOpacity = Float(0.12 * min(1, p * 4))
        scrim.alpha = WhisperBackRevealStyle.scrim(progress: p)
    }

    func settle(leaving: Bool, velocity: CGFloat = 0, completion: @escaping (Bool) -> Void) {
        guard !finished else { completion(false); return }
        onFinish = completion
        self.leaving = leaving
        let remaining = (leaving ? extent : 0) - (vertical ? card.transform.ty : card.transform.tx)
        let speed = abs(remaining) > 1 ? max(-8, min(8, velocity / remaining)) : 0
        let timing = UISpringTimingParameters(dampingRatio: 1, initialVelocity: CGVector(dx: speed, dy: 0))
        let animation = UIViewPropertyAnimator(duration: UIAccessibility.isReduceMotionEnabled ? 0.12 : 0.32, timingParameters: timing)
        animator = animation
        animation.addAnimations { self.update(translation: leaving ? self.extent : 0) }
        animation.addCompletion { [weak self] position in
            guard let self, !self.finished else { return }
            let valid = position == .end && self.generation == AccountStorage.generation
            self.finish(valid: valid)
        }
        animation.startAnimation()
    }

    func remove() { finish(valid: false) }

    private func finish(valid: Bool) {
        guard !finished else { return }
        finished = true
        let completion = onFinish; onFinish = nil
        if animator?.state == .active { animator?.stopAnimation(true) }
        animator = nil
        if valid, leaving, let window = overlay.window {
            // Keep the revealed destination above the outgoing controller until
            // its nonanimated dismissal has committed. Removing it first flashes the DM.
            let frame = overlay.convert(overlay.bounds, to: window)
            window.addSubview(overlay)
            overlay.frame = frame
            // The snapshot can be content-scoped and exclude the old Back button.
            // Consume rapid follow-up taps across the whole window while the
            // destination commits, rather than exposing a post under that button.
            let touchShield = WhisperTransitionCover(frame: window.bounds)
            touchShield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            touchShield.backgroundColor = .clear
            touchShield.accessibilityElementsHidden = true
            window.addSubview(touchShield)
            UIView.performWithoutAnimation { completion?(true); window.layoutIfNeeded() }
            _ = WhisperRevealHandoff(cover: overlay, touchShield: touchShield, departure: departure, destination: destination,
                local: localTransition, generation: generation)
        } else {
            overlay.removeFromSuperview()
            completion?(valid)
        }
    }
}
