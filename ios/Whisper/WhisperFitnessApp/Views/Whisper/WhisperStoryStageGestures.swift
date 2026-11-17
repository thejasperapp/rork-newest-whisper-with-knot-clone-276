import SwiftUI
import UIKit

/// What a stage gesture is acting on — a sticker (by id) or the background
/// photo (Instagram's pinch-to-shrink recompose).
enum StoryGestureTarget: Equatable {
    case sticker(String)
    case background
}

/// UIKit-backed gesture router for the story stage.
///
/// Why UIKit: SwiftUI attaches gestures to individual sticker views, so a
/// pinch only registers when BOTH fingers land on the sticker — small photo
/// stickers were nearly impossible to resize (one finger off the sticker
/// meant the pinch went to the background photo instead — the "very weird"
/// resize). One set of recognizers over the whole stage fixes that: the
/// first touch picks the target by hit-testing the sticker frames, then
/// pan + pinch + rotate all drive that target simultaneously, anchored at
/// the finger centroid, with incremental deltas (no `@GestureState` reset
/// jump at the end and no minimum-distance hop at the start).
struct StoryStageGestureOverlay: UIViewRepresentable {
    /// Hit-test in stage coordinates — returns the topmost sticker under the
    /// point, or nil for the background.
    var isEnabled: Bool = true
    let hitTest: (CGPoint) -> String?
    let onBegin: (StoryGestureTarget) -> Void
    /// Incremental pan delta (stage points).
    let onPan: (StoryGestureTarget, CGSize) -> Void
    /// Incremental scale factor + the pinch centroid (stage points).
    let onPinch: (StoryGestureTarget, CGFloat, CGPoint) -> Void
    /// Incremental rotation delta (radians) + the rotation centroid.
    let onRotate: (StoryGestureTarget, CGFloat, CGPoint) -> Void
    /// All recognizers finished — the last known finger location.
    let onEnd: (StoryGestureTarget, CGPoint) -> Void
    var onCancel: (StoryGestureTarget, CGPoint) -> Void = { _, _ in }
    let onTap: (StoryGestureTarget) -> Void
    let onLongPress: (StoryGestureTarget) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator

