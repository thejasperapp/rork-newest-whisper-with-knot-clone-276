import SwiftUI
import UIKit
import Supabase

/// Owns a token-free cover above sheets and call windows, without stealing the key window.
@MainActor
@Observable
final class WhisperAccountTransition: NSObject {
    static let shared = WhisperAccountTransition()
    private(set) var id: UUID?
    private(set) var owner: String = ""
    private(set) var username: String = ""
    private(set) var avatarURL: URL?
    private(set) var contentGeneration: UUID?
    private(set) var adoptedGeneration: UUID?
    private(set) var isReady: Bool = false
    private(set) var isPrivate: Bool = false
    private(set) var isTakingLonger: Bool = false
    private(set) var errorMessage: String?
    private(set) var recoveryTitle: String = "Back"
    var isActive: Bool { id != nil }

    @ObservationIgnored private var window: UIWindow?
    @ObservationIgnored private var privacyShield: UIView?
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    @ObservationIgnored private var readinessTimeout: Task<Void, Never>?
    @ObservationIgnored private var connectionNotice: Task<Void, Never>?
    @ObservationIgnored private var revealID: UUID = UUID()
    @ObservationIgnored private var recovery: (() -> Void)?
    @ObservationIgnored private var retry: (() -> Void)?
    @ObservationIgnored private var startedAt: ContinuousClock.Instant = .now
    @ObservationIgnored private var destinationGeneration: UUID?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(backgrounded), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foregrounded), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func begin(owner: String, username: String, avatarURL: String?) async -> UUID? {
        guard !isActive,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return nil }
        let token = UUID()
        id = token; self.owner = owner.lowercased(); self.username = username
        self.avatarURL = avatarURL.flatMap(URL.init(string:))
        errorMessage = nil; isReady = false; isPrivate = false; isTakingLonger = false
        connectionNotice = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard id == token, !isReady else { return }
            isTakingLonger = true
        }
        contentGeneration = nil; destinationGeneration = nil; startedAt = .now
        scene.windows.forEach { $0.endEditing(true) }
        let host = UIHostingController(rootView: WhisperAccountTransitionView(transition: self).scrollIndicators(.hidden))
        host.view.backgroundColor = .systemBackground
        host.view.accessibilityViewIsModal = true
        let cover = UIWindow(windowScene: scene)
        cover.windowLevel = .alert + 3
        cover.rootViewController = host
        cover.backgroundColor = .systemBackground
        cover.alpha = 0
        window = cover
        cover.isHidden = false
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.12 : 0.22, delay: 0, options: [.curveEaseOut]) {
                cover.alpha = 1
            } completion: { _ in continuation.resume() }
        }
        return token
    }

    func adopted(token: UUID, owner: String, generation: UUID) {
        guard id == token, self.owner == owner.lowercased(), generation == AccountStorage.generation else { return }
        adoptedGeneration = generation
    }

    func watchReadiness(retry: @escaping () -> Void, recovery: @escaping () -> Void) {
        readinessTimeout?.cancel()
        let token = id
        readinessTimeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard id == token, isActive, !isReady, errorMessage == nil else { return }
            fail("Your profile is taking longer than expected. You can retry without changing accounts.", recoveryTitle: "Go to sign in", retry: retry, recovery: recovery)
        }
    }

    func prepared(owner: String, generation: UUID) {
        guard isActive, self.owner == owner.lowercased(), generation == AccountStorage.generation,
              adoptedGeneration == generation else { return }
        contentGeneration = generation
        errorMessage = nil
        attemptReveal()
    }

    func destinationDidLayout(generation: UUID) {
        guard isActive, generation == contentGeneration else { return }
        destinationGeneration = generation
        attemptReveal()
    }

    func fail(_ message: String, recoveryTitle: String = "Back", retry: (() -> Void)? = nil, recovery: @escaping () -> Void) {
        guard isActive else { return }
        revealID = UUID()
        revealTask?.cancel(); revealTask = nil
        window?.layer.removeAllAnimations(); window?.alpha = 1
        isReady = false; contentGeneration = nil; destinationGeneration = nil
        errorMessage = message; self.recoveryTitle = recoveryTitle
        self.retry = retry; self.recovery = recovery
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    var canRetry: Bool { retry != nil }
    func retryNow() { let action = retry; errorMessage = nil; retry = nil; action?() }
    func recover() { let action = recovery; recovery = nil; action?() }

    /// Use only after reconciling the SDK/local identity or returning to signed-out UI.
    func close() {
        revealTask?.cancel(); revealTask = nil
        window?.isHidden = true; window?.rootViewController = nil; window = nil
        readinessTimeout?.cancel(); readinessTimeout = nil
        connectionNotice?.cancel(); connectionNotice = nil; revealID = UUID()
        privacyShield = nil; id = nil; contentGeneration = nil; destinationGeneration = nil; adoptedGeneration = nil
        retry = nil; recovery = nil; avatarURL = nil; username = ""; owner = ""
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    private var canReveal: Bool {
        guard let generation = contentGeneration else { return false }
        return WhisperAccountTransitionPolicy.canReveal(
            expectedOwner: owner, localOwner: AccountStorage.currentUserID,
            sessionOwner: SupabaseService.shared.client.auth.currentUser?.id.uuidString,
            profileOwner: AuthenticationService.shared.currentUser.userID,
            expectedGeneration: generation, currentGeneration: AccountStorage.generation,
            destinationGeneration: destinationGeneration, active: !isPrivate,
            signedIn: AuthenticationService.shared.isSignedIn
        ) && errorMessage == nil
    }

    private func attemptReveal() {
        guard canReveal, revealTask == nil, let token = id else { return }
        let reveal = UUID(); revealID = reveal
        revealTask = Task { @MainActor in
            // Minimum visual duration prevents a fast cached switch becoming a flash.
            try? await Task.sleep(until: startedAt.advanced(by: .milliseconds(650)), clock: .continuous)
            guard !Task.isCancelled, id == token, revealID == reveal, canReveal else { return }
            isReady = true
            try? await Task.sleep(for: .milliseconds(UIAccessibility.isReduceMotionEnabled ? 80 : 180))
            guard !Task.isCancelled, id == token, revealID == reveal, canReveal, let cover = window else { return }
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.32, delay: 0, options: [.curveEaseInOut]) {
                cover.alpha = 0
            } completion: { [self] finished in
                guard finished, self.id == token, self.revealID == reveal, self.canReveal else { return }
                self.close()
                Haptics.selection()
            }
        }
    }

    @objc private func backgrounded() {
        guard let window else { return }
        isPrivate = true; revealID = UUID()
        revealTask?.cancel(); revealTask = nil
        window.layer.removeAllAnimations(); window.alpha = 1
        // UIKit shield paints synchronously before the app-switcher snapshot.
        let shield = UIView(frame: window.bounds)
        shield.backgroundColor = .systemBackground
        shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(shield)
        privacyShield?.removeFromSuperview(); privacyShield = shield
    }

    @objc private func foregrounded() {
        guard isActive else { return }
        privacyShield?.removeFromSuperview(); privacyShield = nil
        isPrivate = false
        attemptReveal()
    }
}
