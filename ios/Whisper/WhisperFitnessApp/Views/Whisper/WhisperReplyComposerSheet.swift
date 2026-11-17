import SwiftUI
import PhotosUI

/// Expanded editor for the same targeted reply draft and attachment bag.
struct WhisperReplyComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let post: WhisperPost
    let replyTarget: WhisperCommentRow?
    var initialDraft: String = ""
    var initialPicker: WhisperReplyComposerPicker? = nil
    let onPosted: () -> Void
    var onDraftChanged: ((String) -> Void)? = nil

    @State private var backend = WhisperBackendService.shared
    @State private var coach = WhisperCoachService.shared
    @State private var draft: String = ""
    @State private var sending: Bool = false
    @FocusState private var focused: Bool

    var sharedAttachments: WhisperComposerAttachments? = nil
    @State private var ownedAttachments: WhisperComposerAttachments = WhisperComposerAttachments()
    private var attachments: WhisperComposerAttachments { sharedAttachments ?? ownedAttachments }
    @State private var sendError: String? = nil
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var presentPhotoPicker: Bool = false
    @State private var showCamera: Bool = false
    @State private var showGif: Bool = false
    @State private var showSticker: Bool = false
    @State private var showPoll: Bool = false
    @State private var showVoice: Bool = false
    @State private var showFormatting: Bool = false
    @State private var locationLoading: Bool = false
    @State private var locationError: String?
    @State private var hasInitialized: Bool = false
    @State private var importingPhotos: Bool = false

    private var postIDString: String { post.id.uuidString.lowercased() }

    private var me: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !attachments.isEmpty) && draft.count <= characterLimit && !importingPhotos && !locationLoading
    }

    /// Verified accounts get the long-form ceiling; everyone else gets
    /// the standard cap. See `WhisperVerifiedPerks.characterLimit`.
    private var characterLimit: Int {
        WhisperVerifiedPerks.characterLimit(username: me)
    }

    /// Subtle counter, only shown once the draft is within ~20% of the
    /// cap. Turns red when the user hits the wall so the disabled Post
    /// button doesn't feel like a silent failure.
    @ViewBuilder
    private var characterCounter: some View {
        let limit = characterLimit
        let remaining = limit - draft.count
        let showThreshold = max(40, limit / 5)
        if remaining <= showThreshold {
            let isOver = remaining < 0
            let isNear = remaining <= 20
            HStack {
                Spacer(minLength: 0)
                Text("\(remaining)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(
                        isOver ? .red
                        : (isNear ? .orange : WhisperTheme.muted(colorScheme))
                    )
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            originalPostRow
                            replyRow.disabled(sending)
                            Spacer(minLength: 24)
                        }
                        .padding(.top, 12)
                    }
                    bottomBar.disabled(sending)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(sending)
            .onChange(of: draft) { _, value in onDraftChanged?(value) }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in dismiss() }
            .alert("Reply wasn't sent", isPresented: Binding(get: { sendError != nil }, set: { if !$0 { sendError = nil } })) {
                Button("Keep editing", role: .cancel) { sendError = nil }
            } message: { Text(sendError ?? "") }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDraftChanged?(draft); dismiss() }.disabled(sending)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                ToolbarItem(placement: .principal) {
                    Text("Reply")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .task {
                guard !hasInitialized else { return }
                hasInitialized = true
                draft = initialDraft
                let generation = AccountStorage.generation
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                if let picker = initialPicker {
                    switch picker {
                    case .photos: presentPhotoPicker = true
                    case .gif: showGif = true
                    case .sticker: showSticker = true
                    case .camera: showCamera = true
                    case .poll: showPoll = true
                    case .voice: showVoice = true
                    }
                } else { focused = true }
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
                WhisperCameraPicker { image in attachments.images.append(image) }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showGif) {
                WhisperGifPickerSheet { url in attachments.gifURL = url }
            }
            .sheet(isPresented: $showSticker) {
                WhisperStickerPickerSheet { url in attachments.stickerURL = url }
            }
            .sheet(isPresented: $showPoll) {
                WhisperPollComposerSheet(poll: Binding(get: { attachments.poll }, set: { attachments.poll = $0 }))
            }
            .sheet(isPresented: $showVoice) {
                WhisperVoiceMemoSheet { memo in attachments.voiceMemo = memo }
            }
            .sheet(isPresented: $showFormatting) {
                WhisperFormattingPopover(draft: $draft)
            }
            .alert(
                "Couldn't get your location",
                isPresented: Binding(get: { locationError != nil }, set: { if !$0 { locationError = nil } })
            ) {
                Button("OK", role: .cancel) { locationError = nil }
            } message: {
                Text(locationError ?? "")
            }
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        guard !importingPhotos, !sending else { return }
        let generation = AccountStorage.generation
        importingPhotos = true
        defer { if generation == AccountStorage.generation { importingPhotos = false } }
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                guard !Task.isCancelled, generation == AccountStorage.generation, !sending else { return }
                attachments.images.append(img)
            }
        }
        guard generation == AccountStorage.generation else { return }
        photoItems = []
    }

    private func attachLocation() {
        guard !locationLoading, !sending else { return }
        locationLoading = true
        let generation = AccountStorage.generation
        Task {
            let label = await WhisperLocationGrabber.fetchLabel()
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            if let label {
                attachments.location = label
            } else {
                locationError = "Make sure location access is enabled in Settings."
            }
            locationLoading = false
        }
    }

    private var originalPostRow: some View {
        let contextUsername = replyTarget?.username ?? post.username
        return HStack(alignment: .top, spacing: 8) {
            WhisperAvatar(username: contextUsername, size: 36)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(contextUsername)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    VerifiedBadge(
                        badge: UserVerificationService.shared.badge(forUsername: contextUsername),
                        size: 13,
                        username: contextUsername
                    )
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.45))
                    Text(replyTarget.map { WhisperPost.relativeTime(from: $0.created_at) } ?? post.timeAgo)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                    Spacer(minLength: 0)
                }
                // If this post carries a workout embed, render the rich
                // workout card (orange gradient, stats, exercise list) and
                // strip the raw JSON payload from the caption — otherwise
                // it bleeds through as a wall of characters.
                if let replyTarget {
                    WhisperCommentBodyView(text: replyTarget.body, usesThreadMediaLayout: true)
                } else if let workoutPayload = post.decodedWorkoutPayload() {
                    let visibleCaption = post.displayCaption
                    if !visibleCaption.isEmpty {
                        Text(visibleCaption)
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    WhisperWorkoutPostCard(
                        payload: workoutPayload,
                        username: post.username,
                        accent: post.accent
                    )
                } else if !post.displayCaption.isEmpty {
                    Text(post.displayCaption)
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if replyTarget == nil, let url = post.mediaURLs.first {
                    Color(.secondarySystemBackground)
                        .frame(height: 180)
                        .overlay {
                            WhisperCachedAsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    Image(systemName: "photo")
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                }
                            }
                            .allowsHitTesting(false)
                        }
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
                        }
                }
            }
        }
        .padding(.bottom, 20)
        .background(alignment: .leading) {
            WhisperThreadConnector()
                .stroke(WhisperTheme.hairline(colorScheme), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 12)
    }

    private var replyRow: some View {
        HStack(alignment: .top, spacing: 10) {
            WhisperAvatar(username: me, size: 36)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(me)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    VerifiedBadge(
                        badge: UserVerificationService.shared.badge(forUsername: me),
                        size: 13,
                        username: me
                    )
                    Spacer(minLength: 0)
                }
                Text("Replying to \(replyTarget?.username ?? post.username)")
                    .font(.caption).foregroundStyle(WhisperTheme.muted(colorScheme))
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Add your reply…")
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .padding(.top, 2)
                    }
                    TextField("", text: $draft, axis: .vertical)
                        .focused($focused)
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .tint(WhisperTheme.ink(colorScheme))
                        .lineLimit(1...20)
                }
                WhisperMentionSuggestionsBar(text: $draft)
                characterCounter
                if !attachments.isEmpty {
                    WhisperComposerAttachmentChips(bag: attachments).frame(height: 106)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 22) {
                        iconButton("photo") { presentPhotoPicker = true }
                        iconButton("camera") { showCamera = true }
                        gifButton { showGif = true }
                        iconButton("face.smiling") { showSticker = true }
                        iconButton("chart.bar.xaxis") { showPoll = true }
                        iconButton(locationLoading ? "location.fill" : "location") { attachLocation() }
                        iconButton("mic") { showVoice = true }
                        iconButton("text.alignleft") { showFormatting = true }
                    }
                }
                .scrollClipDisabled()
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.6))
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: name)
                .font(.body.weight(.regular))
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Custom GIF text glyph (no matching SF Symbol). Rendered as an
    /// outlined pill with bold "GIF" text so it reads at a glance, matching
    /// the inline composer.
    private func gifButton(action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text("GIF")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(WhisperTheme.ink(colorScheme).opacity(0.6), lineWidth: 1.4)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text("Replying to \(replyTarget?.username ?? post.username)")
                .font(.footnote).foregroundStyle(WhisperTheme.muted(colorScheme)).lineLimit(1)
            Spacer()
            Button {
                Task { await send() }
            } label: {
                Text(sending ? "Posting…" : "Post")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(canSend ? WhisperTheme.surface(colorScheme) : WhisperTheme.muted(colorScheme))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
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
        .padding(.vertical, 10)
        .background(
            WhisperTheme.surface(colorScheme)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(WhisperTheme.hairline(colorScheme))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func send() async {
        guard canSend, !sending, WhisperPostMeta.parse(from: post.caption)?.commentsOff != true else { return }
        let generation = AccountStorage.generation
        sending = true
        let commentID = attachments.commentID(baseBody: draft, postID: postIDString, parentID: replyTarget?.id)
        Haptics.tap()
        guard let body = await attachments.finalize(baseBody: draft, postID: postIDString) else {
            guard generation == AccountStorage.generation else { return }
            sending = false
            sendError = "An attachment couldn't upload. Your reply is still here; please try again."
            return
        }
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        let parent = replyTarget?.id
        let posted = await backend.addComment(postID: postIDString, body: body, parentCommentID: parent, commentID: commentID)
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        sending = false
        guard posted != nil else {
            sendError = "Your reply couldn't be confirmed. Your text and attachments are still here."
            WhisperFeedback.failed()
            return
        }
        WhisperFeedback.sent()
        onPosted()
        dismiss()
        if WhisperEmberMention.shouldRespond(to: body) {
            let pid = postIDString
            let caption = post.caption
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
