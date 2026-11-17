import SwiftUI
import PhotosUI
import AVFoundation

/// Editable sources stay on disk. Reviewing and choosing a cover never encode a video.
struct WhisperReelComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var captionFocused: Bool
    var initialVideoURL: URL? = nil
    var initialClipURLs: [URL] = []
    var initialClips: [WhisperWaveClip] = []
    var initialMusic: WhisperStoryMusic? = nil
    var initialFilter: SnapFilter = .none
    var initialAREffect: WhisperAREffect = .none
    var onPosted: (() -> Void)? = nil

    @State private var caption: String = ""
    @State private var clips: [WhisperWaveClip] = []
    @State private var music: WhisperStoryMusic?
    @State private var musicVolume: Double = 0.85
    @State private var muteOriginal: Bool = false
    @State private var texts: [WaveTextOverlay] = []
    @State private var filter: SnapFilter = .none
    @State private var adjustments: WhisperWaveColorAdjustments = .init()
    @State private var effect: WhisperAREffect = .none
    @State private var fx: WhisperWaveFXSetting?
    @State private var captions: WhisperWaveCaptions?
    @State private var coverImage: UIImage?
    @State private var coverTime: Double = 0.1
    @State private var audience: String = "everyone"
    @State private var allowComments: Bool = true
    @State private var allowSaves: Bool = true
    @State private var ghost: Bool = false
    @State private var shareToFeed: Bool = true
    @State private var saveToDevice: Bool = false
    @State private var publicationID: String = UUID().uuidString
    @State private var publicationPending: Bool = false
    @State private var restoredLegacy: Bool = false
    @State private var started: Bool = false
    @State private var generation: UUID = UUID()
    @State private var presentClips: Bool = false
    @State private var editorStart: String = "clips"
    @State private var presentCover: Bool = false
    @State private var presentPreview: Bool = false
    @State private var presentPicker: Bool = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var busy: Bool = false
    @State private var stage: String = ""
    @State private var progress: Double?
    @State private var errorMessage: String?
    @State private var work: Task<Void, Never>?
    @State private var coverWork: Task<Void, Never>?
    @State private var lastCoverRequest: WhisperWaveRenderRequest?
    @State private var lastCoverTime: Double?
    @State private var confirmExit: Bool = false
    @State private var cachedRender: URL?
    @State private var cachedRequest: WhisperWaveRenderRequest?
    @State private var uploadedVideo: String?
    @State private var uploadPath: String?
    @State private var uploader: WhisperWaveUploadService = WhisperWaveUploadService()
    @State private var attempt: WhisperWavePostAttempt = WhisperWavePostAttempt()
    @State private var backend: WhisperBackendService = .shared

    private var duration: Double { WhisperWaveTimeline.duration(clips) }
    private var canAct: Bool { !busy && !clips.isEmpty }
    private var request: WhisperWaveRenderRequest {
        WhisperWaveRenderRequest(clips: clips, music: music, volume: musicVolume, muted: muteOriginal, texts: texts, filter: filter, effect: effect, adjustments: adjustments, fx: fx, captions: captions)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    tools
                    settings
                    Text("Up to 6 minutes · video quality adjusts to fit uploads; original clips stay unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                    if publicationPending {
                        Label("Publication needs confirmation. Check this wave before editing or reposting.", systemImage: "clock")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if busy { progressPanel }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.black)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("New wave").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { requestExit() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Close composer").disabled(busy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Preview") { captionFocused = false; presentPreview = true }.disabled(!canAct)
                }
            }
            .sheet(isPresented: $presentCover) {
                WhisperWaveCoverPicker(request: request, selectedTime: coverTime) { time, image in
                    coverTime = time; coverImage = image; presentCover = false
                }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $presentClips, onDismiss: { refreshCover() }) {
                WhisperWaveClipsEditor(clips: $clips, music: $music, musicVolume: $musicVolume, muteOriginal: $muteOriginal, texts: $texts, filter: $filter, adjustments: $adjustments, fx: $fx, captions: $captions, effect: $effect, initialTool: editorStart, onCancel: { presentClips = false }, onDone: { presentClips = false })
            }
            .fullScreenCover(isPresented: $presentPreview) { WhisperWaveReviewView(request: request) }
            .photosPicker(isPresented: $presentPicker, selection: $pickerItem, matching: .videos)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                work = Task { await importVideo(item) }
            }
            .task { await loadInitial() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                generation = UUID(); work?.cancel(); presentClips = false; presentCover = false; presentPreview = false; dismiss()
            }
            .alert("Wave needs attention", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Please retry.") }
            .whisperEdgeBack(isEnabled: !busy && !presentClips && !presentPreview && !presentCover, requiresDecision: !clips.isEmpty || !caption.isEmpty, controller: backTransition) { requestExit() }
            .confirmationDialog("Keep your wave?", isPresented: $confirmExit, titleVisibility: .visible) {
                Button("Save draft") { work = Task { await saveDraftAndClose() } }
                Button("Discard unsaved changes", role: .destructive) { closeComposer() }
                Button("Keep editing", role: .cancel) {}
            } message: { Text("Your original clips and any previously saved draft stay on this device.") }
            .interactiveDismissDisabled(busy || !clips.isEmpty || !caption.isEmpty)
            .preferredColorScheme(.dark).tint(WhisperBrandGradient.accent)
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                captionFocused = false
                if clips.isEmpty { presentPicker = true } else { presentCover = true }
            } label: {
                Color.white.opacity(0.06)
                    .frame(width: 112, height: 192)
                    .overlay {
                        if let coverImage { Image(uiImage: coverImage).resizable().scaledToFill().allowsHitTesting(false) }
                        else { Image(systemName: clips.isEmpty ? "plus" : "film").font(.title).foregroundStyle(.white) }
                    }
                    .clipShape(.rect(cornerRadius: 18))
                    .overlay(alignment: .bottom) {
                        Text(clips.isEmpty ? "Add video" : "Edit cover")
                            .font(.caption.weight(.bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(.black.opacity(0.65), in: .rect(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
                    }
            }
            .buttonStyle(.plain).accessibilityLabel(clips.isEmpty ? "Add video" : "Edit cover")
            .accessibilityIdentifier("wave.editCover")
            VStack(alignment: .leading, spacing: 8) {
                TextField("Write a caption…", text: $caption, axis: .vertical)
                    .lineLimit(4...7).focused($captionFocused).font(.system(size: 15))
                WhisperMentionSuggestionsBar(text: $caption)
                Text("\(caption.count)/2200").font(.caption2.monospacedDigit()).foregroundStyle(caption.count > 2200 ? .red : .secondary)
                HStack(spacing: 10) {
                    Button("# Tag") { caption += " #"; captionFocused = true }
                    Button("@ Mention") { caption += " @"; captionFocused = true }
                    Button("AI") { work = Task { await suggestCaption() } }
                }.font(.caption.weight(.semibold)).buttonStyle(.bordered).buttonBorderShape(.capsule)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(["#fitness", "#gym", "#pr", "#legday", "#cardio", "#transformation", "#lifting"].filter { !caption.lowercased().contains($0) }, id: \.self) { tag in
                            Button(tag) { caption += (caption.isEmpty ? "" : " ") + tag }
                                .font(.caption2).padding(8).background(.white.opacity(0.06), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(14).background(.white.opacity(0.06), in: .rect(cornerRadius: 22))
        .disabled(busy || publicationPending)
    }

    private var tools: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tool("Clips", icon: "film.stack") { openEditor("clips") }
                tool("Text", icon: "textformat") { openEditor("text") }
                tool("Audio", icon: "music.note") { openEditor("audio") }
                tool("Filters", icon: "camera.filters") { openEditor("looks") }
                tool(fx.map { $0.kind.name } ?? "Effects", icon: "sparkles") { openEditor("effects") }
                tool("Face", icon: "face.smiling") { openEditor("face") }
                tool("Cover", icon: "photo") { presentCover = true }
                if effect != .none { tool("Remove \(effect.name)", icon: "face.smiling") { effect = .none; refreshCover() } }
                tool(muteOriginal ? "Original off" : "Original on", icon: muteOriginal ? "speaker.slash" : "speaker.wave.2") { muteOriginal.toggle() }
                tool("Swap video", icon: "arrow.triangle.2.circlepath") { presentPicker = true }
            }
        }.disabled(!canAct || publicationPending)
    }

    private func tool(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); captionFocused = false; action() } label: {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).padding(.horizontal, 14).frame(height: 44)
                .background(.white.opacity(0.08), in: Capsule())
        }.buttonStyle(.plain)
    }

    private var settings: some View {
        VStack(spacing: 12) {
            if let music {
                Button { openEditor("audio") } label: {
                    HStack { Image(systemName: "music.note"); Text(WhisperWaveSound.label(music)).lineLimit(1); Spacer(); Image(systemName: "chevron.right") }
                }.frame(minHeight: 44)
                Divider()
            }
            Picker("Who can watch", selection: $audience) {
                Text("Everyone").tag("everyone")
                Text("Friends · unavailable").tag("friends")
                Text("Only me · draft only").tag("onlyMe")
            }
            Toggle("Also share to feed", isOn: $shareToFeed)
            Toggle("Allow comments", isOn: $allowComments)
            Toggle("Allow saves", isOn: $allowSaves)
            if audience != "everyone" || !allowComments || !allowSaves {
                Text("These restrictions aren't supported by wave publishing yet. Keep a private device draft instead; nothing will be shared.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Toggle("Post as ghost", isOn: $ghost)
            Toggle("Save to device", isOn: $saveToDevice)
        }.font(.subheadline).padding(16).background(.white.opacity(0.06), in: .rect(cornerRadius: 22))
            .disabled(busy || publicationPending)
    }

    private var progressPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { ProgressView().tint(.white); Text(stage).font(.subheadline.weight(.semibold)); Spacer()
                if let progress { Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit() }
            }
            if let progress { ProgressView(value: progress) }
            Text("Keep Whisper open while posting. Your editable clips stay on this device.").font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(.white.opacity(0.06), in: .rect(cornerRadius: 18))
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { work = Task { await saveDraftAndClose() } } label: {
                Label("Drafts", systemImage: "tray.and.arrow.down").frame(height: 50).padding(.horizontal, 18)
                    .background(.white.opacity(0.08), in: Capsule())
            }.accessibilityLabel("Save draft")
            Button { work = Task { await publish() } } label: {
                Text(busy ? stage : (publicationPending ? "Check publication" : "Post wave"))
                    .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).frame(height: 50)
                    .background(WhisperBrandGradient.diagonal, in: Capsule())
            }.accessibilityIdentifier("wave.publish")
        }.buttonStyle(.plain).foregroundStyle(.white).disabled(!canAct)
            .padding(.horizontal, 16).padding(.vertical, 12).background(.black)
    }

    private func openEditor(_ tool: String) { guard canAct, !publicationPending else { return }; editorStart = tool; presentClips = true }

    private func loadInitial() async {
        guard !started else { return }; started = true
        let token = generation
        music = initialMusic; filter = initialFilter; effect = initialAREffect.availableEffect
        if !initialClips.isEmpty { clips = initialClips }
        else if !initialClipURLs.isEmpty || initialVideoURL != nil {
            let urls = initialClipURLs.isEmpty ? [initialVideoURL].compactMap { $0 } : initialClipURLs
            var loaded: [WhisperWaveClip] = []
            for url in urls {
                let length = await WhisperWaveClipStudio.duration(of: url)
                guard generation == token, !Task.isCancelled else { return }
                guard length > 0.2 else { errorMessage = "One selected clip couldn't be opened. Choose it again."; return }
                loaded.append(WhisperWaveClip(url: url, duration: length))
            }
            clips = loaded
        } else {
            do {
                if let draft = try await WhisperWaveEditDraftStore.shared.load(owner: AccountStorage.currentUserID) {
                    guard generation == token, !Task.isCancelled else { return }
                    clips = draft.clips; caption = draft.caption; music = draft.music; musicVolume = draft.volume
                    muteOriginal = draft.muted; texts = draft.texts
                    filter = SnapFilter.all.first { $0.name == draft.filterName } ?? .none
                    effect = (WhisperAREffect(rawValue: draft.effect) ?? .none).availableEffect
                    adjustments = draft.adjustments ?? .init()
                    fx = draft.fx
                    captions = draft.captions
                    audience = draft.audience; ghost = draft.ghost; shareToFeed = draft.shareToFeed
                    allowComments = draft.allowComments ?? false; allowSaves = draft.allowSaves ?? false
                    publicationID = draft.publicationID; publicationPending = draft.publicationPending ?? false
                    coverTime = draft.coverTime ?? 0.1
                } else if let legacy = WhisperReelDraftStore.shared.load() {
                    let url = try await Task.detached { () throws -> URL in
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wave-legacy-\(UUID().uuidString).\(legacy.ext)")
                        try legacy.videoData.write(to: url); return url
                    }.value
                    let length = await WhisperWaveClipStudio.duration(of: url)
                    guard generation == token, !Task.isCancelled else { return }
                    clips = [WhisperWaveClip(url: url, duration: length)]; caption = legacy.caption; restoredLegacy = true
                }
            } catch { errorMessage = "Your saved draft couldn't be opened. It has not been deleted."; return }
        }
        guard generation == token, !Task.isCancelled else { return }
        if clips.isEmpty { presentPicker = true }
        else { if !publicationPending { openEditor("clips") } else { refreshCover() } }
    }

    private func importVideo(_ item: PhotosPickerItem) async {
        guard !busy, !publicationPending else { return }
        busy = true; stage = "Opening video"; progress = nil
        let token = generation
        defer { busy = false; pickerItem = nil }
        do {
            guard let movie = try await item.loadTransferable(type: WhisperPickedMovie.self) else { throw CocoaError(.fileReadCorruptFile) }
            let length = await WhisperWaveClipStudio.duration(of: movie.url)
            guard token == generation, !Task.isCancelled else { return }
            guard length > 0.2 else { throw CocoaError(.fileReadCorruptFile) }
            clips = [WhisperWaveClip(url: movie.url, duration: length)]; texts = []; captions = nil; coverTime = 0.1; coverImage = nil
            muteOriginal = false; busy = false; refreshCover(); openEditor("clips")
        } catch { errorMessage = "Couldn't open this video. Please select it again." }
    }

    private func refreshCover() {
        guard !clips.isEmpty else { return }
        coverTime = min(coverTime, max(0, duration - 0.05))
        let snapshot = request
        let time = coverTime
        if snapshot == lastCoverRequest, time == lastCoverTime, coverImage != nil { return }
        coverWork?.cancel()
        let token = generation
        coverWork = Task {
            let image = await WhisperWaveCoverPicker.thumbnail(request: snapshot, time: time)
            guard !Task.isCancelled, token == generation, snapshot == request, time == coverTime else { return }
            lastCoverRequest = snapshot; lastCoverTime = time
            coverImage = image
        }
    }

    private func draft(pending: Bool) -> WhisperWaveEditDraft {
        WhisperWaveEditDraft(owner: AccountStorage.currentUserID, clips: clips, caption: caption, music: music, volume: musicVolume, muted: muteOriginal, texts: texts, filterName: filter.name, effect: effect.rawValue, audience: audience, ghost: ghost, shareToFeed: shareToFeed, publicationID: publicationID, publicationPending: pending, adjustments: adjustments, allowComments: allowComments, allowSaves: allowSaves, coverTime: coverTime, fx: fx, captions: captions)
    }

    private func persistDraft(pending: Bool) async throws {
        let token = generation
        let before = request
        let saved = try await WhisperWaveEditDraftStore.shared.save(draft(pending: pending))
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        clips = saved.clips
        captions = saved.captions
        if cachedRequest == before { cachedRequest = request }
    }

    private func requestExit() {
        guard !busy else { return }
        if !clips.isEmpty || !caption.isEmpty { confirmExit = true } else { closeComposer() }
    }

    @State private var backTransition: WhisperBackAction = WhisperBackAction()

    private func closeComposer() {
        backTransition.perform { coverWork?.cancel(); generation = UUID(); dismiss() }
    }

    private func saveDraftAndClose() async {
        guard canAct else { return }
        busy = true; stage = "Saving draft"; progress = nil
        defer { busy = false }
        do { try await persistDraft(pending: publicationPending); Haptics.success(); onPosted?(); closeComposer() }
        catch is CancellationError { }
        catch { errorMessage = "Couldn't save your draft. Free some device storage and retry; your edit remains open." }
    }

    private func render() async throws -> URL {
        let snapshot = request
        if cachedRequest == snapshot, let cachedRender, FileManager.default.fileExists(atPath: cachedRender.path) { return cachedRender }
        if let cachedRender { try? FileManager.default.removeItem(at: cachedRender) }
        cachedRender = nil; cachedRequest = nil; uploadedVideo = nil; uploadPath = nil
        let token = generation
        let url = try await WhisperWaveEditRenderer.render(clips: clips, music: music, volume: musicVolume, muted: muteOriginal, texts: texts, filter: filter, effect: effect, adjustments: adjustments, fx: fx, captions: captions) { label, value in
            await MainActor.run { if token == generation { stage = label; progress = value } }
        }
        guard token == generation, !Task.isCancelled else { try? FileManager.default.removeItem(at: url); throw CancellationError() }
        cachedRender = url; cachedRequest = snapshot
        return url
    }

    private func publish() async {
        guard canAct else { return }
        let owner = AccountStorage.currentUserID
        let token = generation
        busy = true; progress = nil
        defer { busy = false }
        do {
            if publicationPending {
                stage = "Checking publication"
                if try await backend.reelPublication(postID: publicationID, owner: owner) != nil { await complete(owner: owner, token: token); return }
                try await WhisperWaveEditDraftStore.shared.setPublicationPending(owner: owner, publicationID: publicationID, pending: false)
                guard token == generation else { return }
                publicationPending = false
            }
            guard audience == "everyone", allowComments, allowSaves else {
                errorMessage = "These privacy restrictions aren't supported yet. Save a private device draft, or review the settings before publishing."; return
            }
            guard WhisperWaveUploadPolicy.accepts(duration: duration) else {
                errorMessage = "Waves can be up to 6 minutes after trimming and speed changes. Open Clips to adjust the timeline; nothing has been removed."; return
            }
            guard caption.count <= 2200 else { errorMessage = "Shorten your caption to 2,200 characters before posting."; return }
            let url = try await render()
            stage = "Uploading video"; progress = 0
            if uploadedVideo == nil {
                let path = uploadPath ?? "\(owner.lowercased())/wave-\(UUID().uuidString)/video.mp4"
                uploadPath = path
                uploadedVideo = try await backend.uploadReel(file: url, path: path, uploader: uploader) { value in
                    if token == generation { progress = value }
                }
            }
            guard token == generation, !Task.isCancelled, let uploadedVideo else { throw CancellationError() }
            stage = "Uploading cover"; progress = nil
            guard let image = await WhisperWaveClipStudio.thumbnail(url: url, at: min(coverTime, max(0, duration - 0.04))), let jpeg = image.jpegData(compressionQuality: 0.85) else {
                errorMessage = "Couldn't read the selected cover. Choose another frame and retry; the video upload is retained."; return
            }
            let covers = await backend.uploadMedia(datas: [jpeg], postID: "wave-cover-\(UUID().uuidString)")
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
            guard let cover = covers.first else { errorMessage = "The cover didn't finish uploading. Check your connection and retry; the video won't be rendered again."; return }
            var finalCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            if let meta = WhisperWaveSound.metaLine(music: music, cover: cover, feed: shareToFeed) { finalCaption = "\(meta)\n\(finalCaption)" }
            stage = "Publishing wave"
            let row = await backend.createPost(kind: "reel", caption: finalCaption, symbol: "play.rectangle.fill", accentHex: nil, mediaCount: 1, isGhost: ghost, isReel: true, postID: publicationID, uploadedVideoURL: uploadedVideo, attempt: attempt, beforeInsert: {
                try await persistDraft(pending: true)
                guard token == generation else { throw CancellationError() }
                publicationPending = true
            })
            guard token == generation else { return }
            if let row {
                if ghost { WhisperGhostService.shared.mark(row.id) }
                if saveToDevice { _ = await WhisperWaveStudio.saveToPhotos(url) }
                await complete(owner: owner, token: token)
            } else {
                if !attempt.needsReconciliation, publicationPending {
                    try await WhisperWaveEditDraftStore.shared.setPublicationPending(owner: owner, publicationID: publicationID, pending: false)
                    publicationPending = false
                }
                errorMessage = attempt.message ?? backend.lastError ?? "Publication couldn't be confirmed. Check this wave before trying again; your edit is retained."
                Haptics.error()
            }
        } catch is CancellationError { }
        catch {
            guard token == generation else { return }
            errorMessage = (error as NSError).domain == "WaveUpload" || (error as NSError).domain == "WhisperWaveEdit" ? error.localizedDescription : "\(stage) stopped. Check your connection and available device storage, then retry. Your edits remain here."
            Haptics.error()
        }
    }

    private func complete(owner: String, token: UUID) async {
        guard token == generation else { return }
        try? await WhisperWaveEditDraftStore.shared.clear(owner: owner, publicationID: publicationID)
        guard token == generation else { return }
        if restoredLegacy { WhisperReelDraftStore.shared.clear() }
        WhisperFeedback.published()
        onPosted?()
        closeComposer()
    }

    private func suggestCaption() async {
        let token = generation
        let original = caption
        let suggestion = await WhisperEmberService.shared.captionForReel(description: original.isEmpty ? "a short vertical video" : original)
        guard token == generation, caption == original, !busy, !suggestion.isEmpty else { return }
        caption = suggestion
    }
}
