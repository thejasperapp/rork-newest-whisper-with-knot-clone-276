import SwiftUI
import UIKit
import PhotosUI

/// Story canvas editor. The background fills the screen with a blurred copy
/// of the chosen photo so any letterboxing (when the photo isn't 9:16)
/// disappears into a soft Instagram-style gradient. The photo itself sits
/// on top with `aspect-fit` and can be pinched / dragged to recompose the
/// shot. Stickers (text, GIFs, polls, sliders, mentions, music, etc.) drop
/// on top and are independently draggable.
struct WhisperStoryEditor: View {
    /// The background photo — or, for video stories, the POSTER frame that
    /// strips/highlights/older clients show while `videoURL` plays here.
    let image: UIImage
    /// Round 77 — hold-to-record video stories. When set, the stage plays
    /// this clip (looping) instead of the still, the draw tool hides (strokes
    /// can't bake into video), and posting uploads the clip beside the poster.
    var videoURL: URL? = nil
    /// Optional stickers to pre-populate the canvas with (e.g. when
    /// re-sharing a question answer Instagram-style — the question card
    /// + the responder's reply are dropped on the canvas before the
    /// author opens the editor).
    var initialStickers: [WhisperStorySticker] = []
    var initialReferenceWidth: Double? = nil
    var sharedPostBackground: Bool = false
    var restoredDraft: WhisperStoryDraftService.Draft? = nil
    var restoredBackgroundPhoto: UIImage? = nil
    /// Fires only after a story is successfully posted, so the caller can
    /// dismiss the composer behind the editor. The editor closes itself via
    /// its own `@Environment(\.dismiss)` in all cases.
    let onPosted: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsExtraTools: Bool = false
    @State private var showsJasper: Bool = false
    @State private var showsEffects: Bool = false
    @State private var editedImage: UIImage?
    @State private var missingDraftEdit: Bool = false
    private var workingImage: UIImage { editedImage ?? image }
    @State private var pendingTool: Tool?
    @State private var pendingPhotoPicker: Bool = false
    @State private var selectedLayout: WhisperStoryPhotoLayout = .grid
    @State private var replacingPhotoID: String?
    @State private var editingLink: WhisperStorySticker?
    @State private var editingPhotoCard: WhisperStorySticker?
    @State private var inlineDraftFont: String? = "classic"
    @State private var inlineDraftSize: Double = 28
    @State private var inlineDraftAlignment: String = "center"
    @State private var inlineTextTool: Int = 0
    @State private var isLoadingSticker: Bool = false
    @State private var sendAfterPosting: Bool = false
    @State private var publishedStory: WhisperStoryRow?
    @State private var didPublish: Bool = false
    @State private var stories = WhisperStoryService.shared
    @State private var stickers: [WhisperStorySticker] = []
    /// LIFO snapshot stack for undo. Each meaningful mutation (add, delete,
    /// drag-end, scale, rotate, duplicate, reorder, text edit) pushes the
    /// pre-mutation state. Capped at 30 entries so the array can't bloat.
    @State private var history: [(stickers: [WhisperStorySticker], music: WhisperStoryMusic?, image: UIImage?)] = []
    @State private var music: WhisperStoryMusic?
    @State private var isPosting: Bool = false
    @State private var postError: String?
    @State private var activeTool: Tool?
    @State private var editingTextID: String?
    @State private var editingLayer: WhisperStorySticker?
    @State private var canvasSize: CGSize = .zero
    @State private var viewportGeometry: WhisperStoryViewportGeometry?
    @State private var didSeedCanvas: Bool = false
    @State private var backgroundSelection: WhisperStoryBackgroundSelection = .blurred
    @State private var backgroundPhoto: UIImage?
    @State private var backgroundPhotoItem: PhotosPickerItem?
    @State private var isLoadingBackground: Bool = false
    @State private var backgroundError: String?
    @State private var editorGeneration: UUID = AccountStorage.generation
    @State private var editorClosed: Bool = false
    @State private var showStoryHelp: Bool = false
    @State private var showHelpPrompt: Bool = false

    private var isSharedPost: Bool { sharedPostBackground || restoredDraft?.backgroundSelection != nil }

    /// Current user's handle so the on-canvas question card can render the
    /// poster's avatar at the top of the bubble — matching the Instagram
    /// "ask me anything" design.
    private var currentAuthorUsername: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    // Photo recompose state — Instagram-style pinch-to-shrink. When the
    // user pinches the background photo it scales down and the
    // surrounding canvas fills with a heavily blurred copy of the same
    // photo, exactly like IG's story composer. Two-finger drag repositions
    // the photo while it's shrunk.
    @State private var photoScale: CGFloat = 1.0
    @State private var photoOffset: CGSize = .zero

    // Stage gesture routing (WhisperStoryStageGestures.swift). Each sticker
    // reports its UNSCALED layout size so the router can hit-test touches
    // against the real rendered frame (rotation + scale applied in math).
    @State private var stickerSizes: [String: CGSize] = [:]
    @State private var draggingStickerID: String?
    @State private var stageTransforming: Bool = false
    @State private var trashArmed: Bool = false
    @State private var gestureSnapshotTaken: Bool = false
    @State private var layerMenuStickerID: String?

    // Inline tap-to-type editor state. When `inlineTextEditing` is true an
    // overlay covers the canvas with a centred TextField and a floating
    // toolbar above the keyboard for colour + style. Tapping the canvas
    // background (or an existing text sticker) enters this mode — no sheet.
    @State private var inlineTextEditing: Bool = false
    @State private var inlineDraftText: String = ""
    @State private var inlineDraftStyle: Int = 0
    @State private var inlineDraftColor: Color = .white
    @State private var inlineDraftBackground: Color = .black
    /// Retains the first pre-edit value, then word-boundary/deletion snapshots.
    /// Capped at 50 entries; applying Undo never creates another snapshot.
    @State private var inlineTextHistory: [String] = []
    @State private var inlineUndoRepeatTask: Task<Void, Never>?
    @FocusState private var inlineTextFocused: Bool

    enum Tool: String, Identifiable {
        case text, sticker, photo, poll, slider, question, music, location, mention, gif, hashtag, countdown, background, templates, share, layout, cutout, link, makeTemplate, reaction
        var id: String { rawValue }
    }

    @State private var photoStickerPicker: PhotosPickerItem?
    @State private var showPhotoStickerPicker: Bool = false

    // Instagram draw tool — strokes are baked into the posted image.
    @State private var isDrawing: Bool = false
    @State private var drawStrokes: [WhisperStoryDrawStroke] = []
    @State private var activeStroke: WhisperStoryDrawStroke? = nil
    @State private var drawColorHex: String = "#FFFFFF"
    @State private var drawWidth: CGFloat = 7
    @State private var drawMarker: WhisperStoryDrawStroke.Marker = .pen
    @State private var inlineUndoTarget: String? = nil
    @State private var inlineMusic: WhisperStoryMusic? = nil
    @State private var pendingInlineMusic: WhisperStoryMusic? = nil

