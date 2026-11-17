import SwiftUI
import UIKit

/// Post/reply actions use the same compact recipient tray as ordinary DM forwarding.
struct WhisperPostShareSheet: View {
    let post: WhisperPost
    var comment: WhisperCommentRow? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var reposts = WhisperRepostService.shared
    @State private var toast: String?
    @State private var storyShare: WaveStoryShare?
    @State private var preparingStory: Bool = false
    @State private var reposting: Bool = false
    @State private var generation: UUID = AccountStorage.generation
    @State private var closed: Bool = false
    @State private var presentSystemShare: Bool = false

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var postID: String { post.id.uuidString.lowercased() }
    private var link: String { "https://www.mydailywhisper.com/post/\(postID)" }
    private var isCurrent: Bool { !closed && generation == AccountStorage.generation && !Task.isCancelled }
    private var systemItems: [Any] {
        if let comment {
            return ["Reply by @\(comment.username):\n\(WhisperReplySharePreview.excerpt(comment.body))\n\nOriginal thread: \(link)"]
        }
        return [link]
    }

    var body: some View {
        WhisperRecipientShareSheet(payload: sharePayload, hasActions: true, isBusy: preparingStory || reposting) {
            actionsRow
        }
        .overlay {
            if preparingStory {
                ZStack {
                    WhisperTheme.surface(colorScheme).opacity(0.95)
                    ProgressView("Preparing story…").tint(ink)
                }
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast).font(.footnote.weight(.semibold)).padding(12)
                    .foregroundStyle(WhisperTheme.surface(colorScheme)).background(ink, in: .capsule)
                    .padding(.top, 8).allowsHitTesting(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            closed = true; storyShare = nil; presentSystemShare = false; dismiss()
        }
        .fullScreenCover(item: $storyShare) { share in
            WhisperStoryEditor(image: share.background, initialStickers: [share.sticker], sharedPostBackground: true,
                               onPosted: { storyShare = nil; dismiss() })
        }
        .sheet(isPresented: $presentSystemShare) { ShareSheet(items: systemItems) }
    }

    private var actionsRow: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                action("square.and.arrow.up", label: "Share to") { presentSystemShare = true }
                action(comment == nil ? "link" : "doc.on.doc", label: comment == nil ? "Copy link" : "Copy text") {
                    UIPasteboard.general.string = comment.map { WhisperReplySharePreview.excerpt($0.body) } ?? link
                    Haptics.success(); showToast("Copied")
                }
                if comment == nil {
                    action("plus.circle", label: "Add to story") { Task { await addToStory() } }
                    action("repost", label: reposts.isReposted(postID) ? "Reposted" : "Repost") {
                        Task {
                            guard isCurrent, !reposting else { return }
                            reposting = true
                            defer { if generation == AccountStorage.generation { reposting = false } }
                            _ = await reposts.toggle(postID: postID)
                        }
                    }
                }
            }
        }.contentMargins(.horizontal, 16).scrollIndicators(.hidden)
    }

    private func action(_ symbol: String, label: String, perform: @escaping () -> Void) -> some View {
        Button { guard isCurrent else { return }; Haptics.tap(); perform() } label: {
            VStack(spacing: 8) {
                Group {
                    if symbol == "repost" { WhisperRoundedGlyph(kind: .repost, size: 22) }
                    else { Image(systemName: symbol).font(.system(size: 22, weight: .medium)) }
                }.frame(width: 54, height: 54).background(WhisperTheme.card(colorScheme), in: .circle)
                Text(label).font(.caption).multilineTextAlignment(.center).lineLimit(2)
            }.frame(width: 76).contentShape(.rect)
        }.buttonStyle(.plain).foregroundStyle(ink)
    }

    private var sharePayload: String {
        WhisperSharedPostEmbed.encode(.init(postID: postID, username: post.username, caption: post.displayCaption,
            kindRaw: post.kind.rawValue, symbol: post.symbol, accentHex: post.accent.toHex(),
            mediaURL: post.mediaURLs.first?.absoluteString, isVideo: post.mediaURLs.first.map { WhisperVideo.isVideo($0) } ?? false,
            likes: post.likes, comments: post.comments, isReel: post.isReel,
            commentID: comment?.id, commentUsername: comment?.username,
            commentExcerpt: comment.map { WhisperReplySharePreview.excerpt($0.body) }))
    }

    private func addToStory() async {
        guard isCurrent, !preparingStory, comment == nil else { return }
        preparingStory = true
        defer { if generation == AccountStorage.generation { preparingStory = false } }
        var cover: UIImage?
        if let still = post.mediaURLs.first(where: { !WhisperVideo.isVideo($0) }) {
            cover = await WhisperImageCache.load(still, maxPixelSize: 1920)
        }
        guard isCurrent else { return }
        if cover == nil, let video = post.mediaURLs.first(where: { WhisperVideo.isVideo($0) }) {
            cover = await WhisperStoryPoster.firstFrame(of: video, maxSize: CGSize(width: 540, height: 960))
        }
        guard isCurrent else { return }
        if cover == nil && !post.mediaURLs.isEmpty { showToast("Couldn't load the preview. Try again."); return }
        let source = cover
        let background = await Task.detached(priority: .userInitiated) { WhisperWaveStoryBackground.blurred(from: source) }.value
        guard isCurrent else { return }
        var sticker = WhisperStorySticker.card(for: post)
        if sticker.kind == .post {
            sticker.cardWidthFraction = 0.88
            sticker.mediaAspectRatio = cover.map { Double($0.size.width / max(1, $0.size.height)) }
            sticker.mediaCount = post.mediaURLs.count
            sticker.y = 0.52
        }
        storyShare = WaveStoryShare(background: background, sticker: sticker)
    }

    private func showToast(_ text: String) {
        guard isCurrent else { return }
        toast = text
        Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(1400)) } catch { return }
            if isCurrent, toast == text { toast = nil }
        }
    }
}
