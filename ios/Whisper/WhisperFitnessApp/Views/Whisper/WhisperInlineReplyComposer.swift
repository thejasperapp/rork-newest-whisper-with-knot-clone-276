import SwiftUI
import PhotosUI

/// Threads-style compact inline reply composer. Slides up from the bottom
/// as a small sheet (single short detent) with the keyboard active. Shows
/// the user's avatar, a single-line growing text field, an icon strip, an
/// expand glyph (which hands off to the full-screen `WhisperReplyComposerSheet`)
/// and a "Post" CTA on the trailing edge.
///
/// Used as the *first* surface when tapping the comment button on a feed
/// post or the inline composer bar in the thread detail. Matches the
/// behavior shown in Threads where the comment box appears just above the
/// keyboard rather than going straight to a full screen.
struct WhisperInlineReplyComposer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let post: WhisperPost
    let replyTarget: WhisperCommentRow?
    let onPosted: () -> Void

    @State private var backend = WhisperBackendService.shared
    @State private var draft: String = ""
    @State private var sending: Bool = false
    @State private var presentFullComposer: Bool = false
    @State private var expandedPosted: Bool = false
    @FocusState private var focused: Bool

    // Attachment state
    @State private var attachments: WhisperComposerAttachments = WhisperComposerAttachments()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera: Bool = false
    @State private var showGif: Bool = false
    @State private var showSticker: Bool = false
    @State private var showPoll: Bool = false
    @State private var showVoice: Bool = false
    @State private var showFormatting: Bool = false
    @State private var locationLoading: Bool = false
    @State private var locationError: String?
    @State private var presentPhotoPicker: Bool = false

    private var postIDString: String { post.id.uuidString.lowercased() }

    private var me: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !attachments.isEmpty) && draft.count <= characterLimit
    }

    /// Verified accounts unlock the long-form ceiling. Everyone else gets
    /// the standard cap. See `WhisperVerifiedPerks.characterLimit`.
    private var characterLimit: Int {
        WhisperVerifiedPerks.characterLimit(username: me)
    }

    private var placeholder: String {
        if let t = replyTarget { return "Reply to \(t.username)…" }
        return "Reply to \(post.username)…"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header strip: "Replying to @username" + close
            HStack(spacing: 6) {
                Text("Replying to ")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                +
                Text("@\(replyTarget?.username ?? post.username)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(WhisperTheme.ink(colorScheme))
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().background(WhisperTheme.hairline(colorScheme))

            // Attachment chip strip (only visible when something queued)
            WhisperComposerAttachmentChips(bag: attachments)

            WhisperMentionSuggestionsBar(text: $draft)

            // Composer row: avatar · field · icons · expand · Post
            HStack(alignment: .center, spacing: 10) {
                WhisperAvatar(username: me, size: 32, ring: false)
                ZStack(alignment: .leading) {
                    if draft.isEmpty {
                        Text(placeholder)
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    TextField("", text: $draft, axis: .vertical)
                        .focused($focused)
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .tint(WhisperTheme.ink(colorScheme))
                        .lineLimit(1...4)
                        .onChange(of: draft) { _, newValue in
                            if newValue.count > characterLimit {
                                draft = String(newValue.prefix(characterLimit))
                                Haptics.warning()
                            }
                        }
                }
                if characterLimit - draft.count <= max(40, characterLimit / 5) {
                    let remaining = characterLimit - draft.count
                    Text("\(remaining)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(
                            remaining < 0 ? .red
                            : (remaining <= 20 ? .orange : WhisperTheme.muted(colorScheme))
                        )
                }
                Button {
                    Haptics.tap()
                    if !sending { presentFullComposer = true }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .rotationEffect(.degrees(90))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Spacer(minLength: 0)

            // Bottom toolbar: icon strip on the leading edge, Post CTA trailing.
            // Matches Threads' reply composer: photo, camera, GIF, sticker,
            // poll, location, audio.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    inlineIcon("photo") { presentPhotoPicker = true }
                    inlineIcon("camera") { showCamera = true }
                    inlineGifIcon { showGif = true }
                    inlineIcon("face.smiling") { showSticker = true }
                    inlineIcon("chart.bar.xaxis") { showPoll = true }
                    inlineIcon(locationLoading ? "location.fill" : "location") { attachLocation() }
                    inlineIcon("mic") { showVoice = true }
                }
                .padding(.horizontal, 14)
            }
            .scrollClipDisabled()
            HStack {
                Spacer()
                Button {
                    Task { await send() }
                } label: {
                    Text(sending ? "Posting…" : "Post")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(canSend ? WhisperTheme.surface(colorScheme) : WhisperTheme.muted(colorScheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(
                                canSend
                                    ? WhisperTheme.ink(colorScheme)
                                    : WhisperTheme.card(colorScheme)
                            )
                        )
                        .overlay {
                            Capsule().strokeBorder(
                                canSend ? .clear : WhisperTheme.hairline(colorScheme),
                                lineWidth: 1
                            )
                        }
                }
                .buttonStyle(.plain)
                .disabled(!canSend || sending)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .background(
                WhisperTheme.surface(colorScheme)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(WhisperTheme.hairline(colorScheme))
                            .frame(height: 0.5)
                    }
            )
        }
        .background(WhisperTheme.surface(colorScheme))
        .presentationDetents([.height(attachments.isEmpty ? 240 : 320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(WhisperTheme.surface(colorScheme))
        .presentationCornerRadius(22)
        .whisperSheetBorder()
        .interactiveDismissDisabled(false)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { focused = true }
        }
        .photosPicker(
            isPresented: $presentPhotoPicker,
            selection: $photoItems,
            maxSelectionCount: 4,
            matching: .images
        )
        .onChange(of: photoItems) { _, items in
            Task { await loadPhotos(items) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            WhisperCameraPicker { image in
                attachments.images.append(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showGif) {
            WhisperGifPickerSheet { url in attachments.gifURL = url }
        }
        .sheet(isPresented: $showSticker) {
            WhisperStickerPickerSheet { url in attachments.stickerURL = url }
        }
        .sheet(isPresented: $showPoll) {
            WhisperPollComposerSheet(poll: $attachments.poll)
        }
        .sheet(isPresented: $showVoice) {
            WhisperVoiceMemoSheet { memo in attachments.voiceMemo = memo }
        }
        .alert(
            "Couldn't get your location",
            isPresented: Binding(get: { locationError != nil }, set: { if !$0 { locationError = nil } })
        ) {
            Button("OK", role: .cancel) { locationError = nil }
        } message: {
            Text(locationError ?? "")
        }
        .fullScreenCover(isPresented: $presentFullComposer, onDismiss: {
            // If the full composer posted, we already bubbled the callback
            // up — close ourselves so we don't sit behind it.
            if expandedPosted { dismiss() } else { focused = true }
        }) {
            WhisperReplyComposerSheet(
                post: post,
                replyTarget: replyTarget,
                initialDraft: draft,
                onPosted: { expandedPosted = true; onPosted() },
                onDraftChanged: { draft = $0 },
                sharedAttachments: attachments
            )
        }
    }

    private func inlineIcon(_ name: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: name)
                .font(.body.weight(.regular))
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.65))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    /// Custom GIF glyph — no SF Symbol, so we render a small outlined pill.
    private func inlineGifIcon(action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text("GIF")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.65))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(WhisperTheme.ink(colorScheme).opacity(0.55), lineWidth: 1.2)
                }
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                attachments.images.append(img)
            }
        }
        photoItems = []
    }

    private func attachLocation() {
        guard !locationLoading else { return }
        locationLoading = true
        Task {
            if let label = await WhisperLocationGrabber.fetchLabel() {
                attachments.location = label
            } else {
                locationError = "Make sure location access is enabled in Settings."
            }
            locationLoading = false
        }
    }

    private func send() async {
        guard canSend, !sending, WhisperPostMeta.parse(from: post.caption)?.commentsOff != true else { return }
        let generation = AccountStorage.generation
        sending = true
        let commentID = attachments.commentID(baseBody: draft, postID: postIDString, parentID: replyTarget?.id)
        Haptics.tap()
        guard let body = await attachments.finalize(baseBody: draft, postID: postIDString) else {
            sending = false
            WhisperErrorService.shared.report("An attachment couldn't upload. Your reply is still here; please retry.")
            return
        }
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        let parent = replyTarget?.id
        let posted = await backend.addComment(postID: postIDString, body: body, parentCommentID: parent, commentID: commentID)
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        sending = false
        guard posted != nil else { WhisperFeedback.failed(); return }
        WhisperFeedback.sent()
        onPosted()
        dismiss()
        // If the comment mentioned @ember, kick off a background Jasper
        // reply so the AI answers in the same thread — just like Grok on X.
        if WhisperEmberMention.shouldRespond(to: body) {
            let pid = postIDString
            let parentForReply = posted?.id ?? parent
            let snapshotPost = post
            Task {
                await WhisperEmberMention.respond(
                    toComment: body,
                    postID: pid,
                    parentCommentID: parentForReply,
                    post: snapshotPost
                )
            }
        }
    }
}

