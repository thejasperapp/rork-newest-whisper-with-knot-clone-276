import SwiftUI
import AVFoundation
import PhotosUI
import UIKit
import CoreImage
import Photos

// MARK: - Create flow (recorder → composer)

/// The wave creation flow: the TikTok-style camera first, then the edit /
/// post composer with the recorded (or uploaded) clip already loaded.
struct WhisperWaveCreateFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var handoff: WaveHandoff?
    @State private var showDraft: Bool = false
    @State private var hasSavedEdit: Bool = false
    @State private var closingFlow: Bool = false
    /// "Use this sound" from a sound page — the recorder opens with it loaded.
    var initialMusic: WhisperStoryMusic? = nil
    var onSelectCreationMode: ((WhisperCaptureMode) -> Void)? = nil
    var sharedCamera: SnapCameraSession? = nil
    var previewBridge: WhisperCapturePreviewBridge? = nil
    var isActive: Bool = true
    var onCloseFlow: (() -> Void)? = nil
    private func closeFlow() { if let onCloseFlow { onCloseFlow() } else { dismiss() } }

    var body: some View {
        WhisperWaveRecorderView(
            initialMusic: initialMusic,
            flowClosing: closingFlow,
            onReady: { url, music, filter, effect in
                handoff = WaveHandoff(url: url, clipURLs: [], music: music, filter: filter, effect: effect)
            },
            onReadyClips: { url, clips, music, filter, effect in
                handoff = WaveHandoff(url: url, clipURLs: clips.map(\.url), clips: clips, music: music, filter: filter, effect: effect)
            },
            onClose: closeFlow,
            onSelectCreationMode: onSelectCreationMode,
            sharedCamera: sharedCamera, previewBridge: previewBridge,
            isActive: isActive && handoff == nil && !showDraft
        )
        .onChange(of: handoff != nil || showDraft, initial: true) { _, covered in previewBridge?.suspended = covered }
        .overlay(alignment: .bottomTrailing) {
            if hasSavedEdit && isActive {
                Button { showDraft = true } label: {
                    Label("Drafts", systemImage: "tray.full").font(.subheadline.weight(.semibold))
                        .padding(12).background(.ultraThinMaterial, in: Capsule())
                }.padding(.trailing, 16).padding(.bottom, 100)
            }
        }
        .task(id: "\(handoff?.id.uuidString ?? "camera")-\(showDraft)") {
            hasSavedEdit = (try? await WhisperWaveEditDraftStore.shared.load(owner: AccountStorage.currentUserID)) != nil || WhisperReelDraftStore.shared.hasDraft
        }
        .fullScreenCover(isPresented: $showDraft, onDismiss: { if closingFlow { closeFlow() } }) {
            WhisperReelComposerView(onPosted: { closingFlow = true })
        }
        .fullScreenCover(item: $handoff, onDismiss: { if closingFlow { closeFlow() } }) { h in
            WhisperReelComposerView(
                initialVideoURL: h.url,
                initialClipURLs: h.clipURLs,
                initialClips: h.clips,
                initialMusic: h.music,
                initialFilter: h.filter,
                initialAREffect: h.effect,
                onPosted: { closingFlow = true }
            )
        }
    }
}

struct WaveHandoff: Identifiable {
    let id = UUID()
    let url: URL
    /// The separate gallery clips behind `url` when several were picked — the
    /// composer's Clips editor opens on them so each stays trimmable.
    var clipURLs: [URL] = []
    var clips: [WhisperWaveClip] = []
    let music: WhisperStoryMusic?
    let filter: SnapFilter
    /// The AR effect picked on the viewfinder — baked at publish.
    let effect: WhisperAREffect
}

/// One recorded take. `speed` is the playback multiplier chosen while it
/// was shot (0.5× slow-mo … 3× fast); `seconds` is the raw recorded length.
struct WaveSegment: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let seconds: Double
    let speed: Double
    var face: WhisperWaveFaceSetting? = nil
    var background: WhisperWaveBackground? = nil
    var cameraEffect: WhisperWaveCameraEffect? = nil
    /// Effective length after the speed is applied.
    var effectiveSeconds: Double { seconds / max(0.1, speed) }
}

// MARK: - Recorder

