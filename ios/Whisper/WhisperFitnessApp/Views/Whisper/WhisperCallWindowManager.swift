import SwiftUI
import UIKit

/// Hosts the in-app call UI in its own `UIWindow` floating ABOVE every
/// sheet, fullScreenCover, and navigation stack.
///
/// Why a window: SwiftUI only allows one modal per presentation context.
/// The DM thread (where calls start) is itself presented as a
/// `fullScreenCover`, so a root-level cover for the call could never
/// present while the chat was open — the caller had to close the chat to
/// see their own call. A dedicated window (the same pattern FaceTime-style
/// apps use) always wins, so the flow is ring → connecting → in-call
/// without ever leaving the conversation.
@MainActor
@Observable
final class WhisperCallWindowManager {
    static let shared = WhisperCallWindowManager()

    @ObservationIgnored private var window: UIWindow?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    private(set) var minimized: Bool = false
    var tileFrame: CGRect = .zero

    private init() {}

    /// True while the call window is on screen.
    var isPresenting: Bool { window != nil }

    private func bestScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    /// Presents the call UI over everything. Idempotent.
    ///
    /// Cold-launch safety: when a notification tap answers a call while the
    /// app is still launching, no `UIWindowScene` is connected yet — instead
    /// of silently dropping the call UI (the `active` didSet only fires
    /// once), keep retrying briefly until a scene exists.
    func show() {
        guard window == nil else { return }
        guard let scene = bestScene() else {
            scheduleShowRetry()
            return
        }
        retryTask?.cancel()
        retryTask = nil

        minimized = false
        tileFrame = .zero
        let host = UIHostingController(rootView: WhisperCallWindowRoot().scrollIndicators(.hidden))
        host.view.backgroundColor = .clear
        host.overrideUserInterfaceStyle = .dark

        let w = WhisperCallPassthroughWindow(windowScene: scene)
        w.rootViewController = host
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        w.alpha = 0
        w.isHidden = false
        w.makeKeyAndVisible()
        window = w

        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
            w.alpha = 1
        }
    }

    func minimize() {
        guard let window, WhisperCallService.shared.active?.state != .ended else { return }
        window.endEditing(true)
        minimized = true
        UIApplication.shared.isIdleTimerDisabled = false
        window.windowScene?.windows.first { $0 !== window && !$0.isHidden && $0.windowLevel == .normal }?.makeKey()
    }

    /// Explicit user intent only; automatic call updates must not expand the window.
    func restore() {
        show()
        minimized = false
        window?.makeKey()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func scheduleShowRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { @MainActor in
            for _ in 0..<16 {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { break }
                // Call already over — stop retrying.
                if WhisperCallService.shared.active == nil { break }
                if self.window != nil { break }
                if self.bestScene() != nil {
                    self.retryTask = nil
                    self.show()
                    return
                }
            }
            self.retryTask = nil
        }
    }

    /// Fades the call window out and releases it. Idempotent.
    func hide() {
        retryTask?.cancel()
        retryTask = nil
        guard let w = window else { return }
        window = nil
        minimized = false
        tileFrame = .zero
        w.windowScene?.windows.first { $0 !== w && !$0.isHidden && $0.windowLevel == .normal }?.makeKey()
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn]) {
            w.alpha = 0
        } completion: { _ in
            w.isHidden = true
            w.rootViewController = nil
        }
    }
}
