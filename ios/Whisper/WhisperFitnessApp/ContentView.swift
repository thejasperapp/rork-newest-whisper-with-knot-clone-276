import SwiftUI
import StoreKit

/// App entry point. Whisper is the entire app — the legacy Whisper fitness
/// shell (MainTabView, FirstDelight popup, Jasper update / wellness / summer
/// event popups) has been removed. Sign-in is handled by `WhisperAuthSheet`
/// inside `WhisperRootView`, and new users continue straight into
/// `WhisperOnboardingView` from there.
struct ContentView: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var authService = AuthenticationService.shared
    /// One-shot launch cover. Session readiness or the safety timeout dismisses
    /// it; feed and image warming never extend its lifetime.
    @State private var splashVisible: Bool = true
    /// Simulator-only manual color-scheme override so we can sanity-check
    /// light/dark UI without flipping the system setting. `nil` = follow
    /// system. Toggle button is gated to simulator builds only.
    @State private var simulatorOverride: ColorScheme? = nil
    /// True while `bootstrap()` owns account warm-up, so the sign-in
    /// observer does not fire the same fetches a second time at launch.
    @State private var bootstrapWarming: Bool = true
    @State private var didBootstrap: Bool = false

    var body: some View {
        ZStack {
            WhisperRootView()
                .preferredColorScheme(simulatorOverride)
                .onChange(of: authService.isSignedIn) { _, signedIn in
                    // A later sign-in (after the cold-launch bootstrap) warms
                    // the same account slice. During launch this flip races
                    // bootstrap(), which already runs these — skip the double.
                    guard signedIn, !bootstrapWarming else { return }
                    Task {
                        async let flags: Void = UserFlagsService.shared.hydrate()
                        async let friends: Void = FriendRequestsService.shared.refresh()
                        _ = await (flags, friends)
                    }
                }
                .onAppear {
                    bootstrap()
                    ReviewManager.incrementLaunchCount()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if ReviewManager.shouldRequestReview() {
                            requestReview()
                        }
                    }
                }

            if splashVisible {
                WhisperSplashView()
                    .preferredColorScheme(simulatorOverride)
                    .zIndex(10)
                    .transition(.opacity)
            }

            #if targetEnvironment(simulator)
            SimulatorColorSchemeToggle(override: $simulatorOverride)
                .zIndex(20)
            #endif
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: splashVisible)
    }

    /// Reveal the authenticated shell without waiting for social or image requests.
    /// Visible screens own their content; launch retains identity and safety work.
    private func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        #if DEBUG
        print("[WhisperLaunch] root_appeared restoring=\(authService.isRestoringSession)")
        #endif
        Task {
            defer { bootstrapWarming = false }
            // Hard safety net so the splash NEVER hangs the app.
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                await MainActor.run {
                    if splashVisible { splashVisible = false }
                }
            }

            // Warm account-bound services only after the saved login has
            // been reconciled. Observe the flag instead of polling every
            // 50 ms so the main thread stays idle during restoration.
            await waitForSessionRestoration()
            guard authService.isSignedIn else {
                bootstrapWarming = false
                splashVisible = false
                return
            }

            let epoch = AccountStorage.generation
            splashVisible = false
            async let profile: Void = refreshProfileIfNeeded(generation: epoch)
            async let username: String? = LeaderboardService.shared.hydrateUsernameFromSupabase()
            async let flags: Void = UserFlagsService.shared.hydrate()
            async let friends: Void = FriendRequestsService.shared.refresh()
            async let followReqs: Void = WhisperFollowRequestService.shared.refresh()

            _ = await (profile, username)
            guard epoch == AccountStorage.generation, !Task.isCancelled else { return }
            if splashVisible { splashVisible = false; WhisperFeedback.ready() }
            _ = await (flags, friends, followReqs)
            guard epoch == AccountStorage.generation, !Task.isCancelled else { return }

            // Mirror only content already available. Widgets must not trigger
            // speculative inbox/story downloads during launch.
            await MainActor.run {
                WhisperBackendService.shared.cacheWidgetSnapshot()
            }

            await MainActor.run {
                bootstrapWarming = false
                if splashVisible {
                    splashVisible = false
                    WhisperFeedback.ready()
                }
            }
        }
    }

    private func refreshProfileIfNeeded(generation: UUID) async {
        guard !Task.isCancelled, generation == AccountStorage.generation,
              authService.profileLoadedGeneration != generation else { return }
        await authService.refreshProfileNow()
    }

    /// Suspends until `AuthenticationService.isRestoringSession` turns false,
    /// waking on the observation change rather than a timer.
    private func waitForSessionRestoration() async {
        while authService.isRestoringSession {
            if Task.isCancelled { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                withObservationTracking {
                    _ = authService.isRestoringSession
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }
}
