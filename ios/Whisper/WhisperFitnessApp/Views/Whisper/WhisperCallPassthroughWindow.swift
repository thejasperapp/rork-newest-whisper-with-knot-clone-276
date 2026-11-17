import UIKit

final class WhisperCallPassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let manager = WhisperCallWindowManager.shared
        if manager.minimized && !manager.tileFrame.contains(point) { return nil }
        return super.hitTest(point, with: event)
    }
}
