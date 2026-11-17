import SwiftUI
import UIKit

/// UIKit owns the entire transform: pinch centroid, two-finger translation,
/// inertial panning and edge bounce never compete with independent SwiftUI offsets.
struct WhisperPhotoZoomSurface: UIViewRepresentable {
    let image: UIImage
    let isActive: Bool
    var reduceMotion: Bool = false
    let onZoomChanged: (Bool) -> Void
    var onSingleTap: (() -> Void)?

    func makeUIView(context: Context) -> WhisperPhotoZoomScrollView {
        let view = WhisperPhotoZoomScrollView()
        view.zoomChanged = onZoomChanged
        view.singleTap = onSingleTap
        view.reduceMotion = reduceMotion
        view.setImage(image)
        return view
    }

    func updateUIView(_ view: WhisperPhotoZoomScrollView, context: Context) {
        view.zoomChanged = onZoomChanged
        view.singleTap = onSingleTap
        view.reduceMotion = reduceMotion
        view.setImage(image)
        if !isActive { view.resetZoom() }
    }

    static func dismantleUIView(_ view: WhisperPhotoZoomScrollView, coordinator: ()) {
        view.zoomChanged = nil
        view.singleTap = nil
        view.delegate = nil
    }
}

final class WhisperPhotoZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let photo = UIImageView()
    private var viewport: CGSize = .zero
    private var reportedZoom = false
    var zoomChanged: ((Bool) -> Void)?
    var singleTap: (() -> Void)?
    var reduceMotion = false

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 8
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        decelerationRate = .fast
        photo.contentMode = .scaleAspectFit
        photo.isAccessibilityElement = true
        photo.accessibilityLabel = "Photo"
        photo.accessibilityHint = "Pinch to zoom at your fingers. Drag to explore the enlarged photo."
        addSubview(photo)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Zoom in", target: self, selector: #selector(accessibleZoomIn)),
            UIAccessibilityCustomAction(name: "Reset zoom", target: self, selector: #selector(accessibleReset))
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: UIImage) {
        guard photo.image !== image else { return }
        resetZoom()
        photo.image = image
        viewport = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, viewport != bounds.size,
              let image = photo.image, image.size.width > 0, image.size.height > 0 else { return }
        viewport = bounds.size
        setZoomScale(1, animated: false)
        let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
        photo.transform = .identity
        photo.frame = CGRect(origin: .zero, size: CGSize(width: image.size.width * fit, height: image.size.height * fit))
        contentSize = photo.bounds.size
        contentOffset = .zero
        centerPhoto()
        // Geometry changes are a reset, not a scroll gesture.
        reportZoom(false)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // At fit size, leave single-finger paging/dismissal to the enclosing viewer.
        if gestureRecognizer === panGestureRecognizer, zoomScale <= 1.01, !isZooming { return false }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        reportZoom(true)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPhoto() }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        reportZoom(scale > 1.01)
    }

    private func centerPhoto() {
        photo.center = CGPoint(x: max(contentSize.width, bounds.width) / 2,
                               y: max(contentSize.height, bounds.height) / 2)
    }

    private func reportZoom(_ zoomed: Bool) {
        guard reportedZoom != zoomed else { return }
        reportedZoom = zoomed
        // A reset can occur inside updateUIView/layout. Never mutate SwiftUI
        // state synchronously there; discard callbacks superseded by another gesture.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.reportedZoom == zoomed else { return }
            self.zoomChanged?(zoomed)
        }
    }

    func resetZoom() {
        if zoomScale != 1 { setZoomScale(1, animated: false) }
        if contentOffset != .zero { contentOffset = .zero }
        centerPhoto()
        reportZoom(false)
    }

    @objc private func toggleZoom(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > 1.01 {
            setZoomScale(1, animated: !reduceMotion)
        } else {
            zoomAround(recognizer.location(in: photo))
        }
    }

    private func zoomAround(_ point: CGPoint) {
        guard photo.bounds.width > 0, photo.bounds.height > 0 else { return }
        let target: CGFloat = min(maximumZoomScale, max(2.5, zoomScale * 1.6))
        let size = CGSize(width: bounds.width / target, height: bounds.height / target)
        reportZoom(true)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                        width: size.width, height: size.height), animated: !reduceMotion)
    }

    @objc private func tapped() { singleTap?() }
    @objc private func accessibleZoomIn() -> Bool {
        zoomAround(CGPoint(x: photo.bounds.midX, y: photo.bounds.midY)); return true
    }
    @objc private func accessibleReset() -> Bool { resetZoom(); return true }
}
