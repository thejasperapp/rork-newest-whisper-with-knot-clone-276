import SwiftUI

struct WhisperAccountTransitionView: View {
    let transition: WhisperAccountTransition
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared: Bool = false

    var body: some View {
        ZStack {
            WhisperTheme.surface(scheme).ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer(minLength: 24)
                WhisperAccountAvatarMedallion(isReady: transition.isReady, isPaused: transition.isPrivate || transition.errorMessage != nil, avatar: avatar)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.86)
                    .rotation3DEffect(.degrees(appeared || reduceMotion ? 0 : -55), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                    .offset(y: appeared || reduceMotion ? 0 : 16)
                    .animation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.12), value: appeared)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: transition.isReady ? "checkmark" : "arrow.left.arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WhisperTheme.surface(scheme))
                        .frame(width: 36, height: 36)
                        .background(WhisperTheme.ink(scheme), in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: transition.isReady)
                }
                .accessibilityHidden(true)

                VStack(spacing: 9) {
                    Text(transition.errorMessage == nil ? (transition.isReady ? "You're in" : "Switching account") : "Let's try that again")
                        .font(.title2.weight(.semibold))
                    Text("@\(transition.username)")
                        .font(.body.weight(.medium))
                        .foregroundStyle(WhisperTheme.muted(scheme))
                        .lineLimit(2)
                    if let error = transition.errorMessage {
                        Text(error).font(.subheadline).foregroundStyle(WhisperTheme.muted(scheme))
                            .padding(.top, 8)
                    } else if transition.isTakingLonger && !transition.isReady {
                        Text("Still connecting. Your saved accounts are safe.")
                            .font(.subheadline).foregroundStyle(WhisperTheme.muted(scheme))
                            .padding(.top, 8)
                    }
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)

                if transition.errorMessage != nil {
                    VStack(spacing: 10) {
                        if transition.canRetry {
                            Button("Try again") { transition.retryNow() }
                                .buttonStyle(.borderedProminent).tint(WhisperTheme.ink(scheme))
                                .controlSize(.large)
                        }
                        Button(transition.recoveryTitle) { transition.recover() }
                            .buttonStyle(.bordered).controlSize(.large)
                    }
                } else {
                    ProgressView().tint(WhisperTheme.muted(scheme))
                        .opacity(transition.isReady ? 0 : 1)
                        .accessibilityLabel("Preparing your profile")
                }
                Spacer(minLength: 24)
                Text("Whisper").font(.headline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(scheme)).padding(.bottom, 24)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 440)
            .opacity(transition.isPrivate ? 0 : 1)
        }
        .foregroundStyle(WhisperTheme.ink(scheme))
        .onAppear { appeared = true }
        .accessibilityIdentifier("accountSwitchTransition")
    }

    private var avatar: some View {
        Circle().fill(WhisperBrandGradient.accent.opacity(0.22))
            .frame(width: 116, height: 116)
            .overlay {
                WhisperCachedAsyncImage(url: transition.avatarURL, maxPixelSize: 320) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill().allowsHitTesting(false)
                    } else {
                        Text(transition.username.first.map { String($0).uppercased() } ?? "W")
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                    }
                }
            }
            .clipShape(Circle())
    }
}
