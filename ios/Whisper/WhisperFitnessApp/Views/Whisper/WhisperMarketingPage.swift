import SwiftUI

/// A reusable full-screen marketing sheet in the style of Instagram's
/// subscription modal: a centered transparent product illustration floats above
/// a raised bottom card with a handle, a bold headline, a compact feature list,
/// legal copy, and a pinned round action button at the bottom. It uses the
/// Whisper system theme so it looks correct in both light and dark mode.
struct WhisperMarketingPage<Footer: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let config: WhisperCloudHeroConfig
    let title: String
    let subtitle: String
    let bullets: [(icon: String, title: String, body: String)]
    let legal: String?
    /// Maximum width for the hero illustration. Defaults to 220 (Whisper);
    /// Whisper One passes 300 for a larger hero.
    var heroMaxWidth: CGFloat = 220
    let footer: Footer

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                Spacer(minLength: 4)

                WhisperCloudHero(config: config)
                    .frame(maxWidth: heroMaxWidth)
                    .frame(minHeight: 80, idealHeight: 140, maxHeight: 180)

                Spacer(minLength: 4)

                contentCard
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .frame(width: 32, height: 32)
                    .background(WhisperTheme.card(colorScheme).opacity(0.8), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Bottom card

    private var contentCard: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                        .padding(.top, 20)

                    bulletsSection
                        .padding(.top, 22)

                    if let legal {
                        legalText(legal)
                            .padding(.top, 16)
                    }

                    Spacer(minLength: 12)

                    footerSection

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WhisperTheme.card(colorScheme))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 28,
                style: .continuous
            )
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            titleText
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
                .lineSpacing(1)

            Text(subtitle)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }

    private var titleText: some View {
        HStack(spacing: 0) {
            let accent = config.accent
            let words = title.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            let accentWords: Set<String> = [config.accentWord]
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                let isAccent = accentWords.contains(word)
                Text(index == 0 ? word : " \(word)")
                    .foregroundStyle(isAccent ? accent : WhisperTheme.ink(colorScheme))
            }
        }
    }

    // MARK: - Bullets

    private var bulletsSection: some View {
        VStack(spacing: 0) {
            ForEach(bullets.indices, id: \.self) { i in
                let bullet = bullets[i]
                bulletRow(bullet)
                if i < bullets.count - 1 {
                    Divider()
                        .background(WhisperTheme.hairline(colorScheme))
                        .padding(.leading, 44)
                }
            }
        }
    }

    private func bulletRow(_ bullet: (icon: String, title: String, body: String)) -> some View {
        HStack(spacing: 14) {
            Image(systemName: bullet.icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(bullet.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))

                if !bullet.body.isEmpty {
                    Text(bullet.body)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.vertical, bullet.body.isEmpty ? 12 : 10)
    }

    // MARK: - Legal

    private func legalText(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.7))
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .padding(.horizontal, 8)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            footer
        }
    }
}

// MARK: - Cloud hero

enum WhisperCloudHeroConfig {
    case jasper
    case whisperOne

    var accent: Color {
        switch self {
        case .jasper:
            return Color(red: 0.96, green: 0.45, blue: 0.13) // Whisper orange
        case .whisperOne:
            return Color(red: 0.25, green: 0.85, blue: 0.65) // Whisper mint
        }
    }

    var accentWord: String {
        switch self {
        case .jasper: return "Whisper"
        case .whisperOne: return "One"
        }
    }

    /// The exact image asset to use as the hero. These PNGs have transparent
    /// backgrounds so they float cleanly on the Whisper system surface.
    var imageName: String? {
        switch self {
        case .jasper: return "jasper_promo_hero"
        case .whisperOne: return "whisper_one_hero"
        }
    }
}

/// The marketing hero. If the config supplies an image asset name we render that
/// exact transparent image at the top — otherwise we fall back to the flat
/// cloud/doodle illustration.
struct WhisperCloudHero: View {
    @Environment(\.colorScheme) private var colorScheme
    let config: WhisperCloudHeroConfig

    var body: some View {
        if let imageName = config.imageName {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 340)
                .frame(maxHeight: 260)
                .accessibilityLabel(heroAccessibilityLabel)
        } else {
            drawnCloudHero
        }
    }

    private var heroAccessibilityLabel: String {
        switch config {
        case .jasper: return "Whisper illustration: a cloud with fitness icons, a heart rate, a dumbbell, and a paper airplane."
        case .whisperOne: return "Whisper One illustration: a cloud with a camera, a heart, a checkmark, and a paper airplane."
        }
    }

    private var drawnCloudHero: some View {
        ZStack {
            CloudShape()
                .fill(colorScheme == .dark ? Color.white : Color(white: 0.96))
                .frame(width: 240, height: 140)
                .offset(y: 40)
                .blur(radius: 28)

            CloudShape()
                .fill(colorScheme == .dark ? Color.white : Color(white: 0.96))
                .overlay(
                    CloudShape()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: WhisperTheme.ink(colorScheme).opacity(0.08), radius: 20, x: 0, y: 10)
                .frame(width: 240, height: 140)
                .offset(y: 40)
        }
        .frame(width: 280, height: 200)
    }
}

// MARK: - Cloud shape

private struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()

        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: w, y: h * 0.55))
        p.addCurve(
            to: CGPoint(x: w * 0.75, y: h * 0.20),
            control1: CGPoint(x: w * 0.94, y: h * 0.55),
            control2: CGPoint(x: w * 0.90, y: h * 0.20)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.08),
            control1: CGPoint(x: w * 0.65, y: h * 0.12),
            control2: CGPoint(x: w * 0.58, y: h * 0.08)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.25, y: h * 0.20),
            control1: CGPoint(x: w * 0.42, y: h * 0.08),
            control2: CGPoint(x: w * 0.35, y: h * 0.12)
        )
        p.addCurve(
            to: CGPoint(x: 0, y: h * 0.55),
            control1: CGPoint(x: w * 0.10, y: h * 0.20),
            control2: CGPoint(x: w * 0.06, y: h * 0.55)
        )
        p.closeSubpath()
        return p
    }
}

#Preview("Whisper") {
    WhisperMarketingPage(
        config: .jasper,
        title: "Whisper",
        subtitle: "AI fitness coach by the Whisper team",
        bullets: [
            ("dumbbell", "Workouts that adapt to you", ""),
            ("apple.logo", "Track macros in seconds", ""),
            ("person.badge.plus", "Hire coaches from Whisper", ""),
            ("person.2", "Sync with your circle", "")
        ],
        legal: "By downloading Whisper, you agree to the App Store Terms and Whisper's Privacy Policy.",
        footer: Text("Footer")
    )
}

#Preview("Whisper One") {
    WhisperMarketingPage(
        config: .whisperOne,
        title: "Whisper One",
        subtitle: "Unlock the full Whisper experience",
        bullets: [
            ("plus.circle", "Whisper One + badge", ""),
            ("person.2", "Coach tools — 3 client slots", ""),
            ("chart.bar.xaxis", "Analytics — reach, interactions, top posts", ""),
            ("figure.strengthtraining.traditional", "Hire & book coaches", "")
        ],
        legal: "Cancel anytime. Subscription auto-renews until canceled. Manage your subscription from Settings.",
        footer: Text("Footer")
    )
}
