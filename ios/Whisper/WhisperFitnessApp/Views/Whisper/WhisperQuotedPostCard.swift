import SwiftUI

/// Hydrates the original under current visibility rules; never substitutes a stale snapshot.
struct WhisperQuotedPostCard: View {
    let payload: WhisperSharedPostEmbed.Payload
    let depth: Int
    let parentPostID: UUID?
    var isPreview: Bool = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.whisperMediaActive) private var surfaceActive
    @State private var post: WhisperPost? = nil
    @State private var authorID: String? = nil
    @State private var blocks = WhisperBlockService.shared
    @State private var follows = WhisperFollowService.shared
    @State private var loaded: Bool = false
    @State private var failed: Bool = false
    @State private var retry: Int = 0
    @State private var opensPost: Bool = false
    @State private var backend = WhisperBackendService.shared

    private var displayedPost: WhisperPost? {
        if let post { return post }
        guard UUID(uuidString: payload.postID) != parentPostID,
              let row = backend.cachedReferencedPost(postID: payload.postID) else { return nil }
        return WhisperRootView.mapRowToPost(row, fallbackUsername: row.username)
    }

    var body: some View {
        Group {
            if let post = displayedPost, !backend.deletedPostIDs.contains(payload.postID.lowercased()), !blocks.isBlocked(userID: authorID ?? "") {
                if depth == 0 {
                    AnyView(WhisperPostCard(post: post, isPreview: isPreview, quoteDepth: depth + 1))
                } else {
                    Button { opensPost = true } label: {
                        Label("Open quoted post", systemImage: "quote.bubble")
                            .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
                    }.buttonStyle(.plain)
                }
            } else if loaded {
                VStack(alignment: .leading, spacing: 8) {
                    Label(failed ? "Couldn't load quoted post" : "Quoted post unavailable", systemImage: "quote.bubble")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if failed { Button("Try again") { loaded = false; failed = false; retry += 1 }.frame(minHeight: 44) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            } else {
                ProgressView("Loading quoted post…").frame(maxWidth: .infinity, minHeight: 90)
            }
        }
        .background(WhisperTheme.surface(scheme), in: .rect(cornerRadius: 18))
        .clipShape(.rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(WhisperTheme.ink(scheme).opacity(0.18), lineWidth: 1))
        .task(id: "\(payload.postID)|\(retry)|\(surfaceActive)") {
            guard surfaceActive, !loaded else { return }
            let epoch = AccountStorage.generation
            let blocked = blocks.blockedUserIDs
            let following = follows.following
            failed = false
            guard let id = UUID(uuidString: payload.postID), id != parentPostID else { loaded = true; return }
            do {
                let row = try await backend.loadReferencedPost(postID: id.uuidString.lowercased())
                guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                authorID = row?.user_id
                let profile = if let row { await WhisperUserService.shared.fetchByUserID(row.user_id) } else { nil as WhisperUserRow? }
                guard !Task.isCancelled, epoch == AccountStorage.generation,
                      blocked == blocks.blockedUserIDs, following == follows.following,
                      !backend.deletedPostIDs.contains(payload.postID.lowercased()) else { return }
                post = row.map { WhisperRootView.mapRowToPost($0, fallbackUsername: profile?.username) }
                loaded = true
            } catch {
                guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                failed = true; loaded = true
            }
        }
        .onChange(of: blocks.blockedUserIDs) { _, _ in post = nil; loaded = false; retry += 1 }
        .onChange(of: follows.following) { _, _ in post = nil; loaded = false; retry += 1 }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in post = nil; loaded = false; retry += 1 }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            post = nil; loaded = true; opensPost = false
        }
        .fullScreenCover(isPresented: $opensPost) {
            if let post = displayedPost { WhisperPostDetailView(post: post) }
        }
    }
}
