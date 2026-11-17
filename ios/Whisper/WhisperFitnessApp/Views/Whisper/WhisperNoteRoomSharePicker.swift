import SwiftUI

/// "Share to the room" — pick one of the room owner's posts (or your own)
/// and drop it into a notes room as the same shared-post card DMs use.
/// Rows render the exact card the room will show, so what you pick is what
/// everyone sees.
struct WhisperNoteRoomSharePicker: View {
    let ownerUID: String?
    let ownerUsername: String?
    let onPick: (WhisperPost) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var backend = WhisperBackendService.shared
    @State private var scope: Scope = .theirs

    enum Scope: String, CaseIterable, Identifiable {
        case theirs = "Their posts"
        case mine = "Your posts"
        var id: String { rawValue }
    }

    private var me: String { AccountStorage.currentUserID.lowercased() }

    /// True when the room belongs to someone else — the scope picker only
    /// makes sense then (your own room has one source: you).
    private var hasOwner: Bool {
        guard let owner = ownerUID?.lowercased(), !owner.isEmpty else { return false }
        return owner != me
    }

    private var posts: [WhisperPost] {
        let target: String = (scope == .theirs && hasOwner) ? (ownerUID ?? me).lowercased() : me
        return backend.posts
            .filter { $0.user_id.lowercased() == target }
            .prefix(60)
            .map { row in
                WhisperRootView.mapRowToPost(
                    row,
                    fallbackUsername: backend.postAuthorProfiles[row.user_id]?.username
                )
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if hasOwner {
                        Picker("Whose posts", selection: $scope) {
                            ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 4)
                    }
                    if posts.isEmpty {
                        emptyState
                    } else {
                        ForEach(posts, id: \.id) { post in
                            WhisperSharedPostInlineCard(
                                payload: Self.payload(for: post),
                                mine: false
                            ) {
                                Haptics.tap()
                                onPick(post)
                                dismiss()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(WhisperTheme.surface(colorScheme))
            .navigationTitle("Share to the room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            WhisperMeetDoodle(symbol: "photo.on.rectangle", height: 120)
            Text(
                scope == .theirs && hasOwner
                    ? "@\(ownerUsername ?? "they") hasn't posted anything yet."
                    : "You haven't posted anything yet."
            )
            .font(.footnote)
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: Wire

    /// The shared-post payload for a post — the same fields the share sheet
    /// sends, so the room's card and a DM's card are identical.
    static func payload(for post: WhisperPost) -> WhisperSharedPostEmbed.Payload {
        let isWave = post.isReel || post.mediaURLs.contains(where: { WhisperVideo.isVideo($0) })
        return WhisperSharedPostEmbed.Payload(
            postID: post.id.uuidString.lowercased(),
            username: post.username,
            caption: post.displayCaption,
            kindRaw: post.kind.rawValue,
            symbol: post.symbol,
            accentHex: post.accent.toHex(),
            mediaURL: post.mediaURLs.first?.absoluteString,
            isVideo: post.mediaURLs.first.map { WhisperVideo.isVideo($0) } ?? false,
            likes: post.likes,
            comments: post.comments,
            isReel: isWave
        )
    }

    /// The encoded message body that carries the card.
    static func body(for post: WhisperPost) -> String {
        WhisperSharedPostEmbed.encode(payload(for: post))
    }
}
