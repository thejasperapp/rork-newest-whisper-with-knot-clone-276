import SwiftUI
import UIKit

/// Saves the visible predecessor before a push or cover removes its render tree.
struct WhisperNavigationPreview: UIViewControllerRepresentable {
    var enabled: Bool = true
    @Environment(\.whisperRootChromeActive) private var rootActive
    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ controller: Probe, context: Context) { controller.enabled = enabled && rootActive }

    final class Probe: UIViewController {
        var enabled: Bool = true
        private let account: UUID = AccountStorage.generation
        private var accountInvalidated: Bool = false
        override func viewDidLoad() {
            super.viewDidLoad()
            NotificationCenter.default.addObserver(self, selector: #selector(invalidateAccount), name: Notification.Name("WhisperMeetingAccountWillChange"), object: nil)
        }
        @objc private func invalidateAccount() { accountInvalidated = true }
        override func loadView() { view = UIView(); view.backgroundColor = .clear; view.isUserInteractionEnabled = false }
        override func viewWillDisappear(_ animated: Bool) {
            if enabled, !accountInvalidated, account == AccountStorage.generation, let parent, view.window != nil {
                var owner = parent
                while let ancestor = owner.parent, !(ancestor is UINavigationController) { owner = ancestor }
                if let content = owner.viewIfLoaded {
                    let scope = view.convert(view.bounds, to: content)
                    if scope.width >= content.bounds.width * 0.9, scope.height >= content.bounds.height * 0.65 {
                        let store = WhisperNavigationSnapshots.shared
                        store.capture(content, account: account)
                        if let nav = owner.navigationController,
                           nav.topViewController === owner || nav.transitionCoordinator?.viewController(forKey: .from) === owner {
                            store.capture(nav.view, key: content, account: account)
                        }
                        // Full-screen covers may be presented by a tab host or by
                        // its containing shell. Capture those exact lookup keys.
                        var ancestor = owner.parent
                        while let container = ancestor {
                            if let surface = container.viewIfLoaded, surface.window === content.window,
                               container.presentedViewController != nil {
                                store.capture(surface, account: account)
                            }
                            ancestor = container.parent
                        }
                    }
                }
            }
            super.viewWillDisappear(animated)
        }
    }
}
