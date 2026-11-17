import SwiftUI

/// Facebook-style stories carousel slotted into the feed every N posts.
/// Renders rectangular tiles (same dimensions as the legacy reels strip)
/// so the feed gets a second, more visual entry point into stories beyond
/// the small avatar strip at the top.
struct FeedStoriesCarousel: View {
    /// Tuple matches `WhisperStoryService.storiesByUser()`.
    typealias Group = (username: String, userID: String, latest: WhisperStoryRow, all: [WhisperStoryRow])

    let groups: [Group]
    let storyService: WhisperStoryService
    let onCreateStory: () -> Void
    let onOpenStory: (WhisperStoryRow) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let tileWidth: CGFloat = 130
    private let tileHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "circle.dashed")
                    .font(.subheadline.weight(.bold))
                Text("Stories")
                    .font(.subheadline.weight(.bold))
                Spacer()
            }
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    createTile
                    ForEach(groups, id: \.userID) { group in
                        storyTile(group: group)
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
        }
    }

    private var createTile: some View {
        let me = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
        return Button {
            Haptics.tap()
            onCreateStory()
        } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.55, blue: 1.0),
                        Color(red: 0.10, green: 0.30, blue: 0.85)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: tileWidth, height: tileHeight)
                .clipShape(.rect(cornerRadius: 14))
                .overlay(alignment: .top) {
                    WhisperAvatar(username: me, size: 44, ring: false)
                        .padding(.top, 14)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 28, height: 28)
                            Image(systemName: "plus")
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 1.0))
                        }
                        Text("Create\nstory")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    .padding(10)
                }
            }
            .frame(width: tileWidth, height: tileHeight)
        }
        .buttonStyle(.plain)
    }

    private func storyTile(group: Group) -> some View {
        let story = group.latest
        let url = URL(string: story.image_url)
        let unseen = storyService.hasUnseenStories(userID: group.userID)
        return Button {
            Haptics.tap()
            onOpenStory(story)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Color(.secondarySystemBackground)
                    .frame(width: tileWidth, height: tileHeight)
                    .overlay {
                        if let url {
                            WhisperCachedAsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    LinearGradient(
                                        colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                }
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 14))

                // Avatar (top-left)
                WhisperAvatar(
                    username: group.username,
                    size: 36,
                    imageURL: URL(string: story.image_url),
                    ring: unseen
                )
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)

                // Username footer with darkening gradient
                Text(group.username)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
                    .lineLimit(1)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(.rect(cornerRadius: 14))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
            .frame(width: tileWidth, height: tileHeight)
        }
        .buttonStyle(.plain)
    }
}
