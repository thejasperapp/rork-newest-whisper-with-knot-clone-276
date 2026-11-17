import SwiftUI

/// Public-facing profile for the Jasper AI assistant. Lists every post Jasper
/// has been tagged on (via `@ember` mentions) along with Jasper's reply, so
/// readers can browse what Jasper has been weighing in on across the app.
struct WhisperEmberProfileView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var tracker = WhisperEmberReplyTracker.shared
    @State private var backend = WhisperBackendService.shared
    /// Server-side Jasper comments, fetched on appear. Merged with the local
    /// tracker so the profile renders the same global feed regardless of
    /// which device the viewer is on.
    @State private var globalEmberRows: [WhisperCommentRow] = []
    @State private var loadingGlobal: Bool = false
    /// Presents the full Jasper assistant chat (shared brain) over the profile.
    @State private var showEmberChat: Bool = false

    /// Resolves the cached post row for an Jasper reply entry, if we have one.
    /// Used to render the real media + author handle + caption — and to push
    /// the actual `WhisperPostDetailView` when the row is tapped.
    private func cachedRow(for entry: WhisperEmberReplyTracker.Entry) -> WhisperPostRow? {
        let pid = entry.postID.lowercased()
        return backend.posts.first(where: { $0.id.lowercased() == pid })
            ?? backend.myPosts.first(where: { $0.id.lowercased() == pid })
    }

    /// Merged feed of Jasper replies. Server rows take precedence (global
    /// truth across devices); the local tracker fills any gaps (offline
    /// captures, older replies not surfaced by the server query).
    ///
    /// Deduped by `postID` so a post Jasper has answered multiple times only
    /// shows up once in the profile — the most recent reply wins. Without
    /// this dedupe, popular posts with several @ember threads were
    /// rendering as a stack of identical-looking rows.
    private var mergedEntries: [WhisperEmberReplyTracker.Entry] {
        var seenReplyIDs: Set<String> = []
        var collected: [WhisperEmberReplyTracker.Entry] = []
        // 1. Server rows first — convert each into the same Entry shape.
        for row in globalEmberRows {
            seenReplyIDs.insert(row.id)
            let cachedPost = backend.posts.first(where: { $0.id == row.post_id })
                ?? backend.myPosts.first(where: { $0.id == row.post_id })
            let createdAt = WhisperBackendService.parseISO(row.created_at) ?? Date()
            collected.append(.init(
                id: row.id,
                postID: row.post_id,
                postUsername: cachedPost?.username ?? "",
                postCaption: cachedPost?.caption ?? "",
                parentCommentID: row.parent_comment_id,
                body: row.body,
                askedBy: nil,
                askedText: nil,
                created_at: createdAt
            ))
        }
        // 2. Local tracker entries the server didn't return (matched by
        // reply id so we don't double-count the same reply if it's both
        // tracked locally and pulled from the server).
        for e in tracker.entries where !seenReplyIDs.contains(e.id) {
            collected.append(e)
        }
        // 3. Sort newest first, then collapse to one row per source post —
        // since we sorted descending, the first occurrence is the most
        // recent reply for that post, which is the one we keep.
        let sorted = collected.sorted { $0.created_at > $1.created_at }
        var seenPostIDs: Set<String> = []
        var deduped: [WhisperEmberReplyTracker.Entry] = []
        for entry in sorted {
            let key = entry.postID.lowercased()
            guard !key.isEmpty, !seenPostIDs.contains(key) else { continue }
            seenPostIDs.insert(key)
            deduped.append(entry)
        }
        return deduped
    }

    /// Synthesises a `WhisperPost` from the cached row (or from the tracker
    /// entry as a fallback) so `WhisperPostDetailView` can render it.
    private func resolvedPost(for entry: WhisperEmberReplyTracker.Entry) -> WhisperPost {
        if let row = cachedRow(for: entry) {
            let kind = (row.kind.flatMap { WhisperPostKind(rawValue: $0) }) ?? .photo
            let urls: [URL] = (row.media_urls ?? []).compactMap { URL(string: $0) }
            let postUUID = UUID(uuidString: row.id) ?? UUID()
            return WhisperPost(
                id: postUUID,
                username: row.username ?? entry.postUsername,
                timeAgo: WhisperPost.relativeTime(from: row.created_at),
                kind: kind,
                caption: row.caption,
                symbol: row.symbol ?? "sparkles",
                accent: .gray,
                mediaURLs: urls,
                likes: row.likes_count ?? 0,
                comments: row.comments_count ?? 0,
                isReel: row.is_reel ?? false,
                createdAt: WhisperBackendService.parseISO(row.created_at)
            )
        }
        let postUUID = UUID(uuidString: entry.postID) ?? UUID()
        return WhisperPost(
            id: postUUID,
            username: entry.postUsername,
            timeAgo: "",
            kind: .photo,
            caption: entry.postCaption,
            symbol: "sparkles",
            accent: .gray,
            likes: 0,
            comments: 0
        )
    }

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    bio
                    chatButton
                    Divider()
                        .background(WhisperTheme.hairline(colorScheme))
                        .padding(.horizontal, 16)
                    repliesSection
                }
                .padding(.bottom, 32)
            }
        }
        .navigationDestination(for: WhisperEmberProfileRoute.self) { route in
            switch route {
            case .post(let postID):
                // Look in the merged feed (server + tracker) so server-only
                // Jasper replies still resolve to a real post detail screen
                // instead of pushing a blank Color.clear destination.
                let pid = postID.lowercased()
                let entry = mergedEntries.first(where: { $0.postID.lowercased() == pid })
                    ?? tracker.entries.first(where: { $0.postID.lowercased() == pid })
                if let entry {
                    WhisperPostDetailView(post: resolvedPost(for: entry))
                } else if let row = backend.posts.first(where: { $0.id.lowercased() == pid })
                            ?? backend.myPosts.first(where: { $0.id.lowercased() == pid }) {
                    // Last-resort: synthesize an Entry straight from the cached row.
                    let synthetic = WhisperEmberReplyTracker.Entry(
                        id: "route-\(row.id)",
                        postID: row.id,
                        postUsername: row.username ?? "",
                        postCaption: row.caption,
                        parentCommentID: nil,
                        body: "",
                        askedBy: nil,
                        askedText: nil,
                        created_at: WhisperBackendService.parseISO(row.created_at) ?? Date()
                    )
                    WhisperPostDetailView(post: resolvedPost(for: synthetic))
                } else {
                    ProgressView()
                        .task { _ = await backend.fetchPost(postID: postID) }
                }
            }
        }
        .task {
            // Refresh feed so cached rows for any Jasper replies are available
            // for media + tappable navigation.
            if backend.posts.isEmpty { await backend.fetchPosts() }
            // Pull every Jasper reply server-side so the profile is identical
            // across devices instead of being scoped to the local tracker.
            await refreshGlobalEmberRows()
            // For any tracked Jasper reply whose post is still not in the
            // feed cache, pull it individually so we render the *actual*
            // post (real author, real media, real caption) instead of the
            // tracker's bare-bones placeholder fields.
            await hydrateMissingEmberPosts()
        }
        .whisperRefreshable {
            await refreshGlobalEmberRows()
            await hydrateMissingEmberPosts()
        }
        .fullScreenCover(isPresented: $showEmberChat) {
            // Full screen like native Jasper — the chat implements its own
            // swipe-down-to-close, so it stays swipe-dismissable.
            WhisperEmberChatView()
                .presentationBackground(.clear)
        }
        .whisperSheetOutline()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 4) {
                    Text("@ember")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.orange)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            WhisperAvatar(username: "ember", size: 96, ring: false)
                .padding(.top, 12)
            HStack(spacing: 6) {
                WhisperKnotWordmark(width: 72)
                Image(systemName: "checkmark.seal.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.orange)
            }
            Text("@ember · AI assistant")
                .font(.footnote)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
    }

    private var bio: some View {
        VStack(alignment: .center, spacing: 6) {
            Text("Your in-app fitness, nutrition & wellness sidekick. Tag **@ember** in any comment and I'll jump in with sources, ideas, or a quick fact-check.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                stat(value: mergedEntries.count.formatted(), label: "replies")
                stat(value: "—", label: "followers")
                stat(value: "∞", label: "iq")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
    }

    private var chatButton: some View {
        Button {
            Haptics.tap()
            showEmberChat = true
        } label: {
            WhisperJasperIntelligencePill()
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .accessibilityLabel("Open Knot")
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text(label)
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
    }

    @ViewBuilder
    private var repliesSection: some View {
        let entries = mergedEntries
        if entries.isEmpty {
            VStack(spacing: 8) {
                WhisperMeetDoodle(symbol: "bubble.left", height: 144)
                Text("No replies yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Tag **@ember** in any comment and Knot's answer will show up here.")
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .padding(.horizontal, 32)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    replyCell(entry)
                    Divider()
                        .background(WhisperTheme.hairline(colorScheme))
                        .padding(.leading, 60)
                }
            }
        }
    }

    /// Pulls every `username='ember'` comment from Supabase so the profile
    /// reflects Jasper's actual global reply log instead of just whatever
    /// this device cached. Throttled — a second fetch while one is in
    /// flight is a no-op.
    private func refreshGlobalEmberRows() async {
        guard !loadingGlobal else { return }
        loadingGlobal = true
        defer { loadingGlobal = false }
        let rows = await backend.fetchEmberCommentsGlobal()
        await MainActor.run { globalEmberRows = rows }
    }

    /// Best-effort username resolution: prefer the row's username column,
    /// then the cached author profile (filled by `fetchPost` /
    /// `hydratePostAuthors`), then the tracker entry's snapshot, and only
    /// fall back to the literal "post" placeholder if every source is empty.
    private func resolvedUsername(for entry: WhisperEmberReplyTracker.Entry, row: WhisperPostRow?) -> String {
        if let u = row?.username, !u.isEmpty { return u }
        if let uid = row?.user_id,
           let profileUsername = backend.postAuthorProfiles[uid]?.username,
           !profileUsername.isEmpty {
            return profileUsername
        }
        if !entry.postUsername.isEmpty { return entry.postUsername }
        return "post"
    }

    private func replyCell(_ e: WhisperEmberReplyTracker.Entry) -> some View {
        let row = cachedRow(for: e)
        let resolvedUsername = resolvedUsername(for: e, row: row)
        let resolvedCaption = (row?.caption.isEmpty == false ? row?.caption : nil)
            ?? (e.postCaption.isEmpty ? "(no caption)" : e.postCaption)
        let mediaURLs: [URL] = (row?.media_urls ?? []).compactMap { URL(string: $0) }
        // Parse Jasper's reply so any generated image URL renders inline
        // rather than as raw text (image gen path appends the URL on a new
        // line of the comment body).
        return Button {
            Haptics.tap()
            // Fire the same notification the bell/activity rows use so the
            // root presents the post in the standard detail sheet — same
            // experience as tapping the post from the feed, not a nested
            // push inside the Jasper profile stack.
            NotificationCenter.default.post(
                name: Notification.Name("WhisperOpenPostByID"),
                object: nil,
                userInfo: ["postID": e.postID]
            )
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Quoted post (the thing Jasper replied to)
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        Haptics.tap()
                        openProfile(resolvedUsername)
                    } label: {
                        WhisperAvatar(username: resolvedUsername, size: 32)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Button {
                                Haptics.tap()
                                openProfile(resolvedUsername)
                            } label: {
                                Text("@\(resolvedUsername)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                            .buttonStyle(.plain)
                            if let kind = row?.kind, !kind.isEmpty {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                Text(kind)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                        // (close of HStack)
                        Text(resolvedCaption)
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        if !mediaURLs.isEmpty {
                            postMediaPreview(urls: mediaURLs)
                                .padding(.top, 4)
                        }
                    }
                }
                // Jasper's reply row
                HStack(alignment: .top, spacing: 10) {
                    WhisperAvatar(username: "ember", size: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("ember")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.orange)
                            Text("·")
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                            Text(relativeTime(from: e.created_at))
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        WhisperCommentBodyView(text: e.body)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func postMediaPreview(urls: [URL]) -> some View {
        let shown = Array(urls.prefix(3))
        HStack(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, url in
                WhisperCachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .empty:
                        Color(.secondarySystemBackground)
                            .overlay { ProgressView().controlSize(.small) }
                    case .failure:
                        Color(.secondarySystemBackground)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                    @unknown default:
                        Color(.secondarySystemBackground)
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(.rect(cornerRadius: 10))
            }
            if urls.count > shown.count {
                Text("+\(urls.count - shown.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.leading, 2)
            }
            Spacer(minLength: 0)
        }
    }

    /// Fetches every Jasper-reply target post that isn't already in the
    /// in-memory cache so the profile row can render the genuine post
    /// row (and tap-through navigates to the real detail screen).
    private func hydrateMissingEmberPosts() async {
        let cachedIDs = Set(
            (backend.posts + backend.myPosts).map { $0.id.lowercased() }
        )
        // Source post ids come from both the server rows AND the local
        // tracker so cross-device entries get hydrated too.
        let trackerIDs = tracker.entries.map { $0.postID.lowercased() }
        let serverIDs = globalEmberRows.map { $0.post_id.lowercased() }
        let missingIDs = Set((trackerIDs + serverIDs).filter { !cachedIDs.contains($0) })
        for id in missingIDs {
            _ = await backend.fetchPost(postID: id)
        }
    }

    private func relativeTime(from date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    /// Routes to a username's profile via the global open-user notification
    /// so taps on avatar/handle work even when the row sits inside a
    /// NavigationLink (which would otherwise swallow the tap).
    private func openProfile(_ username: String) {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "post" else { return }
        NotificationCenter.default.post(
            name: .whisperOpenUserByUsername,
            object: nil,
            userInfo: ["username": trimmed]
        )
    }
}

/// Routes pushed from Jasper's profile. Pushing the post id lets the destination
/// resolve the latest cached row at navigation time rather than at list build.
enum WhisperEmberProfileRoute: Hashable {
    case post(String)
}
