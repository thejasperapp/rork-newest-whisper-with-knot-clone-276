import SwiftUI

/// Full-screen "connection established" moment for Jasper Connect, dressed
/// in Jasper's own orange-glow language (thejasperapp.com): ink stage, ember
/// blooms, glow boxes. Plays after every successful one-tap authorize and
/// reopens from the settings card. Page 0 is the confirmation animation —
/// the marks slide together, an ember ring sweeps shut, the seal pops, then
/// the live "what Whisper sees" numbers stagger in — followed by a paged
/// walkthrough (deck-tour style) of what flows in, what you can do now, and
/// the ground rules.
struct JasperConnectionCelebration: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var client = JasperConnectClient.shared
    @State private var link = WhisperWhisperLinkService.shared
    @State private var snapshot: JasperLiveSnapshot?
    @State private var snapshotFailed = false

    var body: some View {
        JasperGlowWalkthrough(slides: slides, onDone: { dismiss() }) {
            JasperLinkConfirmation(title: "Connection established", subtitle: subtitleLine) {
                WhisperMarkTile()
            } below: {
                liveSection
            }
        }
        .task { await loadSnapshot(force: false) }
    }

    // MARK: Hero content

    private var subtitleLine: String {
        guard let info = client.connection else { return "Whisper ↔ Jasper" }
        var parts: [String] = []
        if let username = info.username { parts.append("@\(username)") }
        parts.append(info.scopeSummary)
        parts.append("Never expires")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var liveSection: some View {
        VStack(spacing: 12) {
            resolutionPill
            Group {
                if let snap = snapshot {
                    VStack(spacing: 10) {
                        JasperGlowCountsGrid(resources: snap.resources)
                        if snap.totalRows == 0 {
                            Text("Connected and readable — log a workout or meal in Jasper and it shows up here.")
                                .font(.caption2)
                                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
                                .multilineTextAlignment(.center)
                        }
                        if !snap.failedResources.isEmpty {
                            Text("Couldn't read \(snap.failedResources.joined(separator: ", ")) right now.")
                                .font(.system(size: 10))
                                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                        }
                    }
                } else if snapshotFailed {
                    failedCard
                } else {
                    JasperGlowPlaceholderGrid()
                }
            }
            Text("Live from the Jasper API — swipe to see what you can do now.")
                .font(.caption2)
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    /// §8.4 resolution: linked flag from Jasper's own authorize/me answer,
    /// falling back to Whisper's account-link service for older metadata.
    private var resolutionBadge: (label: String, icon: String, tint: Color) {
        guard let info = client.connection else {
            return ("Not connected", "exclamationmark.triangle.fill", JasperBrand.ember)
        }
        if info.linked == true { return ("Accounts linked", "link", Color(red: 0.36, green: 0.86, blue: 0.72)) }
        if info.username != nil {
            return ("Same account in both apps", "person.fill.checkmark", JasperBrand.text(colorScheme))
        }
        if info.linked == false {
            return ("No Jasper profile on this sign-in", "exclamationmark.triangle.fill", JasperBrand.ember)
        }
        return link.isLinked
            ? ("Accounts linked", "link", Color(red: 0.36, green: 0.86, blue: 0.72))
            : ("No Jasper profile on this sign-in", "exclamationmark.triangle.fill", JasperBrand.ember)
    }

    private var resolutionPill: some View {
        let badge = resolutionBadge
        return HStack(spacing: 5) {
            Image(systemName: badge.icon)
                .font(.system(size: 10, weight: .bold))
            Text(badge.label)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(badge.tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(badge.tint.opacity(0.14), in: .capsule)
    }

    private var failedCard: some View {
        JasperGlowBox(cornerRadius: 16, glow: 0.4) {
            VStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(JasperBrand.ember)
                Text("Couldn't read your Jasper data right now")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(JasperBrand.text(colorScheme))
                if let reason = client.lastLiveError {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                }
                Button {
                    Haptics.tap()
                    Task { await loadSnapshot(force: true) }
                } label: {
                    Text("Retry")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(JasperBrand.ember)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(JasperBrand.ember.opacity(0.14), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    private func loadSnapshot(force: Bool) async {
        snapshotFailed = false
        if let snap = await client.liveSnapshot(force: force) {
            snapshot = snap
        } else {
            snapshotFailed = client.connection != nil
        }
    }

    // MARK: Walkthrough slides

    private var slides: [JasperWalkthroughSlide] {
        [
            JasperWalkthroughSlide(
                id: "reads",
                kicker: "What flows in",
                title: "Your Jasper, everywhere in Whisper",
                rows: [
                    JasperWalkthroughRow(icon: "figure.strengthtraining.traditional",
                                         title: "Training & body",
                                         detail: "Workouts, programs, PRs, weight, and measurements — your last 30 days at a glance."),
                    JasperWalkthroughRow(icon: "fork.knife",
                                         title: "Nutrition",
                                         detail: "Meals with full macros, water, and your full diet plan — targets, daily meals, and Jasper's grocery checklist, verbatim."),
                    JasperWalkthroughRow(icon: "moon.zzz.fill",
                                         title: "Sleep & recovery",
                                         detail: "Sleep stages, readiness, heart rate, steps, and energy."),
                    JasperWalkthroughRow(icon: "waveform.path.ecg",
                                         title: "Biological age",
                                         detail: "Your calibrated bio-age history — display-only; nothing outside Jasper can ever write it."),
                ],
                extra: nativeLooksStrip()
            ),
            JasperWalkthroughSlide(
                id: "actions",
                kicker: "What you can do now",
                title: "Put it to work",
                rows: [
                    JasperWalkthroughRow(icon: "bubble.left.and.bubble.right.fill",
                                         title: "Share health cards in DMs",
                                         detail: "Send readiness, sleep, or bio-age as living cards — drawn exactly like Jasper draws them."),
                    JasperWalkthroughRow(icon: "tray.and.arrow.down.fill",
                                         title: "Post to your Jasper inbox",
                                         detail: "Any chart Jasper drafts in chat can land in your Jasper \"Shared with you\" inbox with one tap."),
                    JasperWalkthroughRow(icon: "sparkles",
                                         title: "Ask the assistant",
                                         detail: "Jasper is briefed every turn and pulls live — ask about your diet plan or groceries and it reads the API right then, then opens the real thing."),
                    JasperWalkthroughRow(icon: "square.and.pencil",
                                         title: "Log from Whisper",
                                         detail: "Workouts, meals, water, weight, and goals write straight into Jasper — one account, two apps."),
                ]
            ),
            JasperWalkthroughSlide(
                id: "control",
                kicker: "You're in control",
                title: "Your data, your rules",
                rows: [
                    JasperWalkthroughRow(icon: "key.fill",
                                         title: "One token, yours",
                                         detail: "Never expires, lives in your device Keychain, and rotates with one tap."),
                    JasperWalkthroughRow(icon: "hand.raised.fill",
                                         title: "Revoke anytime",
                                         detail: "Disconnect from either app — access dies instantly, and Whisper says so honestly."),
                    JasperWalkthroughRow(icon: "eye.fill",
                                         title: "See every connection",
                                         detail: "Every app or coach that can read your Jasper is listed in both apps — nothing hides."),
                    JasperWalkthroughRow(icon: "shield.lefthalf.filled",
                                         title: "Sensitive stays sensitive",
                                         detail: "Blood panels need an explicit opt-in, and progress photos never leave Jasper's private storage."),
                ],
                footnote: "Jasper re-verifies access on every single call."
            ),
        ]
    }

    /// Live demo strip of Jasper's native looks — the vitality blob and
    /// recovery ring rendered by the SAME runtime-spec renderers the real
    /// cards use.
    private func nativeLooksStrip() -> AnyView {
        AnyView(
            JasperGlowBox(cornerRadius: 18, glow: 0.5) {
                HStack(spacing: 14) {
                    JasperVitalityBlob(deltaYears: -2.4, size: 46, compact: true)
                    JasperRecoveryRing(score: 82, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Drawn in Jasper's own looks")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(JasperBrand.text(colorScheme))
                        Text("Live render specs from the API — a Jasper redesign restyles Whisper automatically.")
                            .font(.system(size: 11))
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        )
    }
}
