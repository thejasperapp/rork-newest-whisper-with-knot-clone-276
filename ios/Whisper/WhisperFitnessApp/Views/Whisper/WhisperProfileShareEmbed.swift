import SwiftUI

/// Inline "shared profile" card sent through DM when a user shares someone's
/// profile in a chat. Encodes the profile's key info so we can render a rich
/// preview card inside the chat bubble and deep-link to the full profile on tap.
nonisolated enum WhisperProfileShareEmbed {
    static let prefix = "::whisper-profileshare-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let userID: String
        let username: String
        let displayName: String?
        let bio: String?
        let avatarURL: String?
        let isVerified: Bool
        let shareURL: String

        var id: String { userID }
    }

    nonisolated static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    nonisolated static func decode(_ body: String) -> Payload? {
        guard body.hasPrefix(prefix) else { return nil }
        let json = String(body.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return p
    }

    /// Builds a payload from a cached public profile.
    static func make(
        userID: String,
        profile: WhisperBackendService.WhisperPublicProfile
    ) -> Payload {
        let username = profile.username ?? "user"
        let handle = username
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return Payload(
            userID: userID,
            username: username,
            displayName: profile.display_name,
            bio: nil,
            avatarURL: profile.profile_image_url,
            isVerified: profile.is_verified ?? false,
            shareURL: "https://mydailywhisper.com/p/\(handle)"
        )
    }

    /// Builds a payload from a user row (lighter info).
    static func make(from user: WhisperUserRow) -> Payload {
        let handle = user.username
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user.username
        return Payload(
            userID: user.user_id,
            username: user.username,
            displayName: user.display_name,
            bio: user.bio,
            avatarURL: user.profile_image_url,
            isVerified: false,
            shareURL: "https://mydailywhisper.com/p/\(handle)"
        )
    }
}

/// Compact card rendered inside a DM bubble representing a shared profile.
/// Shows avatar, username, bio snippet, and follower count — tapping pushes
/// the full profile view.
struct WhisperProfileShareInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperProfileShareEmbed.Payload
    let mine: Bool
    var onTap: () -> Void

    private var textColor: Color {
        mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme)
    }
    private var mutedColor: Color {
        (mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme)).opacity(0.65)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Hero strip with avatar
                HStack(spacing: 12) {
                    WhisperAvatar(
                        username: payload.username,
                        size: 56,
                        imageURL: payload.avatarURL.flatMap(URL.init(string:)),
                        ring: payload.isVerified
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(payload.displayName ?? payload.username)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(textColor)
                                .lineLimit(1)
                            if payload.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(textColor.opacity(0.7))
                            }
                        }
                        Text("@\(payload.username)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(mutedColor)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)

                // Bio snippet
                if let bio = payload.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.caption)
                        .foregroundStyle(textColor.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }

                // Footer
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.caption2.weight(.bold))
                    Text("View profile")
                        .font(.caption2.weight(.bold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(textColor.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(width: 264, alignment: .leading)
            .background(
                mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme),
                in: .rect(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        mine ? Color.clear : WhisperTheme.hairline(colorScheme),
                        lineWidth: 1
                    )
            }
            .clipShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}
