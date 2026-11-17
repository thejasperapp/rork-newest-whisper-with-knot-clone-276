import SwiftUI
import AVFoundation
import Photos
import PhotosUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

/// Snapchat/Instagram-style story camera. TAP the shutter for a photo,
/// PRESS AND HOLD to record video — a red ring fills around the shutter
/// while recording (60s cap), drag UP while holding to zoom, release to
/// stop. Swipe sideways to cycle filters, tap the bottom-left thumbnail to
/// import a photo OR video from the library. Anything captured is handed to
/// `WhisperStoryEditor` on its fixed 9:16 stage for stickers, text, music
/// and posting.
struct WhisperStoryComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showStarters: Bool = false
    @State private var selectedStarter: WhisperStoryStarter?
    @State private var shownLayout: WhisperStoryPhotoLayout?
    @State private var pendingLayout: WhisperStoryPhotoLayout?
    @State private var supplementalLayers: [WhisperStorySticker] = []
    @State private var pendingTemplateEditor: Bool = false
    @State private var handsFree: Bool = false
    @State private var creationMode: WhisperCaptureMode = .story
    @State private var showsWaves: Bool = false
    @State private var hasOpenedWaves: Bool = false
    @State private var hasOpenedPost: Bool = false
    @State private var postUsesCamera: Bool = false
    @State private var postItems: [PhotosPickerItem] = []
    @State private var postPhoto: UIImage?
    @State private var postHandoff: WhisperCapturePostHandoff?
    @State private var confirmPostDiscard: Bool = false
    private var showsPostLibrary: Bool { creationMode == .post && !postUsesCamera }
    private var hasPostSelection: Bool { !postItems.isEmpty || postPhoto != nil }
    @State private var wavePreview: WhisperCapturePreviewBridge = .init()
    @State private var showsLiveSetup: Bool = false
    @State private var pendingLiveRoom: WhisperLiveRoom?
    @State private var liveRoom: WhisperLiveRoom?
    @State private var layoutGrid: WhisperCaptureGrid?
    @State private var layoutPhotos: [Int: UIImage] = [:]
    @State private var layoutCell: Int = 0
    @State private var showsGridChoices: Bool = false
    @State private var confirmLayoutReset: Bool = false
    @State private var showsGreenScreen: Bool = false
    @State private var backgroundSetting: WhisperWaveBackground?
    @State private var preparedPhoto: CIImage?
    @State private var preparedVideo: WhisperWaveLiveVideoBackground?
    @State private var preparedBackgroundURL: URL?
    @State private var backgroundImporting: Bool = false
    @State private var previewTiming: WhisperCameraPreviewTiming = WhisperCameraPreviewTiming()
    @State private var storyTakeID: UUID?
    @State private var liveSetupID: UUID = UUID()
    @State private var showEffectBrowser: Bool = false

    /// Optional stickers that should be pre-loaded on the canvas after the
    /// user captures or imports a photo. Used by the IG-style Q&A re-share
    /// flow so the question card + answer pill ride along into the editor
    /// after the author shoots a real background photo.
    var initialStickers: [WhisperStorySticker] = []
    /// CARD MODE — when the feed mounts this composer as the layer the feed
    /// card slides off to reveal (the swipe-right grammar), closing means
    /// sliding the feed back over it, not dismissing a modal. The feed
    /// passes that slide here; every close path routes through `close()`.
    var onClose: (() -> Void)? = nil
    /// Opacity-hidden tabs do not disappear. The presenter supplies actual visibility.
    var isActive: Bool = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible: Bool = false
    @State private var previewRevision: Int = 0
    @State private var wasBackgrounded: Bool = false

    private var shouldCapture: Bool {
        isActive && isVisible && scenePhase == .active && captured == nil && postHandoff == nil && !showsPostLibrary && !showPicker && !showStarters && shownLayout == nil && !(showsWaves && wavePreview.suspended) && !showsLiveSetup && liveRoom == nil && mode == .camera && pendingEffectVideo == nil && (pendingEffectPhoto == nil || layoutGrid != nil)
    }

    private func updateCaptureActivity() {
        if scenePhase == .inactive, camera.isRequestingMicrophonePermission, isActive, isVisible, captured == nil, !showPicker { return }
        if shouldCapture {
            camera.configure()
            if !showsWaves { camera.setTorch(flashOn) }
        } else {
            camera.setTorch(false)
            recordArmTask?.cancel()
            pressStartedAt = nil
            shutterPressed = false
            if isRecording {
                recordingStartedAt = nil
                finishingRecording = true
                camera.stopRecording()
            }
            camera.stop()
        }
    }

    /// Closes the composer — the card slide when embedded, `dismiss()` when
    /// presented as a cover.
    private func close() {
        if captureBusy || !layoutPhotos.isEmpty { confirmCaptureDiscard = true; return }
        if hasPostSelection { confirmPostDiscard = true; return }
        isVisible = false
        camera.stop()
        creationMode = .story; showsWaves = false; hasOpenedWaves = false
        hasOpenedPost = false; postUsesCamera = false
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    /// The capture session lives behind a lazy holder: SwiftUI evaluates a
    /// `@State` initial value on EVERY construction of this struct (the feed
    /// re-creates it on every frame of the story slide), and building an
    /// AVCaptureSession + device discovery on the main thread each time was
    /// the stall that read as a blank, unexitable screen.
    @State private var cameraHolder = SnapCameraHolder()
    private var camera: SnapCameraSession { cameraHolder.session }
    @State private var captured: CapturedSnap?
    @State private var libraryThumb: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPicker: Bool = false
    @State private var filterIndex: Int = 0
    @State private var cameraEffect: WhisperWaveCameraEffect = .none
    @State private var showsFaceEffects: Bool = true
    @State private var shutterScrubbed: Bool = false
    @State private var effectThumbnails = WhisperWaveEffectThumbnails()
    @State private var effectCatalogID: UUID = UUID()
    private static let storyEffects: [WhisperWaveCameraEffect] = WhisperWaveCameraEffect.available
    private var liveConfiguration: WhisperWaveLiveFrameRenderer.Configuration {
        var value = selectedEffects.configuration
        value.catalogID = showsFaceEffects && creationMode == .story ? effectCatalogID : nil
        value.takeID = storyTakeID
        return value
    }
    @State private var recordingEffects = WhisperStoryCaptureEffects()
    @State private var captureIssue: String?
    @State private var pendingEffectVideo: URL?
    @State private var pendingEffectPhoto: UIImage?
    @State private var captureTask: Task<Void, Never>?
    @State private var takingPhoto: Bool = false
    @State private var captureGeneration: UUID = AccountStorage.generation
    @State private var captureOperation: UUID = UUID()
    @State private var confirmCaptureDiscard: Bool = false
    var onCaptureBusyChanged: ((Bool) -> Void)? = nil
    var closeRequest: Int = 0
    var onLayoutDirtyChanged: ((Bool) -> Void)? = nil
    private var gridIsComplete: Bool { layoutGrid.map { layoutPhotos.count == $0.cells.count } ?? false }
    private var locksParentNavigation: Bool { captureBusy || showsWaves || hasPostSelection || postHandoff != nil || showsPostLibrary || showsLiveSetup || liveRoom != nil || captured != nil || showPicker || showStarters || shownLayout != nil || showEffectBrowser }
    private var captureBusy: Bool { backgroundImporting || importing || takingPhoto || isRecording || finishingRecording || pendingEffectVideo != nil || pendingEffectPhoto != nil }
    @State private var effectPreviewIssue: String?
    @State private var flashOn: Bool = false
    @State private var filterChipKick: Int = 0
    @State private var drafts = WhisperStoryDraftService.shared
    @State private var showResumePrompt: Bool = false
    @State private var importing: Bool = false
    @State private var showHoldHint: Bool = true

    // Hold-to-record state.
    @State private var pressStartedAt: Date?
    @State private var recordArmTask: Task<Void, Never>?
    @State private var recordingStartedAt: Date?
    @State private var finishingRecording: Bool = false
    @State private var holdZoom: CGFloat = 1
    /// Finger is down on the shutter (before/while recording) — drives the
    /// instant press squash so the button answers the touch immediately.
    @State private var shutterPressed: Bool = false

    /// Snapchat's cap per snap segment; Instagram's continuous story limit.
    static let maxRecordSeconds: Double = 60

    /// Instagram-style create modes — the classic camera and TYPE, which
    /// writes on a gradient canvas instead of a photo.
    enum ComposerMode: String { case camera, type }
    @State private var mode: ComposerMode = .camera
    @State private var typeBackgroundIndex: Int = 0

    /// Instagram's classic TYPE-mode gradient set.
    static let typeGradients: [[Color]] = [
        [Color(red: 0.51, green: 0.23, blue: 0.71), Color(red: 0.93, green: 0.20, blue: 0.32)],
        [Color(red: 0.99, green: 0.35, blue: 0.13), Color(red: 0.99, green: 0.75, blue: 0.29)],
        [Color(red: 0.25, green: 0.36, blue: 0.90), Color(red: 0.88, green: 0.19, blue: 0.42)],
        [Color(red: 0.05, green: 0.63, blue: 0.46), Color(red: 0.13, green: 0.83, blue: 0.93)],
        [Color(red: 0.95, green: 0.42, blue: 0.71), Color(red: 0.55, green: 0.31, blue: 0.97)],
        [Color(red: 0.09, green: 0.09, blue: 0.11), Color(red: 0.30, green: 0.30, blue: 0.36)]
    ]

    private let filters: [SnapFilter] = SnapFilter.all

    private var isRecording: Bool { recordingStartedAt != nil }

    var body: some View { cameraPresentations }

    private var cameraLifecycle: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            captureWorkspace

            if let effectPreviewIssue, !captureBusy, !showsWaves, !showsPostLibrary {
                Text(effectPreviewIssue).font(.caption).foregroundStyle(.white).padding(10)
                    .background(.black.opacity(0.6), in: Capsule()).frame(maxHeight: .infinity, alignment: .top).padding(.top, 115)
            }
            if (pendingEffectVideo != nil || pendingEffectPhoto != nil) && !importing {
                Button("Finish saved capture") { captureTask = Task { await renderPendingCapture() } }
                    .buttonStyle(.borderedProminent)
            }
            if mode == .camera, !showsWaves, !showsPostLibrary {
                WhisperCameraStatusView(interruption: camera.interruptionMessage, silent: WhisperCameraCallMonitor.shared.callOwnsAudio || (isRecording && camera.recordingWithoutAudio))
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 70)
            }

            if drafts.hasDraft && showResumePrompt && !captureBusy && layoutPhotos.isEmpty && creationMode == .story {
                resumeDraftBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if importing {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    ProgressView().tint(.white).controlSize(.large)
                }
                .transition(.opacity)
            }
        }
        // Capture and editing share the same safe-area geometry and status policy.
        .statusBarHidden(false)
        // Use environment override instead of `.preferredColorScheme(.dark)`
        // — the latter mutates the whole window's color scheme and was
        // leaving the parent app stuck in dark mode after the cover
        // dismissed ("clicking the plus button forces the app to dark").
        .environment(\.colorScheme, .dark)
        .task { await prepare() }
        .task(id: backgroundSetting?.url) { await prepareStoryBackground() }
        .onAppear {
            isVisible = true
            drafts.reloadForCurrentAccount()
            updateCaptureActivity()
            print("[StoryCamera] composer appeared active=\(isActive)")
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                showResumePrompt = drafts.hasDraft
            }
            Task {
                try? await Task.sleep(for: .seconds(4))
                await MainActor.run { withAnimation(.easeOut(duration: 0.4)) { showHoldHint = false } }
            }
        }
        .onDisappear {
            isVisible = false
            captureTask?.cancel()
            effectThumbnails.clear()
            recordArmTask?.cancel()
            camera.stop()
            print("[StoryCamera] composer disappeared")
        }
        .onChange(of: shouldCapture) { _, _ in updateCaptureActivity() }
        .onChange(of: camera.interruptionMessage) { _, message in
            guard message != nil else { return }
            recordArmTask?.cancel(); shutterPressed = false
            if isRecording { stopRecording() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                wasBackgrounded = true
                recordArmTask?.cancel()
                pressStartedAt = nil
                shutterPressed = false
                if isRecording { stopRecording() }
                camera.stop()
            } else if phase == .active {
                // Replace only the suspended preview connection, never the editor or draft.
                if wasBackgrounded {
                    wasBackgrounded = false
                    previewRevision &+= 1
                }
                updateCaptureActivity()
                print("[StoryCamera] foreground capture=\(shouldCapture)")
            }
        }
        .onChange(of: postItems) { _, items in if !items.isEmpty { postPhoto = nil } }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            guard !captureBusy else { pickerItem = nil; return }
            captureGeneration = AccountStorage.generation
            captureOperation = UUID()
            importing = true
            captureTask = Task { await handlePick(item) }
        }
    }

    private var captureAlerts: some View {
        cameraLifecycle
        .alert("Couldn't finish your capture", isPresented: Binding(get: { captureIssue != nil }, set: { if !$0 { captureIssue = nil } })) {
            Button("Try again") {
                if gridIsComplete && pendingEffectPhoto == nil && pendingEffectVideo == nil { finishGrid() }
                else { captureTask = Task { await renderPendingCapture() } }
            }
            if pendingEffectPhoto != nil || pendingEffectVideo != nil {
                Button("Use original") { captureTask = Task { await useOriginalCapture() } }
            }
            Button("Keep editing", role: .cancel) {}
        } message: { Text(captureIssue ?? "Your original capture is still available.") }
        .confirmationDialog("Discard this capture?", isPresented: $confirmCaptureDiscard, titleVisibility: .visible) {
            Button("Discard capture", role: .destructive) {
                captureOperation = UUID()
                captureTask?.cancel(); recordArmTask?.cancel(); camera.cancelRecording()
                importing = false; takingPhoto = false; recordingStartedAt = nil; finishingRecording = false
                pendingEffectVideo = nil; pendingEffectPhoto = nil
                layoutPhotos = [:]; layoutGrid = nil; backgroundImporting = false
                close()
            }
            Button("Keep editing", role: .cancel) {}
        }
        .onChange(of: locksParentNavigation, initial: true) { _, busy in onCaptureBusyChanged?(busy) }
        .onChange(of: layoutPhotos.isEmpty, initial: true) { _, empty in onLayoutDirtyChanged?(!empty) }
        .onChange(of: closeRequest) { _, _ in close() }
        .onChange(of: backgroundSetting?.url) { _, _ in effectThumbnails.clear(); effectCatalogID = UUID() }
        .onChange(of: cameraEffect) { old, new in
            if old == .cloneWall || new == .cloneWall { effectThumbnails.clear(); effectCatalogID = UUID() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            captureOperation = UUID()
            captureTask?.cancel(); camera.cancelRecording(); pendingEffectPhoto = nil; pendingEffectVideo = nil
            captured = nil; postHandoff = nil; postItems = []; postPhoto = nil
            takingPhoto = false; importing = false; recordingStartedAt = nil; finishingRecording = false
            selectedStarter = nil; showStarters = false; shownLayout = nil; pendingLayout = nil
            supplementalLayers = []; pendingTemplateEditor = false; handsFree = false
            recordArmTask?.cancel(); pressStartedAt = nil; shutterPressed = false
            layoutPhotos = [:]; layoutGrid = nil; showsWaves = false; showsLiveSetup = false
            liveSetupID = UUID(); storyTakeID = nil
            liveRoom = nil; pendingLiveRoom = nil; backgroundSetting = nil
            preparedPhoto = nil; preparedVideo = nil; preparedBackgroundURL = nil
            showsGreenScreen = false; backgroundImporting = false; showEffectBrowser = false
            isVisible = false; camera.stop()
        }
        .confirmationDialog("Discard the photos in this layout?", isPresented: $confirmLayoutReset, titleVisibility: .visible) {
            Button("Discard layout", role: .destructive) { layoutPhotos = [:]; layoutGrid = nil; showsGridChoices = false }
            Button("Keep layout", role: .cancel) {}
        }
        .confirmationDialog("Discard your post selection?", isPresented: $confirmPostDiscard, titleVisibility: .visible) {
            Button("Discard selection", role: .destructive) { postItems = []; postPhoto = nil; close() }
            Button("Keep creating", role: .cancel) {}
        }
        .interactiveDismissDisabled(captureBusy || !layoutPhotos.isEmpty || hasPostSelection)
    }

    private var cameraPresentations: some View {
        captureAlerts
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: layoutGrid == nil ? .any(of: [.images, .videos]) : .images)
        .sheet(isPresented: $showsLiveSetup, onDismiss: {
            liveSetupID = UUID()
            guard isVisible, isActive else { pendingLiveRoom = nil; return }
            if let room = pendingLiveRoom { pendingLiveRoom = nil; liveRoom = room }
        }) {
            let setupID = liveSetupID
            let generation = AccountStorage.generation
            CreateLiveRoomSheet { room in
                guard showsLiveSetup, setupID == liveSetupID, generation == AccountStorage.generation, isVisible, isActive else { return }
                if room.is_live { pendingLiveRoom = room }
                showsLiveSetup = false
            }
        }
        .fullScreenCover(item: $liveRoom) { room in WhisperLiveRoomView(room: room, isHost: true) }
        .sheet(isPresented: $showEffectBrowser) {
            WhisperCaptureEffectsBrowser(selected: cameraEffect, thumbnails: effectThumbnails) { effect in
                guard !captureBusy, isVisible, isActive else { return }
                cameraEffect = effect; showsFaceEffects = true; showEffectBrowser = false
            }
        }
        .sheet(isPresented: $showStarters, onDismiss: {
            guard isActive, isVisible else { pendingLayout = nil; pendingTemplateEditor = false; return }
            if let next = pendingLayout { pendingLayout = nil; shownLayout = next }
            else if pendingTemplateEditor { pendingTemplateEditor = false; captured = CapturedSnap(image: templateBackground()) }
        }) {
            WhisperStoryStarterSheet(onPick: { starter in
                guard !captureBusy, isActive, isVisible else { return }
                selectedStarter = starter; supplementalLayers = []
            }, photo: libraryThumb, onLayout: { layout in pendingLayout = layout }, onPersonal: { template in
                supplementalLayers = template.layers(for: 390); selectedStarter = nil; pendingTemplateEditor = true
            }, onCreate: { supplementalLayers = []; selectedStarter = nil; pendingTemplateEditor = true }, onEffect: { effect in
                cameraEffect = effect; mode = .camera; showsFaceEffects = true; effectCatalogID = UUID()
            })
        }
        .sheet(item: $shownLayout, onDismiss: {
            guard pendingTemplateEditor, isActive, isVisible else { return }
            pendingTemplateEditor = false; captured = CapturedSnap(image: templateBackground())
        }) { layout in
            WhisperStoryPhotoLayoutSheet(layout: layout, stageWidth: 390) { layers in
                supplementalLayers = layers; selectedStarter = nil; pendingTemplateEditor = true
            }
        }
        .fullScreenCover(item: $postHandoff) { handoff in
            WhisperComposerView(initialPhotos: handoff.photos, initialPhotoPickerItems: handoff.items, onPosted: {
                postItems = []; postPhoto = nil
            })
        }
        .fullScreenCover(item: $captured) { snap in
            WhisperStoryEditor(
                image: snap.image,
                videoURL: snap.videoURL,
                initialStickers: initialStickers + (selectedStarter?.stickers() ?? []) + supplementalLayers,
                initialReferenceWidth: 390,
                restoredDraft: snap.draft,
                restoredBackgroundPhoto: snap.backgroundPhoto,
                onPosted: {
                    captured = nil; layoutPhotos = [:]; layoutGrid = nil
                    close()
                }
            )
        }
    }

    private var currentFilter: SnapFilter { filters[filterIndex] }
    private var selectedEffects: WhisperStoryCaptureEffects {
        creationMode == .live || creationMode == .post ? .init() : .init(effect: cameraEffect, filter: currentFilter, background: backgroundSetting)
    }

    private var captureWorkspace: some View {
        GeometryReader { viewport in
            let layout = WhisperStoryEditorLayout(viewport: viewport.size)
            ZStack(alignment: .topLeading) {
                captureStage(size: layout.stage.size)
                    .frame(width: layout.stage.width, height: layout.stage.height)
                    .clipShape(.rect(cornerRadius: 24, style: .continuous))
                    .overlay {
                        controls(for: creationMode)
                            .opacity(showsWaves || showsPostLibrary ? 0 : 1)
                            .allowsHitTesting(!showsWaves && !showsPostLibrary)
                            .accessibilityHidden(showsWaves || showsPostLibrary)
                    }
                    .position(x: layout.stage.midX, y: layout.stage.midY)
                HStack(spacing: 0) {
                    libraryThumbButton.disabled(captureBusy || creationMode == .live)
                    Color.clear.frame(maxWidth: .infinity).frame(height: 44)
                    flipButton.opacity(showsPostLibrary ? 0 : 1).allowsHitTesting(!showsPostLibrary)
                }
                .padding(.horizontal, 12)
                .frame(width: layout.footer.width, height: layout.footer.height)
                .position(x: layout.footer.midX, y: layout.footer.midY)
                .opacity(isRecording || showsWaves ? 0 : 1)
                .allowsHitTesting(!isRecording && !showsWaves)
                .accessibilityHidden(showsWaves)
                if hasOpenedPost {
                    WhisperCapturePostLibraryView(items: $postItems, capturedPhoto: postPhoto, isActive: showsPostLibrary && isActive && isVisible,
                        onClose: close, onCamera: { postUsesCamera = true }, onClearCapture: { postPhoto = nil }, onNext: openPostSelection)
                        .frame(width: layout.stage.width, height: layout.stage.height)
                        .clipShape(.rect(cornerRadius: 24, style: .continuous))
                        .position(x: layout.stage.midX, y: layout.stage.midY)
                        .opacity(showsPostLibrary ? 1 : 0)
                        .allowsHitTesting(showsPostLibrary).accessibilityHidden(!showsPostLibrary)
                }
                if hasOpenedWaves {
                    WhisperWaveCreateFlow(onSelectCreationMode: selectCreationMode,
                        sharedCamera: camera, previewBridge: wavePreview, isActive: showsWaves && isActive && isVisible,
                        onCloseFlow: closeWaves)
                        .frame(width: viewport.size.width, height: viewport.size.height)
                        .opacity(showsWaves ? 1 : 0)
                        .allowsHitTesting(showsWaves).accessibilityHidden(!showsWaves)
                }
                WhisperCaptureModeStrip(selected: creationMode, disabled: captureBusy || shutterPressed || !layoutPhotos.isEmpty || (showsWaves && wavePreview.modeLocked), onSelect: selectCreationMode)
                    .frame(width: max(1, layout.footer.width - 152), height: 44)
                    .position(x: layout.footer.midX, y: layout.footer.midY)
                    .opacity(isRecording || (showsWaves && wavePreview.hidesModeStrip) ? 0 : 1)
                    .allowsHitTesting(!isRecording && !(showsWaves && wavePreview.hidesModeStrip))
            }.frame(width: viewport.size.width, height: viewport.size.height).clipped()
        }
    }

    @ViewBuilder private func captureStage(size: CGSize) -> some View {
        ZStack {
            WhisperCaptureGridStage(grid: creationMode == .story ? layoutGrid : nil, photos: layoutPhotos, activeCell: layoutCell, locked: captureBusy, onRetake: { index in
                guard !captureBusy else { return }
                layoutPhotos[index] = nil; layoutCell = index
            }) {
                GeometryReader { geometry in
                    let browsing = showsWaves && wavePreview.browsing
                    let height = browsing ? min(260, geometry.size.height * 0.32) : geometry.size.height
                    livePreview
                        .frame(width: browsing ? height * 9 / 16 : geometry.size.width, height: height)
                        .clipShape(.rect(cornerRadius: browsing ? 16 : 0))
                        .position(x: geometry.size.width / 2, y: browsing ? geometry.size.height * 0.2 : geometry.size.height / 2)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: browsing)
                }
                    .overlay {
                        if !camera.isAvailable || camera.isDenied {
                    Color(white: 0.14).overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle").font(.title2)
                            Text("Choose a photo below").font(.caption).multilineTextAlignment(.center)
                        }.foregroundStyle(.white).padding(8)
                    }
                        }
                    }
            }
            if mode == .type { typeCanvas.clipped() }
            else if layoutGrid == nil && !showsWaves {
                if camera.isDenied { cameraDenied }
                else if !camera.isAvailable { cameraUnavailable }
                if let selectedStarter, creationMode == .story {
                    WhisperStoryStarterPreview(starter: selectedStarter, showsBackground: false).allowsHitTesting(false)
                }
                if backgroundSetting != nil, showsGreenScreen, !captureBusy, creationMode == .story {
                    WhisperGreenScreenPositionOverlay(background: $backgroundSetting)
                }
                if camera.isRequestingPermission { cameraAsking }
            }
        }
    }

    private var livePreview: some View {
        Color.black.overlay {
            WhisperWaveLivePreview(camera: camera, configuration: showsWaves ? wavePreview.configuration : liveConfiguration,
                photo: showsWaves ? wavePreview.photo : creationMode == .story ? preparedPhoto : nil,
                video: showsWaves ? wavePreview.video : creationMode == .story ? preparedVideo : nil,
                preparedURL: showsWaves ? wavePreview.preparedURL : creationMode == .story ? preparedBackgroundURL : nil,
                onStatus: { if showsWaves { wavePreview.issue = $0 } else { effectPreviewIssue = $0 } },
                onCatalogFrame: { frame in
                    if showsWaves { wavePreview.thumbnails.prepare(frame) }
                    else { effectThumbnails.prepare(frame, effects: Self.storyEffects) }
                }, fillsFrame: layoutGrid != nil && creationMode == .story, onFrameTime: { previewTiming.elapsed = $0 }, consumerID: creationMode.rawValue)
                .id(previewRevision).allowsHitTesting(false)
        }.clipped()
    }

    private func prepareStoryBackground() async {
        preparedBackgroundURL = nil; preparedPhoto = nil; preparedVideo = nil
        guard let background = backgroundSetting else { return }
        let generation = AccountStorage.generation
        do {
            if background.media == .photo {
                let image = try await Task.detached(priority: .userInitiated) { try WhisperWaveBackgroundImporter.image(at: background.url) }.value
                guard !Task.isCancelled, generation == AccountStorage.generation, backgroundSetting?.url == background.url else { return }
                preparedPhoto = image
            } else {
                let video = try await WhisperWaveLiveVideoBackground.prepare(background.url)
                guard !Task.isCancelled, generation == AccountStorage.generation, backgroundSetting?.url == background.url else { return }
                preparedVideo = video
            }
            preparedBackgroundURL = background.url
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            effectPreviewIssue = "Couldn't prepare the background. Choose it again."
        }
    }

    private func finishGrid() {
        guard let grid = layoutGrid, !captureBusy, layoutPhotos.count == grid.cells.count else { return }
        let photos = grid.cells.indices.compactMap { layoutPhotos[$0] }
        let generation = AccountStorage.generation
        let operation = UUID(); captureOperation = operation; importing = true
        captureTask = Task {
            defer { if captureOperation == operation { importing = false } }
            do {
                let image = try await WhisperCaptureGridRenderer.render(photos, grid: grid)
                guard !Task.isCancelled, operation == captureOperation, generation == AccountStorage.generation, isVisible else { return }
                captured = CapturedSnap(image: image)
            } catch {
                guard !Task.isCancelled, operation == captureOperation else { return }
                captureIssue = "Couldn't assemble the layout. Your photos are still in the grid."
            }
        }
    }

    // MARK: - Controls

    private func controls(for page: WhisperCaptureMode) -> some View {
        VStack(spacing: 0) {
            topBar.opacity(isRecording ? 0 : 1).allowsHitTesting(!isRecording)
            Spacer(minLength: 8)
            if page == .story {
                HStack {
                    Spacer(minLength: 0)
                    ScrollView {
                        VStack(alignment: .trailing, spacing: 4) {
                            cameraTool("Create", symbol: "textformat", selected: mode == .type) {
                                guard layoutPhotos.isEmpty else { return }
                                mode = mode == .type ? .camera : .type
                            }
                            cameraTool("Layout", symbol: "rectangle.split.2x2", selected: layoutGrid != nil) {
                                mode = .camera; handsFree = false
                                if layoutGrid == nil { layoutGrid = .four; layoutCell = 0; showsGridChoices = false }
                                else if layoutPhotos.isEmpty { layoutGrid = nil; showsGridChoices = false }
                                else { confirmLayoutReset = true }
                            }
                            if layoutGrid != nil {
                                cameraTool("Change grid", symbol: "square.grid.2x2", selected: showsGridChoices) { showsGridChoices.toggle() }
                            }
                            if showsGridChoices { gridChoices }
                            if layoutGrid != nil {
                                cameraTool("Exit layout", symbol: "xmark", selected: false) {
                                    if layoutPhotos.isEmpty { layoutGrid = nil; showsGridChoices = false }
                                    else { confirmLayoutReset = true }
                                }
                            }
                            if mode == .camera, layoutGrid == nil {
                                cameraTool("Hands-free", symbol: "record.circle", selected: handsFree) { handsFree.toggle() }
                                cameraTool("Green screen", symbol: "person.and.background.dotted", selected: showsGreenScreen) { showsGreenScreen.toggle() }
                            }
                            cameraTool("Effects", symbol: "sparkles", selected: showsFaceEffects) {
                                showsFaceEffects = true; effectCatalogID = UUID(); showEffectBrowser = true
                            }
                        }.padding(.vertical, 4)
                    }.frame(maxWidth: 170, maxHeight: 290)
                }.padding(.horizontal, 12)
                    .disabled(captureBusy).opacity(isRecording ? 0 : 1).allowsHitTesting(!isRecording)
            }
            Spacer(minLength: 8)
            if page == .story, let selectedStarter, !isRecording {
                HStack(spacing: 4) {
                    Text(selectedStarter.title).font(.caption.weight(.semibold)).lineLimit(1)
                    Button { self.selectedStarter = nil } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 44, height: 44)
                    }.accessibilityLabel("Remove template")
                }
                .padding(.leading, 14).foregroundStyle(.white)
                .background(.black.opacity(0.55), in: .capsule).disabled(captureBusy)
            }
            if page == .story, mode == .camera {
                if isRecording { recordingTimer.padding(.bottom, 8) }
                else if currentFilter != .none { filterChip.padding(.bottom, 8) }
            }
            if page == .live {
                Text("Ready when you are").font(.title3.weight(.bold)).foregroundStyle(.white)
                Text("Choose a title and audience before going live.").font(.footnote).foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                Button { showsLiveSetup = true } label: {
                    Label("Set up Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline).foregroundStyle(.black).padding(.horizontal, 24).frame(height: 52)
                        .background(.white, in: .capsule)
                }.padding(.vertical, 22)
            } else if page == .post {
                Text("Take a photo for your post").font(.footnote).foregroundStyle(.white)
                Button(action: capturePhoto) {
                    Circle().fill(.white).frame(width: 68, height: 68)
                        .padding(7).overlay { Circle().strokeBorder(.white, lineWidth: 4) }
                        .frame(width: 90, height: 120)
                }.buttonStyle(.plain).accessibilityLabel("Take post photo")
                    .disabled(captureBusy || !camera.isAvailable || camera.isDenied)
            } else if mode == .camera {
                if showsGreenScreen, layoutGrid == nil {
                    WhisperGreenScreenMediaRail(background: $backgroundSetting, isImporting: $backgroundImporting, locked: captureBusy && !backgroundImporting)
                        .padding(.bottom, 4)
                }
                if let grid = layoutGrid {
                    Text(layoutPhotos.count == grid.cells.count ? "Tap the checkmark to finish · tap a cell to retake" : "Photo \(layoutPhotos.count + 1) of \(grid.cells.count)")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(8).background(.black.opacity(0.5), in: .capsule)
                }
                WhisperStoryCaptureRail(selected: $cameraEffect, thumbnails: effectThumbnails,
                    effects: Self.storyEffects, expanded: creationMode == .story && showsFaceEffects && layoutGrid == nil && !showsGreenScreen && !isRecording && !finishingRecording,
                    locked: captureBusy, onScrub: {
                        shutterScrubbed = true; recordArmTask?.cancel(); recordArmTask = nil
                        shutterPressed = false
                    }) { shutter }
                HStack(spacing: 8) {
                    if showsFaceEffects, layoutGrid == nil, !showsGreenScreen {
                        HStack(spacing: 4) {
                            Text(cameraEffect == .none ? "No effect" : cameraEffect.name)
                                .font(.footnote.weight(.medium)).lineLimit(1).frame(maxWidth: .infinity)
                            Button { cameraEffect = .none; showsFaceEffects = false } label: {
                                Image(systemName: "xmark.circle").font(.footnote).frame(width: 44, height: 44)
                            }.accessibilityLabel("Close effect selector")
                        }.padding(.leading, 14).foregroundStyle(.white)
                            .background(.ultraThinMaterial, in: .capsule).disabled(captureBusy)
                    }
                }.padding(.horizontal, 64).padding(.bottom, 8)
                    .opacity(isRecording ? 0 : 1).allowsHitTesting(!isRecording)
            } else {
                shutter.padding(.bottom, 8)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isRecording)
    }

    private var gridChoices: some View {
        LazyVGrid(columns: [GridItem(.fixed(44)), GridItem(.fixed(44))], spacing: 4) {
            ForEach(WhisperCaptureGrid.allCases) { grid in
                Button {
                    guard !captureBusy, layoutPhotos.isEmpty else { return }
                    layoutGrid = grid; layoutCell = 0; Haptics.selection()
                } label: {
                    WhisperCaptureGridGlyph(grid: grid).frame(width: 44, height: 44)
                        .background(.white.opacity(layoutGrid == grid ? 0.22 : 0), in: .rect(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityLabel(grid.title)
                    .accessibilityAddTraits(layoutGrid == grid ? .isSelected : [])
                    .disabled(!layoutPhotos.isEmpty)
            }
        }.padding(6).foregroundStyle(.white).background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
            .frame(width: 104)
    }

    private func cameraTool(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard !captureBusy else { return }
            Haptics.tap()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 10) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Image(systemName: symbol).font(.system(size: 21, weight: .regular)).frame(width: 36)
            }
            .foregroundStyle(.white).padding(.horizontal, 10).frame(minHeight: 44)
            .background(.black.opacity(selected ? 0.7 : 0.38), in: .capsule)
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func closeWaves() {
        // The recorder already resolved its take/draft decision. Keep any
        // separate Post selection reachable, including after Wave publication.
        if hasPostSelection {
            showsWaves = false; hasOpenedWaves = false
            creationMode = .post; postUsesCamera = false
        } else { close() }
    }

    private func selectCreationMode(_ next: WhisperCaptureMode) {
        guard isActive, isVisible, !captureBusy, !shutterPressed, layoutPhotos.isEmpty,
              postHandoff == nil, !showsWaves || !wavePreview.modeLocked else { return }
        recordArmTask?.cancel(); pressStartedAt = nil
        mode = .camera
        if next == .waves { hasOpenedWaves = true }
        if next == .post { hasOpenedPost = true }
        creationMode = next; showsWaves = next == .waves
        if next != .waves { camera.setTorch(shouldCapture && flashOn); effectPreviewIssue = nil }
    }

    private func modeLabel(_ label: String, value: ComposerMode) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                guard !captureBusy else { return }
                mode = value
            }
        } label: {
            VStack(spacing: 5) {
                Text(label.uppercased())
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(mode == value ? .white : .white.opacity(0.5))
                    .shadow(color: .black.opacity(0.5), radius: 4)
                Circle()
                    .fill(.white)
                    .frame(width: 4, height: 4)
                    .opacity(mode == value ? 1 : 0)
            }
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(captureBusy)
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }

    /// TYPE mode stage — a full-bleed Instagram gradient; tapping cycles
    /// the palette, the shutter renders it and opens the editor to type.
    private var typeCanvas: some View {
        ZStack {
            LinearGradient(
                colors: Self.typeGradients[typeBackgroundIndex % Self.typeGradients.count],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .contentShape(.rect)
            .onTapGesture {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.3)) {
                    typeBackgroundIndex = (typeBackgroundIndex + 1) % Self.typeGradients.count
                }
            }
            if selectedStarter == nil {
            VStack(spacing: 12) {
                Text("Aa")
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                Text("Tap to change the color · hit the\nshutter to start typing")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .allowsHitTesting(false)
            }
        }
    }

    /// Bake the current TYPE gradient into a 1080×1920 canvas the editor
    /// (and the posted story) treats exactly like a photo.
    private func templateBackground() -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 1920), format: format).image { context in
            UIColor(white: 0.09, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 1080, height: 1920))
        }
    }

    private func renderTypeBackground() -> UIImage {
        let size = CGSize(width: 1080, height: 1920)
        let colors = Self.typeGradients[typeBackgroundIndex % Self.typeGradients.count]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cgColors = colors.map { UIColor($0).cgColor } as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: cgColors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            } else {
                UIColor.black.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            WhisperStoryControl(symbol: "xmark", label: "Close camera") { close() }
            Spacer()
            if mode == .camera {
                WhisperStoryControl(symbol: flashOn ? "bolt.fill" : "bolt.slash", label: flashOn ? "Turn flash off" : "Turn flash on") {
                    flashOn.toggle(); camera.setTorch(flashOn)
                }.disabled(captureBusy)
            }
            Spacer()
            WhisperStoryControl(symbol: "square.stack", label: "Browse Story templates") { showStarters = true }
                .disabled(captureBusy || !layoutPhotos.isEmpty || creationMode != .story)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var filterChip: some View {
        Text(currentFilter.name.uppercased())
            .font(.caption.weight(.heavy))
            .tracking(2)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            .opacity(currentFilter == .none ? 0 : 1)
            .id(filterChipKick)
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: filterIndex)
    }

    /// Red dot + live seconds while a hold-to-record is running.
    private var recordingTimer: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let elapsed = recordingStartedAt.map { context.date.timeIntervalSince($0) } ?? 0
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(red: 1.0, green: 0.23, blue: 0.27))
                    .frame(width: 9, height: 9)
                    .opacity(Int(elapsed * 2) % 2 == 0 ? 1 : 0.35)
                Text(String(format: "0:%02d", Int(min(Self.maxRecordSeconds, elapsed))))
                    .font(.caption.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
        }
    }

    /// Gallery thumb · shutter · flip — the Instagram/Snapchat bottom row.
    private var bottomBar: some View {
        HStack(alignment: .center) {
            libraryThumbButton
                .opacity(isRecording ? 0 : 1)
            Spacer()
            shutter
            Spacer()
            flipButton
                .opacity(isRecording ? 0 : 1)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .overlay(alignment: .top) {
            if showHoldHint && mode == .camera && !isRecording && camera.isAvailable {
                Text(handsFree ? "Tap to start · tap again to stop" : "Tap for photo · hold for video")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 4)
                    .offset(y: -22)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    private var flipButton: some View {
        Button {
            Haptics.tap()
            effectThumbnails.clear()
            effectCatalogID = UUID()
            camera.flipCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 5)
                .frame(width: 56, height: 56)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(mode != .camera || !camera.isAvailable || captureBusy)
        .opacity(mode == .camera ? 1 : 0)
        .accessibilityLabel("Flip camera")
    }

    // MARK: - Shutter (tap = photo · hold = video)

    private var shutter: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isRecording)) { context in
            let elapsed = recordingStartedAt.map { context.date.timeIntervalSince($0) } ?? 0
            let progress = min(1, elapsed / Self.maxRecordSeconds)
            ZStack {
                // Outer ring — white idle, grows + dims into the track for
                // the red progress arc while recording (Snapchat's ring).
                Circle()
                    .strokeBorder(.white.opacity(isRecording ? 0.35 : 1), lineWidth: isRecording ? 6 : 5)
                    .frame(width: isRecording ? 112 : 86, height: isRecording ? 112 : 86)
                if isRecording {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color(red: 1.0, green: 0.23, blue: 0.27),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 106, height: 106)
                }
                if finishingRecording {
                    // The file is being finalized — keep the button alive
                    // with a spinning arc instead of snapping back to idle
                    // and looking like nothing happened.
                    ShutterFinalizingArc()
                        .frame(width: 106, height: 106)
                }
                if let grid = layoutGrid {
                    Circle().fill(.white).frame(width: 68, height: 68)
                    if layoutPhotos.count == grid.cells.count {
                        Image(systemName: "checkmark").font(.system(size: 29, weight: .semibold)).foregroundStyle(.black)
                    } else { WhisperCaptureGridGlyph(grid: grid).foregroundStyle(.black) }
                } else if mode == .camera, showsFaceEffects, cameraEffect != .none, !isRecording, !finishingRecording {
                    WhisperWaveEffectTile(effect: cameraEffect, image: effectThumbnails.images[cameraEffect.id], size: 68)
                        .allowsHitTesting(false)
                } else {
                    Circle()
                        .fill(isRecording ? Color(red: 1.0, green: 0.23, blue: 0.27) : .white)
                        .frame(width: isRecording ? 54 : 68, height: isRecording ? 54 : 68)
                        .opacity(finishingRecording ? 0.6 : 1)
                }
            }
            .frame(width: isRecording ? 120 : 90, height: 120)
            .contentShape(Circle())
            // Instant answer to the touch: the whole control squashes the
            // moment a finger lands, before the hold has decided anything.
            .scaleEffect(shutterPressed && !isRecording ? 0.9 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: shutterPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isRecording)
            .animation(.easeOut(duration: 0.2), value: finishingRecording)
            .onChange(of: progress >= 1) { _, hitCap in
                if hitCap && isRecording { stopRecording() }
            }
        }
        .gesture(shutterGesture)
        .disabled((!gridIsComplete && mode == .camera && (!camera.isAvailable || camera.isDenied || camera.isRequestingPermission)) || finishingRecording || importing || takingPhoto || backgroundImporting)
        .accessibilityLabel(gridIsComplete ? "Finish layout" : isRecording ? "Stop recording" : handsFree ? "Start recording" : "Take photo")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard !finishingRecording else { return }
            if isRecording { stopRecording() } else if handsFree && mode == .camera { startRecording() } else { capturePhoto() }
        }
        .accessibilityAction(named: "Start video recording") {
            guard mode == .camera, camera.isAvailable, !isRecording, !finishingRecording else { return }
            startRecording()
        }
    }

    /// One drag gesture with zero distance drives both behaviours: the first
    /// touch arms a short timer — release before it fires = photo; if it
    /// fires we start recording, dragging UP zooms (Snapchat), and lifting
    /// the finger stops. No gesture composition, no double-fires.
    private var shutterGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if pressStartedAt == nil {
                    shutterScrubbed = false
                    pressStartedAt = Date()
                    shutterPressed = true
                    guard mode == .camera, camera.isAvailable, !handsFree, layoutGrid == nil, creationMode == .story, !captureBusy else { return }
                    recordArmTask?.cancel()
                    recordArmTask = Task {
                        // 240ms: long enough to tell a tap from a hold,
                        // short enough that the ring answers the hold
                        // before the finger notices the wait.
                        try? await Task.sleep(for: .milliseconds(240))
                        guard !Task.isCancelled else { return }
                        await MainActor.run { startRecording() }
                    }
                } else if showsFaceEffects, !isRecording, abs(value.translation.width) > 12,
                          abs(value.translation.width) > abs(value.translation.height) * 1.2 {
                    shutterScrubbed = true; recordArmTask?.cancel(); recordArmTask = nil; shutterPressed = false
                } else if isRecording {
                    // Drag up to zoom — 220pt of travel spans the zoom range.
                    let lift = max(0, -value.translation.height)
                    let z = 1 + min(4, lift / 55)
                    if abs(z - holdZoom) > 0.015 {
                        holdZoom = z
                        camera.setZoom(z)
                    }
                }
            }
            .onEnded { _ in
                recordArmTask?.cancel()
                recordArmTask = nil
                shutterPressed = false
                let wasRecording = isRecording
                pressStartedAt = nil
                if wasRecording { stopRecording() }
                else if shutterScrubbed { return }
                else if handsFree && mode == .camera && layoutGrid == nil { startRecording() }
                else { capturePhoto() }
            }
    }

    private func capturePhoto() {
        guard isVisible, isActive, scenePhase == .active, captured == nil else { return }
        guard !captureBusy else { return }
        if creationMode == .live { showsLiveSetup = true; return }
        if creationMode == .story, let grid = layoutGrid, layoutPhotos.count == grid.cells.count { finishGrid(); return }
        Haptics.tap()
        if mode == .type {
            captured = CapturedSnap(image: renderTypeBackground())
            return
        }
        guard camera.isAvailable else { return }
        guard !captureBusy, creationMode == .post || (effectPreviewIssue == nil &&
              (backgroundSetting == nil || preparedBackgroundURL == backgroundSetting?.url)) else { return }
        takingPhoto = true
        let operation = UUID(); captureOperation = operation
        captureGeneration = AccountStorage.generation
        recordingEffects = selectedEffects
        if creationMode == .post { recordingEffects.cameraFraming = false }
        recordingEffects.photoTime = previewTiming.elapsed
        if recordingEffects.background?.media == .video { recordingEffects.background?.startTime += previewTiming.elapsed }
        camera.capturePhoto(filter: .none, mirrored: camera.position == .front) { img in
            guard operation == captureOperation else { return }
            takingPhoto = false
            guard let img, isVisible, captured == nil, captureGeneration == AccountStorage.generation else { return }
            pendingEffectPhoto = img
            captureTask = Task { await renderPendingCapture() }
        }
    }

    private func startRecording() {
        guard shouldCapture, creationMode == .story, layoutGrid == nil, !captureBusy, effectPreviewIssue == nil, camera.isAvailable,
              backgroundSetting == nil || preparedBackgroundURL == backgroundSetting?.url else { return }
        captureGeneration = AccountStorage.generation
        let operation = UUID(); captureOperation = operation
        // A light impact (not the heavy success buzz) — the ring turning red
        // is the confirmation; the haptic just marks the moment.
        Haptics.tap()
        holdZoom = 1
        recordingEffects = selectedEffects
        storyTakeID = UUID()
        recordingStartedAt = Date()
        camera.startRecording { url in
            guard operation == captureOperation else { return }
            captureTask = Task { @MainActor in await handleRecorded(url) }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        let elapsed = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil
        finishingRecording = true
        camera.setZoom(1)
        holdZoom = 1
        Haptics.tap()
        // A sub-half-second hold reads as a fumbled tap — discard it and
        // take the photo the user probably wanted.
        if elapsed < 0.5 && !handsFree {
            camera.cancelRecording()
            finishingRecording = false
            capturePhoto()
            return
        }
        camera.stopRecording()
        // Safety net: if the movie delegate never calls back (disk full,
        // session torn down mid-write) the shutter must not stay locked.
        Task {
            try? await Task.sleep(for: .seconds(6))
            await MainActor.run {
                if finishingRecording && captured == nil { finishingRecording = false }
            }
        }
    }

    private func handleRecorded(_ url: URL?) async {
        recordingStartedAt = nil
        shutterPressed = false
        defer { finishingRecording = false; storyTakeID = nil }
        guard let url else { return }
        guard captureGeneration == AccountStorage.generation, isVisible, captured == nil else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        pendingEffectVideo = url
        await renderPendingCapture()
    }

    private func useOriginalCapture() async {
        guard captureGeneration == AccountStorage.generation, !importing else { return }
        let operation = captureOperation
        let generation = captureGeneration
        importing = true
        defer { if operation == captureOperation { importing = false } }
        let snap: CapturedSnap
        if let video = pendingEffectVideo, let poster = await WhisperStoryPoster.firstFrame(of: video) {
            snap = CapturedSnap(image: poster, videoURL: video)
        } else if let photo = pendingEffectPhoto { snap = CapturedSnap(image: photo) }
        else { captureIssue = "Couldn't read the original capture. Please try again."; return }
        guard !Task.isCancelled, operation == captureOperation, generation == AccountStorage.generation, isVisible else { return }
        pendingEffectVideo = nil; pendingEffectPhoto = nil
        acceptCapture(snap)
    }

    private func openPostSelection() {
        guard isActive, isVisible, creationMode == .post, !captureBusy, postHandoff == nil else { return }
        if let postPhoto {
            guard let data = postPhoto.jpegData(compressionQuality: 0.94) else { captureIssue = "Couldn't prepare your post photo. Your capture is still available."; return }
            postHandoff = WhisperCapturePostHandoff(photos: [data], items: [])
        } else if !postItems.isEmpty {
            postHandoff = WhisperCapturePostHandoff(photos: [], items: postItems)
        }
    }

    private func acceptCapture(_ snap: CapturedSnap) {
        if creationMode == .post {
            postItems = []; postPhoto = snap.image; postUsesCamera = false; hasOpenedPost = true
        } else if let grid = layoutGrid, snap.videoURL == nil {
            layoutPhotos[layoutCell] = snap.image
            layoutCell = grid.cells.indices.first(where: { layoutPhotos[$0] == nil }) ?? layoutCell
            Haptics.success()
        } else { captured = snap }
    }

    private func renderPendingCapture() async {
        guard !importing else { return }
        importing = true; captureIssue = nil
        let generation = captureGeneration
        let operation = captureOperation
        guard generation == AccountStorage.generation else { importing = false; return }
        defer { if operation == captureOperation { importing = false } }
        do {
            let snap: CapturedSnap
            if let source = pendingEffectVideo {
                let output = try await recordingEffects.video(source)
                guard let poster = await WhisperStoryPoster.firstFrame(of: output) else {
                    try? FileManager.default.removeItem(at: output)
                    throw CocoaError(.fileReadCorruptFile)
                }
                guard !Task.isCancelled, operation == captureOperation, generation == AccountStorage.generation, isVisible, captured == nil else {
                    try? FileManager.default.removeItem(at: output); return
                }
                snap = CapturedSnap(image: poster, videoURL: output)
            } else if let source = pendingEffectPhoto {
                snap = CapturedSnap(image: try await recordingEffects.photo(source))
            } else { return }
            guard !Task.isCancelled, operation == captureOperation, generation == AccountStorage.generation, isVisible, captured == nil else { return }
            pendingEffectVideo = nil; pendingEffectPhoto = nil
            acceptCapture(snap)
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            captureIssue = "Your capture is safe. We couldn't apply the effects. Tap Try again."
        }
    }

    private var libraryThumbButton: some View {
        Button {
            guard !captureBusy else { return }
            Haptics.tap()
            if creationMode == .post { postUsesCamera = false; hasOpenedPost = true }
            else { showPicker = true }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.12))
                if let thumb = libraryThumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .allowsHitTesting(false)
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Upload from library")
    }

    private func roundButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gestures

    private var filterSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard !isRecording else { return }
                let dx = value.translation.width
                guard abs(dx) > 40, abs(dx) > abs(value.translation.height) else { return }
                let delta = dx < 0 ? 1 : -1
                let newIndex = (filterIndex + delta + filters.count) % filters.count
                Haptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    filterIndex = newIndex
                    filterChipKick &+= 1
                }
            }
    }

    // MARK: - Library

    private func prepare() async {
        await loadLatestThumbnail()
    }

    private func loadLatestThumbnail() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        // A decorative thumbnail must not compete with the camera permission alert.
        // PhotosPicker imports without requesting access to the entire library.
        guard status == .authorized || status == .limited else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        let result = PHAsset.fetchAssets(with: options)
        guard let asset = result.firstObject else { return }
        let target = CGSize(width: 200, height: 200)
        let req = PHImageRequestOptions()
        req.deliveryMode = .highQualityFormat
        req.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFill,
            options: req
        ) { img, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if degraded { return }
            Task { @MainActor in self.libraryThumb = img }
        }
    }

    private func handlePick(_ item: PhotosPickerItem) async {
        let operation = captureOperation
        importing = true
        recordingEffects = selectedEffects
        recordingEffects.cameraFraming = layoutGrid != nil
        recordingEffects.background = nil
        defer { if operation == captureOperation { pickerItem = nil; importing = false } }
        let isMovie = item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }
        if isMovie {
            guard let movie = try? await item.loadTransferable(type: WhisperPickedMovie.self) else { return }
            guard !Task.isCancelled, operation == captureOperation, captureGeneration == AccountStorage.generation else { return }
            pendingEffectVideo = movie.url
            importing = false
            await renderPendingCapture()
            return
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        guard !Task.isCancelled, operation == captureOperation, captureGeneration == AccountStorage.generation else { return }
        pendingEffectPhoto = img
        importing = false
        await renderPendingCapture()
    }

    // MARK: - Cloud simulator fallback

    /// Camera permission refused — say so and offer the way to Settings
    /// (the ✕ in the top bar still closes the composer).
    private var cameraDenied: some View {
        VStack(spacing: 14) {
            Image(systemName: camera.isRestricted ? "lock.circle" : "camera.badge.ellipsis")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text(camera.isRestricted ? "Camera access is restricted" : "Allow camera access")
                .font(.headline)
                .foregroundStyle(.white)
            Text(camera.isRestricted
                 ? "Screen Time or a device policy is blocking the camera for Whisper. You can still post from your library below."
                 : "Whisper needs the camera to shoot stories. Turn it on in Settings › Whisper › Camera, then come back — the stage picks it up on its own. You can still post from your library below.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 10) {
                if !camera.isRestricted {
                    Button {
                        Haptics.tap()
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open Settings")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    Haptics.tap()
                    camera.recheckAuthorization()
                } label: {
                    Text("Try again")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().stroke(.white.opacity(0.7), lineWidth: 1.2))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The system permission alert is showing — the stage explains the wait.
    private var cameraAsking: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.75))
            Text("Tap Allow to use the camera")
                .font(.headline)
                .foregroundStyle(.white)
            Text("iOS is asking for camera access right now.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85).ignoresSafeArea())
    }

    private var cameraUnavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text("Camera unavailable")
                .font(.headline)
                .foregroundStyle(.white)
            Text("No camera is connected right now. Install this app on your device via the Rork App to use the camera, or upload a photo or video from your library below.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Haptics.tap()
                camera.retryDiscovery()
            } label: {
                Text("Try again")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Resume draft banner

extension WhisperStoryComposerView {
    fileprivate var resumeDraftBanner: some View {
        VStack {
            HStack(spacing: 12) {
                if let img = drafts.loadDraftImage() {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(.rect(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume your story?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("You left a draft \(relativeSavedAt)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    if let img = drafts.loadDraftImage() {
                        captured = CapturedSnap(image: img, videoURL: drafts.videoURL, draft: drafts.draft, backgroundPhoto: drafts.loadBackgroundPhoto())
                    }
                    withAnimation(.spring(response: 0.3)) { showResumePrompt = false }
                } label: {
                    Text("Resume")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.tap()
                    drafts.clear()
                    withAnimation(.spring(response: 0.3)) { showResumePrompt = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .padding(.horizontal, 14)
            .padding(.top, 60)
            Spacer()
        }
    }

    fileprivate var relativeSavedAt: String {
        guard let saved = drafts.draft?.savedAt else { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: saved, relativeTo: Date())
    }
}

// MARK: - Captured snap wrapper

struct CapturedSnap: Identifiable {
    let id = UUID()
    let image: UIImage
    /// Non-nil for hold-to-record / imported video stories; `image` is the
    /// poster frame in that case.
    var videoURL: URL? = nil
    var draft: WhisperStoryDraftService.Draft? = nil
    var backgroundPhoto: UIImage? = nil
}

/// A movie picked from the Photos library, copied into a temp file so
/// AVFoundation can read it after the picker's security scope closes.
struct WhisperPickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("whisper-picked-\(UUID().uuidString).\(ext)")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

// MARK: - Snap filters

/// The camera looks — Whisper's OWN signature filters first (multi-stage Core
/// Image chains: Ghost · Ember · Pop · Film · Dream · Frost · Midnight · VHS),
/// then the classic single-effect looks. One `process` pipeline serves the
/// story camera's stills AND the wave studio's video bake, so a look picked
/// on the viewfinder is exactly what publishes.
enum SnapFilter: Hashable, CaseIterable {
    case none
    case ghost, ember, pop, film, dream, frost, midnight, vhs
    case mono, noir, fade, instant, transfer, chrome, vivid, process

    static let all: [SnapFilter] = [
        .none, .ghost, .ember, .pop, .film, .dream, .frost, .midnight, .vhs,
        .vivid, .mono, .noir, .fade, .instant, .transfer, .chrome, .process
    ]

    var name: String {
        switch self {
        case .none: return "Original"
        case .ghost: return "Ghost"
        case .ember: return "Ember"
        case .pop: return "Pop"
        case .film: return "Film"
        case .dream: return "Dream"
        case .frost: return "Frost"
        case .midnight: return "Midnight"
        case .vhs: return "VHS"
        case .mono: return "Mono"
        case .noir: return "Noir"
        case .fade: return "Fade"
        case .instant: return "Instant"
        case .transfer: return "Sepia"
        case .chrome: return "Chrome"
        case .vivid: return "Vivid"
        case .process: return "Process"
        }
    }

    /// Core Image filter name for the single-effect looks; nil for Original
    /// and for the Whisper chains (those run through `process`). Nonisolated
    /// so the video bake can read it off the main actor.
    nonisolated var ciFilterName: String? {
        switch self {
        case .none, .ghost, .ember, .pop, .film, .dream, .frost, .midnight, .vhs: return nil
        case .mono: return "CIPhotoEffectMono"
        case .noir: return "CIPhotoEffectNoir"
        case .fade: return "CIPhotoEffectFade"
        case .instant: return "CIPhotoEffectInstant"
        case .transfer: return "CIPhotoEffectTransfer"
        case .chrome: return "CIPhotoEffectChrome"
        case .vivid: return "CIPhotoEffectProcess"
        case .process: return "CIPhotoEffectTonal"
        }
    }

    /// Swatch colors for the Effects tray circle.
    var swatch: [Color] {
        switch self {
        case .none: return [Color(white: 0.30), Color(white: 0.12)]
        case .ghost: return [Color(red: 0.61, green: 0.91, blue: 0.77), Color(red: 0.05, green: 0.62, blue: 0.46)]
        case .ember: return [Color(red: 1.0, green: 0.62, blue: 0.30), Color(red: 0.85, green: 0.25, blue: 0.12)]
        case .pop: return [Color(red: 1.0, green: 0.85, blue: 0.20), Color(red: 0.98, green: 0.30, blue: 0.55)]
        case .film: return [Color(red: 0.86, green: 0.78, blue: 0.62), Color(red: 0.45, green: 0.36, blue: 0.30)]
        case .dream: return [Color(red: 0.98, green: 0.82, blue: 0.92), Color(red: 0.62, green: 0.60, blue: 0.95)]
        case .frost: return [Color(red: 0.85, green: 0.95, blue: 1.0), Color(red: 0.45, green: 0.65, blue: 0.90)]
        case .midnight: return [Color(red: 0.20, green: 0.25, blue: 0.55), Color(red: 0.03, green: 0.04, blue: 0.12)]
        case .vhs: return [Color(red: 0.95, green: 0.35, blue: 0.75), Color(red: 0.25, green: 0.80, blue: 0.90)]
        case .mono, .noir, .process: return [Color(white: 0.85), Color(white: 0.15)]
        case .fade: return [Color(white: 0.95), Color(white: 0.6)]
        case .instant, .transfer: return [Color(red: 0.95, green: 0.75, blue: 0.45), Color(red: 0.55, green: 0.35, blue: 0.20)]
        case .chrome: return [Color(red: 0.75, green: 0.95, blue: 1.0), Color(red: 0.30, green: 0.55, blue: 0.70)]
        case .vivid: return [Color(red: 1.0, green: 0.55, blue: 0.20), Color(red: 0.90, green: 0.15, blue: 0.40)]
        }
    }

    /// Subtle live preview hint so the camera feed at least shifts mood
    /// as the user swipes — the real Core Image pass is applied at capture.
    @ViewBuilder
    var previewOverlay: some View {
        switch self {
        case .none:
            Color.clear
        case .ghost:
            ZStack {
                Color(red: 0.61, green: 0.91, blue: 0.77).opacity(0.16).blendMode(.overlay)
                Color(red: 0.05, green: 0.40, blue: 0.35).opacity(0.10)
                RadialGradient(colors: [.clear, .black.opacity(0.35)], center: .center, startRadius: 120, endRadius: 520)
            }
        case .ember:
            ZStack {
                Color(red: 1.0, green: 0.55, blue: 0.20).opacity(0.18).blendMode(.overlay)
                Color(red: 0.9, green: 0.35, blue: 0.10).opacity(0.08)
                RadialGradient(colors: [.clear, .black.opacity(0.30)], center: .center, startRadius: 140, endRadius: 520)
            }
        case .pop:
            Color(red: 1.0, green: 0.2, blue: 0.5).opacity(0.14).blendMode(.saturation)
        case .film:
            ZStack {
                Color(red: 0.55, green: 0.42, blue: 0.30).opacity(0.14)
                Color.white.opacity(0.08)
                RadialGradient(colors: [.clear, .black.opacity(0.32)], center: .center, startRadius: 120, endRadius: 500)
            }
        case .dream:
            ZStack {
                Color.white.opacity(0.12).blendMode(.softLight)
                Color(red: 0.85, green: 0.70, blue: 0.95).opacity(0.10)
            }
        case .frost:
            ZStack {
                Color(red: 0.70, green: 0.85, blue: 1.0).opacity(0.14)
                Color.white.opacity(0.10)
            }
        case .midnight:
            ZStack {
                Color(red: 0.10, green: 0.15, blue: 0.45).opacity(0.26).blendMode(.multiply)
                Color.black.opacity(0.12)
                RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 100, endRadius: 520)
            }
        case .vhs:
            ZStack {
                LinearGradient(colors: [Color(red: 0.95, green: 0.35, blue: 0.75).opacity(0.10), Color(red: 0.25, green: 0.80, blue: 0.90).opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.clear, .black.opacity(0.40)], center: .center, startRadius: 120, endRadius: 500)
            }
        case .mono, .noir, .process:
            Color.black.opacity(0.18).blendMode(.saturation)
        case .fade:
            Color.white.opacity(0.10)
        case .instant, .transfer:
            LinearGradient(
                colors: [Color.orange.opacity(0.18), Color.brown.opacity(0.12)],
                startPoint: .top, endPoint: .bottom
            )
        case .chrome:
            Color.cyan.opacity(0.08)
        case .vivid:
            Color.orange.opacity(0.06).blendMode(.overlay)
        }
    }

    /// The real look: runs the Core Image pipeline for this filter on any
    /// image (a still or one video frame). Output is cropped back to the
    /// input extent so bloom/vignette stages can't grow the frame.
    nonisolated func process(_ input: CIImage) -> CIImage {
        let extent = input.extent
        var image = input
        switch self {
        case .none:
            return input
        case .ghost:
            image = Self.colorControls(image, saturation: 0.84, brightness: 0.02, contrast: 1.06)
            image = Self.temperature(image, kelvin: 5600)
            image = Self.tintChannels(image, r: 0.97, g: 1.03, b: 1.0)
            image = Self.vignette(image, intensity: 0.7, radius: 1.7)
        case .ember:
            image = Self.temperature(image, kelvin: 8200)
            image = Self.colorControls(image, saturation: 1.12, brightness: 0.0, contrast: 1.05)
            image = Self.tintChannels(image, r: 1.04, g: 0.99, b: 0.94)
            image = Self.vignette(image, intensity: 0.6, radius: 1.6)
        case .pop:
            image = Self.vibrance(image, amount: 0.6)
            image = Self.colorControls(image, saturation: 1.15, brightness: 0.01, contrast: 1.10)
        case .film:
            image = Self.named("CIPhotoEffectFade", image)
            image = Self.sepia(image, intensity: 0.18)
            image = Self.colorControls(image, saturation: 1.0, brightness: 0.0, contrast: 0.97)
            image = Self.vignette(image, intensity: 0.55, radius: 1.9)
        case .dream:
            image = Self.bloom(image, intensity: 0.45, radius: 12)
            image = Self.colorControls(image, saturation: 0.92, brightness: 0.03, contrast: 0.98)
            image = Self.highlightShadow(image, highlight: 0.9, shadow: 0.25)
        case .frost:
            image = Self.exposure(image, ev: 0.25)
            image = Self.temperature(image, kelvin: 5200)
            image = Self.colorControls(image, saturation: 0.78, brightness: 0.0, contrast: 1.02)
        case .midnight:
            image = Self.colorControls(image, saturation: 0.9, brightness: -0.06, contrast: 1.16)
            image = Self.temperature(image, kelvin: 5000)
            image = Self.tintChannels(image, r: 0.94, g: 0.97, b: 1.08)
            image = Self.vignette(image, intensity: 0.95, radius: 1.5)
        case .vhs:
            image = Self.colorControls(image, saturation: 1.28, brightness: 0.04, contrast: 0.92)
            image = Self.tintChannels(image, r: 1.03, g: 0.98, b: 1.04)
            image = Self.vignette(image, intensity: 1.0, radius: 1.35)
        case .mono, .noir, .fade, .instant, .transfer, .chrome, .vivid, .process:
            if let name = ciFilterName { image = Self.named(name, image) }
        }
        return image.cropped(to: extent)
    }

    nonisolated func apply(to image: UIImage) -> UIImage? {
        guard self != .none, let cg = image.cgImage else { return image }
        let output = process(CIImage(cgImage: cg))
        guard let cgOut = CIContext().createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: cgOut, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: Core Image stages

    nonisolated private static func named(_ name: String, _ image: CIImage) -> CIImage {
        guard let f = CIFilter(name: name) else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        return f.outputImage ?? image
    }

    nonisolated private static func colorControls(_ image: CIImage, saturation: Double, brightness: Double, contrast: Double) -> CIImage {
        guard let f = CIFilter(name: "CIColorControls") else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(saturation, forKey: kCIInputSaturationKey)
        f.setValue(brightness, forKey: kCIInputBrightnessKey)
        f.setValue(contrast, forKey: kCIInputContrastKey)
        return f.outputImage ?? image
    }

    /// Shifts the white point: above 6500K warms the image, below cools it.
    nonisolated private static func temperature(_ image: CIImage, kelvin: Double) -> CIImage {
        guard let f = CIFilter(name: "CITemperatureAndTint") else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
        f.setValue(CIVector(x: CGFloat(kelvin), y: 0), forKey: "inputTargetNeutral")
        return f.outputImage ?? image
    }

    nonisolated private static func tintChannels(_ image: CIImage, r: Double, g: Double, b: Double) -> CIImage {
        guard let f = CIFilter(name: "CIColorMatrix") else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(CIVector(x: CGFloat(r), y: 0, z: 0, w: 0), forKey: "inputRVector")
        f.setValue(CIVector(x: 0, y: CGFloat(g), z: 0, w: 0), forKey: "inputGVector")
        f.setValue(CIVector(x: 0, y: 0, z: CGFloat(b), w: 0), forKey: "inputBVector")
        return f.outputImage ?? image
    }

    nonisolated private static func vignette(_ image: CIImage, intensity: Double, radius: Double) -> CIImage {
        guard let f = CIFilter(name: "CIVignette") else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(intensity, forKey: kCIInputIntensityKey)
        f.setValue(radius, forKey: kCIInputRadiusKey)
        return f.outputImage ?? image
    }

    nonisolated private static func vibrance(_ image: CIImage, amount: Double) -> CIImage {
        guard let f = CIFilter(name: "CIVibrance") else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(amount, forKey: "inputAmount")
        return f.outputImage ?? image
    }

    nonisolated private static func sepia(_ image: CIImage, intensity: Double) -> CIImage {
        guard let f = CIFilter(name: "CISepiaTone") else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(intensity, forKey: kCIInputIntensityKey)
        return f.outputImage ?? image
    }

    nonisolated private static func bloom(_ image: CIImage, intensity: Double, radius: Double) -> CIImage {
        guard let f = CIFilter(name: "CIBloom") else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(intensity, forKey: kCIInputIntensityKey)
        f.setValue(radius, forKey: kCIInputRadiusKey)
        return f.outputImage ?? image
    }

    nonisolated private static func highlightShadow(_ image: CIImage, highlight: Double, shadow: Double) -> CIImage {
        guard let f = CIFilter(name: "CIHighlightShadowAdjust") else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(highlight, forKey: "inputHighlightAmount")
        f.setValue(shadow, forKey: "inputShadowAmount")
        return f.outputImage ?? image
    }

    nonisolated private static func exposure(_ image: CIImage, ev: Double) -> CIImage {
        guard let f = CIFilter(name: "CIExposureAdjust") else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(ev, forKey: kCIInputEVKey)
        return f.outputImage ?? image
    }

    nonisolated static func blackImage() -> UIImage? {
        let size = CGSize(width: 1080, height: 1920)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Camera session

/// A trivially cheap box the composer keeps in `@State`; the real session is
/// built once, on first use, so constructing the view costs nothing.
final class SnapCameraHolder {
    lazy var session = SnapCameraSession(wavePortrait: true)
    init() {}
}

/// One AVCaptureSession that shoots photos AND records movie segments.
/// `.hd1920x1080` (falls back to `.high`) so a single format serves both
/// outputs — stills land at 1080×1920 portrait, exactly the story canvas.
@Observable
final class SnapCameraSession {
    nonisolated let session = AVCaptureSession()
    /// Optimistic until discovery runs — ON THE SESSION QUEUE, never on the
    /// main thread (device enumeration can stall for hundreds of ms on some
    /// hardware and the cloud simulator's external-camera plumbing).
    var isAvailable: Bool = true
    /// Camera permission was refused — the composer shows the Settings door.
    var isDenied: Bool = false
    /// Refused by POLICY (Screen Time / MDM), not by the user — Settings can't fix it.
    var isRestricted: Bool = false
    /// The system permission alert is up right now — the stage says so instead
    /// of sitting black behind the alert.
    var isRequestingPermission: Bool = false
    var position: AVCaptureDevice.Position = .back
    var interruptionMessage: String?
    var recordingWithoutAudio: Bool = false
    var isRequestingMicrophonePermission: Bool = false
    private var recordingPreparation: Task<Void, Never>?
    nonisolated(unsafe) private var queueCallOwnsAudio: Bool = false
    /// A configure() is mid-flight (awaiting the permission alert) — a second
    /// call must not start a parallel graph build.
    private var isConfiguring: Bool = false
    private var wantsCapture: Bool = false
    /// Accessed only on sessionQueue; delayed watchdogs must not revive a closed camera.
    nonisolated(unsafe) private var queueWantsCapture: Bool = false

    /// The camera for `position` — the built-in wide lens first, and when a
    /// device has none (the cloud simulator injects the webcam as an EXTERNAL
    /// camera) the first external video device.
    nonisolated static func discoverVideoDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let builtIn = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return builtIn
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.first
    }

    private let sessionQueue = DispatchQueue(label: "whisper.snap.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    /// Live frames for the AR effects viewfinder (iOS 16+ lets a video-data
    /// output run alongside the movie output). The tap is free when no
    /// effect is active.
    nonisolated private let videoDataOutput = AVCaptureVideoDataOutput()
    nonisolated private let videoDataQueue = DispatchQueue(label: "whisper.snap.camera.frames", qos: .userInitiated)
    nonisolated let frameTap = WhisperARFrameTap()
    private var activeDelegate: SnapPhotoCaptureDelegate?
    private var movieDelegate: SnapMovieRecordingDelegate?
    private var movieAttempt: UUID?
    private var configured: Bool = false
    /// One full rebuild is allowed per session life — enough to recover from a
    /// camera briefly held by a torn-down session or a just-ended call.
    private var rebuildAttempted: Bool = false
    nonisolated(unsafe) private var activeDevice: AVCaptureDevice?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    nonisolated private let wavePortrait: Bool
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var captureOrientation: WhisperCameraFrameOrientation?
    nonisolated(unsafe) private var orientationReady: Bool = false

    init(wavePortrait: Bool = false) {
        self.wavePortrait = wavePortrait
        // A runtime error (the device vanished mid-graph) or the END of an
        // interruption (a call, another capture session, backgrounding) used
        // to leave the preview black until the composer was rebuilt — which
        // in practice meant "until I logged out and back in". Both now bring
        // the session back up on their own.
        let center = NotificationCenter.default
        _ = WhisperCameraCallMonitor.shared
        observers.append(center.addObserver(forName: WhisperCameraCallMonitor.changed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshCallAudioOwnership() }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.interruptionMessage = "Camera is temporarily in use. Your work is safe; it will resume when available."
                self.stopRecording()
                if reason == AVCaptureSession.InterruptionReason.audioDeviceInUseByAnotherClient.rawValue {
                    self.releaseCaptureAudio()
                }
            }
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildOnce() }
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.interruptionMessage = nil
                self?.resumeIfStopped()
            }
        })
        // THE COLD-LAUNCH ROOT CAUSE: on the cloud simulator the webcam is an
        // EXTERNAL camera that attaches to the device a beat AFTER the app
        // launches — discovery at first swipe found nothing, `isAvailable`
        // flipped false, and the stage stayed "Camera unavailable" until the
        // composer was rebuilt (in practice: log out and back in). A camera
        // that connects later now re-runs discovery and brings the graph up.
        observers.append(center.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let device = note.object as? AVCaptureDevice, device.hasMediaType(.video) else { return }
            Task { @MainActor [weak self] in self?.retryDiscoveryIfUnavailable() }
        })
        // THE PERMISSION-ON-RETURN ROOT CAUSE: a denial was terminal for the
        // life of the session. Flip the camera toggle in Settings and come
        // back (the simulator does NOT relaunch the app for that, and neither
        // does a real phone every time) and the stage still said "Allow camera
        // access" — only a relaunch ("refresh") re-read the status, and a
        // relaunch mid-alert could leave it denied again. Every return to the
        // foreground re-reads the authorization and rebuilds when it changed.
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.wantsCapture else { return }
                self.configure()
            }
        })
    }

    private func refreshCallAudioOwnership() {
        let callActive = WhisperCameraCallMonitor.shared.callOwnsAudio
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.queueCallOwnsAudio = callActive
            if callActive {
                if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
                else { self.removeAudioInput() }
            }
        }
    }

    nonisolated private func removeAudioInput() {
        session.beginConfiguration()
        for input in session.inputs where (input as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true {
            session.removeInput(input)
        }
        session.automaticallyConfiguresApplicationAudioSession = false
        session.commitConfiguration()
    }

    private func releaseCaptureAudio() {
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else { return }
            self.removeAudioInput()
        }
    }

    /// Re-reads the camera authorization. A session parked on "denied" that is
    /// now authorized rebuilds its graph; an authorized session that lost
    /// access parks itself honestly.
    func recheckAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("[StoryCamera] recheck auth status=\(status.rawValue) denied=\(isDenied) configured=\(configured)")
        if isDenied && status == .authorized {
            isDenied = false
            isRestricted = false
            configured = false
            rebuildAttempted = false
            configure()
        } else if !isDenied && (status == .denied || status == .restricted) && !isConfiguring {
            isRestricted = status == .restricted
            isDenied = true
            stop()
        }
    }

    /// Discovery said "no camera" — a manual retry from the empty state.
    func retryDiscovery() {
        isAvailable = false
        retryDiscoveryIfUnavailable()
    }

    /// Discovery said "no camera" — try again (a device just connected, the
    /// composer re-appeared, or a backoff timer fired).
    private func retryDiscoveryIfUnavailable() {
        guard wantsCapture, !isAvailable, !isDenied else { return }
        isAvailable = true
        configured = false
        discoveryRetries = 0
        configure()
    }

    /// How many discovery retries this "no camera" episode has spent.
    private var discoveryRetries: Int = 0

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Brings a configured-but-stopped session back up (interruption over,
    /// composer re-shown).
    private func resumeIfStopped() {
        guard wantsCapture, UIApplication.shared.applicationState == .active,
              configured, isAvailable, !isDenied else { return }
        sessionQueue.async { [weak self] in
            guard let self, self.queueWantsCapture, !self.session.isRunning, !self.session.isInterrupted else { return }
            self.session.startRunning()
        }
    }

    /// Tears the whole graph down and configures it again from scratch — once.
    private func rebuildOnce() {
        guard wantsCapture, UIApplication.shared.applicationState == .active,
              !isConfiguring, !rebuildAttempted, isAvailable, !isDenied else { return }
        rebuildAttempted = true
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }
            self.session.commitConfiguration()
        }
        configured = false
        configure()
    }

    /// Confirms the graph actually came up ~1.5s after start. A session that
    /// still isn't running gets one nudge, then one full rebuild — a black
    /// stage never stays black.
    nonisolated private func scheduleRunningCheck() {
        sessionQueue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.queueWantsCapture, !self.session.isInterrupted else { return }
            if self.session.isRunning { return }
            self.session.startRunning()
            if self.session.isRunning { return }
            Task { @MainActor [weak self] in self?.rebuildOnce() }
        }
    }

    /// Switches the live AR effect. `.none` stops frame processing entirely;
    /// `onFrame` receives each rendered frame on the main thread.
    func setWaveFrameHandler(_ handler: (@Sendable (CVPixelBuffer, CMTime, WhisperCameraFrameOrientation) -> Void)?) {
        frameTap.waveHandler = handler
    }

    func setAREffect(_ effect: WhisperAREffect, onFrame: (@Sendable (CGImage) -> Void)? = nil) {
        frameTap.onFrame = effect == .none ? nil : onFrame
        frameTap.effect = effect
    }

    func configure() {
        guard UIApplication.shared.applicationState == .active else { return }
        wantsCapture = true
        refreshCallAudioOwnership()
        sessionQueue.async { [weak self] in self?.queueWantsCapture = true }
        if isDenied {
            // Not terminal anymore: Settings may have changed since.
            recheckAuthorization()
            return
        }
        if !isAvailable {
            // Never terminal: a re-shown composer re-runs discovery instead of
            // trusting a stale "no camera" answer from launch.
            isAvailable = true
            configured = false
            discoveryRetries = 0
        }
        if configured {
            // Re-appearing after stop() (a tab switch, the editor round-trip,
            // the story layer opened a second time): the capture graph is
            // intact — bring the session back up instead of leaving the
            // preview black.
            sessionQueue.async { [weak self] in
                guard let self, self.queueWantsCapture, !self.session.isRunning, !self.session.isInterrupted else { return }
                self.session.startRunning()
            }
            return
        }
        // One permission round-trip at a time. `configured` used to flip true
        // BEFORE the alert was answered — leave the composer while the alert
        // was up, come back, and configure() saw a "configured" session with
        // no inputs and just called startRunning() on an empty graph: a black
        // stage that never recovered until a relaunch.
        guard !isConfiguring else { return }
        isConfiguring = true
        // Ask for the camera EXPLICITLY before touching the device. Relying
        // on AVFoundation's implicit prompt leaves the first session running
        // with no frames until a restart — the "works only the first time"
        // class of bug — and a denial used to look like a dead black stage.
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isConfiguring = false }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            print("[StoryCamera] configure auth status=\(status.rawValue) (0 notDetermined · 1 restricted · 2 denied · 3 authorized)")
            var granted = status == .authorized
            if status == .notDetermined {
                self.isRequestingPermission = true
                granted = await AVCaptureDevice.requestAccess(for: .video)
                self.isRequestingPermission = false
                print("[StoryCamera] permission alert answered granted=\(granted)")
            }
            guard granted else {
                self.isRestricted = status == .restricted
                self.isDenied = true
                return
            }
            guard self.wantsCapture else { return }
            self.isDenied = false
            self.isRestricted = false
            self.configured = true
            self.buildGraphAndStart()
        }
    }

    /// Discovery + graph configuration + start, all on the session queue.
    private func buildGraphAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Finish the enqueued graph even if closed meanwhile. Otherwise
            // `configured` could describe an empty session on the next open.
            let hasDevice = Self.discoverVideoDevice(position: .back) != nil
                || Self.discoverVideoDevice(position: .front) != nil
            print("[StoryCamera] discovery hasDevice=\(hasDevice)")
            guard hasDevice else {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isAvailable = false
                    self.configured = false
                    // Backoff retries — the external camera usually lands
                    // within a couple of seconds of launch.
                    guard self.discoveryRetries < 5 else { return }
                    self.discoveryRetries += 1
                    let delay = 0.6 * pow(2.0, Double(self.discoveryRetries - 1))
                    let attempt = self.discoveryRetries
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self, self.wantsCapture, !self.isAvailable, !self.isDenied else { return }
                        self.isAvailable = true
                        self.configured = false
                        self.discoveryRetries = attempt
                        self.configure()
                    }
                }
                return
            }
            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(.hd1920x1080) {
                self.session.sessionPreset = .hd1920x1080
            } else {
                self.session.sessionPreset = .high
            }
            self.attachInputs()
            // Preview/photos are video-only; never take the call's microphone.
            self.session.automaticallyConfiguresApplicationAudioSession = false
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            if self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
                self.movieOutput.maxRecordedDuration = CMTime(seconds: WhisperStoryComposerView.maxRecordSeconds + 1, preferredTimescale: 600)
            }
            self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
            self.videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            self.videoDataOutput.setSampleBufferDelegate(self.frameTap, queue: self.videoDataQueue)
            if self.session.canAddOutput(self.videoDataOutput) {
                self.session.addOutput(self.videoDataOutput)
            }
            self.session.commitConfiguration()
            self.applyOrientation()
            if self.queueWantsCapture && !self.session.isRunning && !self.session.isInterrupted {
                self.session.startRunning()
            }
            print("[StoryCamera] graph built inputs=\(self.session.inputs.count) outputs=\(self.session.outputs.count) running=\(self.session.isRunning)")
            self.scheduleRunningCheck()
        }
    }

    /// Lock both connections to portrait + mirror the front camera so what's
    /// captured matches the preview.
    nonisolated private func applyOrientation() {
        guard let device = activeDevice else { return }
        frameTap.suspendSource()
        videoDataQueue.sync {}
        let angle: CGFloat = wavePortrait ? CGFloat(captureOrientation?.clockwiseDegrees ?? (device.deviceType == .external ? 0 : 90)) : (device.deviceType == .external ? 0 : 90)
        let outputs = [photoOutput.connection(with: .video), movieOutput.connection(with: .video), videoDataOutput.connection(with: .video)]
        orientationReady = outputs[1] != nil && outputs[2] != nil
        for conn in outputs.compactMap({ $0 }) {
            let isRawWave = wavePortrait && conn === videoDataOutput.connection(with: .video)
            let requested: CGFloat = isRawWave ? 0 : angle
            if conn.isVideoRotationAngleSupported(requested) { conn.videoRotationAngle = requested }
            else { orientationReady = false }
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = !isRawWave && (device.position == .front)
            } else if !isRawWave && device.position == .front {
                // Don't show a mirrored effect preview if capture can't honor it.
                orientationReady = false
            }
            if conn.isVideoStabilizationSupported {
                conn.preferredVideoStabilizationMode = .off
            }
        }
        if wavePortrait {
            // Drain old-camera frames before publishing the new orientation contract.
            videoDataQueue.sync {
                frameTap.waveOrientation = orientationReady ? WhisperCameraFrameOrientation(clockwiseDegrees: Int(angle), mirrored: device.position == .front) : nil
            }
            print("[WaveCamera] orientation ready=\(orientationReady) angle=\(angle) position=\(device.position.rawValue)")
        }
    }

    private func trackWaveOrientation(_ device: AVCaptureDevice) {
        guard wavePortrait else { return }
        rotationObservation = nil
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
            let degrees = WhisperCameraFrameOrientation.quarterTurn(coordinator.videoRotationAngleForHorizonLevelCapture)
            Task { @MainActor [weak self] in
                guard let self, self.movieDelegate == nil else { return }
                self.sessionQueue.async { [weak self] in
                    guard let self, self.activeDevice?.uniqueID == device.uniqueID, !self.movieOutput.isRecording else { return }
                    let next = WhisperCameraFrameOrientation(clockwiseDegrees: degrees, mirrored: device.position == .front)
                    guard self.captureOrientation != next else { return }
                    self.captureOrientation = next
                    self.applyOrientation()
                }
            }
        }
    }

    func stop() {
        recordingPreparation?.cancel()
        wantsCapture = false
        // Keep the owner alive until teardown actually reaches the session queue.
        sessionQueue.async { [self] in
            self.queueWantsCapture = false
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
            if self.session.isRunning { self.session.stopRunning() }
            if !self.movieOutput.isRecording { self.removeAudioInput() }
            print("[StoryCamera] capture stopped")
        }
    }

    func flipCamera() {
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording,
                  let device = Self.discoverVideoDevice(position: next), device.uniqueID != self.activeDevice?.uniqueID,
                  let replacement = try? AVCaptureDeviceInput(device: device) else { return }
            self.frameTap.suspendSource()
            self.videoDataQueue.sync {}
            self.session.beginConfiguration()
            let previous = self.session.inputs.filter { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }
            for input in previous { self.session.removeInput(input) }
            if self.session.canAddInput(replacement) {
                self.session.addInput(replacement); self.activeDevice = device; self.captureOrientation = nil
            } else {
                for input in previous where self.session.canAddInput(input) { self.session.addInput(input) }
            }
            self.session.commitConfiguration()
            self.applyOrientation()
            let actual = self.activeDevice?.position ?? .back
            let attached = self.activeDevice
            Task { @MainActor [weak self] in
                self?.position = actual
                if let attached { self?.trackWaveOrientation(attached) }
            }
        }
    }

    nonisolated private func attachInputs(position override: AVCaptureDevice.Position? = nil) {
        let pos = override ?? activeDevice?.position ?? .back
        guard let device = Self.discoverVideoDevice(position: pos)
            ?? Self.discoverVideoDevice(position: pos == .back ? .front : .back)
        else { return }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) {
            session.addInput(input)
            activeDevice = device
            Task { @MainActor [weak self] in
                self?.position = device.position
                self?.trackWaveOrientation(device)
            }
        }
    }

    nonisolated private func attachAudio() {
        guard !queueCallOwnsAudio, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic) else { return }
        if session.canAddInput(input) { session.addInput(input) }
    }

    /// Torch for video / flash hint for photos.
    func setTorch(_ on: Bool) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.activeDevice, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
            } catch {}
        }
    }

    /// Snapchat's drag-up zoom while holding the shutter. Ramped rather
    /// than set, so each finger update glides into the next instead of
    /// stepping — the stepping read as stutter in the recording.
    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.activeDevice else { return }
            let clamped = max(1, min(factor, min(device.activeFormat.videoMaxZoomFactor, 6)))
            do {
                try device.lockForConfiguration()
                if abs(device.videoZoomFactor - clamped) < 0.005 {
                    device.unlockForConfiguration()
                    return
                }
                device.ramp(toVideoZoomFactor: clamped, withRate: 14)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func capturePhoto(filter: SnapFilter, mirrored: Bool, completion: @escaping @MainActor (UIImage?) -> Void) {
        guard wantsCapture, isAvailable, !isDenied else { completion(nil); return }
        let settings = AVCapturePhotoSettings()
        // The connection-level mirroring already applied to the output
        // produces an image that matches the preview, so the delegate
        // doesn't need to reapply mirroring.
        let delegate = SnapPhotoCaptureDelegate(filter: filter, mirrored: false) { [weak self] img in
            Task { @MainActor [weak self] in
                self?.activeDelegate = nil
                completion(img)
            }
        }
        activeDelegate = delegate
        sessionQueue.async { [weak self] in
            guard let self, self.queueWantsCapture, self.session.isRunning, !self.session.isInterrupted,
                  self.photoOutput.connection(with: .video) != nil else {
                Task { @MainActor [weak self] in
                    self?.activeDelegate = nil
                    completion(nil)
                }
                return
            }
            self.applyOrientation()
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    // MARK: Video

    /// Permission does not activate audio. Resolve it before a countdown, and preserve intent through its system alert.
    func prepareRecordingAudio() async {
        guard !WhisperCameraCallMonitor.shared.callOwnsAudio,
              AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        isRequestingMicrophonePermission = true
        defer { isRequestingMicrophonePermission = false }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        while UIApplication.shared.applicationState == .inactive && wantsCapture && !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
    }

    /// Begin a hold-to-record segment. `completion` fires once the file is
    /// finalized (nil on failure).
    func startRecording(completion: @escaping (URL?) -> Void) {
        guard wantsCapture, isAvailable, !isDenied, movieDelegate == nil, recordingPreparation == nil else { completion(nil); return }
        recordingPreparation = Task { @MainActor [weak self] in
            guard let self else { completion(nil); return }
            defer { self.recordingPreparation = nil }
            await self.prepareRecordingAudio()
            let authorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            guard !Task.isCancelled, self.wantsCapture, UIApplication.shared.applicationState == .active else { completion(nil); return }
            self.refreshCallAudioOwnership()
            let includeAudio = authorized && !WhisperCameraCallMonitor.shared.callOwnsAudio
            self.recordingWithoutAudio = !includeAudio
            self.beginRecording(includeAudio: includeAudio, completion: completion)
        }
    }

    private func beginRecording(includeAudio: Bool, completion: @escaping (URL?) -> Void) {
        guard wantsCapture, isAvailable, !isDenied, movieDelegate == nil else { completion(nil); return }
        let attempt = UUID(); movieAttempt = attempt
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-story-\(UUID().uuidString).mov")
        let delegate = SnapMovieRecordingDelegate { [weak self] url in
            Task { @MainActor [weak self] in
                guard let self, self.movieAttempt == attempt else { return }
                self.movieDelegate = nil; self.movieAttempt = nil
                self.releaseCaptureAudio()
                if let device = self.rotationCoordinator?.device { self.trackWaveOrientation(device) }
                completion(url)
            }
        }
        delegate.didStart = { [weak self] time in self?.frameTap.recordingOrigin = time }
        movieDelegate = delegate
        frameTap.recordingOrigin = nil
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Orientation/mirroring were locked at configure + flip time;
            // re-touching the connection here forced a pipeline reconfigure
            // on the first frame of every take — the visible hitch when a
            // hold began.
            guard self.queueWantsCapture, self.session.isRunning, !self.session.isInterrupted,
                  self.movieOutput.connection(with: .video) != nil, !self.movieOutput.isRecording,
                  !self.wavePortrait || self.orientationReady else {
                Task { @MainActor [weak self] in
                    guard let self, self.movieAttempt == attempt else { return }
                    self.movieDelegate = nil; self.movieAttempt = nil
                    completion(nil)
                }
                return
            }
            self.session.beginConfiguration()
            let useAudio = includeAudio && !self.queueCallOwnsAudio
            self.session.automaticallyConfiguresApplicationAudioSession = useAudio
            if useAudio { self.attachAudio() }
            self.session.commitConfiguration()
            self.movieOutput.startRecording(to: url, recordingDelegate: delegate)
        }
    }

    func stopRecording() {
        recordingPreparation?.cancel()
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    /// Stop and throw the file away (fumbled taps).
    func cancelRecording() {
        movieDelegate?.discard = true
        stopRecording()
    }
}

nonisolated final class SnapPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let filter: SnapFilter
    let mirrored: Bool
    let completion: (UIImage?) -> Void

    init(filter: SnapFilter, mirrored: Bool, completion: @escaping (UIImage?) -> Void) {
        self.filter = filter
        self.mirrored = mirrored
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let raw = UIImage(data: data) else {
            completion(nil); return
        }
        // Bake the image's own orientation flag into the pixel data so
        // downstream consumers (renderer, sticker pipeline, upload) always
        // see an "up" portrait image regardless of how the sensor was held.
        let normalized = raw.normalizedUpright()
        let filtered = filter.apply(to: normalized) ?? normalized
        completion(filtered)
    }
}

nonisolated final class SnapMovieRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let completion: (URL?) -> Void
    var discard: Bool = false
    var didStart: (@Sendable (CMTime) -> Void)?

    @available(iOS 18.2, *)
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, startPTS: CMTime, from connections: [AVCaptureConnection]) {
        didStart?(startPTS)
    }

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if discard {
            try? FileManager.default.removeItem(at: outputFileURL)
            completion(nil)
            return
        }
        // Hitting maxRecordedDuration reports an error but still writes a
        // playable file — keep it.
        let finished = (error as NSError?).map { ($0.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false } ?? true
        if error == nil || finished {
            completion(outputFileURL)
        } else {
            try? FileManager.default.removeItem(at: outputFileURL)
            completion(nil)
        }
    }
}

