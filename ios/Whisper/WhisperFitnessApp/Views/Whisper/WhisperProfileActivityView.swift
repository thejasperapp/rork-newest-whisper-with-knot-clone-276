import SwiftUI

/// Public activity queried for the viewed account, never the viewer's saved fallback.
struct WhisperProfileActivityView: View {
    let userID: String
    let username: String
    let tab: WhisperProfileTab
    @State private var posts: [WhisperPostRow] = []
    @State private var replies: [WhisperReplyPair] = []
    @State private var loading: Bool = true
    @State private var failed: Bool = false
    @State private var retry: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if loading {
                ProgressView("Loading \(tab.label.lowercased())…")
                    .frame(maxWidth: .infinity).padding(.vertical, 32)
            } else if failed {
                VStack(spacing: 12) {
                    Text("Couldn't load activity").font(.headline)
                    Button("Try again") { retry += 1 }.buttonStyle(.bordered)
                }.padding(24)
            } else if posts.isEmpty && replies.isEmpty {
                WhisperProfileEmptyState(illustration: tab == .reposts ? .reposts : .replies, title: "No \(tab.label.lowercased()) to show", message: "Public \(tab.label.lowercased()) from @\(username) appear here.")
                    .padding(.horizontal, 16).padding(.top, 24)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(posts) { row in
                        WhisperPostCard(post: WhisperRootView.mapRowToPost(row))
                        Divider()
                    }
                    ForEach(replies) { pair in
                        WhisperPostCard(post: WhisperRootView.mapRowToPost(pair.post))
                        HStack(alignment: .top, spacing: 10) {
                            WhisperAvatar(username: pair.myComment.username, size: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pair.myComment.username).font(.subheadline.weight(.semibold))
                                WhisperCommentBodyView(text: pair.myComment.body)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        Divider()
                    }
                }
            }
        }
        .task(id: "\(userID)-\(tab.rawValue)-\(retry)") {
            posts = []; replies = []; loading = true; failed = false
            let generation = AccountStorage.generation
            do {
            if tab == .replies {
                let rows = try await WhisperBackendService.shared.fetchRepliedPosts(userID: userID)
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                let allowed = Set(try await WhisperPostVisibilityService.visible(rows.map(\.post)).map(\.id))
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                replies = rows.filter { allowed.contains($0.post.id) }.map { WhisperReplyPair(post: $0.post, myComment: $0.myComment) }
            } else {
                let rows = try await WhisperRepostService.shared.fetchPublicReposts(userID: userID)
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                let allowed = try await WhisperPostVisibilityService.visible(rows)
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                posts = allowed
            }
            } catch {
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                failed = true
            }
            loading = false
        }
    }
}
