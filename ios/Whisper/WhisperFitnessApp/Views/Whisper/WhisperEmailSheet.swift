import SwiftUI

/// Whisper-branded monochrome email sign-in / sign-up sheet. Uses the same
/// Supabase auth backend as Whisper but visually owns Whisper's ink/surface
/// palette and wordmark.
struct WhisperEmailSheet: View {
    let onSubmit: (_ name: String, _ email: String, _ password: String, _ isSignIn: Bool, _ inviteCode: String) async -> String?
    let onForgotPassword: (_ email: String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var isSignIn: Bool = true
    @State private var switcher = WhisperAccountSwitcher.shared
    @FocusState private var passwordFocused: Bool
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var inviteCode: String = ""
    @State private var showPassword: Bool = false
    @State private var errorText: String?
    @State private var isSubmitting: Bool = false
    @State private var isResettingPassword: Bool = false
    @State private var resetSentMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        header
                            .padding(.top, 8)

                        if switcher.reauthAccount == nil { modePicker }

                        VStack(spacing: 12) {
                            if !isSignIn {
                                field(icon: "person.fill", placeholder: "Your name", text: $name, contentType: .name, keyboard: .default)
                            }
                            field(icon: isSignIn ? "person.crop.circle" : "envelope.fill", placeholder: isSignIn ? "Email, username or phone" : "Email address", text: $email, contentType: isSignIn ? .username : .emailAddress, keyboard: isSignIn ? .asciiCapable : .emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            passwordField(placeholder: "Password", text: $password)
                                .focused($passwordFocused)
                            if isSignIn {
                                Text("Phone sign-in uses a verified login number, including +country code.")
                                    .font(.caption).foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                            if !isSignIn {
                                passwordField(placeholder: "Confirm password", text: $confirmPassword)
                                field(icon: "link.badge.plus", placeholder: "Invite / creator code (optional)", text: $inviteCode, contentType: .username, keyboard: .asciiCapable)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                            }
                        }

                        if let errorText {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: { Task { await submit() } }) {
                            HStack(spacing: 8) {
                                if isSubmitting {
                                    ProgressView().tint(WhisperTheme.surface(colorScheme))
                                }
                                Text(isSignIn ? "Sign in to Whisper" : "Create Whisper account")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                canSubmit ? WhisperTheme.ink(colorScheme) : WhisperTheme.ink(colorScheme).opacity(0.3),
                                in: .rect(cornerRadius: 14)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit || isSubmitting)
                        .sensoryFeedback(.impact(weight: .medium), trigger: canSubmit)

                        if isSignIn {
                            Button {
                                Task { await sendPasswordReset() }
                            } label: {
                                HStack(spacing: 6) {
                                    if isResettingPassword { ProgressView().controlSize(.mini) }
                                    Text("Forgot password?")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                                        .underline()
                                }
                            }
                            .disabled(isResettingPassword)
                        }

                        if let resetSentMessage {
                            Text(resetSentMessage)
                                .font(.footnote)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .multilineTextAlignment(.center)
                        }

                        Text(isSignIn
                             ? "Welcome back. Sign in to keep posting on Whisper."
                             : "By creating an account you agree to Whisper's Terms and Privacy Policy.")
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .onAppear {
                if let account = switcher.reauthAccount {
                    isSignIn = true
                    email = account.email ?? "@\(account.username)"
                    password = ""
                    passwordFocused = true
                }
            }
            .navigationTitle(isSignIn ? "Sign in" : "Sign up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { switcher.reauthAccount = nil; dismiss() }
                        .disabled(isSubmitting)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            WhisperWordmark(size: 50)
            Text(switcher.reauthAccount.map { "Welcome back, @\($0.username)" } ?? (isSignIn ? "Welcome back" : "Join Whisper"))
                .font(.title2.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Quiet wins. Loud progress.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            modeChip("Sign up", selected: !isSignIn) { isSignIn = false; errorText = nil }
            modeChip("Sign in", selected: isSignIn)  { isSignIn = true;  errorText = nil }
        }
        .padding(4)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay {
            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func modeChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3)) { action() }
        } label: {
            Text(label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(selected ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(selected ? WhisperTheme.ink(colorScheme) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func field(icon: String, placeholder: String, text: Binding<String>, contentType: UITextContentType, keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .frame(width: 22)
            TextField(placeholder, text: text)
                .font(.body)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .textContentType(contentType)
                .keyboardType(keyboard)
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func passwordField(placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .frame(width: 22)
            Group {
                if showPassword {
                    TextField(placeholder, text: text)
                } else {
                    SecureField(placeholder, text: text)
                }
            }
            .font(.body)
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            .textContentType(isSignIn ? .password : .newPassword)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var canSubmit: Bool {
        if isSignIn { return !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty }
        guard isValidEmail(email), password.count >= 6 else { return false }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty &&
               password == confirmPassword
    }

    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@") else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return at != trimmed.startIndex && domain.contains(".")
    }

    private func sendPasswordReset() async {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard isValidEmail(trimmed) else {
            errorText = "Enter your email above so we know where to send the reset link."
            return
        }
        errorText = nil
        resetSentMessage = nil
        isResettingPassword = true
        let result = await onForgotPassword(trimmed)
        isResettingPassword = false
        if let result {
            errorText = result
        } else {
            resetSentMessage = "Reset link sent to \(trimmed)."
        }
    }

    private func submit() async {
        guard !isSubmitting else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if !isSignIn, trimmedName.isEmpty {
            errorText = "Please enter your name."
            return
        }
        guard isSignIn ? !trimmedEmail.isEmpty : isValidEmail(trimmedEmail) else {
            errorText = "Please enter a valid email address."
            return
        }
        guard isSignIn ? !password.isEmpty : password.count >= 6 else {
            errorText = "Password must be at least 6 characters."
            return
        }
        if !isSignIn, password != confirmPassword {
            errorText = "Passwords don't match."
            return
        }
        errorText = nil
        isSubmitting = true
        let result = await onSubmit(
            trimmedName,
            trimmedEmail,
            password,
            isSignIn,
            inviteCode.trimmingCharacters(in: .whitespaces)
        )
        isSubmitting = false
        if let result {
            errorText = result
        }
    }
}
