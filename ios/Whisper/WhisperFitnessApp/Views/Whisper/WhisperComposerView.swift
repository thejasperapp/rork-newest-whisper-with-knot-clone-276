import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

/// Threads-style composer for Whisper. Text-first single screen with
/// optional photo / video attachments, a "quote post" picker that pulls a
/// real post from the feed, plus the existing Whisper hooks for sharing a
/// workout or a progress photo.
///
/// The visual language matches the Threads "New thread" sheet: avatar
/// column on the left, content column on the right (username header,
/// optional topic chip, text editor, attachment cards, inline toolbar of
/// quick-action icons), with a sticky bottom bar carrying the Ghost-post
/// toggle and the Post button.
struct WhisperThreadComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focused: Bool

    // MARK: - Content state

    @State private var text: String = ""
    /// Extra thread parts (beyond the main post). Each entry becomes its
    /// own follow-up post on publish, with a "k/N" marker so the feed
    /// can render them as a connected chain.
    @State private var threadParts: [String] = []
    @FocusState private var focusedThreadPart: Int?
    @State private var photos: [Data] = []
    @State private var videoFile: URL? = nil
    @State private var videoUploader: WhisperWaveUploadService = WhisperWaveUploadService()
    @State private var uploadedVideoURL: String? = nil
    @State private var isImporting: Bool = false
    @State private var composerClosed: Bool = false
    @State private var importTask: Task<Void, Never>? = nil
    @State private var attachedWorkout: WorkoutSessionRecord? = nil
    @State private var attachedProgress: ProgressPhoto? = nil
    @State private var quotedPost: WhisperPost? = nil
    @State private var ghost: Bool = false
    @State private var topic: String = ""
    /// Shared film/article riding this post — parsed OUT of a Jasper/share
    /// draft so the editor never shows the raw embed token; re-attached to
    /// the caption on publish. Rendered as a removable preview card.
    @State private var filmEmbed: WhisperFilmEmbed.Payload? = nil
    @State private var articleEmbed: WhisperArticleEmbed.Payload? = nil

    /// Optional preset used when this composer is presented as the
    /// "Quote" surface from a repost menu — seeds `quotedPost` so the
    /// quoted card is pre-attached on launch.
    private let initialQuotedPost: WhisperPost?
    /// When true, the post is created with `is_reel = true` so it shows up
    /// in the Reels surface. Used by the "create reel" entry on the
    /// Reels player.
    private let isReelMode: Bool
    private let initialPhotoPickerItems: [PhotosPickerItem]
    private let receivesCaptureMedia: Bool
    private let onPosted: (() -> Void)?
    private let onBusyChanged: ((Bool) -> Void)?
    private let isActive: Bool
    private let onCancel: (() -> Void)?
    private let onDirtyChanged: ((Bool) -> Void)?
    @State private var confirmsCaptureExit: Bool = false
    @State private var failedPhotoItems: [PhotosPickerItem] = []
    @State private var importedCaptureMedia: Bool = false

    init(
        initialQuotedPost: WhisperPost? = nil,
        isReelMode: Bool = false,
        initialTopic: String = "",
        initialText: String = "",
        initialPhotos: [Data] = [],
        initialPhotoPickerItems: [PhotosPickerItem] = [],
        onPosted: (() -> Void)? = nil,
        isActive: Bool = true,
        onBusyChanged: ((Bool) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onDirtyChanged: ((Bool) -> Void)? = nil
    ) {
        self.initialQuotedPost = initialQuotedPost
        self.isReelMode = isReelMode
        self.onPosted = onPosted
        self.isActive = isActive
        self.onBusyChanged = onBusyChanged
        self.onCancel = onCancel
        self.onDirtyChanged = onDirtyChanged
        self.initialPhotoPickerItems = initialPhotoPickerItems
        self.receivesCaptureMedia = !initialPhotos.isEmpty || !initialPhotoPickerItems.isEmpty
        self._photos = State(initialValue: initialPhotos)
        self._isImporting = State(initialValue: !initialPhotoPickerItems.isEmpty)
        self._quotedPost = State(initialValue: initialQuotedPost)
        self._topic = State(initialValue: initialTopic)
        if !initialText.isEmpty {
            self._text = State(initialValue: initialText)
        }
    }

    // MARK: - Picker state

    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var presentPhotoPicker = false
    @State private var presentWorkoutPicker = false
    @State private var presentProgressPicker = false
    @State private var presentQuotePicker = false
    @State private var presentTopicEditor = false
    @State private var presentDrafts = false
    @State private var presentMoreMenu = false

    // MARK: - Services

    @State private var photoService = ProgressPhotoService.shared
    @State private var backend = WhisperBackendService.shared
    @State private var coach = WhisperCoachService.shared

    @State private var workouts: [WorkoutSessionRecord] = []
    @State private var posting: Bool = false
    @State private var publishError: String? = nil
    @State private var importedRouterDraft: Bool = false
    @State private var importGeneration: UUID = UUID()
    @State private var publishedRootID: String? = nil
    @State private var pendingThreadParts: [WhisperPendingThreadPart] = []
    @State private var publicationID: String = UUID().uuidString.lowercased()
    @State private var publicationStarted: Bool = false

    private var displayUsername: String {
        WhisperUserService.shared.me?.username
            ?? LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    private var canPost: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasContent = !trimmed.isEmpty
            || !photos.isEmpty
            || videoFile != nil
            || attachedWorkout != nil
            || attachedProgress != nil
            || quotedPost != nil
            || filmEmbed != nil
            || articleEmbed != nil
        return !posting && !isImporting && ((publishedRootID != nil && !pendingThreadParts.isEmpty) || (hasContent && !anyPartOverLimit))
    }

    /// Hard cap on each composer field. Verified accounts unlock the
    /// long-form ceiling — see `WhisperVerifiedPerks.characterLimit`.
    private var characterLimit: Int {
        WhisperVerifiedPerks.characterLimit(username: displayUsername)
    }

    /// True if any thread part (root or follow-up) exceeds the cap.
    /// `.onChange` clamps incoming edits, but this guards the Post button
    /// against any edge case where a pasted string slipped past the clamp.
    private var anyPartOverLimit: Bool {
        if text.count > characterLimit { return true }
        return threadParts.contains { $0.count > characterLimit }
    }

    private var hasEdits: Bool {
        !text.isEmpty || !photos.isEmpty || videoFile != nil || !threadParts.isEmpty
            || attachedWorkout != nil || attachedProgress != nil || quotedPost != nil
            || filmEmbed != nil || articleEmbed != nil || !topic.isEmpty || ghost
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                WhisperTheme.surface(colorScheme)
                    .ignoresSafeArea()
                    .onAppear {
                        // Jasper can pre-fill the composer with a drafted post
                        // and assign it to a community — the user still
                        // reviews and posts from the real composer.
                        guard !importedRouterDraft, !receivesCaptureMedia else { return }
                        importedRouterDraft = true
                        if text.isEmpty, initialQuotedPost == nil,
                           let draft = WhisperEmberActionRouter.shared.consumeComposerDraft() {
                            // Never show a raw `::whisper-…::` token in the
                            // editor — split it into clean text + a preview
                            // card, then re-attach the token on publish.
                            let split = WhisperContentEmbedParser.parse(draft)
                            text = split.cleaned
                            filmEmbed = split.film
                            articleEmbed = split.article
                            quotedPost = split.quote.flatMap { WhisperSharedPostEmbed.rebuildPost($0) }
                        }
                        if topic.isEmpty,
                           let community = WhisperEmberActionRouter.shared.consumeComposerTopic(),
                           !community.isEmpty {
                            topic = community
                        }
                    }
                ScrollView {
                    threadRow
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                        .disabled(posting || publicationStarted)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            }
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(posting || receivesCaptureMedia)
            .confirmationDialog("Leave this post?", isPresented: $confirmsCaptureExit, titleVisibility: .visible) {
                Button("Discard post edits", role: .destructive) { dismissComposer() }
                Button("Keep editing", role: .cancel) {}
            } message: { Text("Your original selection stays in the creation screen. Caption and post edits will be discarded; any already-published content remains published.") }
            .alert("Post update", isPresented: Binding(get: { publishError != nil }, set: { if !$0 { publishError = nil } })) {
                if !failedPhotoItems.isEmpty {
                    Button("Retry attachments") {
                        let items = failedPhotoItems
                        importTask?.cancel(); importTask = Task { await loadPhotoItems(items) }
                    }
                }
                Button("Back to post", role: .cancel) { publishError = nil }
            } message: { Text(publishError ?? "") }
            .toolbar { toolbarContent }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                importTask?.cancel(); importGeneration = UUID(); dismissComposer()
            }
            .task {
                guard !importedCaptureMedia, !initialPhotoPickerItems.isEmpty else { return }
                importedCaptureMedia = true
                importTask = Task { await loadPhotoItems(initialPhotoPickerItems) }
            }
            .onDisappear { importTask?.cancel() }
            .onChange(of: posting || isImporting || publicationStarted, initial: true) { _, busy in onBusyChanged?(busy) }
            .onChange(of: hasEdits, initial: true) { _, dirty in onDirtyChanged?(dirty) }
            .onChange(of: isActive) { _, active in
                if !active { focused = false; focusedThreadPart = nil }
            }
            .onChange(of: videoFile) { old, _ in
                uploadedVideoURL = nil
                videoUploader = WhisperWaveUploadService()
                if let old { try? FileManager.default.removeItem(at: old) }
            }
            .overlay {
                if isImporting { ProgressView("Preparing attachment…").padding(20).background(.regularMaterial, in: .rect(cornerRadius: 18)) }
            }
            .photosPicker(
                isPresented: $presentPhotoPicker,
                selection: $photoPickerItems,
                maxSelectionCount: isReelMode ? 1 : 10,
                matching: isReelMode ? .videos : .any(of: [.images, .videos]),
                photoLibrary: .shared()
            )
            .onChange(of: photoPickerItems) { _, items in
                guard !items.isEmpty else { return }
                importTask?.cancel()
                importTask = Task { await loadPhotoItems(items) }
            }
            .sheet(isPresented: $presentWorkoutPicker) {
                workoutPickerSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .whisperSheetBorder()
            }
            .sheet(isPresented: $presentProgressPicker) {
                progressPickerSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .whisperSheetBorder()
            }
            .sheet(isPresented: $presentQuotePicker) {
                quotePickerSheet
                    .task { await backend.fetchPostsIfStale() }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $presentTopicEditor) {
                topicEditorSheet
                    .presentationDetents([.fraction(0.4)])
                    .presentationDragIndicator(.visible)
                    .whisperSheetBorder()
            }
            .sheet(isPresented: $presentDrafts) {
                draftsSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .whisperSheetBorder()
            }
            .task {
                loadWorkouts()
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                if isReelMode {
                    // Reels are video-first — drop the user straight into
                    // the video picker so they don't see an empty text
                    // composer that feels like a regular post.
                    presentPhotoPicker = true
                } else if !receivesCaptureMedia && isActive {
                    focused = true
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") {
                if receivesCaptureMedia { confirmsCaptureExit = true }
                else if let onCancel { onCancel() }
                else { dismissComposer() }
            }
                .disabled(posting)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
        ToolbarItem(placement: .principal) {
            Text(isReelMode ? "New reel" : receivesCaptureMedia ? "New post" : "New thread")
                .font(.headline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    presentDrafts = true
                } label: {
                    Image(systemName: "doc.text")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                Menu {
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.3)) { ghost.toggle() }
                    } label: {
                        Label(ghost ? "Disable ghost post" : "Post as ghost",
                              systemImage: "moon.zzz.fill")
                    }
                    Button {
                        Haptics.tap()
                        presentTopicEditor = true
                    } label: {
                        Label("Pick a topic", systemImage: "number")
                    }
                    Button(role: .destructive) {
                        Haptics.warning()
                        clearDraft()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    // MARK: - Thread row (avatar + content)

    private var threadRow: some View {
        HStack(alignment: .top, spacing: 12) {
            avatarColumn

            VStack(alignment: .leading, spacing: 10) {
                headerLine
                textEditor
                attachments
                inlineToolbar
                addToThreadRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }

    /// Avatar column with a thin vertical guide line under it — same visual
    /// trick Threads uses to hint that the post can be the start of a
    /// chained thread.
    private var avatarColumn: some View {
        VStack(spacing: 4) {
            WhisperAvatar(username: displayUsername, size: 40, ring: false)
            Rectangle()
                .fill(WhisperTheme.hairline(colorScheme))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .padding(.top, 2)
        }
        .frame(width: 40)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var headerLine: some View {
        HStack(spacing: 6) {
            Text(displayUsername)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            VerifiedBadge(
                badge: UserVerificationService.shared.badge(forUsername: displayUsername),
                size: 13,
                username: displayUsername
            )
            // Coach badge intentionally omitted here — VerifiedBadge already
            // signals identity in the composer header. Showing both led to
            // two badges stacking on the new-thread screen.
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.4))
            Button {
                Haptics.tap()
                presentTopicEditor = true
            } label: {
                Text(topic.isEmpty
                     ? "Community or topic"
                     : (WhisperCommunity.resolve(topic: topic)?.name ?? topic))
                    .font(.subheadline)
                    .foregroundStyle(topic.isEmpty
                                     ? WhisperTheme.ink(colorScheme).opacity(0.5)
                                     : WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            if ghost {
                Image(systemName: "moon.zzz.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
            }
        }
    }

    private var textEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(isReelMode ? "Caption your reel…" : "What's new?", text: $text, axis: .vertical)
                .focused($focused)
                .font(.body)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .tint(WhisperTheme.ink(colorScheme))
                .lineLimit(1...12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: text) { _, newValue in
                    if newValue.count > characterLimit {
                        text = String(newValue.prefix(characterLimit))
                        Haptics.warning()
                    }
                }
            if WhisperDearEmberService.matches(text) {
                Label("Only you: Knot will tune your feed. This won’t be posted.", systemImage: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            } else {
                WhisperMentionSuggestionsBar(text: $text)
                if text.isEmpty && !isReelMode {
                    Text("Try @knot show me more running posts to tune your feed privately.")
                        .font(.caption).foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            characterCounter(for: text)
        }
    }

    /// Subtle counter that only appears once the user is within the last
    /// ~20% of their cap. Turns red when the limit is hit so the disabled
    /// Post button doesn't feel like a silent failure.
    @ViewBuilder
    private func characterCounter(for value: String) -> some View {
        let limit = characterLimit
        let remaining = limit - value.count
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
                        : (isNear ? .orange : WhisperTheme.ink(colorScheme).opacity(0.5))
                    )
            }
        }
    }

    // MARK: - Attachments stack

    @ViewBuilder
    private var attachments: some View {
        if !photos.isEmpty || videoFile != nil {
            mediaCarousel
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if let workout = attachedWorkout {
            workoutAttachment(workout)
                .transition(.opacity)
        }
        if let progress = attachedProgress {
            progressAttachment(progress)
                .transition(.opacity)
        }
        if let q = quotedPost {
            quoteAttachment(q)
                .transition(.opacity)
        }
        if let f = filmEmbed {
            embedDraftCard(
                kicker: "WHISPER FILM",
                title: f.title,
                subtitle: "A \(f.director) film",
                icon: "film.fill",
                imageURL: f.poster.flatMap(URL.init(string:))
            ) {
                withAnimation(.spring(response: 0.3)) { filmEmbed = nil }
            }
            .transition(.opacity)
        }
        if let a = articleEmbed {
            embedDraftCard(
                kicker: "WHISPER JOURNAL",
                title: a.title,
                subtitle: "By \(a.author)",
                icon: "doc.text.fill",
                imageURL: a.cover.flatMap(URL.init(string:))
            ) {
                withAnimation(.spring(response: 0.3)) { articleEmbed = nil }
            }
            .transition(.opacity)
        }
    }

    /// Compact preview of the film/article card this post will carry —
    /// the wall renders the real tappable card; the composer shows this
    /// stand-in with a remove control instead of raw token text.
    private func embedDraftCard(
        kicker: String,
        title: String,
        subtitle: String,
        icon: String,
        imageURL: URL?,
        onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Color(white: 0.10)
                if let imageURL {
                    WhisperCachedAsyncImage(url: imageURL) { phase in
                        if let img = phase.image {
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        }
                    }
                } else {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker)
                    .font(.system(size: 8, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Text(title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text("Card")
                .font(.system(size: 9, weight: .black))
                .tracking(0.6)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(WhisperTheme.ink(colorScheme).opacity(0.06), in: Capsule())
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .frame(width: 24, height: 24)
                    .background(WhisperTheme.ink(colorScheme).opacity(0.06), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove attached card")
        }
        .padding(8)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var mediaCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.offset) { idx, data in
                    photoThumb(data: data) {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.3)) {
                            photos.remove(at: idx)
                        }
                    }
                }
                if videoFile != nil {
                    videoThumb {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.3)) {
                            videoFile = nil
                        }
                    }
                }
                // Instagram-style "add more" tile at the end of the strip —
                // adding a second photo shouldn't require hunting for the
                // toolbar icon again.
                if videoFile == nil && !photos.isEmpty && photos.count < 10 {
                    addMediaTile
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var addMediaTile: some View {
        Button {
            Haptics.tap()
            presentPhotoPicker = true
        } label: {
            RoundedRectangle(cornerRadius: 14)
                .fill(WhisperTheme.card(colorScheme).opacity(0.6))
                .frame(width: 92, height: 240)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            WhisperTheme.hairline(colorScheme),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                        )
                }
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.bold))
                        Text("Add")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                }
        }
        .buttonStyle(.plain)
    }

    private func photoThumb(data: Data, onRemove: @escaping () -> Void) -> some View {
        let img = UIImage(data: data)
        return Color(.secondarySystemBackground)
            .frame(width: 180, height: 240)
            .overlay {
                if let img {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.black.opacity(0.55), in: Circle())
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
    }

    private func videoThumb(onRemove: @escaping () -> Void) -> some View {
        ZStack {
            Color.black
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 180, height: 240)
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
    }

    private func workoutAttachment(_ w: WorkoutSessionRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.body.weight(.bold))
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .frame(width: 38, height: 38)
                .background(WhisperTheme.ink(colorScheme), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(w.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                Text("\(w.focus) · \(Int(w.duration / 60)) min · \(Int(w.caloriesBurned)) cal")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
                if photos.isEmpty {
                    Text("Add a photo to feature it on the card")
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            removeButton {
                withAnimation(.spring(response: 0.3)) { attachedWorkout = nil }
            }
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
        }
    }

    private func progressAttachment(_ p: ProgressPhoto) -> some View {
        HStack(spacing: 12) {
            Color(.secondarySystemBackground)
                .frame(width: 56, height: 56)
                .overlay {
                    if let img = UIImage(data: p.imageData) {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("Progress · \(p.pose.rawValue)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                if let weight = p.weight {
                    Text("\(Int(weight)) lb · \(p.date.formatted(.dateTime.month().day()))")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                } else {
                    Text(p.date.formatted(.dateTime.month().day().year()))
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            Spacer(minLength: 0)
            removeButton {
                withAnimation(.spring(response: 0.3)) { attachedProgress = nil }
            }
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
        }
    }

    /// Threads-style inline quoted-post card. Tap → opens the quote picker to
    /// swap. The card is rendered as a normal Threads attachment with a
    /// hairline border so it reads as "you're quoting someone".
    private func quoteAttachment(_ p: WhisperPost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quoted post").font(.caption.weight(.semibold))
                Spacer()
                removeButton { quotedPost = nil }
            }
            WhisperQuotedPostCard(payload: .init(postID: p.id.uuidString.lowercased(), username: p.username, caption: "", kindRaw: p.kind.rawValue, symbol: p.symbol, accentHex: nil, mediaURL: nil, isVideo: false, likes: 0, comments: 0), depth: 0, parentPostID: nil, isPreview: true)
                .id(p.id)
        }
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.6))
                .frame(width: 22, height: 22)
                .background(WhisperTheme.surface(colorScheme), in: Circle())
                .overlay {
                    Circle().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
                }
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove attachment")
    }

    // MARK: - Inline toolbar (Threads action icons under the text)

    private var inlineToolbar: some View {
        HStack(spacing: 12) {
            toolbarIcon(systemName: "photo") {
                presentPhotoPicker = true
            }
            toolbarIcon(systemName: "quote.bubble") {
                presentQuotePicker = true
            }
            toolbarIcon(systemName: "dumbbell.fill") {
                presentWorkoutPicker = true
            }
            toolbarIcon(systemName: "chart.line.uptrend.xyaxis") {
                presentProgressPicker = true
            }
            Menu {
                Button {
                    Haptics.tap()
                    presentTopicEditor = true
                } label: { Label("Add topic", systemImage: "number") }
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3)) { ghost.toggle() }
                } label: {
                    Label(ghost ? "Disable ghost post" : "Post as ghost",
                          systemImage: "moon.zzz.fill")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                    .frame(width: 38, height: 38)
                    .contentShape(.rect)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func toolbarIcon(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                .frame(width: 38, height: 38)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Threads-style "Add to thread" row + chained follow-up entries.
    /// Tapping appends a new part the user can edit; each part becomes
    /// its own follow-up post on publish, with a "k/N" marker so they
    /// render as a connected chain in the feed.
    private var addToThreadRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(threadParts.enumerated()), id: \.offset) { idx, _ in
                threadPartRow(index: idx)
            }
            Button {
                Haptics.tap()
                let newIndex = threadParts.count
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    threadParts.append("")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    focusedThreadPart = newIndex
                }
            } label: {
                HStack(spacing: 10) {
                    WhisperAvatar(username: displayUsername, size: 22, ring: false)
                        .opacity(0.55)
                    Text("Add to thread")
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.4))
                    Spacer(minLength: 0)
                    if !threadParts.isEmpty {
                        WhisperThreadPositionPill(
                            index: threadParts.count + 1,
                            total: threadParts.count + 1
                        )
                    }
                }
                .padding(.top, 8)
            }
            .buttonStyle(.plain)
        }
    }

    /// Inline editor row for thread part `index` (0 = first follow-up after
    /// the main post). Mirrors the avatar-column visual language of the
    /// main composer row so the chain reads as one continuous thread.
    private func threadPartRow(index: Int) -> some View {
        let position = index + 2        // main post is 1
        let total = threadParts.count + 1
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                WhisperAvatar(username: displayUsername, size: 40, ring: false)
                Rectangle()
                    .fill(WhisperTheme.hairline(colorScheme))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 2)
            }
            .frame(width: 40)
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(displayUsername)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    WhisperThreadPositionPill(index: position, total: total)
                    Spacer(minLength: 0)
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.3)) {
                            if index < threadParts.count {
                                threadParts.remove(at: index)
                            }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
                TextField("Continue the thread…",
                          text: Binding(
                            get: { index < threadParts.count ? threadParts[index] : "" },
                            set: { newValue in
                                guard index < threadParts.count else { return }
                                let limit = characterLimit
                                if newValue.count > limit {
                                    threadParts[index] = String(newValue.prefix(limit))
                                    Haptics.warning()
                                } else {
                                    threadParts[index] = newValue
                                }
                            }
                          ),
                          axis: .vertical)
                    .focused($focusedThreadPart, equals: index)
                    .font(.body)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .tint(WhisperTheme.ink(colorScheme))
                    .lineLimit(1...10)
                if index < threadParts.count {
                    characterCounter(for: threadParts[index])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Bottom bar (Post Options + Post button)

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().background(WhisperTheme.hairline(colorScheme))
            HStack(spacing: 12) {
                postOptionsPill
                Spacer(minLength: 0)
                emojiPill
                postButton
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var postOptionsPill: some View {
        Button {
            Haptics.tap()
            presentMoreMenu = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption.weight(.heavy))
                Text(ghost ? "Ghost · Friends" : "Post Options")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.75))
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Post options", isPresented: $presentMoreMenu, titleVisibility: .hidden) {
            Button(ghost ? "Disable ghost post" : "Post as ghost") {
                Haptics.tap()
                withAnimation(.spring(response: 0.3)) { ghost.toggle() }
            }
            Button("Edit topic") {
                Haptics.tap()
                presentTopicEditor = true
            }
            Button("Clear draft", role: .destructive) {
                Haptics.warning()
                clearDraft()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var emojiPill: some View {
        Menu {
            ForEach(["🔥", "💪", "🥲", "😤", "👀", "🙏", "🧊", "🐐"], id: \.self) { e in
                Button(e) {
                    Haptics.tap()
                    text += e
                }
            }
        } label: {
            Image(systemName: "face.smiling")
                .font(.body.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(WhisperTheme.card(colorScheme), in: Capsule())
                .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5) }
        }
    }

    private var postButton: some View {
        Button {
            Haptics.press()
            Task { await publish() }
        } label: {
            HStack(spacing: 6) {
                if posting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(WhisperTheme.surface(colorScheme))
                }
                Text(posting ? "Posting…" : (isReelMode ? "Share reel" : "Post"))
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(WhisperTheme.surface(colorScheme))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                canPost
                ? WhisperTheme.ink(colorScheme)
                : WhisperTheme.ink(colorScheme).opacity(0.4),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(!canPost)
    }

    // MARK: - Workout picker

    private var workoutPickerSheet: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                if workouts.isEmpty {
                    pickerEmptyState(
                        icon: "dumbbell.fill",
                        title: "No workouts yet",
                        subtitle: "Log a workout in Whisper to attach it to a post."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(workouts) { w in
                                Button {
                                    Haptics.tap()
                                    attachedWorkout = w
                                    presentWorkoutPicker = false
                                } label: {
                                    workoutPickRow(w)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Attach workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { presentWorkoutPicker = false }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private func workoutPickRow(_ w: WorkoutSessionRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .frame(width: 38, height: 38)
                .background(WhisperTheme.ink(colorScheme), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(w.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("\(w.focus) · \(Int(w.duration / 60)) min · \(Int(w.caloriesBurned)) cal")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
        }
    }

    // MARK: - Progress picker

    private var progressPickerSheet: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                if photoService.photos.isEmpty {
                    pickerEmptyState(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "No progress photos",
                        subtitle: "Add a progress photo in Whisper to attach it here."
                    )
                } else {
                    ScrollView {
                        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
                        LazyVGrid(columns: cols, spacing: 8) {
                            ForEach(photoService.photos) { p in
                                Button {
                                    Haptics.tap()
                                    attachedProgress = p
                                    presentProgressPicker = false
                                } label: {
                                    progressPhotoThumb(p)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Attach progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { presentProgressPicker = false }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private func progressPhotoThumb(_ p: ProgressPhoto) -> some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let img = UIImage(data: p.imageData) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(.rect(cornerRadius: 10))
            .overlay(alignment: .bottomLeading) {
                Text(p.pose.rawValue)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(6)
            }
    }

    // MARK: - Quote-post picker

    private var quotePickerSheet: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                let pool = quotePool()
                if pool.isEmpty {
                    pickerEmptyState(
                        icon: "quote.bubble",
                        title: "Nothing to quote yet",
                        subtitle: "When friends post, you'll be able to quote them here."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(pool) { p in
                                Button {
                                    Haptics.tap()
                                    quotedPost = p
                                    presentQuotePicker = false
                                } label: {
                                    quotePickRow(p)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Quote a post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { presentQuotePicker = false }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private func quotePickRow(_ p: WhisperPost) -> some View {
        HStack(alignment: .top, spacing: 10) {
            WhisperAvatar(username: p.username, size: 36, ring: false)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(p.username)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.4))
                    Text(p.timeAgo)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                    Spacer(minLength: 0)
                }
                if !p.displayCaption.isEmpty {
                    Text(WhisperContentEmbedParser.parse(p.displayCaption).cleaned)
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.85))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
        }
    }

    /// Maps the backend's `WhisperPostRow` cache into the `WhisperPost`
    /// model the quote picker (and quote attachment card) expects.
    private func quotePool() -> [WhisperPost] {
        backend.posts.prefix(30).map { row in
            let urls: [URL] = (row.media_urls ?? []).compactMap { URL(string: $0) }
            return WhisperPost(
                id: UUID(uuidString: row.id) ?? UUID(),
                username: backend.resolvedAuthorUsername(rowUsername: row.username, rowUserID: row.user_id),
                timeAgo: WhisperPost.relativeTime(from: row.created_at),
                kind: WhisperPostKind(rawValue: row.kind ?? "") ?? .photo,
                caption: row.caption,
                symbol: row.symbol ?? WhisperPostKind(rawValue: row.kind ?? "")?.icon ?? "sparkles",
                accent: WhisperPost.color(fromHex: row.accent_hex) ?? Color(red: 0.5, green: 0.5, blue: 0.5),
                mediaURLs: urls,
                likes: row.likes_count ?? 0,
                comments: row.comments_count ?? 0,
                liked: false,
                isReel: row.is_reel ?? false,
                createdAt: WhisperBackendService.parseISO(row.created_at)
            )
        }
    }

    // MARK: - Topic editor

    private var topicEditorSheet: some View {
        WhisperTopicSearchSheet(
            selected: $topic,
            isPresented: $presentTopicEditor
        )
    }

    // MARK: - Drafts (placeholder)

    private var draftsSheet: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                pickerEmptyState(
                    icon: "doc.text",
                    title: "No drafts",
                    subtitle: "Drafts you save in this composer will show up here."
                )
            }
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { presentDrafts = false }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    // MARK: - Empty state used by all picker sheets

    private func pickerEmptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            WhisperMeetDoodle(symbol: icon, height: 144)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Photo loading

    private func loadPhotoItems(_ items: [PhotosPickerItem]) async {
        guard !composerClosed, !posting, !publicationStarted else { return }
        let epoch = AccountStorage.generation
        let operation = UUID()
        importGeneration = operation
        failedPhotoItems = items
        var newPhotos: [Data] = []
        isImporting = true
        defer { if operation == importGeneration { isImporting = false } }
        var newVideo: URL? = nil
        let hasVideo = items.contains { item in item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) } }
        guard !hasVideo || items.count == 1 else {
            publishError = "Choose up to 10 photos or one video, not a mixture. Your current post is unchanged."
            failedPhotoItems = []; return
        }
        for item in items {
            guard !Task.isCancelled, epoch == AccountStorage.generation, operation == importGeneration, !composerClosed else { return }
            let isVideo = item.supportedContentTypes.contains { t in
                t.conforms(to: .movie) || t.conforms(to: .video) || t.conforms(to: .audiovisualContent)
            }
            if isVideo {
                do {
                    guard let movie = try await item.loadTransferable(type: WhisperPickedMovie.self) else { throw CocoaError(.fileReadCorruptFile) }
                    do {
                        let prepared = try await WhisperPostVideoPreparation.prepare(movie.url)
                        if prepared != movie.url { try? FileManager.default.removeItem(at: movie.url) }
                        newVideo = prepared
                    } catch {
                        try? FileManager.default.removeItem(at: movie.url)
                        throw error
                    }
                    break
                } catch {
                    guard epoch == AccountStorage.generation, operation == importGeneration, !Task.isCancelled else { return }
                    publishError = "Couldn't prepare this video. Choose a playable clip under 50 MiB or a shorter video. Your current post is unchanged."
                    return
                }
            } else {
                guard let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else {
                    guard !Task.isCancelled, epoch == AccountStorage.generation, operation == importGeneration, !composerClosed else { return }
                    publishError = "Couldn't load every selected photo. Retry or choose another selection. Your current post is unchanged."
                    return
                }
                newPhotos.append(data)
            }
        }
        await MainActor.run {
            guard epoch == AccountStorage.generation, operation == importGeneration, !Task.isCancelled else {
                if let newVideo { try? FileManager.default.removeItem(at: newVideo) }
                return
            }
            if let v = newVideo {
                videoFile = v
                photos = []
            } else if !newPhotos.isEmpty {
                photos.append(contentsOf: newPhotos)
                if photos.count > 10 { photos = Array(photos.prefix(10)) }
                videoFile = nil
            }
            failedPhotoItems = []
            photoPickerItems = []
        }
    }

    // MARK: - Workouts loader

    private func loadWorkouts() {
        guard let data = AccountStorage.data(forKey: "workoutSessionHistory"),
              let decoded = try? JSONDecoder().decode([WorkoutSessionRecord].self, from: data) else {
            workouts = []
            return
        }
        workouts = decoded.sorted { $0.date > $1.date }
    }

    private func dismissComposer() {
        composerClosed = true
        importTask?.cancel(); importGeneration = UUID()
        if !posting, let videoFile { try? FileManager.default.removeItem(at: videoFile) }
        dismiss()
    }

    private func clearDraft() {
        guard !posting, !publicationStarted else { return }
        importTask?.cancel(); importTask = nil; isImporting = false
        importGeneration = UUID()
        photoPickerItems = []
        threadParts = []
        focusedThreadPart = nil
        filmEmbed = nil
        articleEmbed = nil
        withAnimation(.spring(response: 0.3)) {
            text = ""
            photos = []
            videoFile = nil
            attachedWorkout = nil
            attachedProgress = nil
            quotedPost = nil
            topic = ""
        }
    }

    // MARK: - Publish

    private func publish() async {
        guard canPost else { return }
        if WhisperDearEmberService.matches(text), WhisperDearEmberService.wishBody(text).isEmpty {
            publishError = "Tell Knot what you’d like to see, for example: @knot more running posts."
            return
        }
        guard !(attachedWorkout != nil && (attachedProgress != nil || videoFile != nil || photos.count > 1)),
              !(attachedProgress != nil && (videoFile != nil || !photos.isEmpty)) else {
            publishError = "Keep one attachment style per post. Workouts support one photo; progress photos and videos need their own posts. Remove the extra attachments before posting."
            return
        }
        posting = true
        defer { if composerClosed, let videoFile { try? FileManager.default.removeItem(at: videoFile) } }
        publishError = nil
        let generation = AccountStorage.generation
        if publishedRootID != nil {
            await publishRemainingParts(generation: generation)
            return
        }
        if !publicationStarted {
            publicationStarted = true
            importGeneration = UUID()
            pendingThreadParts = threadParts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.map { WhisperPendingThreadPart(body: $0) }
        }

        // "@knot …" (and legacy aliases) — intercept the magical feed-curation directive
        // before it ever becomes a post. We capture the wish, fire the
        // overlay animation on the feed, and dismiss the composer. The
        // user's actual words never get published.
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if WhisperDearEmberService.matches(raw) {
            WhisperDearEmberService.shared.curate(wish: raw)
            await MainActor.run {
                posting = false
                dismissComposer()
            }
            return
        }

        // The picked community rides as DATA on the post now — never folded
        // into the caption as a hashtag (mirrors the web composer).
        var finalCaption = ""
        let topicTrimmed = topic.trimmingCharacters(in: .whitespaces)
        let pickedCommunity = WhisperCommunity.resolve(topic: topicTrimmed)
        finalCaption = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let q = quotedPost {
            let token = WhisperSharedPostEmbed.encode(.init(
                postID: q.id.uuidString.lowercased(), username: q.username,
                caption: "", kindRaw: q.kind.rawValue, symbol: q.symbol,
                accentHex: nil, mediaURL: nil, isVideo: false,
                likes: q.likes, comments: q.comments, isReel: q.isReel
            ))
            finalCaption += (finalCaption.isEmpty ? "" : "\n\n") + token
        }

        // Re-attach any shared film/article card as its embed token — the
        // feed strips it back out and renders the tappable card.
        if let f = filmEmbed {
            let token = WhisperFilmEmbed.encode(f)
            if !token.isEmpty {
                finalCaption = finalCaption.isEmpty ? token : finalCaption + "\n\n" + token
            }
        }
        if let a = articleEmbed {
            let token = WhisperArticleEmbed.encode(a)
            if !token.isEmpty {
                finalCaption = finalCaption.isEmpty ? token : finalCaption + "\n\n" + token
            }
        }

        // Pick the kind to match the strongest attachment.
        let kind: String
        var symbol: String? = nil
        var mediaCount = 0
        var mediaDatas: [Data] = []
        var sendVideo: URL? = nil

        if let w = attachedWorkout {
            kind = "workout"
            symbol = "dumbbell.fill"
            // Embed the full workout payload at the head of the caption so
            // the feed card can render a rich (and savable) shared-workout
            // card. The post card strips the prefix before showing text.
            let embed = WhisperWorkoutEmbed.encode(w)
            let userText = finalCaption.trimmingCharacters(in: .whitespacesAndNewlines)
            finalCaption = embed + (userText.isEmpty ? "" : "\n" + userText)
            // Photos attached alongside a workout ride with the post — the
            // feed card renders the first one as the card's hero header.
            if !photos.isEmpty {
                mediaCount = photos.count
                mediaDatas = photos
            }
        } else if let p = attachedProgress {
            kind = "progress"
            symbol = "chart.line.uptrend.xyaxis"
            mediaCount = 1
            mediaDatas = [p.imageData]
        } else if let v = videoFile {
            // Match the existing convention: store videos under "photo" with
            // media_urls carrying the .mp4/.mov so the feed detects it.
            kind = "photo"
            symbol = "play.rectangle.fill"
            mediaCount = 1
            sendVideo = v
        } else if !photos.isEmpty {
            kind = "photo"
            symbol = "photo"
            mediaCount = photos.count
            mediaDatas = photos
        } else {
            kind = "text"
            symbol = "quote.opening"
        }

        if let sendVideo, uploadedVideoURL == nil {
            do {
                uploadedVideoURL = try await backend.uploadVideo(file: sendVideo, postID: publicationID, uploader: videoUploader)
            } catch {
                guard generation == AccountStorage.generation else { return }
                posting = false
                publicationStarted = false
                publishError = error.localizedDescription
                return
            }
        }
        guard generation == AccountStorage.generation, !Task.isCancelled else { return }
        let row = await backend.createPost(
            kind: kind,
            caption: finalCaption,
            symbol: symbol,
            accentHex: nil,
            mediaCount: mediaCount,
            isGhost: ghost,
            mediaDatas: mediaDatas,
            isReel: isReelMode && sendVideo != nil,
            communityID: topicTrimmed.isEmpty
                ? nil
                : (pickedCommunity?.id ?? topicTrimmed.lowercased().replacingOccurrences(of: " ", with: "-")),
            communityName: topicTrimmed.isEmpty ? nil : (pickedCommunity?.name ?? topicTrimmed),
            postID: publicationID,
            uploadedVideoURL: uploadedVideoURL
        )

        guard generation == AccountStorage.generation, !Task.isCancelled else { return }
        guard row != nil else {
            posting = false
            publishError = "Couldn’t confirm publication. Your post is still here. Tap Post to safely check and retry."
            WhisperFeedback.failed()
            return
        }
        publishedRootID = row?.id
        if let row, ghost {
            WhisperGhostService.shared.mark(row.id)
        }
        // The moment it is live — or the moment it is not. The button press
        // itself only confirms the tap; success is reported when the row
        // actually exists.
        await MainActor.run {
            if row != nil { WhisperFeedback.published() } else { WhisperFeedback.failed() }
        }

        // (Fact-check pre-warm removed — background AI spend. Verdicts now
        // come only from the explicit "Fact-check with Jasper" action.)

        // If the caption tagged @ember, fire Jasper's auto-reply as a
        // comment under the new post — same flow as comment-thread
        // mentions, so the AI joins the conversation right at publish time.
        if let row, WhisperEmberMention.shouldRespond(to: finalCaption) {
            let pid = row.id.lowercased()
            let caption = finalCaption
            Task {
                await WhisperEmberMention.respond(
                    toComment: caption,
                    postID: pid,
                    parentCommentID: nil,
                    postCaption: caption
                )
            }
        }

        // Publish any chained thread parts as author comments on the
        // parent post. Threads-style continuations should read as the
        // author replying to themselves immediately under the main post,
        // not as separate floating posts in the feed. The existing
        // author-comment rendering already gives us the connected visual
        // (avatar column + hairline) for free.
        await publishRemainingParts(generation: generation)
    }

    private func publishRemainingParts(generation: UUID) async {
        guard let postID = publishedRootID else { posting = false; return }
        while let part = pendingThreadParts.first {
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            let comment = await backend.addComment(postID: postID, body: part.body, commentID: part.id)
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            guard comment != nil else {
                posting = false
                publishError = "Your main post is published, but a thread reply wasn’t sent. Tap Post to retry the remaining replies without publishing the main post again."
                return
            }
            pendingThreadParts.removeFirst()
        }
        guard generation == AccountStorage.generation, !Task.isCancelled, !composerClosed else { return }
        posting = false
        onPosted?()
        dismissComposer()
    }
}

// MARK: - Tiny chip-flow helper used by the topic editor

private struct FlowChips: View {
    @Environment(\.colorScheme) private var colorScheme
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button { onTap(item) } label: {
                        Text("#\(item)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(WhisperTheme.card(colorScheme), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