/// The wave camera — Instagram's Reels camera grammar: ✕ top-left, the
/// flash · speed · timer cluster top-center in dark circles, the gear
/// top-right, an "Add audio" pill under it, a LABELED left rail (Audio ·
/// Effects · Length · Teleprompter · Hands-free), and a white shutter with the
/// gallery tile to its left and the flip orb to its right. No bottom mode
/// bar. Press-and-hold the shutter to record a take (release to stop), or
/// flip HANDS-FREE and tap to start/stop. Takes stack into one wave — the
/// thin progress bar along the top fills per allotted time with a tick per
/// take — with delete-last, 15s · 60s · 3m lengths, 3s / 10s countdown,
/// 0.5× · 1× · 2× · 3× speed per take, swipe-able Whisper filters, and the
/// real Whisper audio selector (saved · trending · original sounds · songs).
struct WhisperWaveRecorderView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var countdownTask: Task<Void, Never>?
    var initialMusic: WhisperStoryMusic? = nil
    var flowClosing: Bool = false
    let onReady: (URL, WhisperStoryMusic?, SnapFilter, WhisperAREffect) -> Void
    /// Fires instead of `onReady` when the gallery pick was SEVERAL videos:
    /// the straight cut of all of them, plus the separate clip files.
    var onReadyClips: ((URL, [WhisperWaveClip], WhisperStoryMusic?, SnapFilter, WhisperAREffect) -> Void)? = nil
    let onClose: () -> Void
    var onSelectCreationMode: ((WhisperCaptureMode) -> Void)? = nil
    var sharedCamera: SnapCameraSession? = nil
    var previewBridge: WhisperCapturePreviewBridge? = nil
    var isActive: Bool = true
    @State private var backgroundImporting: Bool = false
    @State private var importOperation: UUID = UUID()
    @State private var uploadTask: Task<Void, Never>?

    @State private var cameraHolder: SnapCameraHolder = .init()
    private var camera: SnapCameraSession { sharedCamera ?? cameraHolder.session }
    @State private var segments: [WaveSegment] = []
    @State private var recordingStartedAt: Date?
    @State private var finishing: Bool = false
    @State private var pressActive: Bool = false
    @State private var shutterHoldTask: Task<Void, Never>?
    @State private var shutterSwiping: Bool = false
    @State private var cameraVisible: Bool = false
    @State private var holdZoom: CGFloat = 1
    /// Plays the picked sound WHILE a take records (TikTok's lip-sync
    /// grammar) — resumes from where the previous take left off so the
    /// stitched wave lines up with the mix baked at publish.
    @State private var soundPlayer: AVPlayer?

    @State private var maxSeconds: Double = 60
    @State private var speed: Double = 1
    @State private var handsFree: Bool = false
    @State private var flashOn: Bool = false
    @State private var filterIndex: Int = 0
    /// The live AR effect (background swap or face accessory) — previewed on
    /// the viewfinder through Vision, baked into the wave at publish.
    @State private var arEffect: WhisperAREffect = .none
    @State private var faceSetting: WhisperWaveFaceSetting = .init(amount: 0.35)
    @State private var backgroundSetting: WhisperWaveBackground?
    @State private var preparedPhoto: CIImage?
    @State private var preparedVideo: WhisperWaveLiveVideoBackground?
    @State private var preparedBackgroundURL: URL?
    @State private var cameraIssue: String? = "Starting camera…"
    @State private var showGreenScreen: Bool = false
    @State private var takeID: UUID?
    @State private var preparationID: UUID = UUID()
    @State private var cameraEffect: WhisperWaveCameraEffect = .none
    @State private var localThumbnails: WhisperWaveEffectThumbnails = .init()
    private var effectThumbnails: WhisperWaveEffectThumbnails { previewBridge?.thumbnails ?? localThumbnails }
    @State private var catalogID: UUID?
    @State private var carouselActive: Bool = false
    @State private var savedEffects: Set<String> = []
    @State private var showRetouch: Bool = false
    @State private var timerChoice: Int = 0           // 0 off · 3 · 10
    @State private var countdown: Int? = nil
    @State private var music: WhisperStoryMusic?
    @State private var pendingDeleteLast: Bool = false
    @State private var deleteResetTask: Task<Void, Never>?

    @State private var showSettings: Bool = false
    @State private var showMusic: Bool = false
    @State private var showFilters: Bool = false
    @State private var showPicker: Bool = false
    @State private var showTeleprompter: Bool = false
    /// The teleprompter script — scrolls over the viewfinder while you record.
    @State private var teleprompterText: String = ""
    @State private var teleprompterSpeed: Double = 1
    @State private var gridOn: Bool = false
    @State private var playSoundDuringTakes: Bool = true
    /// Gallery picks — up to 10 videos at once (TikTok's multi-select upload);
    /// several clips are cut together and stay editable in the composer.
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var exporting: Bool = false
    @State private var exportError: String?
    @State private var backTransition: WhisperBackAction = WhisperBackAction()
    @State private var confirmExit: Bool = false

    private let filters: [SnapFilter] = SnapFilter.all
    private var currentFilter: SnapFilter { filters[filterIndex] }
    private var isRecording: Bool { recordingStartedAt != nil }

    private var recordedSeconds: Double { segments.reduce(0) { $0 + $1.effectiveSeconds } }

    var body: some View {
        recordingPresentation
            .whisperEdgeBack(isEnabled: isActive && canExit && !showFilters && !showGreenScreen, requiresDecision: !segments.isEmpty, controller: backTransition) { requestExit() }
            .confirmationDialog("Keep your recorded takes?", isPresented: $confirmExit, titleVisibility: .visible) {
                Button("Save draft") { Task { await saveRecordedDraft() } }
                Button("Discard", role: .destructive) { discardRecordedTakes() }
                Button("Keep recording", role: .cancel) {}
            } message: { Text("Save a private draft to keep your takes and effects before leaving.") }
            .interactiveDismissDisabled(!canExit || !segments.isEmpty)
    }

    private var canExit: Bool { !backgroundImporting && !isRecording && !finishing && !exporting && countdown == nil && !flowClosing }
    private var modeLocked: Bool {
        !canExit || !segments.isEmpty || pressActive || showPicker || showFilters || showSettings || showMusic || showRetouch || showTeleprompter
    }
    private func requestExit() {
        guard canExit else { return }
        Haptics.tap()
        if segments.isEmpty { backTransition.perform { onClose() } } else { confirmExit = true }
    }
    private func discardRecordedTakes() {
        guard canExit else { return }
        let urls = segments.map(\.url)
        backTransition.perform {
            segments = []; cameraVisible = false; onClose()
            Task.detached(priority: .utility) { for url in urls { try? FileManager.default.removeItem(at: url) } }
        }
    }
    private func saveRecordedDraft() async {
        guard canExit, !segments.isEmpty else { return }
        let generation = AccountStorage.generation
        let owner = AccountStorage.currentUserID
        exporting = true
        defer { exporting = false }
        let clips = segments.map { take in
            var clip = WhisperWaveClip(url: take.url, duration: take.seconds, speed: take.speed)
            clip.fillsFrame = true; clip.face = take.face; clip.background = take.background; clip.cameraEffect = take.cameraEffect
            return clip
        }
        let draft = WhisperWaveEditDraft(owner: owner, clips: clips, caption: "", music: music, volume: 0.85, muted: false, texts: [], filterName: currentFilter.name, effect: WhisperAREffect.none.rawValue, audience: "everyone", ghost: false, shareToFeed: true, publicationID: UUID().uuidString, allowComments: true, allowSaves: true)
        do {
            _ = try await WhisperWaveEditDraftStore.shared.save(draft)
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            Haptics.success(); exporting = false; backTransition.perform { cameraVisible = false; onClose() }
        } catch { exportError = "Couldn't save your draft. Your takes are still here. Free some storage and try again." }
    }

    private var captureContent: AnyView {
        AnyView(GeometryReader { viewport in
            let layout = WhisperStoryEditorLayout(viewport: viewport.size)
            ZStack(alignment: .topLeading) {
                if sharedCamera == nil { Color.black.ignoresSafeArea() }
                ZStack {
            if camera.isDenied {
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill").font(.largeTitle)
                    Text(camera.isRestricted ? "Camera restricted" : "Allow camera access").font(.headline)
                    if !camera.isRestricted {
                        Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                            .frame(minHeight: 44)
                    }
                }.foregroundStyle(.white)
            } else if camera.isAvailable {
                if sharedCamera == nil { cameraStage }
                else { Color.clear.contentShape(.rect).gesture(filterSwipe, including: showFilters || showGreenScreen || !isActive ? .none : .all) }
            } else {
                unavailable
            }

            if showGreenScreen, backgroundSetting != nil, !isRecording, !finishing, !backgroundImporting {
                WhisperGreenScreenPositionOverlay(background: $backgroundSetting)
            }
            chrome.opacity(showFilters ? 0 : 1).allowsHitTesting(!showFilters)
            WhisperCameraStatusView(interruption: camera.interruptionMessage, silent: WhisperCameraCallMonitor.shared.callOwnsAudio || (isRecording && camera.recordingWithoutAudio))
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 78)
            if showFilters {
                GeometryReader { geometry in
                    WhisperWaveEffectsBrowser(selected: cameraEffect, thumbnails: effectThumbnails, saved: $savedEffects, onPick: { effect in
                        cameraEffect = effect; carouselActive = true
                        withAnimation(.snappy) { showFilters = false }
                    }, onClose: { withAnimation(.snappy) { showFilters = false } })
                    .frame(height: geometry.size.height * 0.6)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }.ignoresSafeArea(edges: .bottom)
            }

            if let countdown {
                countdownOverlay(countdown)
            }

            if exporting {
                exportingOverlay
            }
                }
                .frame(width: layout.stage.width, height: layout.stage.height)
                .clipShape(.rect(cornerRadius: 24, style: .continuous))
                .position(x: layout.stage.midX, y: layout.stage.midY)
                VStack(spacing: -8) {
                    bottomRow.frame(height: 44).disabled(!canExit || pressActive)
                    if sharedCamera == nil, let onSelectCreationMode {
                        WhisperCaptureModeStrip(selected: .waves, disabled: !canExit || !segments.isEmpty || pressActive) { next in
                            guard canExit, segments.isEmpty, !pressActive else { return }
                            cameraVisible = false
                            if sharedCamera == nil { camera.stop() }
                            onSelectCreationMode(next)
                        }
                    }
                }.padding(.horizontal, 12)
                    .frame(width: layout.footer.width, height: layout.footer.height)
                    .position(x: layout.footer.midX, y: layout.footer.midY)
                    .opacity(isRecording || showFilters ? 0 : 1).allowsHitTesting(!isRecording && !showFilters)
            }
        })
    }

    private var cameraStage: some View {
        GeometryReader { geometry in
            let height = showFilters ? min(260, geometry.size.height * 0.32) : geometry.size.height
            WhisperWaveLivePreview(camera: camera, configuration: .init(face: faceSetting, background: backgroundSetting, filter: currentFilter, speed: speed, takeID: takeID, cameraEffect: cameraEffect, catalogID: catalogID), photo: preparedPhoto, video: preparedVideo, preparedURL: preparedBackgroundURL, onStatus: { if cameraVisible { cameraIssue = $0 } }, onCatalogFrame: { if cameraVisible { effectThumbnails.prepare($0) } })
                .frame(width: showFilters ? height * 9 / 16 : geometry.size.width, height: height)
                .clipShape(.rect(cornerRadius: showFilters ? 16 : 24))
                .position(x: geometry.size.width / 2, y: showFilters ? geometry.size.height * 0.2 : geometry.size.height / 2)
                .animation(.snappy(duration: 0.3), value: showFilters)
                .contentShape(.rect)
                .gesture(filterSwipe, including: showFilters || showGreenScreen ? .none : .all)
        }
    }

    private var cameraLifecycle: AnyView {
        AnyView(captureContent
        .statusBarHidden(false)
        .environment(\.colorScheme, .dark)
        .task {
            guard !flowClosing else { return }
            cameraVisible = isActive
            if isActive && sharedCamera == nil { camera.configure() }
            if isActive { camera.setTorch(flashOn); if let previewBridge { cameraIssue = previewBridge.issue } }
            publishPreview()
            if let data = AccountStorage.data(forKey: "whisper.camera.saved-effects.v1"), let ids = try? JSONDecoder().decode(Set<String>.self, from: data) { savedEffects = ids }
            if music == nil, let initialMusic { music = initialMusic }
        }
        .task(id: "\(backgroundSetting?.url.absoluteString ?? "none")-\(preparationID)") { await prepareBackground(); publishPreview() }
        .onChange(of: previewConfiguration) { _, _ in publishPreview() }
        .onChange(of: modeLocked, initial: true) { _, locked in previewBridge?.modeLocked = locked }
        .onChange(of: isRecording || showFilters, initial: true) { _, hidden in previewBridge?.hidesModeStrip = hidden }
        .onChange(of: isActive) { _, active in
            cameraVisible = active
            if active { publishPreview(); camera.setTorch(flashOn); if let previewBridge { cameraIssue = previewBridge.issue } }
            else {
                countdownTask?.cancel(); countdownTask = nil; countdown = nil
                shutterHoldTask?.cancel(); pressActive = false; soundPlayer?.pause()
            }
        }
        .onChange(of: previewBridge?.issue) { _, issue in if isActive { cameraIssue = issue } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            cameraVisible = false; effectThumbnails.clear(); shutterHoldTask?.cancel()
            importOperation = UUID(); uploadTask?.cancel(); exporting = false; pickerItems = []
            if sharedCamera == nil { camera.setWaveFrameHandler(nil); camera.stop() }
            soundPlayer?.pause()
            preparationID = UUID(); onClose()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive && camera.isRequestingMicrophonePermission { return }
            if phase == .active, isActive, cameraVisible, !flowClosing, !exporting {
                if sharedCamera == nil { camera.configure() }
            }
            else if phase != .active {
                countdownTask?.cancel(); countdown = nil
                shutterHoldTask?.cancel(); pressActive = false
                if isRecording { stopTake() }
                if sharedCamera == nil { camera.stop() }
                soundPlayer?.pause()
            }
        }
        .onChange(of: camera.isRequestingMicrophonePermission) { _, requesting in
            if !requesting, isRecording { recordingStartedAt = Date() }
        }
        .onChange(of: camera.interruptionMessage) { _, message in
            guard message != nil else { return }
            countdownTask?.cancel(); countdown = nil
            if isRecording { stopTake() }
            soundPlayer?.pause()
        }
        .onDisappear {
            countdownTask?.cancel(); countdown = nil
            cameraVisible = false; shutterHoldTask?.cancel(); pressActive = false
            importOperation = UUID(); uploadTask?.cancel(); exporting = false
            effectThumbnails.clear()
            if sharedCamera == nil {
                camera.setWaveFrameHandler(nil)
                camera.setAREffect(.none)
                camera.stop()
            }
            soundPlayer?.pause()
            soundPlayer = nil
        }
        .onChange(of: cameraEffect) { old, effect in
            if effect == .cloneWall || old == .cloneWall { effectThumbnails.clear(); catalogID = UUID() }
            faceSetting.select(effect.faceKind)
            filterIndex = 0
        }
        .onChange(of: savedEffects) { _, ids in
            if let data = try? JSONEncoder().encode(ids) { AccountStorage.set(data, forKey: "whisper.camera.saved-effects.v1") }
        }
        .onChange(of: showFilters) { _, shown in
            if shown { catalogID = UUID() }
            if isActive { previewBridge?.browsing = shown }
        }
        .onChange(of: backgroundSetting) { _, _ in effectThumbnails.clear(); catalogID = UUID() }
        .onChange(of: arEffect) { _, effect in
            if effect == .none { camera.setAREffect(.none) }
        }
        )
    }

    private var previewConfiguration: WhisperWaveLiveFrameRenderer.Configuration {
        .init(face: faceSetting, background: backgroundSetting, filter: currentFilter, speed: speed, takeID: takeID, cameraEffect: cameraEffect, catalogID: catalogID)
    }

    private func publishPreview() {
        guard isActive, let previewBridge else { return }
        previewBridge.photo = preparedPhoto; previewBridge.video = preparedVideo
        previewBridge.preparedURL = preparedBackgroundURL
        previewBridge.configuration = previewConfiguration
        previewBridge.browsing = showFilters
    }

    private var recordingPresentation: AnyView {
        AnyView(cameraLifecycle
        .sheet(isPresented: $showSettings) {
            settingsSheet
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRetouch) {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text("Touch up").font(.headline); Spacer(); Button("Done") { showRetouch = false }.frame(minHeight: 44) }
                Text("Optional, on-device adjustments for your next take.").font(.subheadline).foregroundStyle(.secondary)
                Text("Skin smoothing").font(.subheadline.weight(.medium))
                Slider(value: $faceSetting.smoothing, in: 0...1).accessibilityLabel("Skin smoothing")
                if faceSetting.kind != .none {
                    Text("\(faceSetting.kind.title) amount").font(.subheadline.weight(.medium))
                    Slider(value: $faceSetting.amount, in: 0...1).accessibilityLabel("Face effect amount")
                }
                Button("Reset touch up") { faceSetting.smoothing = 0; faceSetting.amount = faceSetting.kind.defaultAmount }.frame(minHeight: 44)
            }.padding(20)
            .presentationDetents([.medium]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTeleprompter) {
            teleprompterSheet
                .presentationDetents([.fraction(0.6), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMusic) {
            WhisperAudioPickerSheet(
                current: music,
                onPick: { picked in
                    music = picked
                    showMusic = false
                },
                onRemove: { music = nil }
            )
            .presentationDetents([.fraction(0.75), .large])
            .presentationDragIndicator(.visible)
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItems, maxSelectionCount: 10, matching: .videos)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty, canExit, !pressActive else { return }
            uploadTask = Task { await handleUpload(items) }
        }
        .alert("Couldn't build your wave", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        })
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            if !segments.isEmpty || isRecording {
                progressBar
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .transition(.opacity)
            } else {
                Color.clear.frame(height: 12)
            }
            topRow
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .opacity(isRecording ? 0 : 1)
            if !isRecording {
                audioPill
                    .padding(.top, 14)
                    .transition(.opacity)
            }
            Spacer()
            if let cameraIssue {
                HStack(spacing: 10) {
                    Text(cameraIssue).font(.caption).multilineTextAlignment(.center)
                    if !isRecording && backgroundSetting != nil {
                        Button("Retry") { preparationID = UUID() }.font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(.white).padding(12)
                .background(.black.opacity(0.75), in: .rect(cornerRadius: 14))
                .padding(.horizontal, 16).padding(.bottom, 10)
            }
            if showGreenScreen && !isRecording {
                WhisperGreenScreenMediaRail(background: $backgroundSetting, isImporting: $backgroundImporting, locked: finishing || exporting || countdown != nil)
                    .padding(.bottom, 8)
                Button("Done") { showGreenScreen = false }.font(.footnote.weight(.semibold))
                    .frame(minHeight: 44).foregroundStyle(.white).disabled(backgroundImporting)
            }
            WhisperStoryCaptureRail(selected: $cameraEffect, thumbnails: effectThumbnails,
                effects: WhisperWaveCameraEffect.available, expanded: carouselActive && !showGreenScreen && !isRecording,
                locked: finishing || exporting || countdown != nil || isRecording,
                onScrub: { shutterSwiping = true; shutterHoldTask?.cancel() }) { shutter }
            if isRecording {
                recordingTimer
                    .padding(.bottom, 16)
            }
            Color.clear.frame(height: 10)
        }
        .overlay(alignment: .trailing) {
            if !isRecording && !showGreenScreen && !showFilters && !carouselActive {
                leftRail
                    .padding(.trailing, 14)
                    .offset(y: -24)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if !teleprompterText.isEmpty {
                teleprompterPanel
                    .padding(.top, isRecording ? 26 : 122)
                    .padding(.horizontal, 22)
                    .transition(.opacity)
            }
        }
        .overlay {
            if gridOn {
                gridOverlay
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
        }
        .animation(.easeOut(duration: 0.2), value: isRecording)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showFilters)
        .animation(.easeOut(duration: 0.2), value: segments.count)
    }

    /// Rule-of-thirds guide (from the camera settings).
    private var gridOverlay: some View {
        GeometryReader { geo in
            Path { p in
                for i in 1...2 {
                    let x = geo.size.width * CGFloat(i) / 3
                    let y = geo.size.height * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: geo.size.height))
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.7)
        }
    }

    /// TikTok's top progress bar — the recorded takes as filled portions of
    /// the allotted length with a white tick between takes; the live take
    /// grows as you hold.
    private var progressBar: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isRecording)) { context in
            let live = recordingStartedAt.map { context.date.timeIntervalSince($0) / max(0.1, speed) } ?? 0
            GeometryReader { geo in
                let w = max(1, geo.size.width)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.28))
                    HStack(spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { i, seg in
                            let isLast = i == segments.count - 1
                            Rectangle()
                                .fill(isLast && pendingDeleteLast ? Color(red: 1.0, green: 0.23, blue: 0.27) : Color(red: 0.98, green: 0.30, blue: 0.42))
                                .frame(width: max(0, w * (seg.effectiveSeconds / maxSeconds)))
                            Rectangle().fill(.white).frame(width: 2)
                        }
                        if live > 0 {
                            Rectangle()
                                .fill(Color(red: 0.98, green: 0.30, blue: 0.42))
                                .frame(width: max(0, w * (live / maxSeconds)))
                        }
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 4)
            .onChange(of: live >= max(0, maxSeconds - recordedSeconds)) { _, hit in
                if hit && isRecording { stopTake() }
            }
        }
    }

    /// ✕ (or ‹ to discard takes) top-left · flash · speed · timer centered in
    /// dark circles · the gear top-right — Instagram's Reels camera top row.
    private var topRow: some View {
        ZStack {
            HStack(spacing: 10) {
                topCircle(icon: flashOn ? "bolt.fill" : "bolt.slash.fill", active: flashOn) {
                    flashOn.toggle()
                    camera.setTorch(flashOn)
                }
                .accessibilityLabel(flashOn ? "Flash on" : "Flash off")
                topCircle(text: speedLabel(speed), active: speed != 1) { cycleSpeed() }
                    .accessibilityLabel("Speed \(speedLabel(speed))")
                topCircle(icon: timerChoice == 0 ? "clock" : nil, text: timerChoice == 0 ? nil : "\(timerChoice)s", active: timerChoice != 0) { cycleTimer() }
                    .accessibilityLabel(timerChoice == 0 ? "Timer off" : "Timer \(timerChoice) seconds")
            }

            HStack {
                Button {
                    requestExit()
                } label: {
                    Image(systemName: segments.isEmpty ? "xmark" : "chevron.left")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(segments.isEmpty ? "Close" : "Back")
                .disabled(!canExit)

                Spacer()

                Button {
                    Haptics.tap()
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Camera settings")
            }
        }
    }

    /// One of the top-center controls: a 40pt dark translucent circle with a
    /// glyph or a short label ("1x", "3s"); pink when non-default.
    private func topCircle(icon: String? = nil, text: String? = nil, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            ZStack {
                Circle().fill(Color.black.opacity(0.38))
                if let text {
                    Text(text)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(active ? Color(red: 0.98, green: 0.30, blue: 0.42) : .white)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(active ? Color(red: 0.98, green: 0.30, blue: 0.42) : .white)
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    /// "♫ Add audio" — the dark pill under the top row; shows the picked sound
    /// with a clear button once one is attached.
    private var audioPill: some View {
        Button {
            Haptics.tap()
            showMusic = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .bold))
                Text(music.map { WhisperWaveSound.label($0) } ?? "Add audio")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if music != nil {
                    Button {
                        Haptics.tap()
                        music = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove audio")
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .frame(maxWidth: 240)
            .background(Color.black.opacity(0.42), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(music == nil ? "Add audio" : "Change audio")
    }

    /// Instagram's labeled left rail: Audio · Effects · Length · Teleprompter ·
    /// Hands-free — glyph left, 15pt label right.
    private var leftRail: some View {
        VStack(alignment: .trailing, spacing: 4) {
            railItem(icon: "music.note", label: "Audio", active: music != nil) { showMusic = true }
            railItem(icon: "sparkles", label: "Effects", active: cameraEffect != .none || showFilters) {
                withAnimation { showFilters.toggle() }
            }
            railItem(icon: "person.and.background.dotted", label: "Green Screen", active: backgroundSetting != nil) {
                showFilters = false; showGreenScreen = true
            }
            railItem(icon: "wand.and.stars", label: "Touch up", active: faceSetting.smoothing > 0) { showRetouch = true }
            railItem(badge: lengthLabel, label: "Length", active: maxSeconds != 60) { cycleLength() }
            railItem(icon: "text.alignleft", label: "Teleprompter", tag: teleprompterText.isEmpty ? "NEW" : nil, active: !teleprompterText.isEmpty) {
                showTeleprompter = true
            }
            railItem(icon: handsFree ? "hand.raised.fill" : "hand.raised", label: "Hands-free", active: handsFree) {
                handsFree.toggle()
            }
        }
    }

    private var lengthLabel: String {
        maxSeconds >= 120 ? "\(Int(maxSeconds / 60))m" : "\(Int(maxSeconds))"
    }

    /// The Effects rail label — the AR effect wins, then the look, then "Effects".
    private var effectsLabel: String {
        if cameraEffect != .none { return cameraEffect.name }
        if faceSetting.kind != .none { return faceSetting.kind.title }
        if currentFilter != .none { return currentFilter.name }
        return "Effects"
    }

    private func railItem(
        icon: String? = nil,
        badge: String? = nil,
        label: String,
        tag: String? = nil,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Text(label).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
                    .shadow(color: .black.opacity(0.55), radius: 3)
                ZStack {
                    if let badge {
                        Circle()
                            .strokeBorder(active ? Color(red: 0.98, green: 0.30, blue: 0.42) : .white, lineWidth: 2)
                            .frame(width: 30, height: 30)
                        Text(badge)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(active ? Color(red: 0.98, green: 0.30, blue: 0.42) : .white)
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 25, weight: .regular))
                            .foregroundStyle(active ? Color(red: 0.98, green: 0.30, blue: 0.42) : .white)
                    }
                }
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.55), radius: 4)

            }
            .frame(height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The Effects tray — two rows: the AR EFFECTS (background swaps + face
    /// accessories, Vision-driven) on top, Whisper's color LOOKS beneath.
    private var selectedEffectPill: some View {
        HStack(spacing: 0) {
            Button {
                if savedEffects.contains(cameraEffect.id) { savedEffects.remove(cameraEffect.id) }
                else { savedEffects.insert(cameraEffect.id) }
                Haptics.tap()
            } label: {
                Image(systemName: savedEffects.contains(cameraEffect.id) ? "bookmark.fill" : "bookmark").frame(width: 44, height: 44)
            }.accessibilityLabel(savedEffects.contains(cameraEffect.id) ? "Unsave effect" : "Save effect")
            Button { showFilters = true } label: {
                Text(cameraEffect.name).font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: .infinity, minHeight: 44)
            }.accessibilityLabel("Browse effects, \(cameraEffect.name) selected")
            Button { carouselActive = false; showFilters = false } label: {
                Image(systemName: "xmark").font(.caption).frame(width: 44, height: 44)
            }.accessibilityLabel("Close effects, keep selected effect")
        }.foregroundStyle(.white).background(.black.opacity(0.5), in: Capsule())
    }

    /// AR effects — glyph tiles; one active at a time, tap again to clear.
    private var arEffectsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AR EFFECTS")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.7))
                .shadow(color: .black.opacity(0.5), radius: 2)
                .padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(WhisperAREffect.available) { effect in
                        Button {
                            Haptics.tap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                arEffect = (arEffect == effect || effect == .none) ? .none : effect
                            }
                        } label: {
                            VStack(spacing: 5) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: effect.tint, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 50, height: 50)
                                    Text(effect.glyph)
                                        .font(.system(size: effect == .none ? 16 : 24, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .overlay {
                                    Circle().strokeBorder(.white, lineWidth: arEffect == effect ? 3 : 0)
                                }
                                .scaleEffect(arEffect == effect ? 1.08 : 1)
                                Text(effect.name)
                                    .font(.system(size: 10.5, weight: arEffect == effect ? .heavy : .semibold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.55), radius: 3)
                                    .lineLimit(1)
                            }
                            .frame(width: 62)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(effect.name) effect")
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    /// Whisper's filter looks as swatch circles with names.
    private var looksRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Array(filters.enumerated()), id: \.offset) { i, f in
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { filterIndex = i }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: f.swatch, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 56, height: 56)
                                if f == .none {
                                    Image(systemName: "circle.slash")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                            }
                            .overlay {
                                Circle().strokeBorder(.white, lineWidth: filterIndex == i ? 3 : 0)
                            }
                            .scaleEffect(filterIndex == i ? 1.08 : 1)
                            Text(f.name)
                                .font(.system(size: 11, weight: filterIndex == i ? .heavy : .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.55), radius: 3)
                                .lineLimit(1)
                        }
                        .frame(width: 66)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(f.name) filter")
                }
            }
            .padding(.horizontal, 18)
        }
    }

    // MARK: Teleprompter

    /// The script panel over the viewfinder — static while idle (tap to edit),
    /// scrolling upward at the chosen pace while a take records; the scroll
    /// position carries across takes so the script never restarts mid-wave.
    private var teleprompterPanel: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isRecording)) { context in
            let live = recordingStartedAt.map { context.date.timeIntervalSince($0) } ?? 0
            let elapsed = recordedSeconds + live
            let pointsPerSecond = 22.0 * teleprompterSpeed
            let offset = -CGFloat(max(0, elapsed - 1.5) * pointsPerSecond)
            Button {
                guard !isRecording else { return }
                Haptics.tap()
                showTeleprompter = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("TELEPROMPTER")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        if !isRecording {
                            Button {
                                Haptics.tap()
                                teleprompterText = ""
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(width: 24, height: 24)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear script")
                        }
                    }
                    Text(teleprompterText)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineSpacing(5)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(y: offset)
                        .frame(height: 118, alignment: .top)
                        .clipped()
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .white, location: 0.12),
                                    .init(color: .white, location: 0.82),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var teleprompterSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Teleprompter")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    Haptics.tap()
                    showTeleprompter = false
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)

            Text("Paste or type your script. It scrolls over the camera while you record, at the pace you pick.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))

            TextEditor(text: $teleprompterText)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 150)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if teleprompterText.isEmpty {
                        Text("Hey everyone — today I want to talk about…")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(18)
                            .allowsHitTesting(false)
                    }
                }

            Text("PACE")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 8) {
                ForEach([(0.7, "Slow"), (1.0, "Normal"), (1.4, "Fast")], id: \.1) { pace in
                    Button {
                        Haptics.tap()
                        teleprompterSpeed = pace.0
                    } label: {
                        Text(pace.1)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(teleprompterSpeed == pace.0 ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(teleprompterSpeed == pace.0 ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.12)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !teleprompterText.isEmpty {
                Button {
                    Haptics.tap()
                    teleprompterText = ""
                } label: {
                    Text("Clear script")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.4))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .background(Color(red: 0.07, green: 0.07, blue: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: Camera settings

    private var settingsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Camera settings")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 18)

            settingToggle("Hands-free", "Tap the shutter to start and stop instead of holding it.", isOn: $handsFree)
            settingToggle("Grid", "Rule-of-thirds lines over the viewfinder.", isOn: $gridOn)
            settingToggle("Play audio while recording", "Hear the picked sound during takes for lip-sync. The mix is baked at publish either way.", isOn: $playSoundDuringTakes)

            VStack(alignment: .leading, spacing: 8) {
                Text("SPEED")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 8) {
                    ForEach([0.5, 1.0, 2.0, 3.0], id: \.self) { s in
                        Button {
                            Haptics.tap()
                            speed = s
                        } label: {
                            Text(speedLabel(s))
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(speed == s ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(speed == s ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.12)), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Applies to the takes you record next.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .background(Color(red: 0.07, green: 0.07, blue: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func settingToggle(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color(red: 0.05, green: 0.62, blue: 0.46))
    }

    // MARK: Cycles

    private func cycleSpeed() {
        let options: [Double] = [0.5, 1.0, 2.0, 3.0]
        let idx = options.firstIndex(of: speed) ?? 1
        speed = options[(idx + 1) % options.count]
    }

    private func cycleTimer() {
        timerChoice = timerChoice == 0 ? 3 : (timerChoice == 3 ? 10 : 0)
    }

    /// Skip lengths shorter than the already-recorded output timeline.
    private func cycleLength() {
        let options: [Double] = [15, 60, 180, WhisperWaveUploadPolicy.maximumDuration]
        let idx = options.firstIndex(of: maxSeconds) ?? 1
        for step in 1...options.count {
            let candidate = options[(idx + step) % options.count]
            if recordedSeconds <= candidate {
                withAnimation(.easeOut(duration: 0.2)) { maxSeconds = candidate }
                return
            }
        }
    }

    private var recordingTimer: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let live = recordingStartedAt.map { context.date.timeIntervalSince($0) / max(0.1, speed) } ?? 0
            let total = recordedSeconds + live
            HStack(spacing: 7) {
                Circle().fill(Color(red: 1.0, green: 0.23, blue: 0.27)).frame(width: 8, height: 8)
                    .opacity(Int(total * 2) % 2 == 0 ? 1 : 0.35)
                Text(String(format: "%d:%02d / %d:%02d", Int(total) / 60, Int(total) % 60, Int(maxSeconds) / 60, Int(maxSeconds) % 60))
                    .font(.caption.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
        }
    }

    /// Gallery tile (or delete-last) · the white shutter · flip orb (or Next).
    private var bottomRow: some View {
        HStack(alignment: .center) {
            if segments.isEmpty && !isRecording {
                Button {
                    Haptics.tap()
                    showPicker = true
                } label: {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white, lineWidth: 1.5) }
                        .shadow(color: .black.opacity(0.4), radius: 4)
                        .frame(width: 64, height: 64)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Upload from your library")
            } else if !segments.isEmpty && !isRecording {
                Button {
                    Haptics.tap()
                    deleteLastTake()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: pendingDeleteLast ? "trash.fill" : "delete.backward.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(pendingDeleteLast ? Color(red: 1.0, green: 0.23, blue: 0.27) : .white)
                            .shadow(color: .black.opacity(0.5), radius: 4)
                            .frame(width: 38, height: 38)
                        Text(pendingDeleteLast ? "Confirm" : "Delete")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3)
                    }
                    .frame(width: 64)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 64, height: 64)
            }

            Spacer()
            if sharedCamera != nil {
                Color.clear.frame(maxWidth: .infinity).frame(height: 44)
            } else if carouselActive && !isRecording && !showGreenScreen { selectedEffectPill }
            else { Text(isRecording ? "Recording" : (handsFree ? "Tap to record" : "Hold to record")).font(.caption).foregroundStyle(.white.opacity(0.8)) }
            Spacer()

            if !segments.isEmpty && !isRecording {
                Button {
                    Haptics.tap()
                    Task { await finishAndHandoff() }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(.black)
                            .frame(width: 44, height: 44)
                            .background(Color.white, in: Circle())
                        Text("Next")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3)
                    }
                    .frame(width: 64)
                }
                .buttonStyle(.plain)
                .disabled(exporting || finishing)
                .accessibilityLabel("Next")
            } else if !isRecording {
                Button {
                    Haptics.tap()
                    camera.flipCamera()
                } label: {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: .black.opacity(0.4), radius: 4)
                        .frame(width: 64, height: 64)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Flip camera")
            } else {
                Color.clear.frame(width: 64, height: 64)
            }
        }
    }

    /// Instagram's Reels shutter: a white ring around a white disc; while a
    /// take records the ring swells and the disc becomes a pink stop square.
    private var shutter: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(isRecording ? 0.9 : 1), lineWidth: isRecording ? 5 : 4)
                .frame(width: isRecording ? 100 : 84, height: isRecording ? 100 : 84)
            if isRecording {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.98, green: 0.30, blue: 0.42))
                    .frame(width: 32, height: 32)
            } else {
                Circle()
                    .fill(Color.white)
                    .frame(width: 66, height: 66)
                    .overlay {
                        if carouselActive && cameraEffect != .none {
                            WhisperWaveEffectTile(effect: cameraEffect, image: effectThumbnails.images[cameraEffect.id], size: 66)
                        } else if handsFree {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color(red: 0.98, green: 0.30, blue: 0.42))
                        }
                    }
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .frame(width: 116, height: 116)
        .contentShape(Circle())
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isRecording)
        .gesture(shutterGesture)
        .disabled(!camera.isAvailable || exporting || countdown != nil)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard cameraVisible, camera.isAvailable, !exporting, countdown == nil else { return }
            if isRecording { stopTake() }
            else if timerChoice > 0 { beginCountdown() }
            else { startTake() }
        }
    }

    /// Hold = record; release = stop. In hands-free mode a tap toggles. Drag
    /// up while holding to zoom (Snapchat/TikTok).
    private var shutterGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !pressActive {
                    pressActive = true; shutterSwiping = false
                    if handsFree { return }
                    shutterHoldTask = Task {
                        try? await Task.sleep(for: .milliseconds(180))
                        guard !Task.isCancelled, cameraVisible, pressActive, !shutterSwiping else { return }
                        if timerChoice > 0 && !isRecording { beginCountdown() }
                        else if !isRecording { startTake() }
                    }
                } else if !isRecording && abs(value.translation.width) > 14 && abs(value.translation.width) > abs(value.translation.height) {
                    shutterSwiping = true; shutterHoldTask?.cancel()
                } else if isRecording && !handsFree {
                    let lift = max(0, -value.translation.height)
                    let z = 1 + min(4, lift / 55)
                    if abs(z - holdZoom) > 0.02 {
                        holdZoom = z
                        camera.setZoom(z)
                    }
                }
            }
            .onEnded { value in
                pressActive = false; shutterHoldTask?.cancel()
                if shutterSwiping && !isRecording {
                    carouselActive = true
                    shutterSwiping = false
                    return
                }
                if handsFree {
                    if isRecording {
                        stopTake()
                    } else if timerChoice > 0 {
                        beginCountdown()
                    } else {
                        startTake()
                    }
                } else if isRecording {
                    stopTake()
                }
            }
    }

    // MARK: Countdown / takes

    private func beginCountdown() {
        guard countdown == nil, scenePhase == .active, camera.interruptionMessage == nil else { return }
        countdown = timerChoice
        Haptics.tap()
        countdownTask?.cancel()
        countdownTask = Task {
            await camera.prepareRecordingAudio()
            guard !Task.isCancelled, cameraVisible, scenePhase == .active else { countdown = nil; return }
            var n = timerChoice
            while n > 0 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard !Task.isCancelled else { return }
                guard cameraVisible, scenePhase == .active else { countdown = nil; return }
                n -= 1
                await MainActor.run {
                    countdown = n > 0 ? n : nil
                    if n > 0 { Haptics.tap() }
                }
            }
            await MainActor.run {
                // Timed takes are hands-free by nature: they run until the
                // allotted time or a tap on the shutter.
                handsFree = true
                startTake()
            }
        }
    }

    private func countdownOverlay(_ n: Int) -> some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            Text("\(n)")
                .font(.system(size: 120, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 20)
                .id(n)
                .transition(.scale(scale: 1.4).combined(with: .opacity))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: n)
        .allowsHitTesting(false)
    }

    private func startTake() {
        guard !backgroundImporting else { return }
        guard cameraVisible, scenePhase == .active, camera.interruptionMessage == nil, !isRecording, !finishing, camera.isAvailable, !camera.isDenied,
              cameraIssue == nil, backgroundSetting == nil || preparedBackgroundURL == backgroundSetting?.url else { return }
        guard recordedSeconds < maxSeconds - 0.3 else { return }
        Haptics.tap()
        pendingDeleteLast = false
        holdZoom = 1
        recordingStartedAt = Date()
        let attempt = UUID()
        takeID = attempt
        showFilters = false; showGreenScreen = false
        let takeFace = faceSetting.isActive ? faceSetting : nil
        let takeBackground = backgroundSetting
        let takeEffect = cameraEffect
        let account = AccountStorage.currentUserID; let generation = AccountStorage.generation
        let takeSpeed = speed
        playSoundForTake()
        camera.startRecording { url in
            Task { @MainActor in
                guard takeID == attempt, account == AccountStorage.currentUserID, generation == AccountStorage.generation else {
                    if let url { try? FileManager.default.removeItem(at: url) }; return
                }
                recordingStartedAt = nil; takeID = nil; soundPlayer?.pause()
                await appendTake(url, speed: takeSpeed, face: takeFace, background: takeBackground, cameraEffect: takeEffect)
            }
        }
    }

    private func stopTake() {
        guard isRecording else { return }
        let elapsed = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil
        finishing = true
        camera.setZoom(1)
        holdZoom = 1
        soundPlayer?.pause()
        Haptics.tap()
        if elapsed < 0.35 {
            camera.cancelRecording()
            return
        }
        camera.stopRecording()
    }

    /// Start the picked sound at the point this take will occupy in the
    /// finished wave (the sound's own start offset + everything recorded so
    /// far), so what you hear while shooting is what the mix will be.
    private func playSoundForTake() {
        guard !WhisperCameraCallMonitor.shared.callOwnsAudio, playSoundDuringTakes, let music, let url = URL(string: music.previewURL) else { return }
        let player: AVPlayer
        if let existing = soundPlayer, (existing.currentItem?.asset as? AVURLAsset)?.url == url {
            player = existing
        } else {
            player = AVPlayer(url: url)
            player.volume = 1.0
            soundPlayer = player
        }
        let at = music.startSeconds + recordedSeconds
        player.seek(to: CMTime(seconds: at, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    private func appendTake(_ url: URL?, speed: Double, face: WhisperWaveFaceSetting?, background: WhisperWaveBackground?, cameraEffect: WhisperWaveCameraEffect) async {
        defer { finishing = false }
        guard let url else { return }
        let seconds = await WhisperStoryPoster.duration(of: url)
        guard seconds > 0.2 else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            segments.append(WaveSegment(url: url, seconds: seconds, speed: speed, face: face, background: background, cameraEffect: cameraEffect))
        }
    }

    /// TikTok's two-tap delete: the last take turns red, tap again to remove.
    private func deleteLastTake() {
        if pendingDeleteLast {
            if let last = segments.popLast() {
                try? FileManager.default.removeItem(at: last.url)
            }
            pendingDeleteLast = false
            deleteResetTask?.cancel()
        } else {
            pendingDeleteLast = true
            deleteResetTask?.cancel()
            deleteResetTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await MainActor.run { pendingDeleteLast = false }
            }
        }
    }

    private func prepareBackground() async {
        preparedBackgroundURL = nil; preparedPhoto = nil; preparedVideo = nil
        guard let background = backgroundSetting else { return }
        let owner = AccountStorage.currentUserID; let generation = AccountStorage.generation
        do {
            if background.media == .photo {
                let photo = try await Task.detached(priority: .userInitiated) { try WhisperWaveBackgroundImporter.image(at: background.url) }.value
                try Task.checkCancellation()
                guard owner == AccountStorage.currentUserID, generation == AccountStorage.generation else { return }
                preparedPhoto = photo
            } else {
                let video = try await WhisperWaveLiveVideoBackground.prepare(background.url)
                try Task.checkCancellation()
                guard owner == AccountStorage.currentUserID, generation == AccountStorage.generation else { return }
                preparedVideo = video
            }
            preparedBackgroundURL = background.url
        } catch {
            guard !Task.isCancelled else { return }
            cameraIssue = "Couldn't prepare the background. Replace it or retry."
        }
    }

    // MARK: Finish

    private func finishAndHandoff() async {
        guard !segments.isEmpty, !exporting, !finishing, !isRecording else { return }
        exporting = true
        defer { exporting = false }
        let filter = currentFilter
        let effect = arEffect
        // Keep recorded takes and their speeds editable; no export on handoff.
        if let onReadyClips, let first = segments.first {
            let clips = segments.map { take in
                var clip = WhisperWaveClip(url: take.url, duration: take.seconds, speed: take.speed)
                clip.fillsFrame = true
                clip.face = take.face; clip.background = take.background; clip.cameraEffect = take.cameraEffect
                return clip
            }
            onReadyClips(first.url, clips, music, filter, .none)
            return
        }
        if segments.count == 1, segments[0].speed == 1 {
            onReady(segments[0].url, music, filter, effect)
            return
        }
        guard let merged = await WhisperWaveStudio.merge(segments: segments) else {
            exportError = "The takes couldn't be stitched together. Try recording again."
            return
        }
        onReady(merged, music, filter, effect)
    }

    private func handleUpload(_ items: [PhotosPickerItem]) async {
        guard canExit, !items.isEmpty, !Task.isCancelled else { return }
        let operation = UUID(); importOperation = operation
        let generation = AccountStorage.generation
        let pickedMusic = music; let pickedFilter = currentFilter; let pickedEffect = arEffect
        exporting = true
        defer { if operation == importOperation { pickerItems = []; exporting = false } }
        var urls: [URL] = []
        var handedOff = false
        defer {
            if !handedOff { let abandoned = urls; Task.detached(priority: .utility) { for url in abandoned { try? FileManager.default.removeItem(at: url) } } }
        }
        for item in items {
            if let movie = try? await item.loadTransferable(type: WhisperPickedMovie.self) {
                urls.append(movie.url)
            }
            guard !Task.isCancelled, operation == importOperation, generation == AccountStorage.generation else { return }
        }
        guard urls.count == items.count, let first = urls.first else {
            exportError = "Some selected videos couldn't be loaded. Please select them again; no clips have been dropped."
            return
        }
        if urls.count == 1 || onReadyClips == nil {
            handedOff = true
            onReady(first, pickedMusic, pickedFilter, pickedEffect)
            return
        }
        // Several videos: cut them together in order for the composer's
        // preview, and hand the separate clips along so the Clips editor
        // opens on each one (trim · speed · transitions).
        var clips: [WhisperWaveClip] = []
        for url in urls {
            let d = await WhisperWaveClipStudio.duration(of: url)
            guard !Task.isCancelled, operation == importOperation, generation == AccountStorage.generation else { return }
            if d > 0.2 { clips.append(WhisperWaveClip(url: url, duration: d)) }
        }
        guard clips.count == urls.count else {
            exportError = "A selected video couldn't be read. Please choose a playable video."
            return
        }
        handedOff = true
        onReadyClips?(first, clips, pickedMusic, pickedFilter, pickedEffect)
    }

    private func speedLabel(_ s: Double) -> String {
        s == 0.5 ? "0.5x" : "\(Int(s))x"
    }

    private var filterSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard !isRecording else { return }
                let dx = value.translation.width
                guard abs(dx) > 40, abs(dx) > abs(value.translation.height) else { return }
                let delta = dx < 0 ? 1 : -1
                Haptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    filterIndex = (filterIndex + delta + filters.count) % filters.count
                }
            }
    }

    private var exportingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.white).controlSize(.large)
                Text("Stitching your takes…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .transition(.opacity)
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text("Camera unavailable")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Install this app on your device via the Rork App to record. You can still upload a video from your library.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Haptics.tap()
                showPicker = true
            } label: {
                Label("Upload a video", systemImage: "photo.on.rectangle.angled")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Studio (AVFoundation export helpers)

/// The text FONTS for wave text layers — Instagram's set, Whisper's names.
nonisolated enum WaveTextFont: String, CaseIterable, Identifiable, Equatable, Codable, Sendable {
    case classic, modern, neon, typewriter, strong
    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "Classic"
        case .modern: return "Modern"
        case .neon: return "Neon"
        case .typewriter: return "Typewriter"
        case .strong: return "Strong"
        }
    }

    /// True for the all-caps condensed style.
    var uppercase: Bool { self == .strong }
    /// True for the glowing style (shadow becomes a colored glow).
    var glows: Bool { self == .neon }

    nonisolated func uiFont(size: CGFloat) -> UIFont {
        switch self {
        case .classic:
            return UIFont.systemFont(ofSize: size, weight: .heavy)
        case .modern:
            if let d = UIFont.systemFont(ofSize: size, weight: .semibold).fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: d, size: size)
            }
            return UIFont.systemFont(ofSize: size, weight: .semibold)
        case .neon:
            if let d = UIFont.systemFont(ofSize: size, weight: .bold).fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: d, size: size)
            }
            return UIFont.systemFont(ofSize: size, weight: .bold)
        case .typewriter:
            return UIFont.monospacedSystemFont(ofSize: size * 0.92, weight: .medium)
        case .strong:
            return UIFont.systemFont(ofSize: size * 1.05, weight: .black)
        }
    }

    func swiftUIFont(size: CGFloat) -> Font {
        switch self {
        case .classic: return .system(size: size, weight: .heavy)
        case .modern: return .system(size: size, weight: .semibold, design: .serif)
        case .neon: return .system(size: size, weight: .bold, design: .rounded)
        case .typewriter: return .system(size: size * 0.92, weight: .medium, design: .monospaced)
        case .strong: return .system(size: size * 1.05, weight: .black)
        }
    }
}

