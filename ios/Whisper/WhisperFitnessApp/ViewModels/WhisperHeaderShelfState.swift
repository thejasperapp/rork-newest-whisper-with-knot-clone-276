import SwiftUI

@Observable @MainActor
final class WhisperHeaderShelfState {
    var height: CGFloat = 56
    private(set) var isHidden: Bool = false
    private var travel: CGFloat = 0
    private(set) var blurProgress: CGFloat = 0

    /// Independent of shelving: accessibility and programmatic scrolling still
    /// need the correct scroll-edge appearance, but must not move navigation.
    func updateOverlap(_ offset: CGFloat) {
        guard offset.isFinite else { return }
        let progress = min(1, max(0, offset / 28))
        if abs(progress - blurProgress) > 0.01 || progress == 0 || progress == 1 {
            if blurProgress != progress { blurProgress = progress }
        }
    }

    func reveal() { isHidden = false; travel = 0 }
    func resetTravel() { travel = 0 }

    func update(old: CGFloat, new: CGFloat, enabled: Bool) {
        guard enabled, old.isFinite, new.isFinite else { return }
        if new <= 32 { reveal(); return }
        let delta = new - old
        if delta.sign != travel.sign { travel = 0 }
        travel += delta
        if travel > 18 { isHidden = true; travel = 0 }
        if travel < -10 { reveal() }
    }
}