/// Helper that detects `@ember` mentions in comment text and posts an AI
/// response back as a local comment so other readers can see Jasper’s
/// reply inline — mirrors how Grok responds to `@grok` on X.
enum WhisperEmberMention {
    /// Per-post throttle so a thread that gets a burst of `@ember` mentions
    /// (or a quick double-tap that fires the same mention twice) only bills
    /// OpenAI once per minute per post. Stored in-memory — restart resets.
    @MainActor private static var lastReplyAt: [String: Date] = [:]
    private static let throttleWindow: TimeInterval = 60

    @MainActor
    static func isThrottled(postID: String) -> Bool {
        let key = postID.lowercased()
        if let last = lastReplyAt[key], Date().timeIntervalSince(last) < throttleWindow {
            return true
        }
        return false
    }

    @MainActor
    static func markReplied(postID: String) {
        lastReplyAt[postID.lowercased()] = Date()
        let cutoff = Date().addingTimeInterval(-600)
        lastReplyAt = lastReplyAt.filter { $0.value > cutoff }
    }

    /// True when the body addresses Jasper directly (token must be a whole
    /// word, not part of a longer handle like `@embers`).
    static func shouldRespond(to body: String) -> Bool {
        body.range(of: #"(?<![\p{L}\p{N}_])@(knot|jasper|ember)(?![\p{L}\p{N}_])"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Detects when the asker explicitly wants Jasper to draw / generate /
    /// imagine an image. Kept narrow so casual mentions of "picture" or
    /// "photo" don't accidentally trigger a generation.
    static func wantsImage(_ text: String) -> Bool {
        let s = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Slash command prefix — anything after `/imagine`, `/edit`, or `/draw`
        // is treated as an image prompt.
        if s.hasPrefix("/imagine") || s.hasPrefix("/draw") || s.hasPrefix("/image") || s.hasPrefix("/edit") { return true }
        let triggers = [
            // Pure generation triggers
            "generate an image", "generate image", "generate a pic",
            "make an image", "make me an image", "make a picture", "make me a picture",
            "draw me", "draw a", "draw an", "draw it", "draw this",
            "sketch a", "sketch an", "sketch me",
            "imagine a", "imagine an", "imagine this",
            "render a", "render an", "render me",
            "create an image", "create a picture", "create a photo",
            "picture of", "photo of", "illustration of", "visualize",
            "show me a picture", "show me an image", "give me a pic", "give me an image",
            "can you draw", "can you make an image", "can you generate",
            "ai image", "ai pic", "ai picture",
            // Photo-edit triggers (operate on the post's existing image) — same
            // shape as Grok's "put this person in X" UX.
            "put this person", "put them in", "put him in", "put her in",
            "put this guy", "put this girl", "put this dude", "put this woman", "put this man",
            "edit this photo", "edit this image", "edit this pic", "edit the photo", "edit the image",
            "change this photo", "change this image", "change the photo", "change the background",
            "make this person", "make him", "make her", "make them",
            "give him", "give her", "give them",
            "in a bikini", "in a suit", "in a tuxedo", "in a dress", "in a costume",
            "as a", "swap the", "replace the", "remove the",
            "add a", "add sunglasses", "add a hat",
            "turn this into", "turn him into", "turn her into", "turn them into",
            "reimagine this", "restyle", "transform this photo", "transform this image"
        ]
        return triggers.contains(where: { s.contains($0) })
    }

    /// Strips the slash-command prefix (if any) before sending the prompt to
    /// the image model so `/imagine a sunrise` becomes `a sunrise`.
    static func extractImagePrompt(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["/imagine", "/draw", "/image"] {
            if s.lowercased().hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return s
    }

    /// Back-compat overload for call sites that only have the caption text
    /// available (composer, reel comments). Synthesizes a minimal
    /// `WhisperPost` so the full-context path can still run.
    @MainActor
    static func respond(
        toComment body: String,
        postID: String,
        parentCommentID: String?,
        postCaption: String
    ) async {
        let cachedRow = WhisperBackendService.shared.posts.first(where: { $0.id.lowercased() == postID.lowercased() })
            ?? WhisperBackendService.shared.myPosts.first(where: { $0.id.lowercased() == postID.lowercased() })
        let parsedKind: WhisperPostKind = {
            if let raw = cachedRow?.kind, let k = WhisperPostKind(rawValue: raw) { return k }
            return .photo
        }()
        let urls: [URL] = (cachedRow?.media_urls ?? []).compactMap { URL(string: $0) }
        let synthesized = WhisperPost(
            username: cachedRow?.username ?? "",
            timeAgo: "",
            kind: parsedKind,
            caption: postCaption,
            symbol: cachedRow?.symbol ?? "sparkles",
            accent: .gray,
            mediaURLs: urls,
            likes: cachedRow?.likes_count ?? 0,
            comments: cachedRow?.comments_count ?? 0
        )
        await respond(
            toComment: body,
            postID: postID,
            parentCommentID: parentCommentID,
            post: synthesized
        )
    }

    /// Generates a short Jasper reply and persists it as a real Supabase
    /// comment so every viewer of the post sees it. The reply is built
    /// with full post context (caption + kind + recent comments) and can
    /// include an inline generated image when the asker requests one.
    @MainActor
    static func respond(
        toComment body: String,
        postID: String,
        parentCommentID: String?,
        post: WhisperPost
    ) async {
        let ember = WhisperEmberService.shared
        let backend = WhisperBackendService.shared
        let postCaption = post.caption
        // Strip the mention so we don't bias the model.
        let cleaned = body
            .replacingOccurrences(of: "@ember", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Pull the most recent comments so Jasper can read the whole thread
        // before answering — same context any human reader would have.
        let allComments = backend.commentsByPostID[postID] ?? []
        let threadSnippet: String = {
            let tail = allComments.suffix(20)
            return tail.map { "@\($0.username): \($0.body)" }.joined(separator: "\n")
        }()
        let mediaCount = post.mediaURLs.count

        let prompt: String = {
            let header = "You are commenting on a Whisper fitness post (kind: \(post.kind.label), \(mediaCount) attached media). The post caption: \"\(postCaption)\"."
            let question = cleaned.isEmpty
                ? "Someone tagged you for input. Reply helpfully in 2 sentences max."
                : "Someone in the comments tagged you and asked: \"\(cleaned)\"."
            let thread = threadSnippet.isEmpty
                ? ""
                : "\n\nRecent thread:\n\(threadSnippet)"
            return """
            \(header)
            \(question) Reply in 2 sentences max, friendly, specific, grounded in the post + thread, no preamble.\(thread)
            """
        }()

        // Per-post throttle: skip the round-trip entirely if Jasper already
        // answered on this post within the last minute. Saves tokens on hot
        // threads where many users tag @ember in rapid succession.
        if isThrottled(postID: postID) { return }
        markReplied(postID: postID)

        // If the asker wants an image, drop in a live "Jasper is imagining"
        // placeholder comment so viewers see the generation in flight
        // instead of a quiet pause. We remove it once the real reply lands.
        let askedForImage = wantsImage(cleaned.isEmpty ? postCaption : cleaned)
        let imagePromptSeed: String = {
            guard askedForImage else { return "" }
            let raw = cleaned.isEmpty ? postCaption : extractImagePrompt(cleaned)
            return raw.isEmpty
                ? "Bright, motivating fitness illustration for: \(postCaption)"
                : raw
        }()
        var placeholderID: String? = nil
        if askedForImage {
            let placeholder = backend.appendLocalComment(
                postID: postID,
                username: "ember",
                body: "[[EMBER_IMAGINING:\(imagePromptSeed)]]",
                parentCommentID: parentCommentID
            )
            placeholderID = placeholder.id
        }

        // When the post itself has media, prefer image-to-image editing so
        // "@ember put this person in a bikini" actually transforms the photo
        // in place (Grok-on-X behavior) instead of dreaming up a stranger
        // from scratch. Falls back to pure text-to-image when there's no
        // source photo to edit.
        let sourceImageURL: URL? = post.mediaURLs.first
        // Kick off the text answer and (if needed) the image generation in
        // parallel so the user doesn't wait on a serial pipeline.
        async let answerTask = ember.ask(prompt)
        async let imageURLTask: String? = askedForImage
            ? generateAndUploadImage(prompt: imagePromptSeed, postID: postID, sourceImageURL: sourceImageURL)
            : nil
        let answer = await answerTask
        let uploadedURL = await imageURLTask

        // Remove the placeholder before posting the real comment so the
        // loading card visually "morphs" into the finished image.
        if let pid = placeholderID {
            _ = await backend.deleteComment(commentID: pid, postID: postID)
        }

        guard !answer.isEmpty else { return }

        var finalBody = answer
        if askedForImage, let uploadedURL {
            finalBody = "\(answer)\n\(uploadedURL)"
        }

        // Persist as a real comment row so all viewers see it. Falls back
        // to a local-only synthetic row if the network insert fails.
        let persisted = await backend.addEmberComment(
            postID: postID,
            body: finalBody,
            parentCommentID: parentCommentID
        )
        let rowID: String = persisted?.id ?? backend.appendLocalComment(
            postID: postID,
            username: "ember",
            body: finalBody,
            parentCommentID: parentCommentID
        ).id

        // Persist to Jasper's profile feed so the answer shows up there too.
        let me = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
        WhisperEmberReplyTracker.shared.record(.init(
            id: rowID,
            postID: postID,
            postUsername: post.username,
            postCaption: postCaption,
            parentCommentID: parentCommentID,
            body: finalBody,
            askedBy: me,
            askedText: cleaned.isEmpty ? nil : cleaned,
            created_at: Date()
        ))
        Haptics.success()
    }

    /// Generates an image via OpenAI and uploads it to whisper-media so the
    /// public URL can be appended to the comment body. When `sourceImageURL`
    /// is provided we download the post's first photo and route through
    /// `/v1/images/edits` so the result is a true edit of the original
    /// (same person, new scene/outfit/etc). Falls back to text-to-image
    /// on any failure path — the caller falls back to a text-only Jasper
    /// reply if even that fails.
    @MainActor
    private static func generateAndUploadImage(
        prompt: String,
        postID: String,
        sourceImageURL: URL? = nil
    ) async -> String? {
        let service = OpenAIService()
        let editPrompt = """
        Edit the provided photo according to this request: \(prompt).
        Keep the subject's face, hair, body proportions, and overall identity unmistakably the same — only change what the request asks to change. Photoreal lighting that matches the existing scene unless the request explicitly asks for a new setting.
        """
        let imageData: Data? = await {
            // Image-to-image first when we have a source photo.
            if let url = sourceImageURL {
                if let (downloaded, _) = try? await URLSession.shared.data(from: url) {
                    if let edited = try? await service.editImage(imageData: downloaded, prompt: editPrompt) {
                        return edited
                    }
                }
            }
            // Text-to-image fallback.
            return try? await service.generateImage(prompt: prompt)
        }()
        guard let data = imageData else { return nil }
        let urls = await WhisperBackendService.shared.uploadMedia(
            datas: [data],
            postID: "ember-\(postID)"
        )
        return urls.first
    }
}