/// Entrance ANIMATIONS for wave text layers — baked as Core Animation so
/// every platform sees the motion.
nonisolated enum WaveTextAnimation: String, CaseIterable, Identifiable, Equatable, Codable, Sendable {
    case none, pop, fade, rise, typewriter
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .pop: return "Pop"
        case .fade: return "Fade"
        case .rise: return "Rise"
        case .typewriter: return "Type"
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle.slash"
        case .pop: return "arrow.up.left.and.arrow.down.right"
        case .fade: return "circle.lefthalf.filled"
        case .rise: return "arrow.up"
        case .typewriter: return "keyboard"
        }
    }
}

/// The eight text colors on the wave text tool.
enum WaveTextPalette {
    static let hexes: [String] = ["FFFFFF", "0C1014", "9BE8C4", "0E9F76", "5A5FE8", "FF4D8D", "FFC94D", "38BDF8"]

    nonisolated static func uiColor(_ hex: String) -> UIColor {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return .white }
        return UIColor(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }

    static func color(_ hex: String) -> Color { Color(uiColor: uiColor(hex)) }
}

/// One baked TEXT LAYER on a wave — the fun formatting: font, color, plate
/// (`style` 0 = none / 1 = black pill / 2 = white pill), size, an entrance
/// animation, a timing window, and a normalized (0…1) position. `isSticker`
/// marks an emoji sticker (no plate, drawn large). Rendered onto every frame
/// at publish so all platforms see it.
nonisolated struct WaveTextOverlay: Equatable, Identifiable, Codable, Sendable {
    var id: UUID = UUID()
    var text: String = ""
    var style: Int = 1
    var font: WaveTextFont = .classic
    var colorHex: String = "FFFFFF"
    var animation: WaveTextAnimation = .none
    var x: Double = 0.5
    var y: Double = 0.5
    /// Size multiplier (0.7 … 2.6).
    var scale: Double = 1.0
    /// Seconds into the wave when the layer appears (0 = from the start).
    var start: Double = 0
    /// Seconds into the wave when the layer leaves (0 = until the end).
    var end: Double = 0
    var isSticker: Bool = false

    /// Text color, resolved (white plates flip dark text automatically).
    nonisolated var uiTextColor: UIColor {
        if style == 2, colorHex.uppercased() == "FFFFFF" { return UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1) }
        return WaveTextPalette.uiColor(colorHex)
    }

    /// The rendered string (Strong is all caps).
    var displayText: String { font.uppercase && !isSticker ? text.uppercased() : text }

    /// An emoji sticker layer.
    static func sticker(_ emoji: String) -> WaveTextOverlay {
        var o = WaveTextOverlay()
        o.text = emoji
        o.style = 0
        o.scale = 2.4
        o.isSticker = true
        o.animation = .pop
        return o
    }
}

