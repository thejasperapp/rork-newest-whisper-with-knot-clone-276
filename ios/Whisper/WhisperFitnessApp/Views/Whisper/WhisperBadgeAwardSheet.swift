import SwiftUI

/// Celebration popup shown the first time a user earns a badge. Mirrors the
/// look & feel of `WhisperCoachWelcomeView` — animated glyph, accent
/// gradient, celebratory copy — and includes a "Share" CTA so the user can
/// post the achievement to their stories or another platform.
struct WhisperBadgeAwardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let kind: WhisperBadgeKind
    /// Called after the user dismisses the sheet (Done/Share both count).
    /// The presenter should clear the pending state.
    let onDismiss: () -> Void

    @State private var liar = WhisperLiarLiarService.shared
    @State private var sealScale: CGFloat = 0.4
    @State private var sealRotation: Double = -18
    @State private var glowOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 16
    @State private var presentShare: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    kind.accent.opacity(0.28),
                    WhisperTheme.surface(colorScheme),
                    WhisperTheme.surface(colorScheme)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    seal
                        .padding(.top, 24)
                    titleBlock
                        .opacity(contentOpacity)
                        .offset(y: contentOffset)
                    detailCard
                        .opacity(contentOpacity)
                        .offset(y: contentOffset)
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 160)
            }

            VStack(spacing: 10) {
                Spacer()
                Button {
                    Haptics.tap()
                    presentShare = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.headline)
                        Text("Share badge")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(kind.accent, in: Capsule())
                    .shadow(color: kind.accent.opacity(0.4), radius: 16, x: 0, y: 6)
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.tap()
                    finish()
                } label: {
                    Text("Done")
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
        .sheet(isPresented: $presentShare) {
            WhisperBadgeShareSheet(kind: kind)
        }
        .interactiveDismissDisabled(false)
        .onDisappear {
            // If the user swipes to dismiss, still mark the badge as seen
            // so the popup doesn't fire again next launch.
            WhisperBadgeAwardService.shared.markSeen(kind)
            onDismiss()
        }
    }

    private func finish() {
        WhisperBadgeAwardService.shared.markSeen(kind)
        dismiss()
    }

    private var seal: some View {
        ZStack {
            Circle()
                .fill(kind.accent.opacity(0.20))
                .frame(width: 200, height: 200)
                .blur(radius: 24)
                .opacity(glowOpacity)
            Circle()
                .fill(kind.accent.opacity(0.14))
                .frame(width: 150, height: 150)
            kind.view(size: 96, liar: liar)
                .scaleEffect(sealScale)
                .rotationEffect(.degrees(sealRotation))
                .shadow(color: kind.accent.opacity(0.45), radius: 18, x: 0, y: 10)
        }
        .frame(height: 210)
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text("Badge unlocked")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(kind.accent)
            Text(kind.title)
                .font(.system(size: 30, weight: .heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text(kind.tagline)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 24)
        }
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(kind.accent)
                Text("What this means")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            Text(kind.celebrationCopy)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }
}
