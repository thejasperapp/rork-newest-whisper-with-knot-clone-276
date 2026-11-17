import SwiftUI

/// Tappable teaser card for Whisper in Whisper Settings. Tapping opens the
/// Whisper product page with a native-style download banner that rises from
/// the bottom — like the smart app banners websites show when they have an
/// app available.
struct WhisperWhisperPromoCard: View {
    @Environment(\.colorScheme) private var colorScheme

    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/jasper-fitness-made-easy/id6753958717")
    static let websiteURL = URL(string: "https://www.thejasperapp.com")
    private static let deepLink = URL(string: "jasper://")

    private var isInstalled: Bool {
        guard let deepLink = Self.deepLink else { return false }
        return UIApplication.shared.canOpenURL(deepLink)
    }

    private var ink: Color {
        colorScheme == .dark ? .white : .black
    }

    private var muted: Color {
        ink.opacity(0.55)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image("WhisperGhostMono")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text("Get Jasper")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ink)

                Text("AI fitness coach by the Whisper team")
                    .font(.caption)
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}

// MARK: - Full-page product sheet with bottom smart-app banner

/// Whisper product page. Content scrolls (hero, ratings strip, feature list)
/// while a native-feeling download banner slides UP from the bottom edge —
/// the way websites surface their app — with the real Whisper app icon and a
/// GET button into the App Store.
struct WhisperWhisperPromoPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var bannerShown: Bool = false

    private var jasperOrange: Color { Color(red: 0.96, green: 0.45, blue: 0.13) }

    private var isInstalled: Bool {
        guard let deepLink = URL(string: "jasper://") else { return false }
        return UIApplication.shared.canOpenURL(deepLink)
    }

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    WhisperCloudHero(config: .jasper)
                        .frame(maxWidth: 290)
                        .frame(minHeight: 120, maxHeight: 210)
                        .padding(.top, 46)

                    VStack(spacing: 8) {
                        Text("Jasper")
                            .font(.system(size: 30, weight: .black))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text("Fitness made easy \u{2014} by the Whisper team")
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .padding(.top, 6)

                    statsStrip
                        .padding(.top, 20)

                    featureList
                        .padding(.top, 14)

                    Button {
                        Haptics.tap()
                        if let url = WhisperWhisperPromoCard.websiteURL {
                            WhisperInAppBrowser.shared.open(url)
                        }
                    } label: {
                        Text("Learn more at thejasperapp.com")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)

                    Text("By downloading Jasper, you agree to the App Store Terms and Jasper's Privacy Policy.")
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 12)
                        // Leave room for the floating bottom banner.
                        .padding(.bottom, 130)
                }
                .padding(.horizontal, 22)
            }

            // Close
            VStack {
                HStack {
                    Spacer()
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .frame(width: 30, height: 30)
                            .background(WhisperTheme.card(colorScheme).opacity(0.9), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.top, 14)
                }
                Spacer()
            }

            // Smart app banner — rises from the bottom like a native
            // "open in app" bar.
            VStack {
                Spacer()
                smartAppBanner
                    .offset(y: bannerShown ? 0 : 180)
                    .opacity(bannerShown ? 1 : 0)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.25)) {
                bannerShown = true
            }
        }
    }

    /// The native-style download bar: real app icon tile, name + rating,
    /// and a GET pill — pinned to the bottom edge.
    private var smartAppBanner: some View {
        HStack(spacing: 12) {
            // Real Whisper app icon look — the ghost mark on its signature
            // orange tile, matching the App Store icon.
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [jasperOrange, Color(red: 1.0, green: 0.60, blue: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image("WhisperGhostMono")
                    .resizable()
                    .scaledToFit()
                    .padding(9)
            }
            .frame(width: 58, height: 58)
            .shadow(color: jasperOrange.opacity(0.35), radius: 10, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("Jasper \u{2014} Fitness Made Easy")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\u{2605}\u{2605}\u{2605}\u{2605}\u{2605}")
                        .font(.system(size: 10))
                        .foregroundStyle(jasperOrange)
                    Text("4.9 \u{00B7} Health & Fitness")
                        .font(.system(size: 11))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Text("Free \u{00B7} On the App Store")
                    .font(.system(size: 10.5))
                    .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.8))
            }

            Spacer(minLength: 0)

            Button {
                Haptics.success()
                openWhisper()
            } label: {
                Text(isInstalled ? "OPEN" : "GET")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(jasperOrange, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
    }

    private func openWhisper() {
        if let deepLink = URL(string: "jasper://"), UIApplication.shared.canOpenURL(deepLink) {
            UIApplication.shared.open(deepLink)
        } else if let store = WhisperWhisperPromoCard.appStoreURL {
            UIApplication.shared.open(store)
        }
    }

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statCell(top: "4.9", bottom: "\u{2605}\u{2605}\u{2605}\u{2605}\u{2605}")
            statDivider
            statCell(top: "Free", bottom: "Price")
            statDivider
            statCell(top: "Health", bottom: "& Fitness")
            statDivider
            statCell(top: "4+", bottom: "Age")
        }
        .padding(.vertical, 12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private func statCell(top: String, bottom: String) -> some View {
        VStack(spacing: 3) {
            Text(top)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text(bottom)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(WhisperTheme.hairline(colorScheme))
            .frame(width: 0.75, height: 28)
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            featureRow(icon: "dumbbell", title: "Workouts that adapt to you", detail: "AI programs that adjust as you get stronger")
            rowDivider
            featureRow(icon: "apple.logo", title: "Track macros in seconds", detail: "Snap a photo \u{2014} Jasper logs the rest")
            rowDivider
            featureRow(icon: "person.badge.plus", title: "Hire coaches from Whisper", detail: "Your Whisper coach's plans sync automatically")
            rowDivider
            featureRow(icon: "person.2", title: "Sync with your circle", detail: "Share workouts and stats with friends")
        }
        .padding(.horizontal, 16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private var rowDivider: some View {
        Divider()
            .background(WhisperTheme.hairline(colorScheme))
            .padding(.leading, 42)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(jasperOrange)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    WhisperWhisperPromoPage()
}
