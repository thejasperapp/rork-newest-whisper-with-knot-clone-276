import SwiftUI

struct WhisperPostActivityRow: View {
    let item: WhisperPostActivityItem
    let onProfile: () -> Void
    let onQuote: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var follows = WhisperFollowService.shared
    @State private var requests = WhisperFollowRequestService.shared
    @State private var followerCount: Int?
    @State private var working: Bool = false
    @State private var followError: Bool = false
    @State private var requested: Bool = false
    @State private var generation: UUID = AccountStorage.generation
    private var followed: Bool { follows.isFollowing(userID: item.profile.user_id) }
    private var pending: Bool { requested || requests.outgoing.contains { $0.target_id.lowercased() == item.profile.user_id.lowercased() && $0.status == "pending" } }
    private var isMe: Bool { item.profile.user_id.lowercased() == AccountStorage.currentUserID.lowercased() }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onProfile) {
                WhisperAvatar(username: item.profile.username, size: 36, imageURL: item.profile.profile_image_url.flatMap(URL.init(string:)), ring: false)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: item.isQuote ? "quote.opening" : "heart.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 18, height: 18).background(item.isQuote ? .orange : .pink, in: .circle)
                            .overlay { Circle().strokeBorder(WhisperTheme.surface(scheme), lineWidth: 1.5) }.offset(x: 3, y: 3)
                    }.frame(width: 44, height: 44)
            }.accessibilityLabel("Open \(item.profile.username)")
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 10) {
                    Button(action: onProfile) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(item.profile.username).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                if let date = item.createdAt { Text(date, format: .relative(presentation: .numeric)).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            if let name = item.profile.display_name, !name.isEmpty { Text(name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
                    }.buttonStyle(.plain)
                    if !isMe && !typeSize.isAccessibilitySize { followButton }
                }
                if let text = item.excerpt, !text.isEmpty {
                    Button(action: onQuote) { Text(text).font(.body).foregroundStyle(.primary).multilineTextAlignment(.leading).lineLimit(6).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }.buttonStyle(.plain)
                } else if item.isQuote {
                    Button("View quote", action: onQuote).font(.subheadline).frame(minHeight: 44)
                } else if let followerCount {
                    Text("\(followerCount.formatted()) \(followerCount == 1 ? "follower" : "followers")").font(.subheadline).foregroundStyle(.primary).padding(.top, 3)
                }
                if !isMe && typeSize.isAccessibilitySize { followButton }
                if followError { Text("Couldn't update following. Try again.").font(.caption).foregroundStyle(.red) }
            }
        }.padding(.horizontal, 14).padding(.vertical, 14).buttonStyle(.plain)
            .task(id: item.profile.user_id) {
                let count = await WhisperPostActivityService.followerCount(item.profile.user_id)
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }; followerCount = count
            }
    }
    private var followButton: some View {
        Button {
            guard !working, generation == AccountStorage.generation else { return }
            working = true; followError = false
            Task {
                defer { working = false }
                if followed {
                    await follows.unfollow(userID: item.profile.user_id)
                    guard generation == AccountStorage.generation else { return }; followError = follows.isFollowing(userID: item.profile.user_id)
                } else if !pending {
                    let result = await follows.attemptFollow(userID: item.profile.user_id, username: item.profile.username)
                    guard generation == AccountStorage.generation else { return }
                    requested = result == .requested; followError = result == .failed
                }
            }
        } label: {
            Text(working ? "…" : followed ? "Following" : pending ? "Requested" : "Follow")
                .font(.subheadline.weight(.semibold)).foregroundStyle(followed || pending ? WhisperTheme.muted(scheme) : WhisperTheme.surface(scheme))
                .frame(minWidth: 84, minHeight: 32).padding(.horizontal, 8)
                .background(followed || pending ? .clear : WhisperTheme.ink(scheme), in: .rect(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(followed || pending ? WhisperTheme.hairline(scheme) : .clear, lineWidth: 1) }
                .frame(minHeight: 44)
        }.disabled(working || pending).accessibilityLabel("\(followed ? "Unfollow" : pending ? "Requested" : "Follow") \(item.profile.username)")
    }
}
