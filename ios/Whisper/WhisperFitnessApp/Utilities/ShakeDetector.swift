import SwiftUI
import UIKit

struct ShakeDetectorModifier: ViewModifier {
    var isEnabled: Bool = true
    let action: () -> Void

    func body(content: Content) -> some View {
        content.background(ShakeDetectorRepresentable(isEnabled: isEnabled, action: action))
    }
}

struct ShakeDetectorRepresentable: UIViewControllerRepresentable {
    var isEnabled: Bool = true
    let action: () -> Void

    func makeUIViewController(context: Context) -> ShakeDetectorViewController {
        let controller = ShakeDetectorViewController()
        controller.isEnabled = isEnabled
        controller.action = action
        return controller
    }

    func updateUIViewController(_ controller: ShakeDetectorViewController, context: Context) {
        controller.action = action
        controller.isEnabled = isEnabled
        controller.updateResponder()
    }

    static func dismantleUIViewController(_ controller: ShakeDetectorViewController, coordinator: ()) {
        controller.isEnabled = false
        controller.action = nil
        controller.resignFirstResponder()
    }
}

class ShakeDetectorViewController: UIViewController {
    var action: (() -> Void)?
    var isEnabled: Bool = true
    private var isVisible: Bool = false
    override var canBecomeFirstResponder: Bool { isEnabled && isVisible }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        NotificationCenter.default.addObserver(self, selector: #selector(updateResponder), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(suspendResponder), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateResponder), name: NSNotification.Name("EmberDismissed"), object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        updateResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        isVisible = false
        resignFirstResponder()
        super.viewWillDisappear(animated)
    }

    private var isUncovered: Bool {
        var ancestor: UIViewController? = self
        while let controller = ancestor {
            if controller.presentedViewController != nil { return false }
            ancestor = controller.parent
        }
        return true
    }

    private func containsTextResponder(_ view: UIView) -> Bool {
        if view.isFirstResponder && view is any UITextInput { return true }
        return view.subviews.contains { containsTextResponder($0) }
    }

    @objc func updateResponder() {
        guard isEnabled, isVisible, isUncovered,
              UIApplication.shared.applicationState == .active,
              let window = viewIfLoaded?.window else { resignFirstResponder(); return }
        // A motion listener must never dismiss a reply/caption keyboard to claim input.
        guard !containsTextResponder(window) else { return }
        if !isFirstResponder { becomeFirstResponder() }
    }

    @objc private func suspendResponder() { resignFirstResponder() }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake, isEnabled, isVisible, isUncovered,
              UIApplication.shared.applicationState == .active else { return }
        action?()
    }
}

extension View {
    func onShake(isEnabled: Bool = true, perform action: @escaping () -> Void) -> some View {
        modifier(ShakeDetectorModifier(isEnabled: isEnabled, action: action))
    }
}
