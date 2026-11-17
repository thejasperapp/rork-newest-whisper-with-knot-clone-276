import SwiftUI
import Supabase

/// Security & login center — Instagram-style settings surface covering:
/// - Saved login (one-tap sign-in) with Face ID and PIN protection
/// - Password change + emailed recovery link
/// - Two-factor authentication (authenticator app / TOTP)
/// - Signing out other devices
struct WhisperSecurityCenterView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var auth = AuthenticationService.shared
    @State private var quick = WhisperQuickLoginStore.shared
    private let supabase = SupabaseService.shared.client

    // Password change
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var passwordBusy: Bool = false
    @State private var passwordMessage: String?
    @State private var passwordError: String?

    // Recovery email
    @State private var resetBusy: Bool = false
    @State private var resetSent: Bool = false

    // 2FA
    @State private var mfaFactors: [Factor] = []
    @State private var mfaLoading: Bool = true
    @State private var mfaError: String?
    @State private var mfaLoadFailed: Bool = false

    // Sheets — ONE enum-driven `.sheet(item:)`. Stacking separate
    // `.sheet(isPresented:)` modifiers on the same view is the exact
    // pattern that hard-crashes release builds elsewhere in this app.
    private enum SecuritySheet: Identifiable {
        case pin(WhisperPinSheet.Mode)
        case enrollTOTP
        var id: String {
            switch self {
            case .pin(let mode): return "pin-\(mode.id)"
            case .enrollTOTP: return "enroll"
            }
        }
    }
    @State private var activeSheet: SecuritySheet?

    // Other devices
    @State private var signOutOthersBusy: Bool = false
    @State private var signOutOthersDone: Bool = false

    private var isEmailAccount: Bool { auth.currentUser.authProvider == .email }

    private var verifiedTOTPFactor: Factor? {
        mfaFactors.first { $0.factorType == "totp" && $0.status == .verified }
    }

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    quickLoginSection
                    passwordSection
                    twoFactorSection
                    devicesSection
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Security & login")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadFactors() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .pin(let mode):
                WhisperPinSheet(mode: mode) { pin in
                    if mode == .create {
                        quick.setPIN(pin)
                        Haptics.success()
                    }
                }
                .presentationDragIndicator(.visible)
                .whisperSheetBorder()
            case .enrollTOTP:
                WhisperTOTPEnrollSheet {
                    Task { await loadFactors() }
                }
                .whisperSheetBorder()
            }
        }
    }

    // MARK: - Quick login

    private var quickLoginSection: some View {
        card(title: "One-tap login", icon: "bolt.fill") {
            if let saved = quick.savedAccount {
                HStack(spacing: 12) {
                    WhisperAvatarChrome(
                        username: saved.username ?? saved.displayName,
                        size: 40,
                        imageURL: saved.avatarURL.flatMap(URL.init(string:))
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(saved.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text(saved.email)
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.bottom, 4)

                divider

                toggleRow(
                    icon: "faceid",
                    title: "Require Face ID",
                    isOn: Binding(
                        get: { quick.faceIDEnabled },
                        set: { newValue in
                            // Never arm biometrics on a device that can't
                            // evaluate them — the toggle would show "on"
                            // while every unlock silently falls through to
                            // PIN, which is confusing. Force it back off and
                            // surface why.
                            if newValue && !quick.biometricsAvailable {
                                quick.faceIDEnabled = false
                                mfaError = "This device doesn't have Face ID, Touch ID, or a passcode set up, so one-tap login can't be protected by biometrics."
                                Haptics.warning()
                            } else {
                                quick.faceIDEnabled = newValue
                                if newValue { Haptics.success() } else { Haptics.tap() }
                            }
                        }
                    )
                )

                divider

                actionRow(
                    icon: "circle.grid.3x3.fill",
                    title: quick.hasPIN ? "Change PIN" : "Set a PIN"
                ) {
                    activeSheet = .pin(.create)
                }

                if quick.hasPIN {
                    divider
                    actionRow(icon: "circle.slash", title: "Remove PIN", destructive: true) {
                        quick.removePIN()
                        Haptics.warning()
                    }
                }

                divider

                actionRow(icon: "trash", title: "Remove saved login", destructive: true) {
                    quick.clearSavedLogin()
                    Haptics.warning()
                }
            } else {
                Text(isEmailAccount
                     ? "Sign in with your email and password once and Whisper will offer one-tap login here."
                     : "One-tap login saves your last email sign-in. You're signed in with Apple, which is already one tap.")
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
    }

    // MARK: - Password

    private var passwordSection: some View {
        card(title: "Password", icon: "key.fill") {
            if isEmailAccount {
                secureRow(placeholder: "Current password", text: $currentPassword)
                secureRow(placeholder: "New password (6+ characters)", text: $newPassword)
                secureRow(placeholder: "Confirm new password", text: $confirmPassword)

                if let passwordError {
                    Text(passwordError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let passwordMessage {
                    Text(passwordMessage)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }

                Button {
                    Task { await changePassword() }
                } label: {
                    HStack(spacing: 8) {
                        if passwordBusy { ProgressView().controlSize(.small).tint(WhisperTheme.surface(colorScheme)) }
                        Text("Update password")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        canChangePassword ? WhisperTheme.ink(colorScheme) : WhisperTheme.ink(colorScheme).opacity(0.3),
                        in: .rect(cornerRadius: 12)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canChangePassword || passwordBusy)

                divider
            } else {
                Text("You sign in with Apple — your password lives with your Apple ID.")
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }

            actionRow(
                icon: "envelope.fill",
                title: resetSent ? "Recovery link sent — check your inbox" : "Email me a recovery link"
            ) {
                Task { await sendRecoveryEmail() }
            }
            .disabled(resetBusy || resetSent || (auth.currentUser.email ?? "").isEmpty)
        }
    }

    private var canChangePassword: Bool {
        !currentPassword.isEmpty && newPassword.count >= 6 && newPassword == confirmPassword
    }

    // MARK: - 2FA

    private var twoFactorSection: some View {
        card(title: "Two-factor authentication", icon: "shield.lefthalf.filled") {
            if mfaLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking your factors…")
                        .font(.footnote)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            } else if mfaLoadFailed {
                Text("Your two-factor status couldn’t be checked. No security settings were changed.")
                    .font(.footnote).foregroundStyle(WhisperTheme.muted(colorScheme))
                actionRow(icon: "arrow.clockwise", title: "Retry security check") {
                    Task { await loadFactors() }
                }
            } else if let factor = verifiedTOTPFactor {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Authenticator app is on")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text("A 6-digit code is required when signing in on a new device.")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    Spacer()
                }
                divider
                actionRow(icon: "xmark.shield", title: "Turn off two-factor", destructive: true) {
                    Task { await unenroll(factor) }
                }
            } else {
                Text("Add a second lock on your account. You'll scan a code with any authenticator app (Apple Passwords, Google Authenticator, 1Password) and enter a 6-digit code on new sign-ins.")
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                actionRow(icon: "plus.circle.fill", title: "Set up authenticator app") {
                    activeSheet = .enrollTOTP
                }
            }

            if let mfaError {
                Text(mfaError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Devices

    private var devicesSection: some View {
        card(title: "Where you're signed in", icon: "iphone.gen3") {
            Text("If something looks off, sign out everywhere else. This device stays signed in.")
                .font(.footnote)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            actionRow(
                icon: "rectangle.portrait.and.arrow.right",
                title: signOutOthersDone ? "Other devices signed out" : "Sign out of other devices",
                destructive: !signOutOthersDone
            ) {
                Task { await signOutOtherDevices() }
            }
            .disabled(signOutOthersBusy || signOutOthersDone)
        }
    }

    private var footer: some View {
        Text("If you enable one-tap login, your saved login credentials are protected by this device’s Keychain. Your app PIN is stored as a hash. You can remove saved login from this screen. Account recovery uses your email.")
            .font(.caption2)
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(.horizontal, 4)
    }

    // MARK: - Actions

    private func changePassword() async {
        passwordError = nil
        passwordMessage = nil
        guard let email = auth.currentUser.email, !email.isEmpty else {
            passwordError = "No email on file for this account."
            return
        }
        passwordBusy = true
        defer { passwordBusy = false }
        do {
            // Re-authenticate with the current password first so a stolen
            // unlocked phone can't silently change the password.
            _ = try await supabase.auth.signIn(email: email, password: currentPassword)
            _ = try await supabase.auth.update(user: UserAttributes(password: newPassword))
            // Keep one-tap login working with the new password.
            if quick.savedAccount?.email.lowercased() == email.lowercased() {
                quick.rememberLogin(
                    userID: auth.currentUser.userID,
                    email: email,
                    password: newPassword,
                    displayName: auth.currentUser.displayName ?? email,
                    username: auth.currentUser.username,
                    avatarURL: auth.currentUser.profileImageURL
                )
            }
            Haptics.success()
            passwordMessage = "Password updated."
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
        } catch {
            Haptics.warning()
            let text = error.localizedDescription.lowercased()
            passwordError = text.contains("invalid")
                ? "Your current password didn't match."
                : error.localizedDescription
        }
    }

    private func sendRecoveryEmail() async {
        guard let email = auth.currentUser.email, !email.isEmpty else { return }
        resetBusy = true
        defer { resetBusy = false }
        do {
            try await auth.sendPasswordReset(email: email)
            resetSent = true
            Haptics.success()
        } catch {
            passwordError = "Couldn't send the recovery email: \(error.localizedDescription)"
        }
    }

    private func loadFactors() async {
        let generation = AccountStorage.generation
        mfaLoading = true
        defer { if generation == AccountStorage.generation { mfaLoading = false } }
        do {
            let response = try await supabase.auth.mfa.listFactors()
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            mfaFactors = response.all
            mfaLoadFailed = false
            mfaError = nil
        } catch {
            guard generation == AccountStorage.generation else { return }
            mfaLoadFailed = true
        }
    }

    private func unenroll(_ factor: Factor) async {
        do {
            _ = try await supabase.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: factor.id))
            Haptics.warning()
            await loadFactors()
        } catch {
            mfaError = "Couldn't turn off two-factor: \(error.localizedDescription)"
        }
    }

    private func signOutOtherDevices() async {
        signOutOthersBusy = true
        defer { signOutOthersBusy = false }
        do {
            try await supabase.auth.signOut(scope: .others)
            signOutOthersDone = true
            Haptics.success()
        } catch {
            mfaError = "Couldn't sign out other devices: \(error.localizedDescription)"
        }
    }

    // MARK: - Building blocks

    private func card(title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .kerning(1.1)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(WhisperTheme.hairline(colorScheme))
            .frame(height: 0.5)
    }

    private func actionRow(
        icon: String,
        title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .foregroundStyle(destructive ? .red : WhisperTheme.ink(colorScheme))
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .frame(width: 22)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Toggle(title, isOn: isOn)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .tint(WhisperTheme.ink(colorScheme))
        }
        .padding(.vertical, 2)
    }

    private func secureRow(placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .font(.subheadline)
            .textContentType(.password)
            .padding(12)
            .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
    }
}

extension WhisperPinSheet.Mode: Identifiable {
    var id: String {
        switch self {
        case .create: return "create"
        case .verify: return "verify"
        }
    }
}

// MARK: - TOTP enrollment sheet

/// Guided authenticator-app setup: shows the secret + open-in-authenticator
/// link, then verifies the first 6-digit code to activate the factor.
struct WhisperTOTPEnrollSheet: View {
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private let supabase = SupabaseService.shared.client

    @State private var factorID: String?
    @State private var secret: String?
    @State private var uri: String?
    @State private var code: String = ""
    @State private var busy: Bool = false
    @State private var error: String?
    @State private var copied: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("1. Add Whisper to your authenticator")
                            .font(.headline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text("Open Apple Passwords, Google Authenticator, or 1Password and add a new one-time code with this secret.")
                            .font(.footnote)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))

                        if let secret {
                            Button {
                                UIPasteboard.general.string = secret
                                copied = true
                                Haptics.success()
                            } label: {
                                HStack {
                                    Text(secret)
                                        .font(.system(.footnote, design: .monospaced).weight(.semibold))
                                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                }
                                .padding(14)
                                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)

                            if let uri, let url = URL(string: uri) {
                                Button {
                                    Haptics.tap()
                                    UIApplication.shared.open(url)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.up.forward.app")
                                        Text("Open in authenticator app")
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    .underline()
                                }
                                .buttonStyle(.plain)
                            }
                        } else if error == nil {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Generating your secret…")
                                    .font(.footnote)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }

                        Text("2. Enter the 6-digit code")
                            .font(.headline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .padding(.top, 6)

                        TextField("123456", text: $code)
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .multilineTextAlignment(.center)
                            .padding(14)
                            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                            .onChange(of: code) { _, newValue in
                                code = String(newValue.filter(\.isNumber).prefix(6))
                            }

                        if let error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Button {
                            Task { await verify() }
                        } label: {
                            HStack(spacing: 8) {
                                if busy { ProgressView().controlSize(.small).tint(WhisperTheme.surface(colorScheme)) }
                                Text("Turn on two-factor")
                                    .font(.body.weight(.bold))
                            }
                            .foregroundStyle(WhisperTheme.surface(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                code.count == 6 ? WhisperTheme.ink(colorScheme) : WhisperTheme.ink(colorScheme).opacity(0.3),
                                in: .rect(cornerRadius: 14)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(code.count != 6 || busy || factorID == nil)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Authenticator setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        Task { await cancelEnrollment() }
                    }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .task { await enroll() }
    }

    private func enroll() async {
        do {
            let response = try await supabase.auth.mfa.enroll(
                params: MFAEnrollParams(issuer: "Whisper", friendlyName: "Whisper 2FA")
            )
            factorID = response.id
            secret = response.totp?.secret
            uri = response.totp?.uri
        } catch {
            self.error = "Couldn't start setup: \(error.localizedDescription)"
        }
    }

    private func verify() async {
        guard let factorID else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await supabase.auth.mfa.challengeAndVerify(
                params: MFAChallengeAndVerifyParams(factorId: factorID, code: code)
            )
            Haptics.success()
            onDone()
            dismiss()
        } catch {
            Haptics.warning()
            self.error = "That code didn't work — codes rotate every 30 seconds, try the newest one."
        }
    }

    /// Abandoning setup leaves an unverified factor behind — clean it up so
    /// it doesn't clutter the factor list.
    private func cancelEnrollment() async {
        if let factorID {
            _ = try? await supabase.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: factorID))
        }
        dismiss()
    }
}
