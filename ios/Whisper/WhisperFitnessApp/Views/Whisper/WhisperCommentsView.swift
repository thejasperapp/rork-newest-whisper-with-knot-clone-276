import SwiftUI

/// Instagram-style comments sheet backed by `WhisperBackendService`.
/// Comments are threaded — tapping "Reply" sets a reply target so the
/// next send creates a child comment under the parent.
struct WhisperCommentsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let postID: String
    let postUsername: String
    let postCaption: String
    /// Inline Waves shares the real thread and composer without another presentation.
    var onClose: (() -> Void)? = nil
    var onExpand: (() -> Void)? = nil
    var closeRequest: UUID? = nil

    @State private var backend = WhisperBackendService.shared
    @State private var ember = WhisperEmberService.shared
    @State private var draft: String = ""
    @State private var loading: Bool = false
    @State private var sendError = false
    @State private var confirmClose = false
    @State private var sending: Bool = false
    @State private var emberSummary: String?
    @State private var loadingSummary: Bool = false
    @State private var emberPickID: String?
    @State private var replyTarget: WhisperCommentRow?
    @State private var expandedReplies: Set<String> = []
    @FocusState private var focused: Bool

    private var comments: [WhisperCommentRow] {
        backend.commentsByPostID[postID] ?? []
    }

    /// Top-level comments only (no parent).
    private var rootComments: [WhisperCommentRow] {
        comments.filter { $0.parent_comment_id == nil }
    }

    private func replies(for parentID: String) -> [WhisperCommentRow] {
        comments.filter { $0.parent_comment_id == parentID }
    }

    var body: some View {
        Group {
            if onClose != nil {
                VStack(spacing: 0) {
                    HStack {
                        Button { onExpand?() } label: {
                            Text("Comments")
                                .font(.headline)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Expands comments within Waves")
                        Spacer()
                        Button(action: requestClose) {
                            Image(systemName: "xmark")
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Collapse comments")
                    }
                    .padding(.horizontal, 16)
                    threadContent
                }
                .background(.black)
            } else {
                NavigationStack {
                    threadContent
                        .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
                        .navigationTitle("Comments")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { dismiss() }
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                            }
                        }
                }
            }
        }
        .onChange(of: closeRequest) { _, _ in requestClose() }
        .confirmationDialog("Discard this comment?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Discard comment", role: .destructive) { focused = false; onClose?() }
            Button("Keep writing", role: .cancel) {}
        }
        .alert("Comment not sent", isPresented: $sendError) {
            Button("Keep writing", role: .cancel) {}
        } message: { Text("Your text is still here. Check your connection and try again.") }
        .task(id: postID) {
            loading = comments.isEmpty
            _ = await backend.fetchComments(postID: postID, maxAge: 30)
            guard !Task.isCancelled else { return }
            loading = false
        }
    }

    private func requestClose() {
        guard !sending else { return }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            focused = false
            onClose?()
        } else { confirmClose = true }
    }

    private var threadContent: some View {
        VStack(spacing: 0) {
            list
            if let target = replyTarget { replyingToBanner(target) }
            composer
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                originalPost
                emberSummaryRow
                Divider().background(WhisperTheme.hairline(colorScheme))
                if let error = backend.commentLoadErrors[postID.lowercased()] {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                        Button("Retry") {
                            Task {
                                loading = true
                                _ = await backend.fetchComments(postID: postID)
                                if !Task.isCancelled { loading = false }
                            }
                        }
                        .frame(minHeight: 44)
                        .disabled(loading)
                    }
                }
                if loading && comments.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if rootComments.isEmpty && backend.commentLoadErrors[postID.lowercased()] == nil {
                    WhisperEmptyState(icon: "bubble.left", title: "No comments yet",
                        message: "Be the first to comment.", isCard: false, compact: true)
                } else if !rootComments.isEmpty {
                    ForEach(rootComments) { c in
                        commentBlock(c)
                    }
                    WhisperCommentAdView(threadID: postID)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var emberSummaryRow: some View {
        if comments.count >= 6 {
            if let summary = emberSummary {
                HStack(alignment: .top, spacing: 10) {
                    WhisperEmberBadge(size: 22)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Jasper's read on \(comments.count) comments")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(.orange.opacity(0.07), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.orange.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            } else {
                Button {
                    Haptics.tap()
                    Task { await summarize() }
                } label: {
                    HStack(spacing: 8) {
                        WhisperEmberBadge(size: 18)
                        Text(loadingSummary ? "Jasper is reading…" : "Summarize \(comments.count) comments with Jasper")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Spacer()
                        if loadingSummary {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                    .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .disabled(loadingSummary)
            }
        }
    }

    private func summarize() async {
        loadingSummary = true
        async let summary = ember.summarizeComments(comments)
        async let pick = ember.bestComment(comments)
        let (text, pickID) = await (summary, pick)
        await MainActor.run {
            withAnimation(.whisperSnappy) {
                emberSummary = text.isEmpty ? nil : text
                emberPickID = pickID
                loadingSummary = false
            }
        }
    }

    private var originalPost: some View {
        HStack(alignment: .top, spacing: 10) {
            WhisperAvatar(username: postUsername, size: 32, ring: false)
            VStack(alignment: .leading, spacing: 2) {
                (
                    Text("@\(postUsername) ").font(.subheadline.weight(.bold))
                    + Text(postCaption).font(.subheadline)
                )
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            Spacer()
        }
    }

    // MARK: - Comment + replies

    @ViewBuilder
    private func commentBlock(_ c: WhisperCommentRow) -> some View {
        let kids = replies(for: c.id)
        VStack(alignment: .leading, spacing: 8) {
            commentRow(c, isReply: false)
            if !kids.isEmpty {
                let isOpen = expandedReplies.contains(c.id)
                Button {
                    Haptics.tap()
                    withAnimation(.whisperSnappy) {
                        if isOpen { expandedReplies.remove(c.id) } else { expandedReplies.insert(c.id) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(WhisperTheme.hairline(colorScheme))
                            .frame(width: 22, height: 0.6)
                        Text(isOpen ? "Hide replies" : "View \(kids.count) \(kids.count == 1 ? "reply" : "replies")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 42)
                if isOpen {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(kids) { k in
                            commentRow(k, isReply: true)
                        }
                    }
                    .padding(.leading, 32)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func commentRow(_ c: WhisperCommentRow, isReply: Bool) -> some View {
        let liked = backend.myLikedCommentIDs.contains(c.id)
        let likes = max((c.likes_count ?? 0) + (liked && (c.likes_count ?? 0) == 0 ? 1 : 0), 0)
        let isEmberPick = emberPickID == c.id
        return HStack(alignment: .top, spacing: 10) {
            WhisperAvatar(username: c.username, size: isReply ? 26 : 32, ring: false)
            VStack(alignment: .leading, spacing: 4) {
                if isEmberPick {
                    HStack(spacing: 4) {
                        WhisperEmberBadge(size: 12)
                        Text("Jasper pick")
                            .font(.caption2.weight(.heavy))
                            .tracking(0.4)
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.12), in: Capsule())
                }
                WhisperCommentBodyView(text: c.body, usernamePrefix: c.username)
                HStack(spacing: 16) {
                    if likes > 0 {
                        Text("\(likes) like\(likes == 1 ? "" : "s")")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    Button {
                        Haptics.tap()
                        withAnimation(.whisperSnappy) {
                            replyTarget = c.parent_comment_id == nil ? c : (rootComments.first { $0.id == c.parent_comment_id } ?? c)
                        }
                        focused = true
                    } label: {
                        Text("Reply")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Button {
                Haptics.tap()
                Task { _ = await backend.toggleCommentLike(commentID: c.id, postID: postID) }
            } label: {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(liked ? Color.red : WhisperTheme.muted(colorScheme))
                    .scaleEffect(liked ? 1.1 : 1)
                    .animation(.whisperSnappy, value: liked)
                    .padding(.top, 2)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Composer

    private func replyingToBanner(_ target: WhisperCommentRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.caption2.weight(.bold))
            Text("Replying to @\(target.username)")
                .font(.caption.weight(.semibold))
            Spacer()
            Button {
                Haptics.tap()
                withAnimation(.whisperSnappy) { replyTarget = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(WhisperTheme.muted(colorScheme))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(WhisperTheme.card(colorScheme))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField(replyTarget == nil ? "Add a comment…" : "Reply to @\(replyTarget!.username)…",
                      text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .modifier(WhisperControlGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
            Button {
                Task { await send() }
            } label: {
                HStack(spacing: 6) {
                    if sending {
                        ProgressView().controlSize(.mini)
                    }
                    Text("Post")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(canSend ? WhisperTheme.ink(colorScheme) : WhisperTheme.muted(colorScheme))
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend || sending)
            .animation(.whisperSnappy, value: sending)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(onClose == nil ? WhisperTheme.surface(colorScheme) : Color.black)
        .overlay(alignment: .top) {
            Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(height: 0.5)
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() async {
        guard canSend, !sending else { return }
        let generation = AccountStorage.generation
        sending = true
        Haptics.tap()
        let parent = replyTarget?.id
        let body = draft
        let posted = await backend.addComment(postID: postID, body: body, parentCommentID: parent)
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        // Only clear the draft when the comment actually landed — on a
        // network failure the user keeps their text instead of losing it.
        if posted != nil {
            draft = ""
            withAnimation(.whisperSnappy) { replyTarget = nil }
            WhisperFeedback.sent()
        } else {
            sendError = true
            WhisperFeedback.failed()
        }
        sending = false
        // Mirror the Threads-style composer: if the comment tagged @ember,
        // kick off Jasper's AI reply in the background so the answer shows
        // up inline (this surface is used from Reels).
        if posted != nil, WhisperEmberMention.shouldRespond(to: body) {
            let pid = postID
            let caption = postCaption
            let parentForReply = posted?.id ?? parent
            Task {
                await WhisperEmberMention.respond(
                    toComment: body,
                    postID: pid,
                    parentCommentID: parentForReply,
                    postCaption: caption
                )
            }
        }
    }
}

/// Lightweight DM recipient row used by the forward sheet — unifies
/// people you follow with people you've messaged recently so the user
/// doesn't need a separate friends graph.
private struct WhisperForwardRecipient: Identifiable, Hashable {
    let userID: String
    let username: String
    /// True when the local user has an existing DM thread with this person.
    let hasThread: Bool
    /// True when the local user follows this person.
    let isFollowing: Bool
    var id: String { userID.lowercased() }
}

/// Sheet that lets the user forward a post to people they follow or have
/// messaged recently. Replaces the old reciprocal-friends source.
struct WhisperForwardPostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let postID: String
    let postUsername: String
    let postCaption: String
    /// Optional rich payload — when present, the sheet sends an inline
    /// post embed instead of a plain-text "Check this post by @x" line
    /// so the recipient sees a tappable post card in the chat.
    var sharedPostPayload: WhisperSharedPostEmbed.Payload? = nil

    @State private var follows = WhisperFollowService.shared
    @State private var backend = WhisperBackendService.shared
    @State private var query: String = ""
    @State private var sentTo: Set<String> = []

    /// Merged recipient list — DM threads first (recent contacts the user
    /// has actively messaged), then everyone else they follow.
    private var recipients: [WhisperForwardRecipient] {
        let me = AccountStorage.currentUserID.lowercased()
        var seen: Set<String> = []
        var out: [WhisperForwardRecipient] = []

        // 1) People I've DM'd, ordered by most recent first.
        let sortedThreads = backend.threads.sorted { $0.lastDate > $1.lastDate }
        for t in sortedThreads {
            let key = t.otherUserID.lowercased()
            guard key != me, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(WhisperForwardRecipient(
                userID: t.otherUserID,
                username: t.otherUsername,
                hasThread: true,
                isFollowing: follows.following.contains(key)
            ))
        }

        // 2) People I follow that haven't been DM'd yet.
        for (id, name) in follows.followingUsernames {
            let key = id.lowercased()
            guard key != me, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(WhisperForwardRecipient(
                userID: id,
                username: name,
                hasThread: false,
                isFollowing: true
            ))
        }
        return out
    }

    private var filtered: [WhisperForwardRecipient] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return recipients }
        return recipients.filter { $0.username.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        searchBar
                        if recipients.isEmpty {
                            empty
                        } else {
                            VStack(spacing: 0) {
                                ForEach(filtered) { r in
                                    recipientRow(r)
                                    Divider().background(WhisperTheme.hairline(colorScheme))
                                }
                            }
                            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Send to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .task {
                async let f: () = follows.refresh()
                async let t: () = backend.fetchThreads()
                _ = await (f, t)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Search people you follow", text: $query)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            WhisperMeetDoodle(symbol: "person.2", height: 120)
            Text("Follow people or start a DM to send posts.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 60)
    }

    private func recipientRow(_ r: WhisperForwardRecipient) -> some View {
        let sent = sentTo.contains(r.userID)
        let subtitle: String = {
            if r.hasThread && r.isFollowing { return "Following · In your messages" }
            if r.hasThread { return "In your messages" }
            return "Following"
        }()
        return HStack(spacing: 12) {
            WhisperAvatar(username: r.username, size: 38, ring: false)
            VStack(alignment: .leading, spacing: 1) {
                Text("@\(r.username)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Button {
                Haptics.tap()
                Task {
                    let body: String
                    if let payload = sharedPostPayload {
                        body = WhisperSharedPostEmbed.encode(payload)
                    } else {
                        body = "Check this post by @\(postUsername): \(postCaption)"
                    }
                    let ok = await backend.sendMessage(
                        toUserID: r.userID,
                        toUsername: r.username,
                        body: body
                    )
                    if ok { sentTo.insert(r.userID) }
                }
            } label: {
                Text(sent ? "Sent" : "Send")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(sent ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(sent ? WhisperTheme.card(colorScheme) : WhisperTheme.ink(colorScheme), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(sent ? WhisperTheme.hairline(colorScheme) : .clear, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(sent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