    var body: some View {
        editorSurface
        .background { Color.black.ignoresSafeArea() }
        .statusBarHidden(false)
        .fullScreenCover(isPresented: $showsEffects) {
            WhisperStoryEffectsView(image: workingImage, original: image) { result in
                guard !editorClosed, !isPosting, editorGeneration == AccountStorage.generation else { return }
                snapshot(); editedImage = result
            }
        }
        .onAppear {
            if !AccountStorage.bool(forKey: "whisper.story.helpPrompt.v1") { showHelpPrompt = true }
        }
        .alert("A quick Story tour?", isPresented: $showHelpPrompt) {
            Button("Show me") { AccountStorage.set(true, forKey: "whisper.story.helpPrompt.v1"); showStoryHelp = true }
            Button("Skip", role: .cancel) { AccountStorage.set(true, forKey: "whisper.story.helpPrompt.v1") }
        } message: { Text("Learn how to move text, resize stickers and choose your music. You can reopen the guide with the question mark anytime.") }
        .sheet(isPresented: $showStoryHelp) { WhisperStoryHelpView() }
        .sheet(item: Binding(
            get: { (activeTool.flatMap { isBubbleTool($0) ? nil : $0 }) },
            set: { activeTool = $0 }
        ), onDismiss: {
            guard !editorClosed, editorGeneration == AccountStorage.generation else { return }
            let next = pendingTool; pendingTool = nil
            if let song = pendingInlineMusic { pendingInlineMusic = nil; inlineMusic = song }
            else if pendingPhotoPicker { pendingPhotoPicker = false; showPhotoStickerPicker = true }
            else if let next { activeTool = next }
        }) { tool in
            toolSheet(for: tool)
                .presentationDetents(detents(for: tool))
                .presentationDragIndicator(tool == .sticker ? .hidden : .visible)
                .presentationBackground {
                    if tool == .sticker { WhisperStoryTrayBackdrop() }
                    else { Color(white: 0.10) }
                }
                .presentationCornerRadius(30)
                .presentationBackgroundInteraction(.disabled)
                .presentationContentInteraction(.scrolls)
                .preferredColorScheme(.dark)
        }
        .sheet(item: $publishedStory, onDismiss: {
            guard didPublish, !editorClosed, editorGeneration == AccountStorage.generation else { return }
            editorClosed = true; dismiss(); onPosted()
        }) { row in
            if let body = WhisperSharedStoryEmbed.encode(storyID: row.id) {
                WhisperRecipientShareSheet(payload: body) { EmptyView() }
            }
        }
        .task(id: backgroundPhotoItem) {
            guard let item = backgroundPhotoItem else { return }
            isLoadingBackground = true; backgroundError = nil
            let selectionAtImport = backgroundSelection
            defer {
                isLoadingBackground = false
                if backgroundPhotoItem == item { backgroundPhotoItem = nil }
            }
            guard let data = try? await item.loadTransferable(type: Data.self), !Task.isCancelled else {
                if !Task.isCancelled { backgroundError = "Couldn't load this photo. Please choose it again." }
                return
            }
            let prepared = await Task.detached(priority: .userInitiated) {
                WhisperImageCache.decode(data, maxPixelSize: 1920).map { WhisperWaveStoryBackground.filledPhoto($0) }
            }.value
            guard !Task.isCancelled, !editorClosed, editorGeneration == AccountStorage.generation else { return }
            if let prepared {
                backgroundPhoto = prepared
                if backgroundSelection == selectionAtImport { backgroundSelection = .photo }
            }
            else { backgroundError = "This photo couldn't be opened. Try another image." }
        }
        .onChange(of: backgroundSelection) { oldValue, newValue in
            if isLoadingBackground && oldValue != newValue && newValue != .photo { backgroundPhotoItem = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            editorClosed = true; activeTool = nil; editingLayer = nil; editingPhotoCard = nil; pendingTool = nil; pendingPhotoPicker = false
            inlineTextEditing = false; inlineTextFocused = false; showsEffects = false; inlineMusic = nil; pendingInlineMusic = nil
            photoStickerPicker = nil; backgroundPhotoItem = nil; publishedStory = nil; dismiss()
        }
        .interactiveDismissDisabled(true)
        .accessibilityAction(.escape) {
            if inlineMusic != nil { inlineMusic = nil }
            else if inlineTextEditing { cancelInlineText() }
            else if isDrawing { isDrawing = false }
            else if editingLayer != nil { editingLayer = nil }
            else if activeTool != nil { activeTool = nil }
            else if showsJasper { showsJasper = false }
            else { closeWithAutosave() }
        }
        .photosPicker(
            isPresented: $showPhotoStickerPicker,
            selection: $photoStickerPicker,
            matching: .images
        )
        .task(id: photoStickerPicker) {
            guard let item = photoStickerPicker else { return }
            await handlePhotoStickerPick(item)
        }
        // Long-press layer menu (replaces the old per-sticker context menu,
        // which the stage gesture router now sits above).
        .confirmationDialog(
            "Sticker",
            isPresented: Binding(
                get: { layerMenuStickerID != nil },
                set: { if !$0 { layerMenuStickerID = nil } }
            ),
            titleVisibility: .hidden
        ) {
            if let id = layerMenuStickerID {
                if let layer = stickers.first(where: { $0.id == id }), layer.isPhotoCard {
                    Button("Edit caption and photos") { editPhotoCard(layer) }
                    if layer.photoLayout == "strip" { Button("Change strip style") { cyclePhotoCardStyle(id) } }
                } else if stickers.first(where: { $0.id == id })?.kind == .photo {
                    Button("Replace photo") { replacingPhotoID = id; showPhotoStickerPicker = true }
                    Button("Toggle frame") {
                        guard let index = stickers.firstIndex(where: { $0.id == id }) else { return }
                        snapshot(); stickers[index].photoFrame = !(stickers[index].photoFrame ?? false)
                    }
                }
                Button("Bring to front") { bringToFront(id) }
                Button("Send to back") { sendToBack(id) }
                Button("Duplicate") { duplicate(id) }
                Button("Delete", role: .destructive) {
                    snapshot()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        stickers.removeAll { $0.id == id }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .alert("Couldn't share story", isPresented: Binding(
            get: { postError != nil },
            set: { if !$0 { postError = nil } }
        )) {
            Button("OK", role: .cancel) { postError = nil }
        } message: {
            Text(postError ?? "")
        }
        // Environment override instead of `.preferredColorScheme(.dark)` so
        // dark mode stays contained to the editor and doesn't bleed into
        // the parent app after dismissal.
        .environment(\.colorScheme, .dark)
    }

    private func detents(for tool: Tool) -> Set<PresentationDetent> {
        switch tool {
        case .sticker: return [.custom(WhisperStoryTrayDetent.self)]
        case .gif, .music, .background: return [.fraction(0.75), .large]
        case .templates, .layout, .cutout, .makeTemplate, .link, .location: return [.large]
        case .share: return [.height(340), .large]
        case .text, .mention, .hashtag: return [.large]
        case .poll, .slider, .question: return [.large]
        default: return [.height(300)]
        }
    }

    /// Poll / slider / question sheets render their own free-floating
    /// bubble over a transparent overlay — no system sheet chrome, no
    /// dimming layer behind the white card.
    private func isBubbleTool(_ tool: Tool) -> Bool {
        switch tool {
        case .poll, .slider, .question, .countdown, .reaction, .mention, .hashtag: return true
        case .layout: return selectedLayout == .frame || selectedLayout == .strip
        default: return false
        }
    }

    /// Inline overlay used for the bubble-style creators (poll / slider /
    /// question). Rendered directly in the editor's ZStack so the only
    /// thing on screen behind the card is the live canvas — no sheet dim,
    /// no ultraThinMaterial, no system chrome.
    @ViewBuilder
    private func bubbleToolOverlay(for tool: Tool) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().contentShape(.rect)
            bubbleToolContent(for: tool)
        }
    }

    @ViewBuilder
    private func bubbleToolContent(for tool: Tool) -> some View {
        let cancel: () -> Void = { activeTool = nil }
        switch tool {
        case .poll, .slider, .question, .countdown, .reaction:
            WhisperStoryAttachmentEditor(kind: tool == .poll ? .poll : tool == .question ? .question : tool == .countdown ? .countdown : .slider, reaction: tool == .reaction, onCancel: cancel) { addSticker($0) }

        case .layout:
            WhisperStoryPhotoCardEditor(layout: selectedLayout, existing: editingPhotoCard, onClose: {
                editingPhotoCard = nil; activeTool = nil
            }) { updated in
                guard canMutateDocument else { return }
                if editingPhotoCard != nil {
                    guard let index = stickers.firstIndex(where: { $0.id == updated.id }) else { return }
                    replaceEditedLayer(updated, at: index)
                } else { addSticker(updated) }
            }.id(editingPhotoCard?.id ?? selectedLayout.rawValue)
        case .mention, .hashtag:
            WhisperStoryLabelEditor(isMention: tool == .mention, onCancel: cancel) { addSticker($0) }
        case .location:
            StoryLocationSheet(
                onDone: { label, lat, lon in
                    var s = WhisperStorySticker(kind: .location, label: label)
                    s.latitude = lat
                    s.longitude = lon
                    addSticker(s)
                },
                onCancel: cancel
            )
        default:
            EmptyView()
        }
    }

    // MARK: - Canvas

    private var editorSurface: some View {
        GeometryReader { viewport in
            ZStack(alignment: .topLeading) {
                Color.black
                WhisperStoryViewportProbe { geometry in
                    guard !editorClosed, viewportGeometry != geometry else { return }
                    viewportGeometry = geometry
                }
                .frame(width: viewport.size.width, height: viewport.size.height)
                .allowsHitTesting(false)
                if let geometry = viewportGeometry {
                    editorWorkspace
                        .frame(width: geometry.workspace.width, height: geometry.workspace.height)
                        .clipped()
                        .position(x: geometry.workspace.midX, y: geometry.workspace.midY)
                        .accessibilityHidden(!showsCanvasChrome && !isDrawing)
                    editorOverlays(size: geometry.controls.size)
                        .clipped()
                        .position(x: geometry.controls.midX, y: geometry.controls.midY)
                } else {
                    VStack(spacing: 16) {
                        ProgressView("Opening editor…").tint(.white)
                        Button("Cancel") { editorClosed = true; dismiss() }.frame(minHeight: 44)
                    }
                    .foregroundStyle(.white)
                    .frame(width: viewport.size.width, height: viewport.size.height)
                }
            }
            .frame(width: viewport.size.width, height: viewport.size.height)
        }
        // UIKit measures container and keyboard boundaries once for this cover.
        // Only controls use the keyboard boundary; the document keeps its size.
        .ignoresSafeArea()
    }

    private func editorOverlays(size: CGSize) -> some View {
        ZStack(alignment: .top) {
            if inlineTextEditing {
                inlineTextOverlay.frame(width: size.width, height: size.height)
            }
            if let inlineMusic {
                Color.black.opacity(0.5)
                WhisperStoryMusicSegmentView(music: inlineMusic, onCancel: { self.inlineMusic = nil }, onApply: applyStoryMusic)
                    .frame(width: size.width, height: size.height)
            }
            if let tool = activeTool, isBubbleTool(tool) {
                bubbleToolOverlay(for: tool).transition(.opacity).zIndex(20)
            }
            if isLoadingSticker {
                VStack {
                    Spacer()
                    Label("Adding photo…", systemImage: "photo").font(.subheadline.weight(.semibold))
                        .padding(12).background(.black.opacity(0.8), in: .capsule).padding(.bottom, 76)
                }.foregroundStyle(.white).allowsHitTesting(false)
            }
            if missingDraftEdit {
                Color.black.opacity(0.85).zIndex(50)
                VStack(spacing: 16) {
                    Text("Your edited photo couldn't be restored").font(.headline)
                    Text("The original and your draft are kept. Retry before continuing, or explicitly return to the original.").font(.subheadline).multilineTextAlignment(.center)
                    Button("Retry edited photo") {
                        editedImage = WhisperStoryDraftService.shared.loadEditedImage()
                        missingDraftEdit = editedImage == nil
                    }.frame(minHeight: 44)
                    Button("Use original photo") { missingDraftEdit = false }.frame(minHeight: 44)
                    Button("Close without changing draft") { editorClosed = true; dismiss() }.frame(minHeight: 44)
                }.foregroundStyle(.white).padding(24).zIndex(51)
            }
            if isPosting { postingOverlay }
            else if pendingPublication != nil {
                Color.black.opacity(0.55)
                VStack(spacing: 14) {
                    Text("Your Story is ready to retry").font(.headline)
                    Text("Retry the same version without duplicating it. If you close, check Your Story before publishing the saved draft again.").font(.subheadline).multilineTextAlignment(.center)
                    Button("Retry same Story") { post() }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                    Button("Save draft and close") { closeWithAutosave() }.buttonStyle(.bordered).frame(minHeight: 44)
                }
                .foregroundStyle(.primary).padding(24)
                .background(.regularMaterial, in: .rect(cornerRadius: 24)).padding(.horizontal, 24)
            }
            if let layer = editingLayer {
                ZStack {
                    Color.black.opacity(0.4)
                    if layer.kind == .mention || layer.kind == .hashtag {
                        WhisperStoryLabelEditor(isMention: layer.kind == .mention, existing: layer, onCancel: { editingLayer = nil }, onDone: commitFocusedLayer).id(layer.id)
                    } else {
                        WhisperStoryAttachmentEditor(kind: layer.kind, existing: layer, reaction: layer.kind == .slider && layer.style == 9, onCancel: { editingLayer = nil }, onSave: commitFocusedLayer).id(layer.id)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private var canMutateDocument: Bool {
        !editorClosed && !isPosting && !didPublish && pendingPublication == nil && editorGeneration == AccountStorage.generation
    }
    private var showsCanvasChrome: Bool {
        !inlineTextEditing && !isDrawing && !showsEffects && inlineMusic == nil && activeTool == nil && editingLayer == nil
    }
    private func isFocusedLayer(_ id: String) -> Bool {
        editingLayer?.id == id || (inlineTextEditing && editingTextID == id) || (activeTool == .layout && editingPhotoCard?.id == id)
    }

    private var editorWorkspace: some View {
        GeometryReader { viewport in
            let layout = WhisperStoryEditorLayout(viewport: viewport.size)
            ZStack(alignment: .topLeading) {
                canvas(stage: layout.stage.size)
                    .overlay {
                        if showsCanvasChrome {
                            topBar.disabled(stageTransforming || isPosting || isLoadingSticker || didPublish)
                        }
                        if isDrawing { drawOverlay }
                    }
                    .frame(width: layout.stage.width, height: layout.stage.height)
                    .position(x: layout.stage.midX, y: layout.stage.midY)
                if showsCanvasChrome {
                    shareBar
                        .frame(width: layout.footer.width, height: layout.footer.height)
                        .position(x: layout.footer.midX, y: layout.footer.midY)
                        .disabled(stageTransforming || isPosting || isLoadingSticker || isLoadingBackground || didPublish)
                    if showsJasper && !isPosting && !didPublish { storyJasperDockOverlay }
                }
            }
            .frame(width: viewport.size.width, height: viewport.size.height)
        }
    }

    private func canvas(stage: CGSize) -> some View {
            ZStack {
                if isSharedPost {
                    WhisperSharedStoryBackdrop(original: workingImage, selection: backgroundSelection, photo: backgroundPhoto, size: stage)
                } else {
                // Instagram-style blurred backdrop. Always full-bleed and
                // never transformed — so when the foreground photo shrinks
                // there's a soft, on-brand background to fall back to.
                Color.black
                    .frame(width: stage.width, height: stage.height)
                    .overlay {
                        Image(uiImage: workingImage)
                            .resizable().aspectRatio(contentMode: .fill)
                            .blur(radius: 60).allowsHitTesting(false)
                    }
                    .clipped()
                    .allowsHitTesting(false)
                Color.black.opacity(0.15)
                    .allowsHitTesting(false)

                // Foreground photo — Instagram-style aspect-FIT so the
                // photo always shows at its natural ratio (4:3, 1:1, 16:9,
                // 9:16) centered on the blurred backdrop, never cropped.
                // Pinch to shrink further, two-finger drag to reposition,
                // single tap to drop a text sticker.
                // Pinch / drag / tap on the photo are routed by the stage
                // gesture overlay below (background target) — the photo
                // itself is inert so it can never steal a sticker's pinch.
                foregroundMedia
                    .frame(width: stage.width, height: stage.height)
                    .scaleEffect(photoScale)
                    .offset(x: photoOffset.width, y: photoOffset.height)
                    .allowsHitTesting(false)
                }

                if !drawStrokes.isEmpty || activeStroke != nil {
                    WhisperStoryDrawCanvas(strokes: drawStrokes, active: activeStroke)
                        .frame(width: stage.width, height: stage.height)
                }

                ForEach(stickers.filter { !isFocusedLayer($0.id) }) { sticker in
                    StickerCanvasItem(
                        sticker: sticker,
                        canvasSize: stage,
                        authorUsername: currentAuthorUsername,
                        onSize: { size in
                            if stickerSizes[sticker.id] != size { stickerSizes[sticker.id] = size }
                        }
                    )
                }

                // ONE gesture router over the whole stage — pan, pinch and
                // rotate all drive whichever sticker the first finger landed
                // on (or the photo when none did). See the overlay's docs for
                // why this replaced per-sticker SwiftUI gestures.
                StoryStageGestureOverlay(
                    isEnabled: !inlineTextEditing && !isDrawing && activeTool == nil && !isPosting && !didPublish && !isLoadingSticker && !showStoryHelp && !showHelpPrompt && !showsJasper && editingLayer == nil && !showsEffects && inlineMusic == nil,
                    hitTest: { point in hitTestSticker(at: point, stage: stage) },
                    onBegin: { target in beginStageGesture(target) },
                    onPan: { target, delta in panStage(target, delta: delta, stage: stage) },
                    onPinch: { target, factor, anchor in pinchStage(target, factor: factor, anchor: anchor, stage: stage) },
                    onRotate: { target, delta, anchor in rotateStage(target, delta: delta, anchor: anchor, stage: stage) },
                    onEnd: { target, _ in endStageGesture(target, stage: stage) },
                    onCancel: { target, _ in endStageGesture(target, stage: stage, allowDeletion: false) },
                    onTap: { target in tapStage(target) },
                    onLongPress: { target in
                        if case .sticker(let id) = target {
                            Haptics.tap()
                            layerMenuStickerID = id
                        }
                    }
                )
                .frame(width: stage.width, height: stage.height)
                .allowsHitTesting(!inlineTextEditing && !isDrawing && activeTool == nil && !isPosting && !didPublish && !isLoadingSticker && !showStoryHelp && !showHelpPrompt && !showsJasper && editingLayer == nil && !showsEffects && inlineMusic == nil)

                if draggingStickerID != nil {
                    trashWell
                        .position(x: stage.width / 2, y: stage.height - 64)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: stage.width, height: stage.height)
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
            .contentShape(.rect(cornerRadius: 24))
            .accessibilityIdentifier("story.editor.stage")
            .onAppear {
                canvasSize = stage
                if !didSeedCanvas {
                    didSeedCanvas = true
                    let reference = restoredDraft?.canvasWidth ?? initialReferenceWidth ?? stage.width
                    stickers = scaledLayers(restoredDraft?.stickers ?? initialStickers, by: stage.width / max(1, reference))
                    if let draft = restoredDraft {
                        photoScale = draft.photoScale
                        let ratio = stage.width / max(1, draft.canvasWidth ?? stage.width)
                        photoOffset = CGSize(width: draft.photoOffsetX * ratio, height: draft.photoOffsetY * ratio)
                        backgroundSelection = draft.backgroundSelection ?? .blurred
                        backgroundPhoto = restoredBackgroundPhoto
                        drawStrokes = (draft.drawStrokes ?? []).map { saved in
                            var stroke = saved
                            if stroke.referenceWidth == nil { stroke.referenceWidth = draft.canvasWidth ?? stage.width }
                            return stroke
                        }
                        music = draft.music
                        editedImage = WhisperStoryDraftService.shared.loadEditedImage()
                        missingDraftEdit = draft.editedImageFilename != nil && editedImage == nil
                    }
                }
            }
            .onChange(of: stage) { _, size in
                guard canvasSize.width > 0, size != canvasSize else { return }
                let ratio = size.width / canvasSize.width
                stickers = scaledLayers(stickers, by: ratio)
                history = history.map { (scaledLayers($0.stickers, by: ratio), $0.music, $0.image) }
                photoOffset = CGSize(width: photoOffset.width * ratio, height: photoOffset.height * ratio)
                canvasSize = size
            }
            .onChange(of: stickers.map(\.id)) { _, ids in
                let valid = Set(ids); stickerSizes = stickerSizes.filter { valid.contains($0.key) }
            }
    }

    private func commitFocusedLayer(_ updated: WhisperStorySticker) {
        guard canMutateDocument, editingLayer?.id == updated.id,
              let index = stickers.firstIndex(where: { $0.id == updated.id }) else { return }
        replaceEditedLayer(updated, at: index); editingLayer = nil
    }

    /// An open tool owns content, not the transform adjusted by a resized viewport.
    private func replaceEditedLayer(_ updated: WhisperStorySticker, at index: Int) {
        let current = stickers[index]
        var result = updated
        result.x = current.x; result.y = current.y
        result.scale = current.scale; result.rotation = current.rotation
        snapshot()
        stickers[index] = result
    }

    private func scaledLayers(_ layers: [WhisperStorySticker], by ratio: CGFloat) -> [WhisperStorySticker] {
        layers.map { layer in
            var value = layer
            if value.cardWidthFraction == nil { value.scale *= ratio }
            return value
        }
    }

    /// The largest 9:16 rect that fits the screen — width-first so the
    /// stage always spans the full width and letterboxes vertically.
    static func stageSize(in container: CGSize) -> CGSize {
        let w = max(1, min(container.width, container.height * 9.0 / 16.0))
        return CGSize(width: w, height: w * 16.0 / 9.0)
    }

    /// Offset of the stage inside the full-screen geometry (for overlays
    /// that capture touches in screen space — the draw tool).
    static func stageOrigin(in container: CGSize) -> CGPoint {
        let s = stageSize(in: container)
        return CGPoint(x: (container.width - s.width) / 2, y: (container.height - s.height) / 2)
    }

    /// Video stories play the clip on the stage; photo stories show the still.
    @ViewBuilder
    private var foregroundMedia: some View {
        if let videoURL {
            WhisperStoryVideoStage(url: videoURL, muted: music != nil)
        } else {
            Image(uiImage: workingImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    /// Instagram's photo-sticker tap: rect → circle → heart → star →
    /// rounded → rect. Each tap is an undoable mutation.
    private func cyclePhotoShape(_ id: String) {
        guard let idx = stickers.firstIndex(where: { $0.id == id }) else { return }
        snapshot()
        let current = WhisperStoryPhotoShape(rawValue: stickers[idx].shape ?? "rect") ?? .rect
        Haptics.tap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            stickers[idx].shape = current.next.rawValue
        }
    }

    // MARK: - Stage gesture routing

    private func stickerCenter(_ s: WhisperStorySticker, stage: CGSize) -> CGPoint {
        CGPoint(x: s.x * stage.width, y: s.y * stage.height)
    }

    /// Topmost sticker under `point` — later stickers render on top, so the
    /// array is walked back to front.
    private func hitTestSticker(at point: CGPoint, stage: CGSize) -> String? {
        let regions = stickers.compactMap { sticker -> WhisperStoryHitRegion? in
            guard let size = stickerSizes[sticker.id], size.width > 0, size.height > 0 else { return nil }
            return WhisperStoryHitRegion(id: sticker.id, center: stickerCenter(sticker, stage: stage), size: size, scale: CGFloat(sticker.scale), rotation: CGFloat(sticker.rotation))
        }
        return WhisperStoryHitRegion.target(at: point, regions: regions)
    }

    private func beginStageGesture(_ target: StoryGestureTarget) {
        stageTransforming = true
        gestureSnapshotTaken = false
        trashArmed = false
        if case .sticker(let id) = target {
            draggingStickerID = id
        }
    }

    /// One undo entry per gesture cycle, pushed lazily on the first real
    /// delta so an aborted touch never pollutes the history.
    private func ensureGestureSnapshot() {
        guard !gestureSnapshotTaken else { return }
        gestureSnapshotTaken = true
        snapshot()
    }

    private func panStage(_ target: StoryGestureTarget, delta: CGSize, stage: CGSize) {
        switch target {
        case .sticker(let id):
            guard let idx = stickers.firstIndex(where: { $0.id == id }) else { return }
            ensureGestureSnapshot()
            stickers[idx].x += Double(delta.width / max(stage.width, 1))
            stickers[idx].y += Double(delta.height / max(stage.height, 1))
            updateTrashArm(for: stickers[idx], stage: stage)
        case .background:
            guard !isSharedPost else { return }
            photoOffset.width += delta.width
            photoOffset.height += delta.height
        }
    }

    /// Scale about the finger centroid so the point under the fingers stays
    /// put — the sticker grows toward the pinch instead of jumping around
    /// its own center.
    private func pinchStage(_ target: StoryGestureTarget, factor: CGFloat, anchor: CGPoint, stage: CGSize) {
        switch target {
        case .sticker(let id):
            guard let idx = stickers.firstIndex(where: { $0.id == id }) else { return }
            ensureGestureSnapshot()
            let current = CGFloat(stickers[idx].scale)
            let viewportScale = stickers[idx].cardWidthFraction == nil ? stage.width / 390 : 1
            // Restored legacy sizes outside today's limits can move back in without snapping.
            let lower = min(current, 0.25 * viewportScale)
            let upper = max(current, 6 * viewportScale)
            let next = min(max(current * factor, lower), upper)
            let applied = next / max(current, 0.0001)
            let center = StoryStickerGeometry.scaled(
                center: stickerCenter(stickers[idx], stage: stage),
                about: anchor,
                factor: applied
            )
            stickers[idx].scale = Double(next)
            stickers[idx].x = Double(center.x / max(stage.width, 1))
            stickers[idx].y = Double(center.y / max(stage.height, 1))
        case .background:
            guard !isSharedPost else { return }
            let next = min(max(photoScale * factor, 0.35), 2.5)
            let center = StoryStickerGeometry.scaled(
                center: CGPoint(x: stage.width / 2 + photoOffset.width, y: stage.height / 2 + photoOffset.height),
                about: anchor, factor: next / max(photoScale, 0.0001)
            )
            photoScale = next
            photoOffset = CGSize(width: center.x - stage.width / 2, height: center.y - stage.height / 2)
        }
    }

    private func rotateStage(_ target: StoryGestureTarget, delta: CGFloat, anchor: CGPoint, stage: CGSize) {
        guard case .sticker(let id) = target,
              let idx = stickers.firstIndex(where: { $0.id == id }) else { return }
        ensureGestureSnapshot()
        let center = StoryStickerGeometry.rotated(
            center: stickerCenter(stickers[idx], stage: stage),
            about: anchor,
            delta: delta
        )
        stickers[idx].rotation += Double(delta)
        stickers[idx].x = Double(center.x / max(stage.width, 1))
        stickers[idx].y = Double(center.y / max(stage.height, 1))
    }

    private func updateTrashArm(for s: WhisperStorySticker, stage: CGSize) {
        let armed = s.y * stage.height > stage.height - 110
        if armed != trashArmed {
            trashArmed = armed
            if armed { Haptics.tap() }
        }
    }

    private func endStageGesture(_ target: StoryGestureTarget, stage: CGSize, allowDeletion: Bool = true) {
        stageTransforming = false
        switch target {
        case .sticker(let id):
            let wasArmed = trashArmed && allowDeletion
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { draggingStickerID = nil }
            trashArmed = false
            gestureSnapshotTaken = false
            guard let idx = stickers.firstIndex(where: { $0.id == id }) else { return }
            if wasArmed {
                Haptics.success()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    _ = stickers.remove(at: idx)
                }
                return
            }
            // Keep every sticker reachable — its center springs back onto
            // the stage if the drag left it hanging off an edge.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                stickers[idx].x = min(max(0.04, stickers[idx].x), 0.96)
                stickers[idx].y = min(max(0.05, stickers[idx].y), 0.95)
            }
        case .background:
            // Preserve deliberate zoom. Only bound travel so the photo remains reachable.
            photoOffset = WhisperStoryPhotoGeometry.boundedOffset(photoOffset, scale: photoScale, image: workingImage.size, stage: stage)
        }
    }

    private func tapStage(_ target: StoryGestureTarget) {
        switch target {
        case .sticker(let id):
            guard let s = stickers.first(where: { $0.id == id }) else { return }
            if s.linkURL != nil { editingLink = s; activeTool = .link }
            else if s.kind == .text {
                beginInlineText(forID: id)
            } else if s.isPhotoCard {
                editPhotoCard(s)
            } else if s.kind == .photo {
                cyclePhotoShape(id)
            } else if s.kind == .music { activeTool = .music }
            else if [.poll, .question, .slider, .countdown, .mention, .hashtag].contains(s.kind) {
                editingLayer = s
            } else {
                bringToFront(id)
            }
        case .background:
            beginInlineText(forID: nil)
        }
    }

    private func editPhotoCard(_ layer: WhisperStorySticker) {
        guard !editorClosed, !isPosting, editorGeneration == AccountStorage.generation else { return }
        editingPhotoCard = layer
        selectedLayout = layer.photoLayout == "strip" ? .strip : .frame
        activeTool = .layout
    }

    private func cyclePhotoCardStyle(_ id: String) {
        guard !editorClosed, !isPosting, editorGeneration == AccountStorage.generation,
              let index = stickers.firstIndex(where: { $0.id == id && $0.photoLayout == "strip" }) else { return }
        snapshot()
        stickers[index].style = ((stickers[index].style ?? 0) + 1) % 3
        Haptics.tap()
    }

    /// Instagram's drag-to-delete well — appears while a sticker is held,
    /// turns red and grows when the sticker hovers over it.
    private var trashWell: some View {
        ZStack {
            Circle()
                .fill(trashArmed ? Color.red : Color.black.opacity(0.55))
                .frame(width: trashArmed ? 60 : 48, height: trashArmed ? 60 : 48)
                .overlay { Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5) }
            Image(systemName: trashArmed ? "trash.fill" : "trash")
                .font(.system(size: trashArmed ? 22 : 18, weight: .bold))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: trashArmed)
    }

    // MARK: - Top bar

    /// Chrome is laid out inside the same stage rectangle as the media.
    private var topBar: some View {
        GeometryReader { geo in
            let topInset: CGFloat = 12

            ZStack(alignment: .top) {
                HStack(spacing: 10) {
                    WhisperStoryControl(symbol: "xmark", label: "Save draft and close") { closeWithAutosave() }
                    if !history.isEmpty {
                        WhisperStoryControl(symbol: "arrow.uturn.backward", label: "Undo Story edit") { undo() }
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: history.isEmpty)

                VStack(alignment: .leading, spacing: 10) {
                if isSharedPost {
                    Button {
                        Haptics.tap(); activeTool = .background
                    } label: {
                        Label("Background", systemImage: "circle.lefthalf.filled")
                            .font(.caption.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 44)
                            .background(Color(white: 0.12).opacity(0.62), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("storyBackgroundPicker")
                }

                if let music {
                    musicPill(music)
                        .frame(maxWidth: 236)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 56)
                .padding(.top, 56)

                HStack {
                Spacer(minLength: 0)
                ScrollView(.vertical) {
                VStack(spacing: 8) {
                    WhisperStoryControl(symbol: "textformat", label: "Add text") { beginInlineText(forID: nil) }
                    WhisperStoryControl(symbol: "face.smiling.inverse", label: "Story attachments") { editingTextID = nil; activeTool = .sticker }
                    WhisperStoryControl(symbol: "music.note", label: "Choose music") { editingTextID = nil; activeTool = .music }
                    if videoURL == nil && !isSharedPost {
                        WhisperStoryControl(symbol: "sparkles", label: "Photo effects and AI editing") { showsEffects = true }
                    }
                    if showsExtraTools {
                        WhisperStoryControl(symbol: "square.stack", label: "Story templates") { activeTool = .templates }
                        WhisperStoryControl(symbol: "pin", label: "Create a reusable template") { activeTool = .makeTemplate }
                        WhisperStoryControl(symbol: "photo.on.rectangle.angled", label: "Add a photo") { replacingPhotoID = nil; showPhotoStickerPicker = true }
                        if videoURL == nil {
                            WhisperStoryControl(symbol: "scribble.variable", label: "Draw") { isDrawing = true }
                        }
                        WhisperStoryControl(symbol: "questionmark", label: "Story editing guide") { showStoryHelp = true }
                    }
                    WhisperStoryControl(symbol: showsExtraTools ? "chevron.up" : "chevron.down", label: showsExtraTools ? "Fewer tools" : "More tools") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showsExtraTools.toggle() }
                    }
                }
                }.scrollBounceBehavior(.basedOnSize).frame(width: 44, height: max(44, geo.size.height - 24), alignment: .top)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: music != nil)
        }
    }

    // MARK: - History / layer ops

    private func snapshot() {
        history.append((stickers: stickers, music: music, image: editedImage))
        if history.count > 30 { history.removeFirst(history.count - 30) }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        Haptics.tap()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            stickers = last.stickers
            music = last.music
            editedImage = last.image
        }
    }

    private func bringToFront(_ id: String) {
        guard let idx = stickers.firstIndex(where: { $0.id == id }),
              idx != stickers.count - 1 else { return }
        snapshot()
        let item = stickers.remove(at: idx)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            stickers.append(item)
        }
        Haptics.tap()
    }

    private func sendToBack(_ id: String) {
        guard let idx = stickers.firstIndex(where: { $0.id == id }), idx != 0 else { return }
        snapshot()
        let item = stickers.remove(at: idx)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            stickers.insert(item, at: 0)
        }
        Haptics.tap()
    }

    private func duplicate(_ id: String) {
        guard let original = stickers.first(where: { $0.id == id }) else { return }
        snapshot()
        var copy = original
        copy.id = UUID().uuidString
        copy.x = min(0.94, original.x + 0.05)
        copy.y = min(0.94, original.y + 0.05)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            stickers.append(copy)
        }
        Haptics.tap()
    }

    private func glassButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    /// Spotify-style pill at the top of the editor showing album art, title,
    /// artist, and a small remove button. Tapping the pill reopens the music
    /// picker so the user can swap tracks without re-adding from scratch.
    private func musicPill(_ m: WhisperStoryMusic) -> some View {
        Button {
            Haptics.tap()
            activeTool = .music
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Color.white.opacity(0.12)
                    if let art = m.artworkURL, let url = URL(string: art) {
                        WhisperCachedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Color.clear
                            }
                        }
                    } else {
                        Image(systemName: "music.note")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(.rect(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.2), lineWidth: 0.5) }

                VStack(alignment: .leading, spacing: 1) {
                    Text(m.title)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    Text(m.artist)
                        .font(.caption2)
                        .opacity(0.75)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 130, alignment: .leading)

                EqualizerBars()
                    .padding(.trailing, 2)

                Button {
                    Haptics.tap()
                    snapshot(); music = nil
                    stickers.removeAll { $0.kind == .music }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 5)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sticker tray

    private func selectAttachment(_ label: String) {
        guard !editorClosed, !isPosting, editorGeneration == AccountStorage.generation else { return }
        guard WhisperStoryTrayTool(rawValue: label)?.unavailableMessage == nil else { return }
        if label == "Portrait", let url = AuthenticationService.shared.currentUser.profileImageURL {
            var layer = WhisperStorySticker(kind: .photo, imageURL: url); layer.shape = "circle"
            addSticker(layer); return
        }
        let routes: [String: Tool] = ["Location": .location, "Mention": .mention, "Music": .music, "GIF": .gif, "Templates": .templates, "Frames": .layout, "Photostrip": .layout, "Cutouts": .cutout, "Questions": .question, "Reaction": .reaction, "Poll": .poll, "Slider": .slider, "Link": .link, "Hashtag": .hashtag, "Countdown": .countdown, "Layout": .layout, "My template": .makeTemplate]
        selectedLayout = label == "Frames" ? .frame : label == "Photostrip" ? .strip : .grid
        editingLink = nil; replacingPhotoID = nil; editingPhotoCard = nil
        pendingTool = routes[label]
        pendingPhotoPicker = label == "Photo" || label == "Portrait"
        activeTool = nil
    }

    /// The Instagram sticker tray's tool pills — the extra creators the old
    /// side rail carried now live HERE (Location · Mention · Hashtag · GIF ·
    /// Photo · Poll · Question · Slider · Countdown), white kit pills on the
    /// dark tray, each opening its existing creator.
    private func stickerTrayTools(query: String) -> some View {
        let tools: [(icon: String, label: String, tool: Tool?)] = [
            ("music.note", "Music", .music),
            ("square.stack", "Templates", .templates),
            ("mappin.circle.fill", "Location", .location),
            ("at", "Mention", .mention),
            ("number", "Hashtag", .hashtag),
            ("photo.on.rectangle.angled", "GIF", .gif),
            ("photo.fill.on.rectangle.fill", "Photo", nil),
            ("rectangle.split.2x2", "Layout", .layout),
            ("rectangle.portrait", "Frames", .layout),
            ("photo.stack", "Photostrip", .layout),
            ("scissors", "Cutouts", .cutout),
            ("link", "Link", .link),
            ("pin", "My template", .makeTemplate),
            ("chart.bar.doc.horizontal", "Poll", .poll),
            ("questionmark.bubble.fill", "Question", .question),
            ("slider.horizontal.below.rectangle", "Slider", .slider),
            ("timer", "Countdown", .countdown),
        ]
        let matches = tools.filter { query.isEmpty || $0.label.localizedStandardContains(query) }
        return VStack(spacing: 8) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 2) {
            ForEach(matches, id: \.label) { entry in
                Button {
                    Haptics.tap()
                    if entry.label == "Frames" { selectedLayout = .frame }
                    else if entry.label == "Photostrip" { selectedLayout = .strip }
                    else if entry.tool == .layout { selectedLayout = .grid }
                    if entry.tool == .link { editingLink = nil }
                    replacingPhotoID = nil
                    pendingTool = entry.tool
                    pendingPhotoPicker = entry.tool == nil
                    activeTool = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: entry.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(stickerToolColor(entry.tool))
                        Text(entry.label)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(.white, in: .rect(cornerRadius: 9))
                    .frame(minHeight: 44).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.label)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        if query.isEmpty || "date time clock".localizedStandardContains(query) {
            HStack(spacing: 24) {
                Button {
                    var layer = WhisperStorySticker(kind: .text, text: Date.now.formatted(.dateTime.month(.abbreviated).day()).uppercased(), color: "#FFFFFF", style: 0)
                    layer.fontName = "typewriter"; layer.fontSize = 26; addSticker(layer)
                } label: { Text(Date.now.formatted(.dateTime.month(.abbreviated).day()).uppercased()).font(.system(size: 22, weight: .medium, design: .monospaced)).frame(minHeight: 44) }.accessibilityLabel("Add today's date")
                Button {
                    var layer = WhisperStorySticker(kind: .text, text: Date.now.formatted(date: .omitted, time: .shortened), color: "#FFFFFF", style: 0)
                    layer.fontSize = 44; addSticker(layer)
                } label: { Text(Date.now.formatted(date: .omitted, time: .shortened)).font(.system(size: 26, weight: .black)).frame(minHeight: 44) }.accessibilityLabel("Add current time")
            }.foregroundStyle(.white)
        }
        }
    }

    private func stickerToolColor(_ tool: Tool?) -> Color {
        switch tool {
        case .music, .question, .poll: .pink
        case .location, .hashtag, .templates: .purple
        case .mention, .countdown: .orange
        default: Color(red: 0.02, green: 0.52, blue: 0.35)
        }
    }

    /// Jasper's floating pill — centered above the bottom controls; expands
    /// into the glass box with the options menu (spark / captions / ask).
    private var storyJasperDockOverlay: some View {
        VStack {
            Spacer()
            StoryJasperDock(
                image: image,
                onCaption: { text in
                    var s = WhisperStorySticker(kind: .text)
                    s.text = text
                    s.style = 0
                    s.color = Color.white.toHex()
                    s.background = Color.black.toHex()
                    addSticker(s)
                },
                onQuestion: { q in
                    let s = WhisperStorySticker(kind: .question, text: q)
                    addSticker(s)
                }
            )
            .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Share bar

    /// The kit send row — "Your story" avatar pill on the left, the white
    /// circular send arrow on the right (Instagram's editor grammar).
    private var shareBar: some View {
        HStack(spacing: 8) {
                Button { sendAfterPosting = false; post() } label: {
                    HStack(spacing: 8) {
                        WhisperAvatar(username: editorUsername, size: 26)
                        Text("Your story").font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity).frame(minHeight: 48)
                    .background(.white.opacity(0.15), in: .capsule)
                }
                Button { closeWithAutosave() } label: {
                    Label("Save draft", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(minHeight: 48)
                        .background(.white.opacity(0.15), in: .capsule)
                }
                Button { activeTool = .share } label: {
                    Image(systemName: "arrow.right").font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.black).frame(width: 48, height: 48)
                        .background(.white, in: .circle)
                }.accessibilityLabel("Story sharing options")
            }
            .buttonStyle(.plain).foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(maxWidth: 560)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityIdentifier("story.editor.share")
    }

    private var editorUsername: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    // MARK: - Tool sheets

    @ViewBuilder
    private func toolSheet(for tool: Tool) -> some View {
        switch tool {
        case .templates:
            WhisperStoryStarterSheet(onPick: { starter in
                appendLayers(starter.stickers().map { layer in var value = layer; value.scale *= canvasSize.width / 390; return value })
            }, photo: image, onLayout: { layout in
                editingPhotoCard = nil; selectedLayout = layout; pendingTool = .layout; activeTool = nil
            }, onPersonal: { template in
                appendLayers(template.layers(for: canvasSize.width))
            }, onCreate: { pendingTool = .makeTemplate; activeTool = nil })
        case .layout:
            if let existing = editingPhotoCard {
                WhisperStoryPhotoCardEditor(layout: selectedLayout, existing: existing) { updated in
                    guard !editorClosed, !isPosting, editorGeneration == AccountStorage.generation,
                          let index = stickers.firstIndex(where: { $0.id == updated.id }) else { return }
                    replaceEditedLayer(updated, at: index); editingPhotoCard = nil; activeTool = nil
                }.id(existing.id)
            } else {
                WhisperStoryPhotoLayoutSheet(layout: selectedLayout, stageWidth: canvasSize.width) { appendLayers($0) }
            }
        case .cutout:
            WhisperStoryCutoutSheet { addSticker($0) }
        case .link:
            WhisperStoryLinkSheet(existing: editingLink) { layer in
                guard !editorClosed, editorGeneration == AccountStorage.generation else { return }
                if let index = stickers.firstIndex(where: { $0.id == layer.id }) { replaceEditedLayer(layer, at: index); activeTool = nil }
                else { addSticker(layer) }
                editingLink = nil
            }
        case .makeTemplate:
            WhisperStoryTemplateBuilder(stickers: stickers, stageWidth: canvasSize.width) { activeTool = nil }
        case .share:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Share your story").font(.title2.weight(.bold))
                        Spacer()
                        Button { activeTool = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .accessibilityLabel("Keep editing")
                    }
                    Text("Your story stays available for 24 hours. Sending to a chat shares a reference, not a separate copy.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        activeTool = nil; sendAfterPosting = false; post()
                    } label: {
                        Label("Publish to your story", systemImage: "plus.circle").frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    Button {
                        activeTool = nil; sendAfterPosting = true; post()
                    } label: {
                        Label("Publish, then send in a message", systemImage: "paperplane").frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.bordered)
                }.padding(20)
            }
        case .background:
            WhisperStoryBackgroundPicker(original: image, photo: backgroundPhoto, selection: Binding(get: { backgroundSelection }, set: { backgroundPhotoItem = nil; backgroundSelection = $0 }), photoItem: $backgroundPhotoItem, isLoading: isLoadingBackground, error: backgroundError, onDone: { activeTool = nil })
        case .text:
            // Inline editor handles text — keep this branch as a no-op so
            // the enum stays exhaustive.
            Color.clear
        case .sticker:
            WhisperStoryAttachmentTray(photo: workingImage, onTool: selectAttachment, onSticker: { addSticker($0) })
        case .poll:
            StoryPollSheet { question, options in
                addSticker(WhisperStorySticker(kind: .poll, text: question, pollOptions: options))
            }
        case .slider:
            StorySliderSheet { question, emoji in
                addSticker(WhisperStorySticker(kind: .slider, text: question, sliderEmoji: emoji))
            }
        case .question:
            StoryQuestionSheet { question, bgHex, fgHex in
                var s = WhisperStorySticker(kind: .question, text: question)
                s.background = bgHex
                s.color = fgHex
                addSticker(s)
            }
        case .music:
            StoryMusicSheet(current: music, onEditSection: { song in
                guard canMutateDocument else { return }
                pendingInlineMusic = song; activeTool = nil
            }) { picked in
                guard !editorClosed, !isPosting, editorGeneration == AccountStorage.generation else { return }
                snapshot(); music = picked
                if let index = stickers.firstIndex(where: { $0.kind == .music }) {
                    stickers[index].musicTitle = picked.title
                    stickers[index].musicArtist = picked.artist
                    stickers[index].musicArtwork = picked.artworkURL
                } else {
                    stickers.append(WhisperStorySticker(kind: .music, y: 0.80, musicTitle: picked.title, musicArtist: picked.artist, musicArtwork: picked.artworkURL))
                }
                activeTool = nil
            }
        case .location:
            WhisperStoryPlacePicker { name, latitude, longitude in
                var layer = WhisperStorySticker(kind: .location, label: name)
                layer.latitude = latitude; layer.longitude = longitude; addSticker(layer)
            }
        case .reaction:
            Color.clear
        case .mention:
            StoryMentionSheet { username in
                addSticker(WhisperStorySticker(kind: .mention, label: username))
            }
        case .gif:
            StoryGifSheet { url in
                addSticker(WhisperStorySticker(kind: .gif, imageURL: url))
            }
        case .hashtag:
            StoryHashtagSheet { tag in
                addSticker(WhisperStorySticker(kind: .hashtag, label: tag))
            }
        case .countdown:
            StoryCountdownSheet { title, date in
                var s = WhisperStorySticker(kind: .countdown, label: title)
                s.text = ISO8601DateFormatter().string(from: date)
                addSticker(s)
            }
        case .photo:
            // Handled by the rail's photo button (system photo picker).
            Color.clear
        }
    }

    /// Instagram draw mode — full-screen capture surface with marker
    /// chips, a width slider, the color row, undo, and Done.
    private var drawOverlay: some View {
        ZStack {
            GeometryReader { geo in
                Color.clear
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                // Strokes normalize against the 9:16 STAGE,
                                // not the screen, so they land where drawn on
                                // every device and bake at the right spot.
                                let stage = Self.stageSize(in: geo.size)
                                let origin = Self.stageOrigin(in: geo.size)
                                let p = CGPoint(
                                    x: min(1, max(0, (v.location.x - origin.x) / max(1, stage.width))),
                                    y: min(1, max(0, (v.location.y - origin.y) / max(1, stage.height)))
                                )
                                if activeStroke == nil {
                                    activeStroke = WhisperStoryDrawStroke(
                                        points: [p],
                                        colorHex: drawColorHex,
                                        width: drawWidth,
                                        marker: drawMarker,
                                        referenceWidth: stage.width
                                    )
                                } else {
                                    activeStroke?.points.append(p)
                                }
                            }
                            .onEnded { _ in
                                if let s = activeStroke, !s.points.isEmpty {
                                    drawStrokes.append(s)
                                }
                                activeStroke = nil
                            }
                    )
            }

                VStack {
                    HStack {
                        Button {
                            Haptics.tap()
                            _ = drawStrokes.popLast()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color(white: 0.12).opacity(0.62), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Undo drawing stroke")
                        .disabled(drawStrokes.isEmpty)
                        .opacity(drawStrokes.isEmpty ? 0.4 : 1)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 2) {
                                ForEach(WhisperStoryDrawStroke.Marker.allCases, id: \.self) { marker in
                                    drawMarkerChip(marker.title, marker: marker)
                                }
                            }
                        }.frame(height: 44)
                        Button {
                            Haptics.tap()
                            isDrawing = false
                        } label: {
                            Text("Done")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .frame(minHeight: 44)
                                .background(.white, in: Capsule())
                        }
                        .buttonStyle(.plain).fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .accessibilityIdentifier("story.drawing.header")

                    Spacer()

                    VStack(spacing: 12) {
                        VStack(spacing: 8) {
                            Slider(value: $drawWidth, in: 3...22)
                                .tint(.white)
                                .accessibilityLabel("Brush width")
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(whisperStoryDrawColors, id: \.self) { hex in
                                    Button {
                                        Haptics.tap()
                                        drawColorHex = hex
                                    } label: {
                                        Circle()
                                            .fill(whisperColorFromHex(hex) ?? .white)
                                            .frame(width: 24, height: 24)
                                            .overlay(
                                                Circle().strokeBorder(
                                                    .white,
                                                    lineWidth: drawColorHex == hex ? 3 : 1
                                                )
                                            )
                                            .frame(width: 44, height: 44).contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Drawing color \(hex)")
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.14), lineWidth: 0.5) }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
        }
    }

    private func drawMarkerChip(_ label: String, marker: WhisperStoryDrawStroke.Marker) -> some View {
        Button {
            Haptics.tap()
            drawMarker = marker
        } label: {
            Image(systemName: marker.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(drawMarker == marker ? .black : .white)
                .frame(width: 32, height: 36)
                .background(
                    drawMarker == marker ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.15)),
                    in: Capsule()
                )
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(drawMarker == marker ? .isSelected : [])
    }

    private func applyStoryMusic(_ picked: WhisperStoryMusic) {
        guard canMutateDocument else { return }
        snapshot(); music = picked; inlineMusic = nil; activeTool = nil
        if let index = stickers.firstIndex(where: { $0.kind == .music }) {
            stickers[index].musicTitle = picked.title; stickers[index].musicArtist = picked.artist
            stickers[index].musicArtwork = picked.artworkURL
        } else {
            stickers.append(WhisperStorySticker(kind: .music, y: 0.80, musicTitle: picked.title, musicArtist: picked.artist, musicArtwork: picked.artworkURL))
        }
    }

    private func existingText() -> WhisperStorySticker? {
        guard let id = editingTextID else { return nil }
        return stickers.first { $0.id == id }
    }

    // MARK: - Inline text editor

    private let inlineTextPalette: [Color] = [
        .white, .black, Color(red: 1.0, green: 0.34, blue: 0.34),
        Color(red: 1.0, green: 0.58, blue: 0.27), Color(red: 1.0, green: 0.85, blue: 0.30),
        Color(red: 0.42, green: 0.86, blue: 0.46), Color(red: 0.30, green: 0.78, blue: 0.94),
        Color(red: 0.32, green: 0.50, blue: 1.0), Color(red: 0.68, green: 0.40, blue: 1.0),
        Color(red: 1.0, green: 0.44, blue: 0.78)
    ]

    /// Enter the inline text editor either to add a new text sticker or to
    /// re-edit an existing one identified by `id`. Preloads draft state
    /// from the existing sticker so colour/style survive the round-trip.
    private func beginInlineText(forID id: String?) {
        guard !inlineTextEditing, activeTool == nil, !isPosting, !editorClosed else { return }
        Haptics.tap()
        editingTextID = id
        if let id, let existing = stickers.first(where: { $0.id == id }) {
            inlineDraftText = existing.text ?? ""
            inlineDraftStyle = existing.style ?? 0
            inlineDraftColor = (existing.color.flatMap { Color(hex: $0) }) ?? .white
            inlineDraftBackground = (existing.background.flatMap { Color(hex: $0) }) ?? .black
            inlineDraftFont = existing.fontName
            inlineDraftSize = existing.fontSize ?? (existing.style == 5 ? 26 : existing.style == 4 ? 30 : 28)
            inlineDraftAlignment = existing.textAlignment ?? "center"
        } else {
            inlineDraftText = ""
            inlineDraftStyle = 0
            inlineDraftColor = .white
            inlineDraftBackground = .black
            inlineDraftFont = "classic"; inlineDraftSize = 28; inlineDraftAlignment = "center"
        }
        inlineTextHistory = []; inlineUndoTarget = nil
        inlineTextEditing = true
    }

    private func cancelInlineText() {
        inlineTextFocused = false; cancelInlineUndoRepeat(); inlineUndoTarget = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { inlineTextEditing = false }
        editingTextID = nil
    }

    /// Commit the inline draft as a sticker (new or updated) and dismiss
    /// the overlay. Empty input cancels without mutating the canvas.
    private func commitInlineText() {
        guard canMutateDocument, inlineTextEditing else { return }
        inlineTextFocused = false
        let trimmed = inlineDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                inlineTextEditing = false
            }
            editingTextID = nil
        }
        guard !trimmed.isEmpty else { return }
        snapshot()
        if let id = editingTextID, let idx = stickers.firstIndex(where: { $0.id == id }) {
            var s = stickers[idx]
            s.text = trimmed
            s.style = inlineDraftStyle
            s.color = inlineDraftColor.toHex()
            s.background = inlineDraftBackground.toHex()
            s.fontName = inlineDraftFont; s.fontSize = inlineDraftSize; s.textAlignment = inlineDraftAlignment
            stickers[idx] = s
        } else {
            var s = WhisperStorySticker(kind: .text)
            s.text = trimmed
            s.style = inlineDraftStyle
            s.color = inlineDraftColor.toHex()
            s.background = inlineDraftBackground.toHex()
            s.fontName = inlineDraftFont; s.fontSize = inlineDraftSize; s.textAlignment = inlineDraftAlignment
            stickers.append(s)
        }
    }

    /// Build a transient sticker that mirrors the current draft so the
    /// inline preview matches exactly what'll land on the canvas.
    private var inlineDraftSticker: WhisperStorySticker {
        var s = WhisperStorySticker(kind: .text)
        s.text = inlineDraftText.isEmpty ? " " : inlineDraftText
        s.style = inlineDraftStyle
        s.color = inlineDraftColor.toHex()
        s.background = inlineDraftBackground.toHex()
        s.fontName = inlineDraftFont; s.fontSize = inlineDraftSize; s.textAlignment = inlineDraftAlignment
        return s
    }

    private var inlineTextOverlay: some View {
        ZStack {
            // Dismiss the keyboard without silently committing the draft.
            Color.black.opacity(0.55)
                .contentShape(.rect)
                .onTapGesture { inlineTextFocused = false }

            VStack(spacing: 0) {
                inlineTextHeader.fixedSize(horizontal: false, vertical: true)
                // This space excludes both the commit row and the keyboard tools.
                GeometryReader { geometry in
            ScrollView {
                WhisperStoryStickerText(sticker: inlineDraftSticker,
                    authoring: WhisperStoryStickerAuthoring(text: $inlineDraftText, focus: $inlineTextFocused))
                    .padding(.horizontal, 24)
                    .task { guard canMutateDocument else { return }; inlineTextFocused = true }
                    .onChange(of: inlineDraftText) { old, new in recordInlineTextSnapshot(previous: old, next: new) }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
                }
                VStack(spacing: 0) {
                    WhisperMentionSuggestionsBar(text: $inlineDraftText)
                    ScrollView { inlineTextToolbar }
                        .frame(maxHeight: 132).scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .transition(.opacity)
    }

    private var inlineTextHeader: some View {
                HStack {
                    Button {
                        Haptics.tap()
                        cancelInlineText()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel text editing")
                    Spacer()
                    Button { inlineTextFocused.toggle() } label: {
                        Image(systemName: inlineTextFocused ? "keyboard.chevron.compact.down" : "keyboard")
                            .frame(width: 44, height: 44).foregroundStyle(.white)
                    }.accessibilityLabel(inlineTextFocused ? "Hide keyboard" : "Show keyboard")
                    Button {
                        commitInlineText()
                    } label: {
                        Text("Done")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .frame(minHeight: 44)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("story.text.done")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
    }

    /// Background pill behind the TextField matches the chosen text style.
    @ViewBuilder
    private var textFieldBackground: some View {
        switch inlineDraftStyle {
        case 1: // Filled
            inlineDraftBackground.opacity(0.9)
                .clipShape(.rect(cornerRadius: 10))
        case 2: // Outline
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(inlineDraftColor.opacity(0.9), lineWidth: 2)
                .background(.black.opacity(0.0001))
        default:
            Color.clear
        }
    }

    /// Floating toolbar that lives above the keyboard (via `safeAreaInset`).
    /// Holds style toggles + colour swatches — the two controls users reach
    /// for most while typing.
    private var inlineTextToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(["Font", "Style", "Color"].enumerated()), id: \.offset) { index, label in
                    Button { inlineTextTool = index; Haptics.tap() } label: {
                        Text(label).font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(inlineTextTool == index ? Color.white.opacity(0.16) : .clear, in: .capsule)
                    }.accessibilityAddTraits(inlineTextTool == index ? .isSelected : [])
                }
                inlineUndoPill
            }.padding(.horizontal, 14)
            if inlineTextTool == 0 {
            HStack(spacing: 12) {
                Menu {
                    Button("Left") { inlineDraftAlignment = "leading" }
                    Button("Center") { inlineDraftAlignment = "center" }
                    Button("Right") { inlineDraftAlignment = "trailing" }
                } label: { Image(systemName: "text.alignleft").frame(width: 44, height: 44) }.accessibilityLabel("Text alignment")
                Slider(value: $inlineDraftSize, in: 14...64).tint(.white).accessibilityLabel("Font size")
            }.padding(.horizontal, 14)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(["classic", "editorial", "serif", "rounded", "typewriter"], id: \.self) { name in
                        Button { inlineDraftFont = name } label: {
                            Text(name.capitalized).font(WhisperStoryTypography.font(name, size: 17)).padding(.horizontal, 12).frame(minHeight: 44)
                                .background(inlineDraftFont == name ? Color.white.opacity(0.2) : .clear, in: .capsule)
                        }.buttonStyle(.plain).accessibilityAddTraits(inlineDraftFont == name ? .isSelected : [])
                    }
                }
            }.contentMargins(.horizontal, 14)
            }
            if inlineTextTool == 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    inlineStylePill("Aa", index: 0)
                    inlineStylePill("Filled", index: 1)
                    inlineStylePill("Outline", index: 2)
                    inlineStylePill("Neon", index: 3)
                    inlineStylePill("Strong", index: 4)
                    inlineStylePill("Mono", index: 5)
                }
            }.contentMargins(.horizontal, 14)
            }
            if inlineTextTool == 2 {
            HStack {
                ColorPicker("Text", selection: $inlineDraftColor, supportsOpacity: false)
                ColorPicker("Background", selection: $inlineDraftBackground, supportsOpacity: false)
            }.font(.subheadline).frame(minHeight: 44).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(inlineTextPalette, id: \.self) { c in
                        Button {
                            Haptics.tap()
                            inlineDraftColor = c
                        } label: {
                            Circle()
                                .fill(c)
                                .frame(width: 30, height: 30)
                                .overlay { Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1) }
                                .overlay {
                                    if inlineDraftColor == c {
                                        Circle().strokeBorder(.white, lineWidth: 2.5).padding(-3)
                                    }
                                }
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }.contentMargins(.horizontal, 14)
            }
        }
        .foregroundStyle(.white).buttonStyle(.plain)
        .padding(.vertical, 8)
        .background(Color(white: 0.10))
    }

    /// Keep the initial value even for a single word, then group typing at
    /// whitespace boundaries and preserve deletions as reversible changes.
    private func recordInlineTextSnapshot(previous: String, next: String) {
        if let target = inlineUndoTarget {
            inlineUndoTarget = nil
            if next == target { return }
        }
        guard previous != next else { return }
        // Avoid duplicate consecutive snapshots.
        if inlineTextHistory.last == previous { return }
        let crossedWordBoundary: Bool = {
            guard let lastChar = next.last else { return false }
            return lastChar == " " || lastChar == "\n"
        }()
        let didDelete = next.count < previous.count
        guard inlineTextHistory.isEmpty || crossedWordBoundary || didDelete else { return }
        inlineTextHistory.append(previous)
        if inlineTextHistory.count > 50 {
            inlineTextHistory.removeFirst(inlineTextHistory.count - 50)
        }
    }

    private func performInlineUndo() {
        guard let last = inlineTextHistory.popLast() else { return }
        Haptics.tap()
        inlineUndoTarget = last
        inlineDraftText = last
    }

    /// Undo pill — tap once to step back a word, long-press to rewind
    /// rapidly (every 0.12s) until the history is empty.
    private var inlineUndoPill: some View {
        let enabled = !inlineTextHistory.isEmpty
        return Button {
            performInlineUndo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.footnote.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minWidth: 44, minHeight: 44)
                .background(Color.white.opacity(enabled ? 0.18 : 0.06), in: Capsule())
                .foregroundStyle(enabled ? .white : Color.white.opacity(0.4))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onLongPressGesture(minimumDuration: 0.35, pressing: { pressing in
            if !pressing { cancelInlineUndoRepeat() }
        }, perform: { startInlineUndoRepeat() })
        .onDisappear { cancelInlineUndoRepeat() }
        .onChange(of: inlineTextEditing) { _, editing in
            if !editing { cancelInlineUndoRepeat() }
        }
        .accessibilityLabel("Undo")
        .accessibilityHint("Long-press to undo multiple times.")
    }

    private func startInlineUndoRepeat() {
        cancelInlineUndoRepeat()
        inlineUndoRepeatTask = Task { @MainActor in
            while !Task.isCancelled, !inlineTextHistory.isEmpty {
                performInlineUndo()
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func cancelInlineUndoRepeat() {
        inlineUndoRepeatTask?.cancel()
        inlineUndoRepeatTask = nil
    }

    private func inlineStylePill(_ label: String, index: Int) -> some View {
        Button {
            Haptics.tap()
            inlineDraftStyle = index
        } label: {
            Text(label)
                .font(.footnote.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    inlineDraftStyle == index ? Color.white : Color.white.opacity(0.12),
                    in: Capsule()
                )
                .foregroundStyle(inlineDraftStyle == index ? .black : .white)
        }
        .buttonStyle(.plain)
    }

    /// Loads the chosen photo, uploads it to the media bucket, and drops it
    /// onto the canvas as a draggable photo sticker.
    private func handlePhotoStickerPick(_ item: PhotosPickerItem) async {
        guard !editorClosed, !isPosting, editorGeneration == AccountStorage.generation else { return }
        isLoadingSticker = true
        defer {
            if photoStickerPicker == item { photoStickerPicker = nil; isLoadingSticker = false }
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            if !Task.isCancelled { postError = "Couldn't load this photo. Choose it again to retry." }; return
        }
        let prepared = await Task.detached(priority: .userInitiated) {
            WhisperImageCache.decode(data, maxPixelSize: 1920)?.jpegData(compressionQuality: 0.9)
        }.value
        guard !Task.isCancelled, !editorClosed, editorGeneration == AccountStorage.generation else { return }
        guard let prepared else { postError = "This photo couldn't be opened. Try another image."; return }
        let stickerID = UUID().uuidString
        let urls = await WhisperBackendService.shared.uploadMedia(datas: [prepared], postID: "sticker-\(stickerID)")
        guard !Task.isCancelled, !editorClosed, editorGeneration == AccountStorage.generation else { return }
        guard let url = urls.first else { postError = "Couldn't add the photo. Your Story is still here; choose the photo again to retry."; return }
        if let id = replacingPhotoID, let index = stickers.firstIndex(where: { $0.id == id }) {
            snapshot(); stickers[index].imageURL = url; replacingPhotoID = nil
        } else {
            var layer = WhisperStorySticker(kind: .photo, imageURL: url)
            if let decoded = UIImage(data: prepared) { layer.mediaAspectRatio = Double(decoded.size.width / max(1, decoded.size.height)) }
            addSticker(layer)
        }
    }

    private func appendLayers(_ layers: [WhisperStorySticker]) {
        guard !editorClosed, !isPosting, !didPublish, editorGeneration == AccountStorage.generation else { return }
        snapshot(); stickers.append(contentsOf: layers); activeTool = nil
    }

    private func addSticker(_ sticker: WhisperStorySticker) {
        guard !editorClosed, !isPosting, !didPublish, editorGeneration == AccountStorage.generation else { return }
        snapshot()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            stickers.append(sticker)
        }
        activeTool = nil
    }

    // MARK: - Post

    /// Snapshot the current canvas to disk as a draft (if there's anything
    /// worth saving), then dismiss. Lets the user back out without losing
    /// 5 stickers of work to an accidental tap.
    private func closeWithAutosave() {
        guard !inlineTextEditing, inlineMusic == nil, pendingInlineMusic == nil, !isDrawing, editingLayer == nil, activeTool == nil, !showsEffects,
              !missingDraftEdit, !isPosting, !isLoadingBackground, !isLoadingSticker, !didPublish, !editorClosed, editorGeneration == AccountStorage.generation else { return }
        do {
            let saved = WhisperStoryDraftService.shared.save(
                image: image,
                stickers: stickers,
                photoScale: photoScale,
                photoOffset: photoOffset,
                canvasWidth: canvasSize.width,
                backgroundSelection: isSharedPost ? backgroundSelection : nil,
                backgroundPhoto: backgroundPhoto,
                drawStrokes: drawStrokes,
                music: music,
                videoURL: videoURL,
                editedImage: editedImage
            )
            guard saved else { postError = "Your draft couldn't be saved. Please try closing again when storage is available."; return }
        }
        editorClosed = true
        dismiss()
    }

    @State private var publicationID: String = UUID().uuidString.lowercased()
    @State private var pendingPublication: WhisperStoryPublication? = nil

    private func post() {
        guard !inlineTextEditing, inlineMusic == nil, pendingInlineMusic == nil, !isDrawing, editingLayer == nil, activeTool == nil, !showsEffects,
              !missingDraftEdit, !isPosting, !isLoadingBackground, !isLoadingSticker, !didPublish, !editorClosed, editorGeneration == AccountStorage.generation else { return }
        isPosting = true
        if pendingPublication == nil {
            pendingPublication = WhisperStoryPublication(
                image: renderComposite(),
                metadata: WhisperStoryMetadata(stickers: stickers, musicSelection: music?.storySelection, referenceStageWidth: canvasSize.width).jsonString,
                music: music, videoURL: videoURL
            )
        }
        guard let publication = pendingPublication else { isPosting = false; return }
        Task {
            let row = await stories.postStory(image: publication.image, caption: nil, metadata: publication.metadata, music: publication.music, videoURL: publication.videoURL, publicationID: publicationID, uploader: publication.uploader)
            guard editorGeneration == AccountStorage.generation, !editorClosed else { return }
            await MainActor.run {
                isPosting = false
                if let row {
                    Haptics.success()
                    WhisperStoryDraftService.shared.clear()
                    didPublish = true; pendingPublication = nil
                    if sendAfterPosting { publishedStory = row }
                    else { editorClosed = true; dismiss(); onPosted() }
                } else {
                    Haptics.warning()
                    postError = stories.lastError
                        ?? "Story upload failed. Check your connection and try again."
                }
            }
        }
    }

    /// Flatten the photo layer (blurred bg + transformed foreground) into a
    /// single JPEG. Stickers are intentionally NOT baked — they're rendered
    /// live by the viewer from `metadata.stickers` so polls/sliders/questions
    /// stay interactive on the saved story, and so we don't double-render
    /// each sticker (once baked + once overlaid at viewer geometry).
    @MainActor
    private func renderComposite() -> UIImage {
        // ALWAYS 1080×1920 — the Instagram story canvas — regardless of the
        // phone it was composed on. Pinch/drag offsets are in stage points,
        // so they scale by (1080 / stage width) into export pixels.
        let size = CGSize(width: 1080, height: 1920)
        let stageWidth = max(1, canvasSize.width)
        let k: CGFloat = size.width / stageWidth
        let img = workingImage
        let bakedScale = photoScale
        let bakedOffset = CGSize(width: photoOffset.width * k, height: photoOffset.height * k)
        let renderer = ImageRenderer(content:
            ZStack {
                if isSharedPost {
                    WhisperSharedStoryBackdrop(original: img, selection: backgroundSelection, photo: backgroundPhoto, size: size)
                } else {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 60 * k)
                    .clipped()
                Color.black.opacity(0.15)
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(bakedScale)
                    .offset(bakedOffset)
                    .clipped()
                }
                if !drawStrokes.isEmpty && videoURL == nil {
                    WhisperStoryDrawCanvas(strokes: drawStrokes, active: nil)
                        .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height)
        )
        renderer.scale = 1.0
        return renderer.uiImage ?? workingImage
    }

    private var postingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Sharing…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Sticker on the stage

/// A sticker as rendered on the editor stage — pure presentation. Every
/// gesture lives in `StoryStageGestureOverlay`; this view only reports its
/// UNSCALED layout size so the router can hit-test the real frame. Model
/// mutations flow straight into `sticker` from the editor, so the view is
/// always the single source of truth (no transient gesture state to reset).
private struct StickerCanvasItem: View {
    let sticker: WhisperStorySticker
    let canvasSize: CGSize
    let authorUsername: String
    let onSize: (CGSize) -> Void

    var body: some View {
        WhisperStoryStickerView(sticker: sticker, stageWidth: canvasSize.width, isInteractive: false, authorUsername: authorUsername)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                onSize(size)
            }
            .scaleEffect(CGFloat(sticker.scale), anchor: .center)
            .rotationEffect(.radians(sticker.rotation), anchor: .center)
            .position(x: sticker.x * canvasSize.width, y: sticker.y * canvasSize.height)
            .allowsHitTesting(false)
    }
}

// MARK: - Animated equalizer

/// Three small bouncing bars used inside the music pill to telegraph that a
/// track is attached. Pure SwiftUI, no timer — driven by an implicit
/// repeat-forever animation toggled on appear.
private struct EqualizerBars: View {
    @State private var animate: Bool = false
    private let bars = 3

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.5, height: animate ? CGFloat(6 + (i % 2) * 6) : CGFloat(12 - (i % 2) * 6))
                    .animation(
                        .easeInOut(duration: 0.42)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.11),
                        value: animate
                    )
            }
        }
        .frame(width: 14, height: 14, alignment: .bottom)
        .onAppear { animate = true }
    }
}

