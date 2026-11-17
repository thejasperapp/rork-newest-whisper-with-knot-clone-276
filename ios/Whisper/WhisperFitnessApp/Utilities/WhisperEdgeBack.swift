import SwiftUI
import UIKit

nonisolated enum WhisperEdgeBackPolicy {
    static func commits(startX: CGFloat, dx: CGFloat, dy: CGFloat, velocityX: CGFloat) -> Bool {
        startX >= 0 && startX <= 24 && dx > 0 && abs(dx) > abs(dy) * 1.15 && velocityX > -120 && (dx >= 54 || (dx >= 24 && velocityX >= 420))
    }
}

extension View {
    /// Screen-owned edge action. The caller supplies exactly the same guarded action as its back button.
    func whisperEdgeBack(isEnabled: Bool = true, requiresDecision: Bool = false, revealPresentation: Bool = true, controller: WhisperBackAction? = nil, action: @escaping () -> Void) -> some View {
        modifier(WhisperEdgeBackModifier(enabled: isEnabled, requiresDecision: requiresDecision, revealPresentation: revealPresentation, controller: controller, action: action))
    }
}

private struct WhisperEdgeBackModifier: ViewModifier {
    let enabled: Bool
    let requiresDecision: Bool
    let revealPresentation: Bool
    let controller: WhisperBackAction?
    let action: () -> Void
    @State private var visible: Bool = false
    func body(content: Content) -> some View {
        content.background(WhisperEdgeBackBridge(enabled: enabled && visible, requiresDecision: requiresDecision, revealPresentation: revealPresentation, controller: controller, action: action))
            .background(WhisperNavigationPreview())
            .onAppear { visible = true }
            .onDisappear { visible = false }
    }
}

