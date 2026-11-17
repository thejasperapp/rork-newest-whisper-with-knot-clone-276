import SwiftUI

/// Celebration sheet shown the first time the user sees `is_verified = true`
/// after an admin approves their verification application. Walks the user
/// through the perks they just unlocked (blue check, algorithm boost,
/// long-form whispers, etc.) — mirrors the Coach welcome flow.
struct WhisperVerifiedWelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var sealScale: CGFloat = 0.4
    @State private var sealRotation: Double = -18
    @State private var glowOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 16

    private let perks: [Perk] = [
        Perk(
            icon: "checkmark.seal.fill",
            title: "Blue verified check",
            detail: "A blue check now shows next to your name across feed, comments, DMs, and stories."
        ),
        Perk(
            icon: "chart.line.uptrend.xyaxis",
            title: "1.6× algorithmic boost",
            detail: "Your posts surface to more new viewers in Discover and the main feed."
        ),
        Perk(
            icon: "flame.fill",
            title: "Trending priority",
            detail: "Verified posts surface above non-verified accounts when trending scores are close."
        ),
        Perk(
            icon: "bell.badge.fill",
            title: "Time-sensitive pushes",
            detail: "Your followers' notifications can break through Focus modes when supported."
        ),
        Perk(
            icon: "sparkles",
            title: "Suggested account",
            detail: "Eligible to be featured to new signups in the suggested-accounts rail."
        ),
        Perk(
            icon: "envelope.badge.shield.half.filled",
            title: "Verified-only DM filter",
            detail: "Optional setting to only receive DMs from other verified accounts."
        ),
        Perk(
            icon: "text.alignleft",
            title: "Long-form whispers",
            detail: "Your character limit jumps from 500 to 1,500 across posts, replies, and threads."
        ),
        Perk(
            icon: "wand.and.stars",
            title: "Early access",
            detail: "First in line for new Whisper features as they roll out."
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.20, green: 0.55, blue: 1.0).opacity(0.22),
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
                        Text("You're verified!")
                            .font(.system(size: 28, weight: .heavy))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text("Welcome to the verified club. Here's what your new blue check unlocks.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .padding(.horizontal, 24)
                    }
                    .opacity(contentOpacity)
                    .offset(y: contentOffset)

                    VStack(spacing: 10) {
                        ForEach(perks) { perk in
                            perkRow(perk)
                        }
                    }
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
                    WhisperVerificationService.shared.markCelebrated()
                    dismiss()
                } label: {
                    Text("Got it")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 0.20, green: 0.55, blue: 1.0), in: Capsule())
                        .shadow(color: Color(red: 0.20, green: 0.55, blue: 1.0).opacity(0.35),
                                radius: 16, x: 0, y: 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .opacity(contentOpacity)
        }
        .interactiveDismissDisabled(false)
        .onDisappear {
            // Mark celebrated even if the user swipes away so it doesn't
            // re-fire on every relaunch.
            WhisperVerificationService.shared.markCelebrated()
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
                .fill(Color(red: 0.20, green: 0.55, blue: 1.0).opacity(0.18))
                .frame(width: 180, height: 180)
                .blur(radius: 22)
                .opacity(glowOpacity)
            Circle()
                .fill(Color(red: 0.20, green: 0.55, blue: 1.0).opacity(0.14))
                .frame(width: 140, height: 140)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 120, weight: .black))
                .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 1.0))
                .shadow(color: Color(red: 0.20, green: 0.55, blue: 1.0).opacity(0.45),
                        radius: 18, x: 0, y: 10)
                .scaleEffect(sealScale)
                .rotationEffect(.degrees(sealRotation))
        }
        .frame(height: 200)
    }

    private func perkRow(_ perk: Perk) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.20, green: 0.55, blue: 1.0).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: perk.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 1.0))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(perk.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(perk.detail)
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

    private struct Perk: Identifiable {
        let id: String
        let icon: String
        let title: String
        let detail: String

        init(icon: String, title: String, detail: String) {
            self.id = title
            self.icon = icon
            self.title = title
            self.detail = detail
        }
    }
}