// MARK: - Sheet chrome

private struct SheetChrome<Content: View>: View {
    let title: String
    let canDone: Bool
    let onDone: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Add") {
                    onDone()
                    dismiss()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(canDone ? Color.white : Color.white.opacity(0.35))
                .disabled(!canDone)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
            content()
        }
    }
}

// MARK: - Text editor sheet

private struct StoryTextEditorSheet: View {
    let initial: WhisperStorySticker?
    let onDone: (WhisperStorySticker) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var style: Int = 0
    @State private var color: Color = .white
    @State private var background: Color = .black

    private let palette: [Color] = [
        .white, .black, Color(red: 1.0, green: 0.34, blue: 0.34),
        Color(red: 1.0, green: 0.58, blue: 0.27), Color(red: 1.0, green: 0.85, blue: 0.30),
        Color(red: 0.42, green: 0.86, blue: 0.46), Color(red: 0.30, green: 0.78, blue: 0.94),
        Color(red: 0.32, green: 0.50, blue: 1.0), Color(red: 0.68, green: 0.40, blue: 1.0),
        Color(red: 1.0, green: 0.44, blue: 0.78)
    ]

    var body: some View {
        SheetChrome(title: "Text", canDone: !text.trimmingCharacters(in: .whitespaces).isEmpty, onDone: emit) {
            VStack(spacing: 16) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Type something…")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(16)
                    }
                    TextEditor(text: $text)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 120)
                }
                .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 14))
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        stylePill("Aa", index: 0)
                        stylePill("Filled", index: 1)
                        stylePill("Outline", index: 2)
                        stylePill("Neon", index: 3)
                        stylePill("Strong", index: 4)
                        stylePill("Mono", index: 5)
                    }
                    .padding(.horizontal, 16)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(palette, id: \.self) { c in
                            Circle()
                                .fill(c)
                                .frame(width: 32, height: 32)
                                .overlay { Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1) }
                                .overlay {
                                    if color == c { Circle().strokeBorder(.white, lineWidth: 2.5).padding(-3) }
                                }
                                .onTapGesture {
                                    Haptics.tap()
                                    color = c
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            if let initial {
                text = initial.text ?? ""
                style = initial.style ?? 0
                if let h = initial.color, let c = Color(hex: h) { color = c }
                if let h = initial.background, let c = Color(hex: h) { background = c }
            }
        }
    }

    private func emit() {
        var s = initial ?? WhisperStorySticker(kind: .text)
        s.kind = .text
        s.text = text
        s.style = style
        s.color = color.toHex()
        s.background = background.toHex()
        onDone(s)
    }

    private func stylePill(_ label: String, index: Int) -> some View {
        Button {
            Haptics.tap()
            style = index
        } label: {
            Text(label)
                .font(.footnote.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(style == index ? Color.white : Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(style == index ? .black : .white)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Poll / slider / question

private struct StoryPollSheet: View {
    let onDone: (String, [String]) -> Void
    var onCancel: (() -> Void)? = nil
    @State private var question: String = ""
    @State private var optionA: String = "Yes"
    @State private var optionB: String = "No"
    @FocusState private var focused: Bool

    var body: some View {
        StickerBubbleScaffold(
            canDone: !question.trimmingCharacters(in: .whitespaces).isEmpty
                && !optionA.isEmpty && !optionB.isEmpty,
            onDone: { onDone(question.isEmpty ? "Poll" : question, [optionA, optionB]) },
            onCancel: onCancel
        ) {
            VStack(spacing: 12) {
                Text("POLL")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 0.42, green: 0.42, blue: 0.45))
                TextField(
                    "",
                    text: $question,
                    prompt: Text("Ask a question…").foregroundStyle(.gray),
                    axis: .vertical
                )
                .font(.headline.weight(.bold))
                .foregroundStyle(.black)
                .tint(.black)
                .multilineTextAlignment(.center)
                .lineLimit(1...4)
                .focused($focused)
                HStack(spacing: 0) {
                    TextField("", text: $optionA, prompt: Text("Yes").foregroundStyle(.gray.opacity(0.7)))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.black)
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    Divider().frame(height: 30)
                    TextField("", text: $optionB, prompt: Text("No").foregroundStyle(.gray.opacity(0.7)))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.black)
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .font(.subheadline.weight(.semibold))
                .background(Color.black.opacity(0.05), in: .rect(cornerRadius: 12))
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(.white, in: .rect(cornerRadius: 22))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        }
        .onAppear { focused = true }
    }
}

private struct StorySliderSheet: View {
    let onDone: (String, String) -> Void
    var onCancel: (() -> Void)? = nil
    @State private var question: String = "Slide to rate"
    @State private var emoji: String = "❤️"
    @FocusState private var focused: Bool
    private let emojis = ["❤️", "🔥", "😍", "🤣", "😮", "💪", "🏃‍♀️", "🥗", "☕️"]

    var body: some View {
        StickerBubbleScaffold(
            canDone: !question.isEmpty,
            onDone: { onDone(question, emoji) },
            onCancel: onCancel
        ) {
            VStack(spacing: 14) {
                VStack(spacing: 12) {
                    Text("SLIDE TO RATE")
                        .font(.caption2.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(Color(red: 0.42, green: 0.42, blue: 0.45))
                    TextField("", text: $question, prompt: Text("Ask a question…").foregroundStyle(.gray))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.black)
                        .tint(.black)
                        .multilineTextAlignment(.center)
                        .focused($focused)
                    ZStack {
                        Capsule()
                            .fill(LinearGradient(colors: [.white, Color(white: 0.85)], startPoint: .leading, endPoint: .trailing))
                            .frame(height: 8)
                        Text(emoji).font(.system(size: 34))
                    }
                    .frame(height: 40)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [.white, Color(white: 0.95)], startPoint: .top, endPoint: .bottom),
                    in: .rect(cornerRadius: 22)
                )
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(emojis, id: \.self) { e in
                            Text(e)
                                .font(.system(size: 26))
                                .frame(width: 46, height: 46)
                                .background(emoji == e ? Color.white.opacity(0.18) : .clear, in: Circle())
                                .overlay { if emoji == e { Circle().strokeBorder(.white, lineWidth: 2) } }
                                .onTapGesture {
                                    Haptics.tap()
                                    emoji = e
                                }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .onAppear { focused = true }
    }
}

private struct StoryQuestionSheet: View {
    /// onDone(question, cardBgHex, textFgHex)
    let onDone: (String, String, String) -> Void
    var onCancel: (() -> Void)? = nil
    @State private var question: String = ""
    @State private var palette: Int = 0
    @FocusState private var focused: Bool

    private var authorUsername: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    /// Question-card themes. Each is (bgHex, fgHex) — bg fills the bubble,
    /// fg colors the bold prompt text. White cards keep dark text; saturated
    /// cards flip to white text for legibility.
    private static let themes: [(String, String)] = [
        ("#FFFFFF", "#0A0A0A"),  // Paper
        ("#111111", "#FFFFFF"),  // Mono
        ("#FF4D6D", "#FFFFFF"),  // Coral
        ("#FF8A3D", "#FFFFFF"),  // Tangerine
        ("#FFD93D", "#1A1A1A"),  // Sun
        ("#6BCB77", "#0A2A12"),  // Mint
        ("#4D96FF", "#FFFFFF"),  // Sky
        ("#8E7BFF", "#FFFFFF"),  // Lilac
        ("#FF6FB5", "#FFFFFF")   // Bubble
    ]

    private var bgHex: String { Self.themes[palette].0 }
    private var fgHex: String { Self.themes[palette].1 }
    private var bgColor: Color { Color(hex: bgHex) ?? .white }
    private var fgColor: Color { Color(hex: fgHex) ?? .black }
    private var isLightCard: Bool { palette == 0 || palette == 4 }

    var body: some View {
        StickerBubbleScaffold(
            canDone: !question.trimmingCharacters(in: .whitespaces).isEmpty,
            onDone: {
                onDone(
                    question.isEmpty ? "Ask me anything" : question,
                    bgHex,
                    fgHex
                )
            },
            onCancel: onCancel
        ) {
            VStack(spacing: 14) {
                bubble
                colorRow
            }
        }
        .onAppear { focused = true }
    }

    private var bubble: some View {
        VStack(spacing: 10) {
            Text("ASK ME ANYTHING")
                .font(.caption2.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(fgColor.opacity(0.65))
            TextField(
                "",
                text: $question,
                prompt: Text("Ask me anything…").foregroundStyle(fgColor.opacity(0.45)),
                axis: .vertical
            )
            .font(.headline.weight(.bold))
            .foregroundStyle(fgColor)
            .tint(fgColor)
            .multilineTextAlignment(.center)
            .lineLimit(1...4)
            .focused($focused)
            Text("Type something…")
                .font(.footnote)
                .foregroundStyle(fgColor.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(fgColor.opacity(isLightCard ? 0.05 : 0.18), in: .rect(cornerRadius: 12))
        }
        .padding(.top, 22 + 32)
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background(bgColor, in: .rect(cornerRadius: 22))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .overlay(alignment: .top) {
            WhisperAvatar(username: authorUsername, size: 56, ring: false)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .offset(y: -28)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: palette)
    }

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(Self.themes.enumerated()), id: \.offset) { idx, theme in
                    Button {
                        Haptics.tap()
                        palette = idx
                    } label: {
                        Circle()
                            .fill(Color(hex: theme.0) ?? .white)
                            .frame(width: 30, height: 30)
                            .overlay { Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1) }
                            .overlay {
                                if palette == idx {
                                    Circle().strokeBorder(.white, lineWidth: 2.5).padding(-3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
}

/// Instagram-style "Add place" creator. On appear, asks for / pulls the
/// device's current location (one prompt the first time), then drops a
/// paper-white card the user can rename freely — while the actual
/// pinned latitude/longitude stays attached so the pin Maps drops on
/// tap matches the spot the user was standing at, even if they renamed
/// the visible label to "the spot" / "home".
private struct StoryLocationSheet: View {
    /// onDone(label, latitude, longitude)
    let onDone: (String, Double?, Double?) -> Void
    var onCancel: (() -> Void)? = nil

    @State private var label: String = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var loading: Bool = true
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        StickerBubbleScaffold(
            canDone: !label.trimmingCharacters(in: .whitespaces).isEmpty,
            onDone: { onDone(label, latitude, longitude) },
            onCancel: onCancel
        ) {
            bubble
        }
        .task { await fetchLocation() }
    }

    private var bubble: some View {
        VStack(spacing: 12) {
            Text("ADD PLACE")
                .font(.caption2.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(.black.opacity(0.55))

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.00, green: 0.36, blue: 0.40),
                                    Color(red: 1.00, green: 0.55, blue: 0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    if loading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.footnote.weight(.heavy))
                            .foregroundStyle(.white)
                    }
                }

                TextField(
                    "",
                    text: $label,
                    prompt: Text(loading ? "Getting your location…" : "Name this place")
                        .foregroundStyle(.black.opacity(0.35))
                )
                .font(.headline.weight(.bold))
                .foregroundStyle(.black)
                .tint(.black)
                .focused($focused)
                .disabled(loading)
                .submitLabel(.done)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.85, green: 0.20, blue: 0.25))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let lat = latitude, let lon = longitude {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Pinned at \(coordString(lat: lat, lon: lon))")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.black.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(.white, in: .rect(cornerRadius: 22))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }

    private func coordString(lat: Double, lon: Double) -> String {
        String(format: "%.4f, %.4f", lat, lon)
    }

    private func fetchLocation() async {
        loading = true
        errorMessage = nil
        do {
            let ctx = try await EmberLocationService.shared.requestCurrentContext()
            latitude = ctx.latitude
            longitude = ctx.longitude
            // Prefill the editable label with the best human-readable
            // name we have: POI name → city → "Here".
            let suggested: String
            if let name = ctx.name, !name.isEmpty {
                suggested = name
            } else if let city = ctx.city, !city.isEmpty {
                suggested = city
            } else {
                suggested = "Here"
            }
            if label.isEmpty { label = suggested }
            loading = false
            focused = true
        } catch {
            loading = false
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't get your location. You can still name the place."
            focused = true
        }
    }
}

/// Mention picker — type to filter handles you follow / DM. Picking a row
/// drops an `@username` sticker on the canvas. Cleaner than free-typing
/// because it guarantees the handle exists.
private struct StoryMentionSheet: View {
    let onDone: (String) -> Void
    @State private var query: String = ""
    /// Mirrored buffer the suggestion bar reads / writes. Two-way synced
    /// with `query` via `.onChange` below so tapping a suggestion fills
    /// the field with the picked handle.
    @State private var mentionBuffer: String = "@"
    @FocusState private var focused: Bool

    var body: some View {
        StickerBubbleScaffold(
            canDone: !cleanedQuery.isEmpty,
            onDone: { onDone(cleanedQuery) }
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("@")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(.gray)
                    TextField(
                        "",
                        text: $query,
                        prompt: Text("username").foregroundStyle(.gray)
                    )
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.black)
                    .tint(.black)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focused)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(.white, in: .rect(cornerRadius: 18))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)

                // Reuse the existing in-progress mention bar — it ranks
                // people you follow, recent DM threads, cached authors and
                // a remote prefix search, exactly like the composer.
                WhisperMentionSuggestionsBar(text: $mentionBuffer)
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear { focused = true }
        .onChange(of: query) { _, new in
            let target = "@\(new)"
            if mentionBuffer != target { mentionBuffer = target }
        }
        .onChange(of: mentionBuffer) { _, new in
            // Bar replaced the in-progress token with @picked (trailing
            // space). Strip the @ + trailing whitespace and surface it.
            let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
            let withoutAt = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
            if withoutAt != query { query = withoutAt }
        }
    }

    private var cleanedQuery: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.hasPrefix("@") ? String(q.dropFirst()) : q
    }
}

/// Replacement for `SheetChrome` used by question/poll/slider sheets —
/// removes the top bar with title + Cancel/Add and instead floats the
/// editable bubble inside a tappable dimmed backdrop. A single "Done"
/// button at the bottom posts the sticker. Tapping the backdrop dismisses.
private struct StickerBubbleScaffold<Content: View>: View {
    let canDone: Bool
    let onDone: () -> Void
    /// When rendered inline (not inside a sheet) callers pass an explicit
    /// dismiss closure since `@Environment(\.dismiss)` is a no-op outside
    /// a sheet / cover context.
    var onCancel: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var envDismiss

    private func dismissNow() {
        if let onCancel { onCancel() } else { envDismiss() }
    }

    var body: some View {
        ZStack {
            // Tap-to-dismiss backdrop — transparent so the live canvas
            // shows through (no sheet dim, no material).
            Color.clear
                .contentShape(.rect)
                .onTapGesture { dismissNow() }

            ScrollView {
                content()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard canDone else { return }
                    Haptics.tap()
                    onDone()
                    dismissNow()
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            canDone ? Color.white : Color.white.opacity(0.45),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canDone)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
        }
    }
}

private struct StorySimpleTextSheet: View {
    let title: String
    let placeholder: String
    let icon: String
    let onDone: (String) -> Void
    @State private var value: String = ""

    var body: some View {
        SheetChrome(title: title, canDone: !value.trimmingCharacters(in: .whitespaces).isEmpty, onDone: { onDone(value) }) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 32)
                    TextField("", text: $value, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.35)))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .tint(.white)
                        .textInputAutocapitalization(.never)
                }
                .padding(14)
                .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 14))
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Sticker / GIF library

