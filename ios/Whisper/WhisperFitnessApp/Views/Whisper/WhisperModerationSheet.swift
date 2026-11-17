import SwiftUI

/// Action sheet shown when a moderator / admin / owner taps the ellipsis on a
/// post (or a profile). Allows muting (silencing posts/comments for a set
/// duration) and — for admins+ — banning the account outright.
struct WhisperModerationSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var moderation = WhisperModerationService.shared

    let username: String

    @State private var scope: WhisperModerationScope = .all
    @State private var duration: WhisperMuteDuration = .oneDay
    @State private var reason: String = ""
    @State private var confirmingBan: Bool = false

    private var viewerBadge: UserBadge { moderation.viewerBadge() }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        targetCard
                        if viewerBadge.canMute { muteSection }
                        if viewerBadge.canBan { banSection }
                        Color.clear.frame(height: 24)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Moderate @\(username)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .alert("Ban @\(username)?", isPresented: $confirmingBan) {
                Button("Cancel", role: .cancel) {}
                Button("Ban", role: .destructive) {
                    Task {
                        await moderation.ban(username: username, reason: reason.isEmpty ? nil : reason)
                        Haptics.success()
                        dismiss()
                    }
                }
            } message: {
                Text("They won't be able to post, comment, or appear in feeds. You can lift this from the moderator dashboard.")
            }
        }
    }

    private var targetCard: some View {
        HStack(spacing: 12) {
            WhisperAvatar(username: username, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("@\(username)")
                        .font(.headline)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    VerifiedBadge(badge: UserVerificationService.shared.badge(forUsername: username), size: 14, username: username)
                }
                Text(roleSubtitle)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var roleSubtitle: String {
        let role = viewerBadge
        switch role {
        case .owner:     return "Acting as owner"
        case .admin:     return "Acting as admin"
        case .moderator: return "Acting as moderator"
        default:         return "View-only"
        }
    }

    private var muteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Mute", systemImage: "speaker.slash.fill")

            Text("Restrict")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Picker("Scope", selection: $scope) {
                ForEach(WhisperModerationScope.allCases, id: \.self) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)

            Text("Duration")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.top, 4)
            durationGrid

            Text("Reason (optional)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.top, 4)
            TextField("e.g. spamming the comments", text: $reason, axis: .vertical)
                .lineLimit(2...4)
                .padding(12)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }

            Button {
                Haptics.tap()
                Task {
                    await moderation.mute(username: username, duration: duration,
                                          scope: scope, reason: reason.isEmpty ? nil : reason)
                    Haptics.success()
                    dismiss()
                }
            } label: {
                Text("Mute \(duration.label) · \(scope.label)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            if moderation.isMuted(username) {
                Button {
                    Haptics.tap()
                    Task {
                        await moderation.unmute(username: username)
                        Haptics.success()
                        dismiss()
                    }
                } label: {
                    Text("Lift mute")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var durationGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(WhisperMuteDuration.allCases, id: \.self) { d in
                Button {
                    Haptics.tap()
                    duration = d
                } label: {
                    Text(d.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(duration == d ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(duration == d ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme),
                                    in: .rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var banSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Ban", systemImage: "nosign")
            Text("Permanent removal from Whisper. Use sparingly — appeals come to your inbox.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            if moderation.isBanned(username) {
                Button {
                    Haptics.tap()
                    Task {
                        await moderation.unban(username: username)
                        Haptics.success()
                        dismiss()
                    }
                } label: {
                    Text("Lift ban")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Haptics.tap()
                    confirmingBan = true
                } label: {
                    Text("Ban account")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
            Text(title)
                .font(.headline)
        }
        .foregroundStyle(WhisperTheme.ink(colorScheme))
    }
}
