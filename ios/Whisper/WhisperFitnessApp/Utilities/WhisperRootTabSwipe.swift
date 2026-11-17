import SwiftUI
import UIKit

nonisolated enum WhisperRootTabSwipePolicy {
    static let order = [0, 3, 1, 2, 4]

    static func prewarmOrder(from selection: Int) -> [Int] {
        guard let origin = order.firstIndex(of: selection) else { return order }
        return order.enumerated().filter { $0.element != selection }.sorted {
            let left = abs($0.offset - origin), right = abs($1.offset - origin)
            return left == right ? $0.offset > $1.offset : left < right
        }.map(\.element)
    }
    static func adjacent(to selection: Int, direction: Int) -> Int? {
        guard let index = order.firstIndex(of: selection), order.indices.contains(index + direction) else { return nil }
        return order[index + direction]
    }
    static func destination(selection: Int, dx: CGFloat, dy: CGFloat, velocity: CGFloat) -> Int? {
        guard abs(dx) > abs(dy) * 1.6, abs(dx) > 54 || (abs(dx) > 22 && abs(velocity) > 650) else { return nil }
        return adjacent(to: selection, direction: dx < 0 ? 1 : -1)
    }
}

/// A root-only horizontal recognizer. Native pushes, presentations and horizontal
/// controls retain their gestures; the physical left edge remains reserved for back.
struct WhisperRootTabSwipe: UIViewControllerRepresentable {
    let enabled: Bool
    let selection: Int
    let pager: WhisperTabPagingState
    let onBegin: (Int) -> Void
    let onEnd: (Bool, CGFloat) -> Void

    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ controller: Probe, context: Context) {
        controller.enabled = enabled
        controller.selection = selection
        controller.pager = pager
        controller.onBegin = onBegin
        controller.onEnd = onEnd
        if !enabled && (controller.pager?.source != nil) {
            DispatchQueue.main.async { [weak controller] in
                guard let controller, !controller.enabled else { return }
                controller.interrupt()
            }
        }
        controller.install()
    }
    static func dismantleUIViewController(_ controller: Probe, coordinator: ()) { controller.remove() }

    final class Probe: UIViewController, UIGestureRecognizerDelegate {
        var enabled = false
        var selection = 0
        weak var pager: WhisperTabPagingState?
        var onBegin: ((Int) -> Void)?
        var onEnd: ((Bool, CGFloat) -> Void)?
        private var epoch: UUID?
        private var direction: Int = 1
        private var pageWidth: CGFloat = 1
        private var startSelection = 0
        private weak var host: UIView?
        private weak var touchedView: UIView?
        private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); install() }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); install() }
        func install() {
            guard let target = parent?.viewIfLoaded, viewIfLoaded?.window != nil, host !== target else { return }
            remove(); host = target
            pan.delegate = self; pan.maximumNumberOfTouches = 1
            target.addGestureRecognizer(pan)
        }
        func remove() { interrupt(); host?.removeGestureRecognizer(pan); host = nil }
        func interrupt() {
            epoch = nil
            if pan.state == .began || pan.state == .changed { pan.isEnabled = false; pan.isEnabled = true }
            if pager?.source != nil { pager?.reset() }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            touchedView = touch.view
            return true
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard enabled, pager?.source == nil, pager?.isSettling != true, let host, let window = host.window, window.isKeyWindow,
                  UIApplication.shared.applicationState == .active else { return false }
            let p = pan.location(in: window), d = pan.translation(in: window), v = pan.velocity(in: window)
            let start = CGPoint(x: p.x - d.x, y: p.y - d.y)
            guard !WhisperInboxFlipRegion.contains(start, in: window) else { return false }
            let viewport = view.convert(view.bounds, to: window)
            guard viewport.contains(CGPoint(x: p.x - d.x, y: p.y - d.y)), p.x - d.x > 24, abs(v.x) > abs(v.y) * 1.6,
                  WhisperRootTabSwipePolicy.adjacent(to: selection, direction: v.x < 0 ? 1 : -1) != nil else { return false }
            var responder: UIResponder? = touchedView
            while let current = responder {
                if let control = current as? UIControl, control.isEnabled { return false }
                if current is UITextView || current is UITextField { return false }
                if let scroll = current as? UIScrollView,
                   scroll.isScrollEnabled && (scroll.contentSize.width > scroll.bounds.width + 2 || scroll.alwaysBounceHorizontal) { return false }
                if let controller = current as? UIViewController {
                    if controller.presentingViewController != nil || controller.presentedViewController != nil || controller.transitionCoordinator != nil { return false }
                    if let nav = controller.navigationController, nav.viewControllers.count > 1 { return false }
                    if let nav = controller as? UINavigationController, nav.viewControllers.count > 1 { return false }
                }
                responder = current.next
            }
            startSelection = selection
            pageWidth = max(1, view.bounds.width)
            direction = v.x < 0 ? 1 : -1
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            guard let scroll = other.view as? UIScrollView else { return false }
            return other === scroll.panGestureRecognizer && scroll.contentSize.width <= scroll.bounds.width + 2 && !scroll.alwaysBounceHorizontal
        }
        @objc private func drag(_ gesture: UIPanGestureRecognizer) {
            guard let host, let pager else { return }
            let d = gesture.translation(in: host)
            let velocity = gesture.velocity(in: host).x
            switch gesture.state {
            case .began:
                epoch = AccountStorage.generation
                if let next = pager.begin(selection: selection, direction: direction) { onBegin?(next) }
                pager.update(translation: d.x, width: pageWidth)
            case .changed:
                guard enabled, epoch == AccountStorage.generation, selection == startSelection else { interrupt(); return }
                pager.update(translation: d.x, width: pageWidth)
            case .ended:
                guard enabled, epoch == AccountStorage.generation, selection == startSelection else { interrupt(); return }
                let travel = -CGFloat(direction) * d.x
                let speed = -CGFloat(direction) * velocity
                let commit = travel > pageWidth * 0.30 && speed > -180 || travel > 22 && speed > 650
                onEnd?(commit, velocity)
                epoch = nil
            case .cancelled, .failed:
                if epoch != nil { onEnd?(false, 0) }; epoch = nil
            default: break
            }
        }
    }
}
