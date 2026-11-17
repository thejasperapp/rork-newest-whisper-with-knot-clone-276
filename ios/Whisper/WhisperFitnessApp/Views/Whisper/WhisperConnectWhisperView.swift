import SwiftUI

/// "Connect Whisper" sheet — optional account linking, Spotify-↔-Instagram
/// style. Primary path opens Whisper's one-tap Allow screen and silently
/// redeems the code it bounces back. Fallback path lets the user paste an
/// 8-char code from Whisper → Settings → Connect to Whisper (for when Whisper
/// isn't installed on this device). Once linked, shows status + Disconnect.
struct WhisperConnectWhisperView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var link = WhisperWhisperLinkService.shared
    @State private var code: String = ""
    @State private var showCodeEntry: Bool
    @State private var confirmDisconnect: Bool = false
    @FocusState private var codeFocused: Bool

    /// `startWithCode` opens straight onto the paste-a-code card — the
    /// one-button connect flow presents it this way as its fallback when
    /// Jasper isn't installed on this device.
    init(startWithCode: Bool = false) {
        _showCodeEntry = State(initialValue: startWithCode)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        header
                        if link.isLinked {
                            linkedCard
                        } else {
                            connectCard
                            codeFallback
                        }
                        if let msg = link.statusMessage {
                            Text(msg)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .transition(.opacity)
                        }
                        Text("Linking is optional. Whisper works fully without Jasper — connect to pull your workouts, nutrition and stats into your profile.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: link.isLinked)
                    .animation(.easeInOut(duration: 0.2), value: link.statusMessage)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showCodeEntry)
                }
            }
            .whisperNavigationBack()
            .navigationTitle("Connect Jasper")
            .navigationBarTitleDisplayMode(.inline)
            .task { await link.refreshStatus() }
            .confirmationDialog(
                "Disconnect from Jasper?",
                isPresented: $confirmDisconnect,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    Task { await link.disconnect() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your Jasper fitness sections will stop showing in Whisper. You can reconnect anytime.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(WhisperTheme.card(colorScheme))
                    .frame(width: 84, height: 84)
                    .overlay {
                        Circle().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
                Image(systemName: link.isLinked ? "link.circle.fill" : "dumbbell.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            Text(link.isLinked ? "Connected to Jasper" : "Bring your fitness into Whisper")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
        .padding(.top, 8)
    }

    // MARK: - Linked state

    private var linkedCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.96))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jasper account linked")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Your workouts, nutrition and stats sync into Whisper.")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
            }

            Button {
                Haptics.warning()
                confirmDisconnect = true
            } label: {
                Text("Disconnect")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                    }
            }
            .buttonStyle(.plain)
            .disabled(link.isBusy)
        }
    }

    // MARK: - Connect (deep link primary)

    private var connectCard: some View {
        VStack(spacing: 14) {
            Button {
                Haptics.tap()
                link.statusMessage = nil
                let opened = link.beginDeepLink()
                if !opened {
                    // Jasper isn't installed — reveal the paste-a-code path.
                    showCodeEntry = true
                    codeFocused = true
                    link.statusMessage = "Jasper isn't installed here. Enter the code from Jasper instead."
                }
            } label: {
                HStack(spacing: 10) {
                    if link.isBusy {
                        ProgressView()
                            .tint(WhisperTheme.surface(colorScheme))
                    }
                    Text(link.isBusy ? "Connecting…" : "Connect Jasper")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(link.isBusy)

            Text("Opens Jasper so you can tap Allow once — then you're back here, connected.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
    }

    // MARK: - Code fallback

    @ViewBuilder
    private var codeFallback: some View {
        if showCodeEntry {
            codeEntryCard
        } else {
            Button {
                Haptics.tap()
                showCodeEntry = true
                codeFocused = true
            } label: {
                Text("Jasper on another device? Enter a code")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .underline()
            }
            .buttonStyle(.plain)
        }
    }

    private var codeEntryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter the code from Jasper")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("In Jasper, go to Settings → Connect to Whisper to see your 8-character code.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))

            TextField("XXXXXXXX", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.title3.weight(.semibold).monospaced())
                .tracking(4)
                .focused($codeFocused)
                .submitLabel(.go)
                .onSubmit { submitCode() }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }

            Button {
                submitCode()
            } label: {
                HStack(spacing: 10) {
                    if link.isBusy { ProgressView().tint(WhisperTheme.surface(colorScheme)) }
                    Text("Redeem code")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    (canSubmit ? WhisperTheme.ink(colorScheme) : WhisperTheme.muted(colorScheme))
                        .opacity(canSubmit ? 1 : 0.5),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || link.isBusy)
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private var canSubmit: Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6
    }

    private func submitCode() {
        guard canSubmit, !link.isBusy else { return }
        Haptics.tap()
        codeFocused = false
        Task {
            let outcome = await link.redeem(code: code)
            if outcome == .linked { code = "" }
        }
    }
}
