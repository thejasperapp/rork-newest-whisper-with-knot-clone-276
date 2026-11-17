import SwiftUI

/// Lists every user who liked a post. Opens when the user taps the
/// "<n> likes" counter under a post card (Instagram-style).
struct WhisperPostLikesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let postID: String

    @State private var likers: [WhisperLiker] = []
    @State private var loading: Bool = true
    @State private var error: String?
    @State private var retry: Int = 0
    @State private var page: Int = 0
    @State private var hasMore: Bool = false
    @State private var openUser: WhisperUserRow?
    @State private var follows = WhisperFollowService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                if loading && likers.isEmpty {
                    ProgressView()
                        .tint(WhisperTheme.ink(colorScheme))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, likers.isEmpty {
                    VStack(spacing: 12) {
                        Text(error).multilineTextAlignment(.center)
                        Button("Try again") { retry += 1 }.frame(minHeight: 44)
                    }.padding(24)
                } else if likers.isEmpty {
                    WhisperEmptyState(
                        icon: "heart",
                        title: "No likes yet",
                        message: "Be the first one to tap that heart."
                    )
                    .padding(.horizontal, 16)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(likers) { liker in
                                row(liker)
                                Divider().background(WhisperTheme.hairline(colorScheme))
                            }
                            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                            if hasMore {
                                Button(loading ? "Loading…" : error == nil ? "Load more" : "Retry") {
                                    if error == nil { page += 1 } else { retry += 1 }
                                }.frame(minHeight: 44).disabled(loading)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Likes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .task(id: "\(page)|\(retry)") {
                let epoch = AccountStorage.generation
                loading = true; error = nil
                do {
                    let rows = try await WhisperBackendService.shared.loadPostLikers(postID: postID, offset: page * 50)
                    guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                    var seen = Set(likers.map(\.id))
                    likers.append(contentsOf: rows.filter { seen.insert($0.id).inserted })
                    hasMore = rows.count == 50; loading = false
                } catch {
                    guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                    self.error = "Couldn't load likes. Check your connection and try again."; loading = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in likers = []; openUser = nil; dismiss() }
            .navigationDestination(item: $openUser) { user in
                WhisperUserProfileView(user: user)
            }
        }
    }

    private func row(_ liker: WhisperLiker) -> some View {
        let followed = follows.isFollowing(userID: liker.user_id)
        let isMe = liker.user_id.lowercased() == AccountStorage.currentUserID.lowercased()
        let url = liker.profile_image_url.flatMap(URL.init(string:))
        return Button {
            Haptics.tap()
            openUser = WhisperUserRow(
                user_id: liker.user_id,
                username: liker.username,
                display_name: liker.display_name,
                bio: nil,
                interests: nil,
                profile_image_url: liker.profile_image_url,
                onboarded_at: nil,
                is_private: nil
            )
        } label: {
            HStack(spacing: 12) {
                WhisperAvatar(username: liker.username, size: 42, imageURL: url, ring: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(liker.username)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    if let name = liker.display_name, !name.isEmpty {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !isMe {
                    Button {
                        Haptics.tap()
                        Task {
                            if followed {
                                await follows.unfollow(userID: liker.user_id)
                            } else {
                                await follows.follow(userID: liker.user_id, username: liker.username)
                            }
                        }
                    } label: {
                        Text(followed ? "Following" : "Follow")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(followed ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(
                                followed ? WhisperTheme.card(colorScheme) : WhisperTheme.ink(colorScheme),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule().strokeBorder(
                                    followed ? WhisperTheme.hairline(colorScheme) : .clear,
                                    lineWidth: 1
                                )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