/// A slow-spinning partial arc drawn over the shutter while a recording's
/// file is being finalized — the button stays visibly "working" instead of
/// snapping back to idle for the half-second before the editor opens.
struct ShutterFinalizingArc: View {
    @State private var spin: Bool = false

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.62)
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
            .allowsHitTesting(false)
    }
}

// MARK: - SwiftUI preview wrapper

struct SnapCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> SnapPreviewUIView {
        let view = SnapPreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: SnapPreviewUIView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }

    static func dismantleUIView(_ uiView: SnapPreviewUIView, coordinator: ()) {
        uiView.videoPreviewLayer.session = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SnapPreviewUIView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

final class SnapPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

// MARK: - UIImage orientation helper

nonisolated extension UIImage {
    /// Returns a copy of the image with its EXIF orientation baked into the
    /// pixel data so the result is always `.up`. Prevents downstream views
    /// that ignore `imageOrientation` (or pipelines that drop it) from
    /// rotating the photo sideways.
    func normalizedUpright() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Legacy camera picker (still used elsewhere)

struct WhisperStoryCameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return cameraUnavailablePlaceholder()
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    @MainActor
    private func cameraUnavailablePlaceholder() -> UIViewController {
        let host = UIHostingController(rootView: CameraUnavailableView(onClose: { onPick(nil) }))
        host.view.backgroundColor = .black
        return host
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let img = info[.originalImage] as? UIImage
            onPick(img)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPick(nil)
        }
    }
}

private struct CameraUnavailableView: View {
    let onClose: () -> Void
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Install this app on your device via the Rork App to use the camera.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button("Close", action: onClose)
                    .foregroundStyle(.white)
                    .padding(.top, 8)
            }
        }
    }
}
