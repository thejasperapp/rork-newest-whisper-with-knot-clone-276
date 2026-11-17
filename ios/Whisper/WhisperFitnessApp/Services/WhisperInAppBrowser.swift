import SafariServices
import UIKit

/// System browser chrome, presented above the currently visible sheet. No web
/// scripts, cookies, form contents or navigation history are exposed to Whisper.
@MainActor
final class WhisperInAppBrowser: NSObject, SFSafariViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    static let shared = WhisperInAppBrowser()
    private weak var browser: SFSafariViewController?
    private var onDismiss: (() -> Void)?

    /// Only ordinary web pages belong here. Explicit app destinations retain
    /// their system handoff; authentication callers bypass this service entirely.
    static func isWebPage(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil,
              !WhisperNotesLink.isNotesURL(url) else { return false }
        return !["apps.apple.com", "itunes.apple.com", "maps.apple.com", "music.apple.com"].contains(host)
    }

    /// Used by SwiftUI's OpenURLAction; returning false keeps non-web actions
    /// with the OS rather than trying to feed an unsupported URL into Safari.
    @discardableResult
    func presentWebPage(_ url: URL, onDismiss: (() -> Void)? = nil) -> Bool {
        if WhisperMeetingLinkRouter.handle(url) {
            onDismiss?()
            return true
        }
        guard Self.isWebPage(url) else { return false }
        // Ignore a second tap while the first browser is still visible.
        if browser?.presentingViewController != nil { return true }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        guard let root = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return false }
        var presenter = root
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed { presenter = presented }
        guard presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed,
              !presenter.isBeingPresented, !(presenter is UIAlertController) else { return false }
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = .label
        controller.dismissButtonStyle = .done
        controller.delegate = self
        browser = controller
        self.onDismiss = onDismiss
        presenter.present(controller, animated: true)
        controller.presentationController?.delegate = self
        return true
    }

    /// For existing explicit website buttons; device settings, phone/email,
    /// store links and app handoffs still use UIApplication directly.
    func open(_ url: URL) {
        if !presentWebPage(url) { UIApplication.shared.open(url) }
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        controller.dismiss(animated: true)
        if browser === controller {
            browser = nil
            let completion = onDismiss
            onDismiss = nil
            completion?()
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let controller = browser, presentationController.presentedViewController === controller else { return }
        browser = nil
        let completion = onDismiss
        onDismiss = nil
        completion?()
    }

    func dismissForAccountChange() {
        onDismiss = nil
        browser?.dismiss(animated: false)
        browser = nil
    }
}
