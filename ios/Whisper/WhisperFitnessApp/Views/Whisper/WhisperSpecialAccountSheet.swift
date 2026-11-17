import SwiftUI

/// Whisper's replacement for "professional account". Instead of generic
/// creator/business toggles, Whisper offers a curated "Special account"
/// type tailored to the fitness audience.
struct WhisperSpecialAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: String

    private struct Tier: Identifiable, Hashable {
        let id: String
        let title: String
        let icon: String
        let blurb: String
        let perks: [String]
    }

    private let tiers: [Tier] = [
        .init(
            id: "Coach",
            title: "Coach",
            icon: "figure.strengthtraining.traditional",
            blurb: "For trainers who run programs and clients.",
            perks: [
                "Verified coach badge",
                "Share Whisper programs to your feed",
                "Client roster + booking link",
                "Workout cards open into Whisper"
            ]
        ),
        .init(
            id: "Athlete",
            title: "Athlete",
            icon: "trophy.fill",
            blurb: "For competitors logging real numbers.",
            perks: [
                "Verified PRs pulled from Whisper",
                "Stat sheet pinned to profile",
                "Athlete-only roster + scouting filter",
                "Meet/event countdown widget"
            ]
        ),
        .init(
            id: "Creator",
            title: "Creator",
            icon: "sparkles",
            blurb: "For those who post the journey, not just the result.",
            perks: [
                "Long-form progress threads",
                "Series & playlists on profile",
                "Audience insights (no ads)",
                "Tip jar with one-tap setup"
            ]
        ),
        .init(
            id: "Studio",
            title: "Studio / Gym",
            icon: "building.2.fill",
            blurb: "For gyms, studios, and teams.",
            perks: [
                "Location pin + class schedule",
                "Member shoutouts feed",
                "Branded story highlights",
                "Group challenge hosting"
            ]
        )
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        header
                        ForEach(tiers) { tier in
                            tierCard(tier)
                        }
                        if !selection.isEmpty {
                            Button {
                                Haptics.warning()
                                selection = ""
                                dismiss()
                            } label: {
                                Text("Switch back to standard account")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        WhisperWordmark(size: 22)
                        Text("Special")
                            .font(.headline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Pick your Special account")
                .font(.title3.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Whisper isn't generic. Pick the lane that matches how you train.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 8)
    }

    private func tierCard(_ tier: Tier) -> some View {
        let active = selection == tier.id
        return Button {
            Haptics.success()
            selection = tier.id
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                dismiss()
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: tier.icon)
                        .font(.body.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(width: 38, height: 38)
                        .background(WhisperTheme.ink(colorScheme), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tier.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text(tier.blurb)
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    Spacer()
                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tier.perks, id: \.self) { perk in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .padding(.top, 2)
                            Text(perk)
                                .font(.footnote)
                                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.85))
                        }
                    }
                }
                .padding(.leading, 50)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(active ? WhisperTheme.ink(colorScheme) : WhisperTheme.hairline(colorScheme), lineWidth: active ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}
