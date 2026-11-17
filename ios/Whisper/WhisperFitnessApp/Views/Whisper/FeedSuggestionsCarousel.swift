import SwiftUI

/// "People to follow" inline shelf. Facebook-style: full-width horizontal
/// scroll of compact user cards with minimal chrome so the break feels like
/// native content, not a banner.
struct FeedSuggestionsCarousel: View {
    let users: [WhisperUserRow]
    let follows: WhisperFollowService
    let onOpenUser: (WhisperUserRow) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAll: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(users.prefix(10)) { u in
                        card(u)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 14)
        .background(WhisperTheme.surface(colorScheme))
        .sheet(isPresented: $showAll) {
            WhisperPeopleSeeAllSheet(users: users, follows: follows, onOpenUser: onOpenUser)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("People to follow")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer()
            WhisperShelfSeeAllButton { showAll = true }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func card(_ u: WhisperUserRow) -> some View {
        let followed = follows.isFollowing(userID: u.user_id)
        let avatarURL = u.profile_image_url.flatMap(URL.init(string:))
        return VStack(spacing: 10) {
            Button {
                Haptics.tap()
                onOpenUser(u)
            } label: {
                VStack(spacing: 8) {
                    WhisperAvatar(username: u.username, size: 64, imageURL: avatarURL, ring: false)
                    Text(u.username)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    if let bio = u.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineLimit(1)
                            .frame(width: 110)
                    } else {
                        Text("Suggested")
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                Task {
                    if followed {
                        await follows.unfollow(userID: u.user_id)
                    } else {
                        await follows.follow(userID: u.user_id, username: u.username)
                    }
                }
            } label: {
                Text(followed ? "Following" : "Follow")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(followed ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        followed
                        ? WhisperTheme.card(colorScheme)
                        : WhisperTheme.ink(colorScheme),
                        in: .rect(cornerRadius: 8)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: followed ? 1 : 0)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 140)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .contentShape(.rect)
    }
}