private struct StoryStickerLibrarySheet<Tools: View>: View {
    let onPick: (String) -> Void
    @ViewBuilder let tools: (String) -> Tools
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    /// Curated Whisper sticker pack. Names line up with the
    /// `WhisperSticker_<name>` imagesets in the main Assets catalog. The
    /// `tags` array is used for the lightweight in-sheet search.
    private static var pack: [(name: String, label: String, tags: [String])] { [
        ("ember", "Jasper", ["ember", "mascot", "ai", "cute"]),
        ("ember_headphones", "Jasper Vibing", ["ember", "music", "headphones", "vibe"]),
        ("ghost_crown", "Royalty", ["crown", "king", "queen", "flex"]),
        ("ghost_king", "King", ["king", "crown", "goat"]),
        ("ghost_bolt", "Energized", ["bolt", "hyped", "energy", "lit"]),
        ("ghost_boost", "Boosted", ["boost", "rocket", "hype"]),
        ("ghost_send", "Send It", ["send", "hype", "yes"]),
        ("ghost_trophy", "Winning", ["trophy", "win", "goat"]),
        ("ghost_beach", "Beach Day", ["beach", "summer", "vacation"]),
        ("jasper_beachball", "Beach Ball", ["beach", "ball", "summer", "fun"]),
        ("ghost_couple", "Couple", ["couple", "love", "date"]),
        ("ghost_home", "Home", ["home", "chill", "couch"]),
        ("ghost_sleepy", "Sleepy", ["sleep", "tired", "night"]),
        ("ghost_sad", "Sad", ["sad", "cry", "mood"]),
        ("ghost_cookie", "Cookie", ["cookie", "snack", "hungry"]),
        ("ghost_book", "Reading", ["book", "study", "read"]),
        ("ghost_dragon", "Dragon Rider", ["dragon", "epic", "fantasy"]),
        ("ghost_kraken", "Kraken", ["kraken", "sea", "epic"])
    ] }

