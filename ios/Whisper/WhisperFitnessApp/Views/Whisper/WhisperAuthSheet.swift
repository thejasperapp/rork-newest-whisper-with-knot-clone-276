import SwiftUI
import AuthenticationServices

/// Whisper-branded sign-in sheet — a floating glass card over a simulated
/// feed backdrop, mirroring the web's centered auth card over flowing posts.
/// Same Supabase auth backend as Whisper, but a dedicated, monochrome surface
/// so Whisper feels like its own product.
struct WhisperAuthSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthenticationService.shared
    @State private var quick = WhisperQuickLoginStore.shared
    @State private var switcher = WhisperAccountSwitcher.shared
    @State private var quickBusy: Bool = false
    @State private var returningToAccount: Bool = false
    @State private var error: String?

    /// "Add account" mode — the sheet is up because the user asked for a
    /// second login, so it offers the way back instead of a dead ✕.
    private var addingAccount: Bool { switcher.isAddingAccount }
    private var lastAccount: WhisperSwitchableAccount? {
        switcher.accounts.sorted { $0.lastActiveAt > $1.lastActiveAt }.first
    }

    /// One enum-driven `.sheet(item:)` — stacking separate
    /// `.sheet(isPresented:)` modifiers on the same view crashes
    /// release builds when presentations overlap.
    private enum AuthSheet: Int, Identifiable {
        case email, pinVerify
        var id: Int { rawValue }
    }
    @State private var activeSheet: AuthSheet?

    var body: some View {
        NavigationStack {
            ZStack {
                // Simulated feed backdrop — flows edge to edge behind the card.
                WhisperSimulatedFeedBackdrop()
                    .ignoresSafeArea()

                // Floating auth card — centered, glass surface over the feed.
                // Floating auth card — centered vertically like the web's
                // `items-center justify-center min-h-screen` layout.
                ScrollView {
                    VStack(spacing: 24) {
                        header
                        authButtons
                        legalText
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 380)
                    .background(
                        (colorScheme == .dark
                            ? WhisperTheme.darkIndigo.opacity(0.88)
                            : Color.white.opacity(0.90)
                        )
                        .clipShape(.rect(cornerRadius: 28))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 28)
                            .strokeBorder(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.14)
                                    : Color.black.opacity(0.06),
                                lineWidth: 0.8
                            )
                    }
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08),
                            radius: 30, y: 12)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.center)
            }
            .navigationBarTitleDisplayMode(.inline)
            .whisperEdgeBack(isEnabled: addingAccount && lastAccount != nil && !returningToAccount, requiresDecision: true, revealPresentation: false) {
                guard !returningToAccount else { return }
                returningToAccount = true
                Task { _ = await switcher.returnToLastAccount(); returningToAccount = false }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if addingAccount, let back = lastAccount {
                        Button {
                            Haptics.tap()
                            guard !returningToAccount else { return }
                            returningToAccount = true
                            Task {
                                _ = await switcher.returnToLastAccount()
                                returningToAccount = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if returningToAccount {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "chevron.left")
                                        .font(.footnote.weight(.bold))
                                }
                                Text("Back to @\(back.username)")
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(
                                (colorScheme == .dark
                                    ? Color.white.opacity(0.12)
                                    : Color.white.opacity(0.7)
                                ),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(returningToAccount)
                    } else {
                        Button {
                            Haptics.tap()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .frame(width: 32, height: 32)
                                .background(
                                    (colorScheme == .dark
                                        ? Color.white.opacity(0.12)
                                        : Color.white.opacity(0.7)
                                    ),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .pinVerify:
                WhisperPinSheet(mode: .verify) { _ in
                    Task { await performQuickLogin() }
                }
                .whisperSheetBorder()
            case .email:
                emailSheet
            }
        }
        .task(id: switcher.reauthAccount?.userID) {
            if switcher.reauthAccount != nil { activeSheet = .email }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            WhisperWordmark(size: 44)
            Text(addingAccount ? "Add a Whisper account" : "Sign in to Whisper")
                .font(.title2.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text(addingAccount
                 ? "Sign in to another account. Your current login stays saved on this phone — switch back anytime from your profile."
                 : "Save your posts, send DMs, and bring your Whisper progress along.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Auth buttons

    private var authButtons: some View {
        VStack(spacing: 12) {
            if switcher.reauthAccount == nil, let saved = quick.savedAccount {
                quickLoginCard(saved)
            }

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
                request.nonce = auth.prepareAppleNonce()
            } onCompletion: { result in
                handleAppleResult(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 54)
            .clipShape(.rect(cornerRadius: 14))

            Button {
                Haptics.tap()
                activeSheet = .email
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                    Text("Email, phone or username")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var legalText: some View {
        VStack(spacing: 8) {
            Text("By continuing you agree to Whisper’s [Terms](https://www.mydailywhisper.com/terms) and [Privacy Policy](https://www.mydailywhisper.com/privacy).")
            Text("AI sharing is optional. Knot asks once before your first chat; you can change your choice anytime.")
        }
        .font(.caption2)
        .foregroundStyle(WhisperTheme.muted(colorScheme))
        .multilineTextAlignment(.center)
    }

    // MARK: - Email sheet

    private var emailSheet: some View {
        WhisperEmailSheet(
            onSubmit: { name, email, password, isSignIn, inviteCode in
                do {
                    if isSignIn {
                        try await auth.signIn(identifier: email, password: password, expectedUserID: switcher.reauthAccount?.userID)
                    } else {
                        try await auth.signUpWithEmail(name: name, email: email, password: password)
                        let code = inviteCode
                        let newUserID = auth.currentUser.userID
                        if !code.isEmpty, newUserID != "guest" {
                            Task { await WhisperReferralService.redeem(code: code, newUserID: newUserID) }
                        }
                    }
                    Haptics.success()
                    await MainActor.run {
                        activeSheet = nil
                        dismiss()
                    }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            },
            onForgotPassword: { email in
                do {
                    try await auth.sendPasswordReset(email: email)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .whisperSheetBorder()
    }

    // MARK: - Quick login

    /// One-tap "Continue as" card for the last saved email login. Gated by
    /// Face ID (when enabled) or the user's PIN before firing.
    private func quickLoginCard(_ saved: WhisperSavedAccount) -> some View {
        Button {
            Haptics.tap()
            startQuickLogin()
        } label: {
            HStack(spacing: 12) {
                WhisperAvatarChrome(
                    username: saved.username ?? saved.displayName,
                    size: 44,
                    imageURL: saved.avatarURL.flatMap(URL.init(string:))
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue as \(saved.username.map { "@\($0)" } ?? saved.displayName)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    Text(saved.email)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
                Spacer()
                if quickBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: quick.faceIDEnabled && quick.biometricsAvailable ? "faceid" : (quick.hasPIN ? "circle.grid.3x3.fill" : "arrow.right.circle.fill"))
                        .font(.title3)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .padding(14)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(quickBusy)
        .contextMenu {
            Button(role: .destructive) {
                quick.clearSavedLogin()
            } label: {
                Label("Remove saved login", systemImage: "trash")
            }
        }
    }

    /// Route the tap through the right lock: Face ID first (when enabled and
    /// available), then PIN, otherwise straight to sign-in.
    private func startQuickLogin() {
        error = nil
        if quick.faceIDEnabled, quick.biometricsAvailable {
            Task {
                if await quick.unlockWithBiometrics() {
                    await performQuickLogin()
                } else if quick.hasPIN {
                    await MainActor.run { activeSheet = .pinVerify }
                }
            }
        } else if quick.hasPIN {
            activeSheet = .pinVerify
        } else {
            Task { await performQuickLogin() }
        }
    }

    private func performQuickLogin() async {
        guard let saved = quick.savedAccount,
              let password = quick.storedPassword() else {
            error = "Saved login is incomplete — sign in with your email once to refresh it."
            return
        }
        quickBusy = true
        defer { quickBusy = false }
        do {
            try await auth.signInWithEmail(email: saved.email, password: password)
            Haptics.success()
            dismiss()
        } catch {
            self.error = "One-tap login failed — your password may have changed. Sign in manually to refresh it."
            print("[QuickLogin] Sign-in failed: \(error.localizedDescription)")
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authResult):
            guard let credential = authResult.credential as? ASAuthorizationAppleIDCredential else {
                error = "Apple sign-in returned an unexpected credential."
                return
            }
            Task {
                do {
                    try await auth.applyAppleCredential(credential)
                    Haptics.success()
                    await MainActor.run { dismiss() }
                } catch {
                    await MainActor.run { self.error = error.localizedDescription }
                }
            }
        case .failure(let err):
            let ns = err as NSError
            if let code = ASAuthorizationError.Code(rawValue: ns.code),
               ns.domain == ASAuthorizationError.errorDomain {
                switch code {
                case .canceled:
                    return
                case .notHandled, .failed, .invalidResponse, .notInteractive:
                    error = "Apple sign-in didn't complete. Check that you're online and signed into iCloud, then try again."
                case .unknown:
                    error = "Apple sign-in failed. Please try again."
                @unknown default:
                    error = err.localizedDescription
                }
                print("[Auth] Apple sign-in failed: domain=\(ns.domain) code=\(ns.code) info=\(ns.userInfo)")
            } else {
                error = err.localizedDescription
                print("[Auth] Apple sign-in failed (non-AS error): \(err)")
            }
        }
    }
}
