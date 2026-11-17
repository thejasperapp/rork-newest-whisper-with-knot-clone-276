import UIKit

/// Owns interruption cleanup even after its animation session has finished and
/// the snapshot temporarily lives in the window during a navigation commit.
final class WhisperTransitionCover: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard window != nil else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(clearForInterruption), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clearForInterruption), name: Notification.Name("WhisperMeetingAccountWillChange"), object: nil)
    }
    @objc func clearForInterruption() { removeFromSuperview() }
}