    private var filtered: [(name: String, label: String, tags: [String])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Self.pack }
        return Self.pack.filter { item in
            item.label.lowercased().contains(q) ||
            item.name.lowercased().contains(q) ||
            item.tags.contains(where: { $0.contains(q) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                searchField(prompt: "Search stickers and tools", text: $query) { }
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Close stickers")
            }.padding(.top, 8).padding(.trailing, 8)
            ScrollView {
                VStack(spacing: 8) {
                tools(query.trimmingCharacters(in: .whitespacesAndNewlines))
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("No artwork matches")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 10) {
                        ForEach(filtered, id: \.name) { item in
                            Button {
                                Haptics.tap()
                                onPick("jasper-sticker://\(item.name)")
                                dismiss()
                            } label: {
                                VStack(spacing: 6) {
                                    Image("WhisperSticker_\(item.name)")
                                        .resizable()
                                        .scaledToFit()
                                        .padding(8)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 76)
                                    Text(item.label)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .contentShape(.rect(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
                }
            }.scrollDismissesKeyboard(.interactively).scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct StoryGifSheet: View {
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var gifs: [WhisperGif] = []
    @State private var query: String = ""
    @State private var loading: Bool = true
    @State private var retry: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            compactSheetHeader("GIFs") { dismiss() }
            searchField(prompt: "Search GIFs", text: $query) {}
            if loading { ProgressView().tint(.white).padding() }
            if !loading && gifs.isEmpty {
                VStack(spacing: 8) {
                    Text("No GIFs available").font(.subheadline)
                    Button("Try again") { retry += 1 }.frame(minHeight: 44)
                }.foregroundStyle(.white).padding(20)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(gifs, id: \.id) { gif in
                        Button {
                            Haptics.tap()
                            onPick(gif.url.absoluteString)
                            dismiss()
                        } label: {
                            Color.white.opacity(0.06)
                                .frame(height: 150)
                                .frame(maxWidth: .infinity)
                                .overlay {
                                    WhisperAnimatedGIFView(url: gif.url, contentMode: .fill)
                                        .allowsHitTesting(false)
                                }
                                .clipShape(.rect(cornerRadius: 14))
                                .contentShape(.rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .task(id: "\(query)-\(retry)") {
            loading = true
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await load(query)
        }
    }

    private func load(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        let epoch = AccountStorage.generation
        let result = trimmed.isEmpty ? await WhisperGiphyService.shared.fetchGifs(for: "trending") : await WhisperGiphyService.shared.search(trimmed)
        guard !Task.isCancelled, epoch == AccountStorage.generation, q == query else { return }
        gifs = result; loading = false
    }
}

// MARK: - Music sheet

struct StoryMusicSheet: View {
    var current: WhisperStoryMusic? = nil
    var onEditSection: ((WhisperStoryMusic) -> Void)? = nil
    let onPick: (WhisperStoryMusic) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var service = WhisperStoryMusicService.shared
    @State private var player = WhisperStoryMusicPlayer()
    @State private var query: String = ""
    @State private var editingSong: WhisperStoryMusic?

    private var list: [WhisperStoryMusic] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? service.trending : service.results
    }

    var body: some View {
        VStack(spacing: 0) {
            compactSheetHeader("Music") {
                player.stop()
                dismiss()
            }
            if let editingSong {
                WhisperStoryMusicSegmentView(music: editingSong, onCancel: { self.editingSong = nil }) { selected in
                    onPick(selected)
                    dismiss()
                }
                .id(editingSong.id)
            } else {
            if let current {
                Button("Edit selected section · \(current.title)") { editSection(current) }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(minHeight: 44).padding(.horizontal, 16)
            }
            searchField(prompt: "Search songs", text: $query) {}
            if let error = service.lastError {
                Text(error).font(.footnote).foregroundStyle(.white).padding(.horizontal, 16)
            }
            if service.isSearching { ProgressView().tint(.white).padding(12) }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(list, id: \.id) { song in
                        musicRow(song)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            }
        }
        .task {
            if service.trending.isEmpty {
                await service.loadTrending()
            }
        }
        .task(id: query) {
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await service.search(query)
        }
        .onDisappear { player.stop() }
    }

    private func editSection(_ song: WhisperStoryMusic) {
        player.stop()
        if let onEditSection { onEditSection(song); dismiss() }
        else { editingSong = song }
    }

    private func musicRow(_ song: WhisperStoryMusic) -> some View {
        HStack(spacing: 8) {
            Button { editSection(song) } label: {
            HStack(spacing: 12) {
            ZStack {
                Color.white.opacity(0.08)
                if let art = song.artworkURL, let url = URL(string: art) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color.clear
                        }
                    }
                } else {
                    Image(systemName: "music.note")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            }.contentShape(.rect)
            }.buttonStyle(.plain)
            Button {
                player.toggle(song.storyPreview)
            } label: {
                Image(systemName: player.nowPlayingID == song.id && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).accessibilityLabel(player.nowPlayingID == song.id && player.isPlaying ? "Pause preview" : "Play preview")
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
    }
}

// MARK: - Hashtag / countdown sheets

private struct StoryHashtagSheet: View {
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tag: String = ""

    var body: some View {
        VStack(spacing: 14) {
            compactSheetHeader("Hashtag") { dismiss() }
            styledField("YOURTAG", text: $tag)
            Button {
                let clean = tag
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "#", with: "")
                guard !clean.isEmpty else { return }
                Haptics.tap()
                onDone(clean)
            } label: {
                Text("Add hashtag")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(tag.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "").isEmpty)
            .opacity(tag.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "").isEmpty ? 0.5 : 1)
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

private struct StoryCountdownSheet: View {
    let onDone: (String, Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var date: Date = Date().addingTimeInterval(60 * 60 * 24)

    var body: some View {
        VStack(spacing: 14) {
            compactSheetHeader("Countdown") { dismiss() }
            styledField("What are you counting down to?", text: $title)
            DatePicker(
                "Ends",
                selection: $date,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .tint(.white)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            Button {
                let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return }
                Haptics.tap()
                onDone(clean, date)
            } label: {
                Text("Add countdown")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

// MARK: - Shared form bits

/// Compact, tight sheet header used by Stickers / GIFs / Music sheets so the
/// content sits high in the sheet instead of leaving a tall dead-space banner
/// at the top.
private func compactSheetHeader(_ title: String, onClose: @escaping () -> Void) -> some View {
    WhisperStoryToolHeader(title: title, onCancel: onClose)
}

private func styledField(_ placeholder: String, text: Binding<String>) -> some View {
    TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.35)))
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .tint(.white)
        .padding(14)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 12))
}

private func searchField(prompt: String, text: Binding<String>, onChange: @escaping () -> Void) -> some View {
    HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
            .foregroundStyle(.white.opacity(0.55))
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(.white.opacity(0.45)))
            .foregroundStyle(.white)
            .tint(.white)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: text.wrappedValue) { _, _ in onChange() }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .background(Color.white.opacity(0.08), in: Capsule())
    .padding(.horizontal, 16)
}

// MARK: - Color hex helper

extension Color {
    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let R = Int(round(r * 255)), G = Int(round(g * 255)), B = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", R, G, B)
    }
}