/// The wave export pipeline. Everything runs off-main and returns temp URLs.
nonisolated enum WhisperWaveStudio {
    /// Stitch recorded takes (each at its own speed) into one upright MP4.
    static func merge(segments: [WaveSegment]) async -> URL? {
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var cursor = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var renderSize = CGSize(width: 1080, height: 1920)
        var first = true

        for seg in segments {
            let asset = AVURLAsset(url: seg.url)
            guard let vTrack = try? await asset.loadTracks(withMediaType: .video).first,
                  let duration = try? await asset.load(.duration) else { continue }
            let transform = (try? await vTrack.load(.preferredTransform)) ?? .identity
            let natural = (try? await vTrack.load(.naturalSize)) ?? CGSize(width: 1080, height: 1920)
            let oriented = natural.applying(transform)
            let orientedSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
            if first {
                renderSize = orientedSize
                first = false
            }
            let range = CMTimeRange(start: .zero, duration: duration)
            do {
                try compVideo.insertTimeRange(range, of: vTrack, at: cursor)
            } catch { continue }
            if let aTrack = try? await asset.loadTracks(withMediaType: .audio).first, let compAudio {
                try? compAudio.insertTimeRange(range, of: aTrack, at: cursor)
            }
            var segDuration = duration
            if seg.speed != 1 {
                let scaled = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / seg.speed)
                let inserted = CMTimeRange(start: cursor, duration: duration)
                compVideo.scaleTimeRange(inserted, toDuration: scaled)
                compAudio?.scaleTimeRange(inserted, toDuration: scaled)
                segDuration = scaled
            }

            // Fit this take into the render frame (all our takes share one
            // camera, but front/back orientation flags can differ).
            var t = transform
            let scale = min(renderSize.width / max(1, orientedSize.width), renderSize.height / max(1, orientedSize.height))
            if abs(scale - 1) > 0.001 {
                let dx = (renderSize.width - orientedSize.width * scale) / 2
                let dy = (renderSize.height - orientedSize.height * scale) / 2
                t = t.concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(CGAffineTransform(translationX: dx, y: dy))
            }
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: segDuration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
            layer.setTransform(t, at: cursor)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)

            cursor = CMTimeAdd(cursor, segDuration)
        }
        guard !instructions.isEmpty else { return nil }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: renderSize.width.rounded(), height: renderSize.height.rounded())
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions

        return await export(composition, videoComposition: videoComposition, audioMix: nil, preset: AVAssetExportPresetHighestQuality)
    }

    /// Legacy baking also uses the shared 3D accessory renderer. Fail the export
    /// rather than silently omitting a selected effect; the source remains intact.
    static func applyAREffect(_ url: URL, effect: WhisperAREffect) async -> URL? {
        guard effect != .none else { return url }
        let asset = AVURLAsset(url: url)
        let processor = WhisperARProcessor.shared
        let videoComposition = AVMutableVideoComposition(asset: asset) { request in
            let source = request.sourceImage
            do {
                let out = try processor.render(source, effect: effect, quality: .export, time: request.compositionTime.seconds).cropped(to: source.extent)
                request.finish(with: out, context: nil)
            } catch {
                request.finish(with: error)
            }
        }
        return await export(asset, videoComposition: videoComposition, audioMix: nil, preset: AVAssetExportPresetHighestQuality)
    }

    /// Bake a Whisper look into a clip (a second pass on an upright file) —
    /// single Core Image effects and the multi-stage Whisper chains alike.
    static func applyFilter(_ url: URL, filter: SnapFilter) async -> URL? {
        guard filter != .none else { return url }
        let asset = AVURLAsset(url: url)
        let videoComposition = AVMutableVideoComposition(asset: asset) { request in
            let source = request.sourceImage
            let out = filter.process(source.clampedToExtent()).cropped(to: source.extent)
            request.finish(with: out, context: nil)
        }
        return await export(asset, videoComposition: videoComposition, audioMix: nil, preset: AVAssetExportPresetHighestQuality)
    }

    /// The publish bake: trim window · mute original · mixed-in sound track ·
    /// every baked text layer (fonts, colors, plates, entrance animations,
    /// timing windows). Returns nil when nothing needs baking.
    static func bake(
        url: URL,
        trimStart: Double,
        trimEnd: Double,
        totalDuration: Double,
        muteOriginal: Bool,
        musicURL: URL?,
        musicVolume: Float,
        texts: [WaveTextOverlay]
    ) async -> URL? {
        let needsTrim = trimStart > 0.05 || (trimEnd > 0 && trimEnd < totalDuration - 0.05)
        let layers = texts.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hasText = !layers.isEmpty
        guard needsTrim || muteOriginal || musicURL != nil || hasText else { return nil }

        let asset = AVURLAsset(url: url)
        guard let total = try? await asset.load(.duration) else { return nil }
        let totalSeconds = total.seconds
        guard totalSeconds.isFinite, totalSeconds > 0 else { return nil }
        let s = max(0, min(trimStart, totalSeconds))
        let e = trimEnd <= 0 ? totalSeconds : min(totalSeconds, max(trimEnd, s + 1.0 / 30))
        guard e - s >= 1.0 / 30 else { return nil }

        let composition = AVMutableComposition()
        guard let vTrack = try? await asset.loadTracks(withMediaType: .video).first,
              let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        let range = CMTimeRange(start: CMTime(seconds: s, preferredTimescale: 600), end: CMTime(seconds: e, preferredTimescale: 600))
        do { try compVideo.insertTimeRange(range, of: vTrack, at: .zero) } catch { return nil }
        let transform = (try? await vTrack.load(.preferredTransform)) ?? .identity
        let natural = (try? await vTrack.load(.naturalSize)) ?? CGSize(width: 1080, height: 1920)
        let oriented = natural.applying(transform)
        let renderSize = CGSize(width: abs(oriented.width).rounded(), height: abs(oriented.height).rounded())

        var mixParams: [AVMutableAudioMixInputParameters] = []
        if !muteOriginal,
           let aTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            do {
                let available = try await aTrack.load(.timeRange)
                let audible = CMTimeRangeGetIntersection(range, otherRange: available)
                if audible.duration.seconds > 0 {
                    try compAudio.insertTimeRange(audible, of: aTrack, at: CMTimeSubtract(audible.start, range.start))
                }
            } catch { return nil }
            let p = AVMutableAudioMixInputParameters(track: compAudio)
            p.setVolume(musicURL == nil ? 1.0 : 0.55, at: .zero)
            mixParams.append(p)
        }
        if let musicURL {
            let musicAsset = AVURLAsset(url: musicURL)
            if let mTrack = try? await musicAsset.loadTracks(withMediaType: .audio).first,
               let mDuration = try? await musicAsset.load(.duration),
               let compMusic = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                // Loop the track to cover the whole cut.
                var at = CMTime.zero
                let target = CMTime(seconds: e - s, preferredTimescale: 600)
                while at < target {
                    let remaining = CMTimeSubtract(target, at)
                    let chunk = CMTimeMinimum(mDuration, remaining)
                    try? compMusic.insertTimeRange(CMTimeRange(start: .zero, duration: chunk), of: mTrack, at: at)
                    at = CMTimeAdd(at, chunk)
                    if chunk.seconds < 0.1 { break }
                }
                let p = AVMutableAudioMixInputParameters(track: compMusic)
                p.setVolume(musicVolume, at: .zero)
                mixParams.append(p)
            }
        }
        var audioMix: AVMutableAudioMix? = nil
        if !mixParams.isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = mixParams
            audioMix = mix
        }

        // Video composition: keep the source upright + optional baked text.
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: e - s, preferredTimescale: 600))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        layer.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layer]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]
        if hasText {
            let cutSeconds = e - s
            videoComposition.animationTool = await MainActor.run { textTool(layers, renderSize: renderSize, duration: cutSeconds) }
        }

        return await export(composition, videoComposition: videoComposition, audioMix: audioMix, preset: AVAssetExportPresetHighestQuality)
    }

    /// CoreAnimation tool that stamps every text layer onto the frames — font,
    /// color, plate, size, timing window, and the entrance animation (pop /
    /// fade / rise / typewriter reveal) as real CAAnimations on the export
    /// timeline.
    @MainActor
    static func textTool(_ overlays: [WaveTextOverlay], renderSize: CGSize, duration: Double) -> AVVideoCompositionCoreAnimationTool {
        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)
        parent.isGeometryFlipped = true
        let videoLayer = CALayer()
        videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)

        for overlay in overlays {
            guard overlay.start < duration else { continue }
            let group = textLayerGroup(overlay, renderSize: renderSize)
            let window = CALayer()
            window.frame = parent.bounds
            window.addSublayer(group)
            applyAnimations(to: group, window: window, overlay: overlay, renderSize: renderSize, duration: duration)
            parent.addSublayer(window)
        }

        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
    }

    /// One layer group per text overlay: the plate + the text, positioned.
    @MainActor
    static func textLayerGroup(_ overlay: WaveTextOverlay, renderSize: CGSize) -> CALayer {
        let baseSize = renderSize.width * (overlay.isSticker ? 0.11 : 0.058)
        let fontSize = baseSize * CGFloat(max(0.5, min(3.0, overlay.scale)))
        let font = overlay.font.uiFont(size: fontSize)
        let maxWidth = max(1, renderSize.width * 0.84 - (overlay.style == 0 ? 0 : fontSize * 1.1))
        let fg = overlay.uiTextColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg, .paragraphStyle: paragraph]
        let attributed = NSAttributedString(string: overlay.displayText, attributes: attrs)
        let bounds = attributed.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let padX = overlay.style == 0 ? 0 : fontSize * 0.55
        let padY = overlay.style == 0 ? 0 : fontSize * 0.35
        let pillSize = CGSize(width: ceil(bounds.width) + padX * 2 + 4, height: ceil(bounds.height) + padY * 2 + 4)
        // The parent layer is geometry-flipped (top-left origin like the
        // SwiftUI preview), so the normalized y maps straight down.
        let center = CGPoint(x: renderSize.width * overlay.x, y: renderSize.height * overlay.y)

        let group = CALayer()
        group.bounds = CGRect(origin: .zero, size: pillSize)
        group.position = center

        let pill = CALayer()
        pill.frame = CGRect(origin: .zero, size: pillSize)
        pill.cornerRadius = fontSize * 0.45
        switch overlay.style {
        case 1: pill.backgroundColor = UIColor.black.withAlphaComponent(0.72).cgColor
        case 2: pill.backgroundColor = UIColor.white.withAlphaComponent(0.94).cgColor
        default: pill.backgroundColor = UIColor.clear.cgColor
        }
        group.addSublayer(pill)

        let textLayer = CATextLayer()
        textLayer.string = attributed
        textLayer.isWrapped = true
        textLayer.alignmentMode = .center
        textLayer.contentsScale = 1
        textLayer.frame = CGRect(x: padX + 2, y: padY + 2, width: ceil(bounds.width), height: ceil(bounds.height) + 2)
        if overlay.style == 0 && !overlay.isSticker {
            if overlay.font.glows {
                textLayer.shadowColor = fg.cgColor
                textLayer.shadowOpacity = 0.95
                textLayer.shadowRadius = fontSize * 0.28
                textLayer.shadowOffset = .zero
            } else {
                textLayer.shadowColor = UIColor.black.cgColor
                textLayer.shadowOpacity = 0.6
                textLayer.shadowRadius = fontSize * 0.12
                textLayer.shadowOffset = CGSize(width: 0, height: fontSize * 0.05)
            }
        }
        group.addSublayer(textLayer)
        return group
    }

    /// The timing window (start/end) plus the entrance animation, on the
    /// export clock (`AVCoreAnimationBeginTimeAtZero`).
    @MainActor
    private static func applyAnimations(to group: CALayer, window visibilityLayer: CALayer, overlay: WaveTextOverlay, renderSize: CGSize, duration: Double) {
        let total = max(0.1, duration)
        let start = max(0, min(overlay.start, total - 0.05))
        let end = overlay.end > 0 ? max(start + 0.2, min(overlay.end, total)) : total
        let base = AVCoreAnimationBeginTimeAtZero

        // Visibility window — hidden before `start` and after `end`.
        if start > 0.01 || end < total - 0.01 {
            let window = CAKeyframeAnimation(keyPath: "opacity")
            let eps = 0.001
            var values: [Double] = []
            var times: [NSNumber] = []
            values.append(start > 0.01 ? 0 : 1); times.append(0)
            if start > 0.01 {
                values.append(0); times.append(NSNumber(value: max(0, (start - eps) / total)))
                values.append(1); times.append(NSNumber(value: start / total))
            }
            if end < total - 0.01 {
                values.append(1); times.append(NSNumber(value: max(0, (end - eps) / total)))
                values.append(0); times.append(NSNumber(value: end / total))
            }
            values.append(end < total - 0.01 ? 0 : 1); times.append(1)
            window.values = values
            window.keyTimes = times
            window.calculationMode = .discrete
            window.beginTime = base
            window.duration = total
            window.isRemovedOnCompletion = false
            window.fillMode = .both
            visibilityLayer.add(window, forKey: "window")
        }

        let entrance = base + start + 0.0001
        switch overlay.animation {
        case .none:
            break
        case .pop:
            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0.35, 1.14, 0.96, 1.0]
            pop.keyTimes = [0, 0.55, 0.8, 1]
            pop.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
            pop.beginTime = entrance
            pop.duration = 0.5
            pop.isRemovedOnCompletion = false
            pop.fillMode = .both
            group.add(pop, forKey: "pop")
        case .fade:
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.beginTime = entrance
            fade.duration = 0.75
            fade.isRemovedOnCompletion = false
            fade.fillMode = .forwards
            group.add(fade, forKey: "fade")
        case .rise:
            // Flipped geometry: +y is DOWN, so "rise" starts below and lifts.
            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = renderSize.height * 0.05
            rise.toValue = 0
            rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
            rise.beginTime = entrance
            rise.duration = 0.55
            rise.isRemovedOnCompletion = false
            rise.fillMode = .both
            group.add(rise, forKey: "rise")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.beginTime = entrance
            fade.duration = 0.4
            fade.isRemovedOnCompletion = false
            fade.fillMode = .forwards
            group.add(fade, forKey: "riseFade")
        case .typewriter:
            // A left-to-right reveal mask — the closest CA gets to typing.
            let mask = CALayer()
            mask.backgroundColor = UIColor.white.cgColor
            mask.anchorPoint = CGPoint(x: 0, y: 0.5)
            mask.position = CGPoint(x: 0, y: group.bounds.midY)
            mask.bounds = CGRect(x: 0, y: 0, width: group.bounds.width, height: group.bounds.height)
            group.mask = mask
            let reveal = CABasicAnimation(keyPath: "bounds.size.width")
            reveal.fromValue = 0
            reveal.toValue = group.bounds.width
            reveal.timingFunction = CAMediaTimingFunction(name: .linear)
            reveal.beginTime = entrance
            reveal.duration = min(2.2, max(0.5, Double(overlay.text.count) * 0.06))
            reveal.isRemovedOnCompletion = false
            reveal.fillMode = .both
            mask.add(reveal, forKey: "reveal")
        }
    }

    private static func export(_ asset: AVAsset, videoComposition: AVVideoComposition?, audioMix: AVAudioMix?, preset: String) async -> URL? {
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wave-studio-\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return nil }
        session.videoComposition = videoComposition
        session.audioMix = audioMix
        session.shouldOptimizeForNetworkUse = true
        if #available(iOS 18.0, *) {
            do {
                try await session.export(to: outURL, as: .mp4)
                return outURL
            } catch {
                return nil
            }
        } else {
            session.outputURL = outURL
            session.outputFileType = .mp4
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { cont.resume() }
            }
            return session.status == .completed ? outURL : nil
        }
    }

    /// Download a remote preview track to a temp file so the export can read it.
    static func localCopy(of remote: URL) async -> URL? {
        if remote.isFileURL { return remote }
        var request = URLRequest(url: remote)
        request.timeoutInterval = 45
        guard let (download, response) = try? await URLSession.shared.download(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        defer { try? FileManager.default.removeItem(at: download) }
        guard let size = try? download.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else { return nil }
        let ext = remote.pathExtension.isEmpty ? "m4a" : remote.pathExtension
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("wave-sound-\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.moveItem(at: download, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    /// Save the finished wave to the user's Photos library (TikTok's "Save to device").
    static func saveToPhotos(_ url: URL) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            return true
        } catch {
            return false
        }
    }
}
