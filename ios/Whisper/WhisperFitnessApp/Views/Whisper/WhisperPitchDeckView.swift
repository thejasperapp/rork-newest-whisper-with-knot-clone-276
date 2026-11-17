import SwiftUI
import SafariServices

/// Whisper pitch audience metadata — mirrors `PITCH_AUDIENCES` on the web so
/// the iOS hub shows the same five decks (brands, creators, athletes, coaches,
/// recruiters) in the same order with the same copy.
struct WhisperPitchAudience: Identifiable, Hashable {
    let id: String
    let title: String
    let tagline: String
    let blurb: String
    let icon: String
    let accent: Color

    /// Canonical public deck URL on the branded site.
    var deckURL: URL {
        URL(string: "\(WhisperBillingBackend.webOrigin)/pitch/\(id)")!
    }
}

let whisperPitchAudiences: [WhisperPitchAudience] = [
    WhisperPitchAudience(
        id: "brands",
        title: "Brands",
        tagline: "Sponsor the right creators — escrowed, tracked, automatic",
        blurb: "Post a sponsorship, see creators apply, accept or counter, fund escrow, and watch tracked posts release payment — all in one dashboard.",
        icon: "building.2.fill",
        accent: Color(red: 0.10, green: 0.10, blue: 0.12)
    ),
    WhisperPitchAudience(
        id: "creators",
        title: "Creators",
        tagline: "Get paid for the content you already make",
        blurb: "Brand marketplace walkthrough, sample sponsorship deals, and the WPP ad-revenue program.",
        icon: "sparkles",
        accent: Color(red: 0.45, green: 0.35, blue: 0.95)
    ),
    WhisperPitchAudience(
        id: "athletes",
        title: "Athletes",
        tagline: "Turn your training into sponsorships",
        blurb: "How athletes get discovered, featured, and sponsored — plus WPP earnings on top.",
        icon: "trophy.fill",
        accent: Color(red: 0.85, green: 0.65, blue: 0.15)
    ),
    WhisperPitchAudience(
        id: "coaches",
        title: "Coaches",
        tagline: "A real coaching business, built in",
        blurb: "The exact money flow: set your rate, clients subscribe, Stripe pays you out. Live calculator.",
        icon: "figure.strengthtraining.traditional",
        accent: Color(red: 0.98, green: 0.45, blue: 0.30)
    ),
    WhisperPitchAudience(
        id: "recruiters",
        title: "Recruiters",
        tagline: "Scout, track, and promote talent",
        blurb: "A live, clickable pipeline with sample talent, meeting requests, and one-tap promotions.",
        icon: "person.badge.checkmark",
        accent: Color(red: 0.66, green: 0.33, blue: 0.91)
    ),
]

/// Whether the signed-in user may open Pitch Mode — mirrors the web
/// `canOpenPitchMode(badge, isRecruiter)`. Moderators, admins, the founder,
/// and recruiters can walk prospects through live decks.
@MainActor
enum WhisperPitchAccess {
    static func canOpen() -> Bool {
        let me = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? ""
        let badge = UserVerificationService.shared.badge(forUsername: me)
        if badge == .moderator || badge == .admin || badge == .owner { return true }
        return WhisperRecruiterService.shared.isMeRecruiter
    }
}

/// Full-screen Pitch Mode hub for iOS. Shows the five audience decks as
/// tappable cards; tapping one opens the live web deck inside an in-app
/// SFSafariViewController so the user stays in the app while presenting.
/// Mirrors the web `/pitch` page so a prospect sees the same content on
/// either surface.
struct WhisperPitchDeckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var openAudience: WhisperPitchAudience?

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        heroCard
                        Text("AUDIENCE DECKS")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .tracking(0.6)
                            .padding(.horizontal, 16)
                        VStack(spacing: 12) {
                            ForEach(whisperPitchAudiences) { audience in
                                audienceCard(audience)
                            }
                        }
                        .padding(.horizontal, 16)
                        Text("Each deck uses the product's real views with clearly-marked sample data — every card, slider, pipeline stage, and payment ledger is clickable so you can demo the exact experience in a meeting. No data leaves your screen.")
                            .font(.footnote)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("Pitch Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .accessibilityLabel("Close")
                }
            }
            .sheet(item: $openAudience) { audience in
                WhisperPitchSafariSheet(url: audience.deckURL)
                    .ignoresSafeArea()
            }
        }
    }

    /// Branded hero — black stage with the wordmark, echoing the web hub.
    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.05, green: 0.05, blue: 0.07))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.subheadline.weight(.bold))
                    Text("Internal · Team")
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                }
                .foregroundStyle(.white.opacity(0.7))
                Text("Walk any prospect through Whisper, live.")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                Text("Interactive decks for every audience — open one and present from your phone.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("\(whisperPitchAudiences.count) audience decks")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
            }
            .padding(22)
        }
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private func audienceCard(_ audience: WhisperPitchAudience) -> some View {
        Button {
            Haptics.tap()
            openAudience = audience
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(audience.accent.opacity(0.12))
                    Image(systemName: audience.icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(audience.accent)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(audience.title)
                        .font(.body.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(audience.tagline)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(14)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(WhisperMenuPressStyle())
    }
}

/// In-app Safari sheet that loads a pitch deck URL so the user stays inside
/// the app while presenting. Uses `SFSafariViewController` for a native,
/// dismissable browser chrome.
struct WhisperPitchSafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        let safari = SFSafariViewController(url: url, configuration: config)
        safari.preferredControlTintColor = UIColor.label
        safari.dismissButtonStyle = .done
        return safari
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
