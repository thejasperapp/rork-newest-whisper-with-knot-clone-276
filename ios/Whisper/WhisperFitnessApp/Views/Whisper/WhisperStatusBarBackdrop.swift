import SwiftUI
import UIKit

/// A canvas-matched fade, not a separate material rectangle at the status edge.
struct WhisperStatusBarBackdrop: UIViewRepresentable {
    let color: Color
    var blurred: Bool = false
    var blurProgress: CGFloat = 1
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func makeUIView(context: Context) -> StatusRegionView { StatusRegionView() }
    func updateUIView(_ view: StatusRegionView, context: Context) {
        let progress = min(1, max(0, blurProgress))
        // Keep the historical opaque cap for unrelated screens. Scrolling
        // roots use their own canvas color so dark/Pitch Black never turns gray.
        view.fadesEdge = blurred && !reduceTransparency
        view.cap.backgroundColor = UIColor(color)
        view.cap.alpha = blurred ? (reduceTransparency ? (progress > 0 ? 1 : 0) : progress * 0.85) : 1
        view.setNeedsLayout()
    }

    final class StatusRegionView: UIView {
        let cap: UIView = UIView()
        let fade = CAGradientLayer()
        var fadesEdge = false
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear; isUserInteractionEnabled = false
            accessibilityElementsHidden = true
            addSubview(cap)
            fade.colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor]
            fade.startPoint = CGPoint(x: 0.5, y: 0)
            fade.endPoint = CGPoint(x: 0.5, y: 1)
        }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window else { return }
            let origin = convert(bounds.origin, to: window)
            let height = min(bounds.height, max(0, window.safeAreaInsets.top - origin.y))
            let feather: CGFloat = fadesEdge ? 36 : 0
            cap.frame = CGRect(x: 0, y: 0, width: bounds.width, height: min(bounds.height, height + feather))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fade.frame = cap.bounds
            fade.locations = [0, NSNumber(value: Double(height / max(1, cap.bounds.height))), 1]
            cap.layer.mask = fadesEdge ? fade : nil
            CATransaction.commit()
        }
    }
}