private struct WhisperEdgeBackBridge: UIViewControllerRepresentable {
    let enabled: Bool
    let requiresDecision: Bool
    let revealPresentation: Bool
    let controller: WhisperBackAction?
    let action: () -> Void
    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ controller: Probe, context: Context) {
        controller.install()
        controller.enabled = enabled; controller.action = action
        controller.requiresDecision = requiresDecision
        controller.revealPresentation = revealPresentation
        controller.backAction = self.controller
        self.controller?.animate = { [weak controller] action in
            guard let controller else { action(); return }
            controller.animateBack(action)
        }
        self.controller?.captureLocal = { [weak controller] in controller?.captureLocalPredecessor() }
        self.controller?.makeVerticalReveal = { [weak controller] in controller?.makeReveal(vertical: true) }
        if !enabled { controller.cancelReveal() }
    }
    static func dismantleUIViewController(_ controller: Probe, coordinator: ()) { controller.remove() }

    final class Probe: UIViewController, UIGestureRecognizerDelegate {
        var enabled: Bool = false
        var action: (() -> Void)?
        var requiresDecision: Bool = false
        var revealPresentation: Bool = true
        weak var backAction: WhisperBackAction?
        private var reveal: WhisperBackRevealSession?
        private var localPredecessor: UIView?
        private var localGeneration: UUID?
        private var isSettling: Bool = false
        private var gestureGeneration: UUID?
        private let navigationLease = WhisperNavigationGestureLease()
        private static weak var gestureOwner: Probe?
        private weak var host: UIView?
        private var startX: CGFloat = 0
        private var touchOrigin: CGPoint = .zero
        private lazy var edge: UIPanGestureRecognizer = {
            let gesture = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            gesture.maximumNumberOfTouches = 1
            gesture.delegate = self
            gesture.cancelsTouchesInView = true
            return gesture
        }()
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false; view.backgroundColor = .clear }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); install() }
        override func viewDidLoad() {
            super.viewDidLoad()
            NotificationCenter.default.addObserver(self, selector: #selector(interrupt), name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(interrupt), name: Notification.Name("WhisperMeetingAccountWillChange"), object: nil)
        }
        @objc private func interrupt() { cancelReveal(); localPredecessor = nil; localGeneration = nil }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); install() }
        func install() {
            guard let parent, viewIfLoaded?.window != nil else { return }
            let owner = navigationOwner(parent)
            guard let target = owner.viewIfLoaded else { return }
            if host !== target {
                cancelReveal(); navigationLease.release()
                host?.removeGestureRecognizer(edge)
                localPredecessor = nil; localGeneration = nil
                host = target; target.addGestureRecognizer(edge)
            }
            if view.window != nil, let nav = owner.navigationController, nav.topViewController === owner {
                navigationLease.acquire(nav)
            }
        }
        func cancelReveal() {
            gestureGeneration = nil
            reveal?.remove(); reveal = nil; isSettling = false
            if Self.gestureOwner === self { Self.gestureOwner = nil }
        }
        func remove() { backAction?.animate = nil; backAction?.captureLocal = nil; backAction?.makeVerticalReveal = nil; localPredecessor = nil; cancelReveal(); navigationLease.release(); host?.removeGestureRecognizer(edge); host = nil }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); cancelReveal(); navigationLease.release() }

        func animateBack(_ completion: @escaping () -> Void) {
            guard !isSettling, Self.gestureOwner == nil else { return }
            guard enabled, host?.window?.isKeyWindow == true else { completion(); return }
            guard let session = makeReveal() else { completion(); return }
            reveal = session
            isSettling = true
            Self.gestureOwner = self
            let epoch = AccountStorage.generation
            session.settle(leaving: true) { [weak self] valid in
                guard let self else { return }
                self.reveal = nil; self.isSettling = false; Self.gestureOwner = nil
                guard valid, epoch == AccountStorage.generation else { return }
                if let backAction = self.backAction { backAction.commit(completion) }
                else { var transaction = Transaction(); transaction.disablesAnimations = true; withTransaction(transaction) { completion() } }
            }
        }

        func captureLocalPredecessor() {
            guard let host, host.window?.isKeyWindow == true, !isSettling else { return }
            let scope = view.convert(view.bounds, to: host)
            guard scope.width > 40, scope.height > 40 else { return }
            let image = WhisperNavigationSnapshots.render(host, rect: scope)
            localPredecessor = UIImageView(image: image)
            localPredecessor?.frame = CGRect(origin: .zero, size: scope.size)
            localGeneration = AccountStorage.generation
        }

        func makeReveal(vertical: Bool = false) -> WhisperBackRevealSession? {
            guard let parent, let host else { return nil }
            if !revealPresentation {
                guard localGeneration == AccountStorage.generation, let localPredecessor else { return nil }
                let scope = view.convert(view.bounds, to: host)
                return WhisperBackRevealSession(surface: host, predecessor: localPredecessor, localTransition: true, scope: scope, vertical: vertical)
            }
            // Presentation exits belong to the hosting screen, even when SwiftUI's probe
            // is measured as a header-sized background. Local panels use the branch above.
            guard host.bounds.width > 40, host.bounds.height > 40 else { return nil }
            let owner = navigationOwner(parent)
            if let nav = owner.navigationController, let index = nav.viewControllers.firstIndex(where: { $0 === owner }), index > 0 {
                guard nav.topViewController === owner, let back = nav.viewControllers[index - 1].viewIfLoaded else { return nil }
                return WhisperBackRevealSession(surface: nav.view, predecessor: back, departure: owner.view, vertical: vertical)
            }
            var presentation = owner
            while let ancestor = presentation.parent { presentation = ancestor }
            if let presenter = presentation.presentingViewController, let back = presenter.viewIfLoaded {
                return WhisperBackRevealSession(surface: presentation.view, predecessor: back, departure: presentation.view, vertical: vertical)
            }
            return nil
        }
        private func navigationOwner(_ controller: UIViewController) -> UIViewController {
            if let nav = controller as? UINavigationController { return nav.topViewController ?? controller }
            var owner = controller
            while let ancestor = owner.parent, !(ancestor is UINavigationController), !(ancestor is WhisperTabPagerController) { owner = ancestor }
            return owner
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard enabled, let host, host.window?.isKeyWindow == true else { return false }
            touchOrigin = touch.location(in: host)
            // A normal pan accepts the entire Settings-sized edge strip, not only UIKit's system edge slop.
            guard touchOrigin.x >= 0, touchOrigin.x <= 24 else { return false }
            var node = touch.view
            while let current = node, current !== host {
                if current is UISlider || current is UITextField || current is UITextView || current is UISwitch { return false }
                node = current.superview
            }
            return node === host
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            enabled && other.view is UIScrollView
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard enabled, !isSettling, Self.gestureOwner == nil, let host, let window = host.window, let parent,
                  window.isKeyWindow, !host.isHidden, host.alpha > 0.01,
                  parent.presentedViewController == nil, parent.transitionCoordinator == nil else { return false }
            let owner = navigationOwner(parent)
            if let nav = owner.navigationController, nav.topViewController !== owner { return false }
            guard owner.presentedViewController == nil, owner.transitionCoordinator == nil else { return false }
            startX = touchOrigin.x
            let bounds = revealPresentation ? host.bounds : view.convert(view.bounds, to: host)
            guard bounds.height > 40, bounds.contains(touchOrigin), startX >= 0, startX <= 24 else { return false }
            let velocity = edge.velocity(in: host)
            return velocity.x > 0 && velocity.x > abs(velocity.y) * 1.15
        }
        @objc private func pan(_ gesture: UIPanGestureRecognizer) {
            guard let host else { cancelReveal(); return }
            let delta = gesture.translation(in: host)
            switch gesture.state {
            case .began:
                Self.gestureOwner = self
                gestureGeneration = AccountStorage.generation
                reveal = makeReveal()
                reveal?.update(translation: delta.x)
            case .changed:
                guard enabled, gestureGeneration == AccountStorage.generation else { cancelReveal(); return }
                reveal?.update(translation: delta.x)
            case .ended:
                guard gestureGeneration == AccountStorage.generation else { cancelReveal(); return }
                let commit = enabled && WhisperEdgeBackPolicy.commits(startX: startX, dx: delta.x, dy: delta.y, velocityX: gesture.velocity(in: host).x)
                guard let reveal else {
                    Self.gestureOwner = nil
                    if commit { action?() }
                    return
                }
                isSettling = true
                // Restore guarded editors before asking: a dialog or failed save must never leave the card offscreen.
                let leaving = commit && !requiresDecision
                reveal.settle(leaving: leaving, velocity: gesture.velocity(in: host).x) { [weak self] valid in
                    guard let self else { return }
                    self.reveal = nil; self.isSettling = false; Self.gestureOwner = nil
                    if valid, commit, self.enabled {
                        if leaving {
                            var transaction = Transaction(); transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                if let backAction = self.backAction { backAction.commit { self.action?() } }
                                else { self.action?() }
                            }
                        } else { self.action?() }
                    }
                }
            case .cancelled, .failed:
                if let reveal {
                    isSettling = true
                    reveal.settle(leaving: false) { [weak self] _ in self?.cancelReveal() }
                } else { cancelReveal() }
            default: break
            }
        }
    }
}