        let rotate = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRotate(_:)))
        rotate.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.delegate = context.coordinator

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        longPress.allowableMovement = 8
        longPress.delegate = context.coordinator

        // A tap must wait for the long press to fail so a held finger never
        // double-fires as tap + menu.
        tap.require(toFail: longPress)

        let observer = WhisperStoryTouchObserver()
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false
        observer.delaysTouchesEnded = false
        observer.onFirstTouch = { [weak coordinator = context.coordinator] point in coordinator?.beginTouches(at: point) }
        observer.onLastTouch = { [weak coordinator = context.coordinator] cancelled in coordinator?.finishTouches(cancelled: cancelled) }
        [observer, pan, pinch, rotate, tap, longPress].forEach { view.addGestureRecognizer($0) }
        context.coordinator.host = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        if uiView.isUserInteractionEnabled && !isEnabled {
            for gesture in uiView.gestureRecognizers ?? [] {
                (gesture as? WhisperStoryTouchObserver)?.cancelEditing()
            }
            context.coordinator.finishTouches(cancelled: true)
        }
        uiView.isUserInteractionEnabled = isEnabled
        for gesture in uiView.gestureRecognizers ?? [] { gesture.isEnabled = isEnabled }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.finishTouches(cancelled: true)
        for gesture in uiView.gestureRecognizers ?? [] {
            if let observer = gesture as? WhisperStoryTouchObserver { observer.cancelEditing(); observer.onFirstTouch = nil; observer.onLastTouch = nil }
            uiView.removeGestureRecognizer(gesture)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: StoryStageGestureOverlay
        weak var host: UIView?

        private var target: StoryGestureTarget?
        private var activeRecognizers: Set<ObjectIdentifier> = []
        private var beganTransform: Bool = false
        private var didTransform: Bool = false
        private var wasCancelled: Bool = false
        private var lastTranslation: CGPoint = .zero
        private var lastScale: CGFloat = 1
        private var lastRotation: CGFloat = 0
        private var lastLocation: CGPoint = .zero

        init(parent: StoryStageGestureOverlay) {
            self.parent = parent
        }

        // MARK: Target resolution

        func beginTouches(at point: CGPoint) {
            if beganTransform { finishTouches(cancelled: true) }
            target = parent.hitTest(point).map { .sticker($0) } ?? .background
            didTransform = false; wasCancelled = false; beganTransform = false
            activeRecognizers.removeAll(); lastLocation = point
        }

        func finishTouches(cancelled: Bool) {
            guard beganTransform else { return }
            beganTransform = false; activeRecognizers.removeAll()
            if let target {
                if cancelled || wasCancelled || !parent.isEnabled { parent.onCancel(target, lastLocation) }
                else { parent.onEnd(target, lastLocation) }
            }
            wasCancelled = wasCancelled || cancelled
            // Retain target and transform suppression until the next physical touch sequence.
        }

        func recognizerBegan(_ recognizer: UIGestureRecognizer, at point: CGPoint) {
            activeRecognizers.insert(ObjectIdentifier(recognizer))
            lastLocation = point
            guard !beganTransform, let target else { return }
            beganTransform = true
            parent.onBegin(target)
        }

        func recognizerEnded(_ recognizer: UIGestureRecognizer) {
            guard activeRecognizers.remove(ObjectIdentifier(recognizer)) != nil else { return }
            wasCancelled = wasCancelled || recognizer.state == .cancelled
        }

        // MARK: Handlers

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let host else { return }
            let location = g.location(in: host)
            switch g.state {
            case .began:
                lastTranslation = .zero
                recognizerBegan(g, at: location)
            case .changed:
                guard parent.isEnabled, let t = target else { return }
                let tr = g.translation(in: host)
                let delta = CGSize(width: tr.x - lastTranslation.x, height: tr.y - lastTranslation.y)
                lastTranslation = tr
                lastLocation = location
                if abs(delta.width) > 0.01 || abs(delta.height) > 0.01 {
                    didTransform = true
                    parent.onPan(t, delta)
                }
            case .ended, .cancelled, .failed:
                lastLocation = location
                recognizerEnded(g)
            default:
                break
            }
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard let host else { return }
            let location = g.location(in: host)
            switch g.state {
            case .began:
                lastScale = 1
                recognizerBegan(g, at: location)
            case .changed:
                guard parent.isEnabled, let t = target else { return }
                let factor = g.scale / max(lastScale, 0.0001)
                lastScale = g.scale
                lastLocation = location
                if abs(factor - 1) > 0.0005 {
                    didTransform = true
                    parent.onPinch(t, factor, location)
                }
            case .ended, .cancelled, .failed:
                recognizerEnded(g)
            default:
                break
            }
        }

        @objc func handleRotate(_ g: UIRotationGestureRecognizer) {
            guard let host else { return }
            let location = g.location(in: host)
            switch g.state {
            case .began:
                lastRotation = 0
                recognizerBegan(g, at: location)
            case .changed:
                guard parent.isEnabled, let t = target else { return }
                let delta = g.rotation - lastRotation
                lastRotation = g.rotation
                lastLocation = location
                if abs(delta) > 0.0005 {
                    didTransform = true
                    parent.onRotate(t, delta, location)
                }
            case .ended, .cancelled, .failed:
                recognizerEnded(g)
            default:
                break
            }
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard parent.isEnabled, g.state == .ended, !didTransform, !wasCancelled, let target else { return }
            parent.onTap(target)
        }

        @objc func handleLongPress(_ g: UILongPressGestureRecognizer) {
            guard parent.isEnabled, g.state == .began, !didTransform, case .sticker = target, let target else { return }
            parent.onLongPress(target)
        }

        // MARK: Delegate

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Pan, pinch and rotate all run together; taps and long presses
            // stay exclusive so they can't fire mid-transform.
            let continuous: [AnyClass] = [UIPanGestureRecognizer.self, UIPinchGestureRecognizer.self, UIRotationGestureRecognizer.self]
            let a = continuous.contains { gestureRecognizer.isKind(of: $0) }
            let b = continuous.contains { otherGestureRecognizer.isKind(of: $0) }
            return a && b
        }
    }
}

/// Pure math for sticker hit-testing + anchor-preserving transforms — kept
/// out of the view so the editor body stays light.
enum StoryStickerGeometry {
    /// True when `point` (stage coords) lands inside the sticker's rendered
    /// frame. `size` is the sticker's UNSCALED layout size; the sticker sits
    /// at `center` with `scale` and `rotation` applied. Tiny stickers get a
    /// 44pt minimum hit box so they stay grabbable.
    static func contains(
        point: CGPoint,
        center: CGPoint,
        size: CGSize,
        scale: CGFloat,
        rotation: CGFloat,
        minimumHitSize: CGFloat = 44
    ) -> Bool {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let c = cos(-rotation)
        let s = sin(-rotation)
        let lx = (dx * c - dy * s) / max(scale, 0.0001)
        let ly = (dx * s + dy * c) / max(scale, 0.0001)
        let halfW = max(size.width / 2, minimumHitSize / 2 / max(scale, 0.0001))
        let halfH = max(size.height / 2, minimumHitSize / 2 / max(scale, 0.0001))
        return abs(lx) <= halfW && abs(ly) <= halfH
    }

    /// New center after scaling by `factor` about `anchor`.
    static func scaled(center: CGPoint, about anchor: CGPoint, factor: CGFloat) -> CGPoint {
        CGPoint(
            x: anchor.x + (center.x - anchor.x) * factor,
            y: anchor.y + (center.y - anchor.y) * factor
        )
    }

    /// New center after rotating by `delta` radians about `anchor`.
    static func rotated(center: CGPoint, about anchor: CGPoint, delta: CGFloat) -> CGPoint {
        let dx = center.x - anchor.x
        let dy = center.y - anchor.y
        let c = cos(delta)
        let s = sin(delta)
        return CGPoint(x: anchor.x + dx * c - dy * s, y: anchor.y + dx * s + dy * c)
    }
}
