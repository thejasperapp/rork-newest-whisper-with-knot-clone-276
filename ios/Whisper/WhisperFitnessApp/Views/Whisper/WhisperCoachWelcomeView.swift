import SwiftUI

/// Celebration sheet shown the first time the user sees `is_coach = true`
/// after an admin approves their application. The "Take a tour" CTA dismisses
/// the sheet and routes the caller to `WhisperCoachProgramsView` (the coach
/// dashboard) where the tour content lives.
struct WhisperCoachWelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Invoked when the user taps **Take a tour**. The caller is expected
    /// to present `WhisperCoachProgramsView` after the sheet dismisses.
    let onTakeTour: () -> Void

    @State private var sealScale: CGFloat = 0.4
    @State private var sealRotation: Double = -18
    @State private var glowOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 16

    var body: some View {
        ZStack {
            // Warm gradient backdrop so the celebration reads instantly.
            LinearGradient(
                colors: [
                    WhisperTheme.coachAccent.opacity(0.22),
                    WhisperTheme.surface(colorScheme),
                    WhisperTheme.surface(colorScheme)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    seal
                        .padding(.top, 24)

                    VStack(spacing: 10) {
                        Text("Congratulations, Coach!")
                            .font(.system(size: 28, weight: .heavy))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text("Your application was approved. Welcome to the Whisper coaching crew.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .padding(.horizontal, 24)
                    }
                    .opacity(contentOpacity)
                    .offset(y: contentOffset)

                    perks
                        .opacity(contentOpacity)
                        .offset(y: contentOffset)

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 140)
            }

            VStack(spacing: 10) {
                Spacer()
                Button {
                    Haptics.success()
                    WhisperCoachService.shared.markCelebrated()
                    dismiss()
                    // Defer routing until after dismissal completes so the
                    // presenting view can swap in the programs sheet cleanly.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onTakeTour()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Take a tour")
                            .font(.headline)
                        Image(systemName: "arrow.right")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(WhisperTheme.coachAccent, in: Capsule())
                    .shadow(color: WhisperTheme.coachAccent.opacity(0.35), radius: 16, x: 0, y: 6)
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.tap()
                    WhisperCoachService.shared.markCelebrated()
                    dismiss()
                } label: {
                    Text("Maybe later")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .opacity(contentOpacity)
        }
        .interactiveDismissDisabled(false)
        .onDisappear {
            // If the user swipes the sheet to dismiss instead of tapping a
            // button, still mark the celebration as seen so it doesn't fire
            // again on every relaunch / inbox appearance.
            WhisperCoachService.shared.markCelebrated()
        }
        .onAppear {
            Haptics.success()
            withAnimation(.spring(response: 0.65, dampingFraction: 0.55)) {
                sealScale = 1.0
                sealRotation = 0
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.05)) {
                glowOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.45).delay(0.18)) {
                contentOpacity = 1
                contentOffset = 0
            }
        }
    }

    private var seal: some View {
        ZStack {
            Circle()
                .fill(WhisperTheme.coachAccent.opacity(0.18))
                .frame(width: 180, height: 180)
                .blur(radius: 22)
                .opacity(glowOpacity)
            Circle()
                .fill(WhisperTheme.coachAccent.opacity(0.14))
                .frame(width: 140, height: 140)
            ZStack {
                Image(systemName: "seal.fill")
                    .font(.system(size: 110, weight: .black))
                    .foregroundStyle(WhisperTheme.coachAccent)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(.white)
            }
            .shadow(color: WhisperTheme.coachAccent.opacity(0.45), radius: 18, x: 0, y: 10)
            .scaleEffect(sealScale)
            .rotationEffect(.degrees(sealRotation))
        }
        .frame(height: 200)
    }

    private var perks: some View {
        VStack(spacing: 10) {
            perkRow(
                icon: "seal.fill",
                title: "Verified coach badge",
                detail: "Your name now shows the coach badge across feeds, DMs, and your profile."
            )
            perkRow(
                icon: "dumbbell.fill",
                title: "Build & share programs",
                detail: "Use Coach Studio to design programs or send ones already saved in Whisper."
            )
            perkRow(
                icon: "paperplane.fill",
                title: "Send straight to clients",
                detail: "Programs land in the client's DM and import into their Whisper library in one tap."
            )
            perkRow(
                icon: "person.2.fill",
                title: "Coach priority in DMs",
                detail: "Messages from coaches skip the request queue for users who follow you."
            )
        }
    }

    private func perkRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(WhisperTheme.coachAccent.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WhisperTheme.coachAccent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }
}
