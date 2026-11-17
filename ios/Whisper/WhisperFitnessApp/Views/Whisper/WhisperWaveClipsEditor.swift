import SwiftUI
import AVFoundation
import PhotosUI
import UIKit

// MARK: - Multi-clip waves
//
// TikTok's "Adjust clips" / Reels' clip timeline, Whisper's way. A wave is a
// LIST OF CLIPS — recorded takes, gallery uploads (several at once), or
// both — each with its own trim window and speed, joined by a transition
// (cut · fade · dip to black), reorderable by drag, splittable at the
// playhead, duplicable, deletable. Edits update an in-memory playback
// composition; Next keeps the edit document. Only final preview/publication
// encodes an MP4 with the same transitions, framing and audio mix.

/// One clip on the wave timeline. Pure data (Sendable) so the export can walk
/// it off the main actor; thumbnails live beside it in view state.
nonisolated struct WhisperWaveClip: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    var url: URL
    /// Source length in seconds.
    var duration: Double
    var trimStart: Double
    var trimEnd: Double
    /// Playback multiplier — 0.25 … 3.
    var speed: Double
    /// The transition INTO the next clip.
    var transitionAfter: WhisperWaveTransition
    var zoom: Double = 1
    var offsetX: Double = 0
    var offsetY: Double = 0
    var fillsFrame: Bool = false
    var face: WhisperWaveFaceSetting? = nil
    var background: WhisperWaveBackground? = nil
    var cameraEffect: WhisperWaveCameraEffect? = nil

    init(url: URL, duration: Double, trimStart: Double = 0, trimEnd: Double? = nil, speed: Double = 1, transitionAfter: WhisperWaveTransition = .cut) {
        self.id = UUID()
        self.url = url
        self.duration = duration
        self.trimStart = trimStart
        self.trimEnd = trimEnd ?? duration
        self.speed = speed
        self.transitionAfter = transitionAfter
    }

    /// Seconds this clip contributes to the finished wave.
    var effectiveSeconds: Double { max(0, trimEnd - trimStart) / max(0.1, speed) }
    /// Seconds kept from the source.
    var keptSeconds: Double { max(0, trimEnd - trimStart) }
    /// True when any trim, speed or framing differs from the untouched source.
    var isTrimmed: Bool { trimStart > 0.01 || trimEnd < duration - 0.01 }
    var isReframed: Bool { fillsFrame || zoom != 1 || offsetX != 0 || offsetY != 0 }
}

/// How one clip hands off to the next.
nonisolated enum WhisperWaveTransition: String, CaseIterable, Sendable, Codable {
    case cut, fade, dip

    var label: String {
        switch self {
        case .cut: return "Cut"
        case .fade: return "Fade"
        case .dip: return "Dip"
        }
    }

    var systemImage: String {
        switch self {
        case .cut: return "circle"
        case .fade: return "circle.lefthalf.filled"
        case .dip: return "circle.fill"
        }
    }

    var next: WhisperWaveTransition {
        switch self {
        case .cut: return .fade
        case .fade: return .dip
        case .dip: return .cut
        }
    }
}

// MARK: - Tools

/// The ten detents on the editor dial — one tool per view.
enum WhisperWaveTool: String, CaseIterable, Identifiable, Hashable {
    case clips, trim, speed, frame, text, captions, audio, beats, looks, effects, face

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clips: return "Clips"
        case .trim: return "Trim"
        case .speed: return "Speed"
        case .frame: return "Frame"
        case .text: return "Text"
        case .captions: return "Captions"
        case .audio: return "Audio"
        case .beats: return "Beats"
        case .looks: return "Looks"
        case .effects: return "Effects"
        case .face: return "Face"
        }
    }

    var systemImage: String {
        switch self {
        case .clips: return "film.stack"
        case .trim: return "scissors"
        case .speed: return "speedometer"
        case .frame: return "aspectratio"
        case .text: return "textformat"
        case .captions: return "captions.bubble"
        case .audio: return "music.note"
        case .beats: return "waveform.path"
        case .looks: return "camera.filters"
        case .effects: return "sparkles"
        case .face: return "face.smiling"
        }
    }

    /// The composer's tool names ("clips", "looks", …) → a dial detent.
    init(key: String) {
        switch key {
        case "text": self = .text
        case "captions": self = .captions
        case "audio": self = .audio
        case "beats": self = .beats
        case "looks": self = .looks
        case "effects": self = .effects
        case "face": self = .face
        default: self = .clips
        }
    }
}

// MARK: - The editor

/// The wave editor: the footage in a rounded 9:16 box, a transport row, ONE
/// tool at a time in a rounded panel, and an edge-to-edge dial that clicks
/// between tools. Everything renders live on the footage above.
struct WhisperWaveClipsEditor: View {
    let onCancel: () -> Void
    let onDone: () -> Void
    @Binding var clips: [WhisperWaveClip]
    @Binding var music: WhisperStoryMusic?
    @Binding var musicVolume: Double
    @Binding var muteOriginal: Bool
    @Binding var texts: [WaveTextOverlay]
    @Binding var filter: SnapFilter
    @Binding var adjustments: WhisperWaveColorAdjustments
    @Binding var fx: WhisperWaveFXSetting?
    @Binding var captions: WhisperWaveCaptions?
    @Binding var effect: WhisperAREffect
    @State private var backTransition: WhisperBackAction = WhisperBackAction()
    @State private var previewModel: WhisperWavePreviewModel = WhisperWavePreviewModel()
    @State private var captionGenerator: WhisperWaveCaptionGenerator = WhisperWaveCaptionGenerator()
    @State private var showCaptionWords: Bool = false
    /// Beat maps for each clip's own audio, keyed by file path.
    @State private var beatMaps: [String: WhisperWaveBeatMap] = [:]
    @State private var musicBeatMap: WhisperWaveBeatMap?
    @State private var musicBeatKey: String?
    @State private var analyzingBeats: Bool = false
    @State private var beatAnalysisToken: UUID = UUID()
    @State private var beatSnap: Bool = false
    @State private var beatEvery: Int = 1
    @State private var selectedTextID: UUID?
    @State private var editingTextID: UUID?
    @State private var showMusicPicker: Bool = false
    @State private var selectedID: UUID?
    @State private var thumbs: [UUID: UIImage] = [:]
    @State private var frameStrips: [UUID: [UIImage]] = [:]
    @State private var tool: WhisperWaveTool = .clips
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPicker: Bool = false
    @State private var importing: Bool = false
    @State private var toast: String?
    @State private var showsTimeline: Bool = true

    private static let maxClips: Int = 12
    private static let minKept: Double = 0.4

    init(clips: Binding<[WhisperWaveClip]>, music: Binding<WhisperStoryMusic?>, musicVolume: Binding<Double>, muteOriginal: Binding<Bool>, texts: Binding<[WaveTextOverlay]>, filter: Binding<SnapFilter>, adjustments: Binding<WhisperWaveColorAdjustments>, fx: Binding<WhisperWaveFXSetting?>, captions: Binding<WhisperWaveCaptions?>, effect: Binding<WhisperAREffect>, initialTool: String = "clips", onCancel: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.onCancel = onCancel
        self.onDone = onDone
        self._clips = clips
        self._music = music
        self._musicVolume = musicVolume
        self._muteOriginal = muteOriginal
        self._texts = texts
        self._filter = filter
        self._adjustments = adjustments
        self._fx = fx
        self._captions = captions
        self._effect = effect
        self._tool = State(initialValue: WhisperWaveTool(key: initialTool))
        self._selectedID = State(initialValue: clips.wrappedValue.first?.id)
    }

    private var selected: WhisperWaveClip? {
        guard let selectedID else { return nil }
        return clips.first { $0.id == selectedID }
    }

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return clips.firstIndex { $0.id == selectedID }
    }

    private var selectedThumb: UIImage? { selectedID.flatMap { thumbs[$0] } }

    private var totalSeconds: Double { WhisperWaveTimeline.duration(clips) }

    /// Beats are only analyzed while someone can see or use them.
    private var needsBeats: Bool { tool == .beats || beatSnap }

    /// Changes whenever a different file needs listening to; empty when idle.
    private var beatAnalysisKey: String {
        guard needsBeats else { return "" }
        if music != nil { return "music:" + (previewModel.musicLocalURL?.path ?? "pending") }
        return "clips:" + clips.map { $0.url.path }.joined(separator: "|")
    }

    /// The beat map on the wave's output clock — the chosen sound through its
    /// start offset and loops, or every clip's own audio through trim and speed.
    private var beatGrid: WhisperWaveBeatGrid? {
        if let music {
            guard let map = musicBeatMap, let local = previewModel.musicLocalURL, musicBeatKey == local.path else { return nil }
            return WhisperWaveBeatGrid.music(map, start: music.startSeconds, length: max(0.1, totalSeconds), title: music.title)
        }
        return WhisperWaveBeatGrid.clips(beatMaps, clips: clips)
    }

    /// Beat times text timing snaps to while Snap is on.
    private var textSnapTimes: [Double] {
        guard beatSnap, let grid = beatGrid else { return [] }
        return grid.times
    }

    /// The keyboard is up for a text layer: the dial steps aside so the
    /// footage keeps room, and returns on Done.
    private var isTyping: Bool {
        guard tool == .text, let editingTextID else { return false }
        return texts.first { $0.id == editingTextID }?.isSticker == false
    }

    var body: some View {
        presentationContent
            .whisperEdgeBack(isEnabled: !importing && !showMusicPicker && !showCaptionWords, controller: backTransition) { backTransition.perform { onCancel() } }
            .overlay(alignment: .top) { toastView }
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: toast)
            .animation(.snappy(duration: 0.3), value: isTyping)
    }

    // Concrete type-erasure boundaries keep this lifecycle chain small for
    // both the simulator compiler and optimized device builds.
    private var editorContent: AnyView {
        AnyView(ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                canvas
                if !isTyping { transport }
                errorRow
                panel
                if !isTyping { dial }
            }
            if importing {
                busyOverlay
            }
        }.preferredColorScheme(.dark))
    }

    private var mediaContent: AnyView {
        AnyView(editorContent.photosPicker(
            isPresented: $showPicker,
            selection: $pickerItems,
            maxSelectionCount: max(1, Self.maxClips - clips.count),
            matching: .videos,
            photoLibrary: .shared()
        )
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPicked(items) }
        }
        .task {
            if effect.isFace, let kind = WhisperWaveFaceSetting.Kind(rawValue: effect.rawValue) {
                for index in clips.indices where clips[index].face == nil { clips[index].face = .init(kind: kind, amount: 1) }
                effect = .none
            }
            previewModel.activate()
            rebuildPreview()
            await hydrateThumbs()
        }
        .onDisappear {
            previewModel.stop()
            WhisperWaveLiveGrade.shared.override = nil
        }
        )
    }

    private var playbackContent: AnyView {
        AnyView(mediaContent
        .onChange(of: clips) { _, _ in rebuildPreview() }
        .onChange(of: music) { _, _ in rebuildPreview() }
        .onChange(of: musicVolume) { _, _ in rebuildPreview() }
        .onChange(of: effect) { _, _ in rebuildPreview() }
        .onChange(of: muteOriginal) { _, _ in rebuildPreview() }
        // Grade dials redraw the current frame; only a change of effect range
        // (whole wave ↔ one clip) needs the composition rebuilt.
        .onChange(of: filter) { _, _ in pushLiveGrade() }
        .onChange(of: adjustments) { _, _ in pushLiveGrade() }
        .onChange(of: fx) { old, new in
            if old?.clipID != new?.clipID { rebuildPreview() } else { pushLiveGrade() }
        }
        // Size and height redraw the paused frame; new words, a new look or a
        // new highlight color re-rasterize the phrases.
        .onChange(of: captions) { old, new in
            if let old, let new, old.words == new.words, old.style == new.style, old.highlightHex == new.highlightHex {
                pushLiveGrade()
            } else {
                rebuildPreview()
            }
        }
        )
    }

    private var presentationContent: AnyView {
        AnyView(playbackContent.task(id: beatAnalysisKey) {
            guard !beatAnalysisKey.isEmpty else { return }
            await analyzeBeats()
        }
        .sheet(isPresented: $showCaptionWords) {
            WhisperWaveCaptionWordsSheet(captions: $captions, clips: clips)
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.scrolls)
        }
        .onChange(of: tool) { old, new in toolChanged(from: old, to: new) }
        .onChange(of: selectedTextID) { _, id in
            if id != editingTextID { editingTextID = nil }
        }
        .onChange(of: selectedID) { _, _ in
            if tool == .trim, let clip = selected { Task { await ensureFrames(for: clip) } }
        }
        .onChange(of: previewModel.time) { _, time in
            guard !previewModel.isPreparing else { return }
            if let active = clips.last(where: { WhisperWaveTimeline.start(of: $0.id, in: clips) <= time + 0.01 }) { selectedID = active.id }
        }
        .sheet(isPresented: $showMusicPicker) {
            WhisperAudioPickerSheet(current: music, onPick: { picked in music = picked; showMusicPicker = false }, onRemove: { music = nil })
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.scrolls)
        }
        )
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                guard !importing else { return }
                Haptics.tap()
                backTransition.perform { onCancel() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to post details, keeping edits")

            Spacer()
            VStack(spacing: 2) {
                Text("Edit wave")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(Self.clock(totalSeconds)) · \(clips.count) clip\(clips.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .contentTransition(.numericText())
            }
            Spacer()

            Button {
                Haptics.press()
                if isTyping { finishTyping() } else { Task { await finish() } }
            } label: {
                Text(isTyping ? "Done" : "Next")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(WhisperBrandGradient.diagonal, in: Capsule())
            }
            .buttonStyle(WhisperMenuPressStyle())
            .disabled(clips.isEmpty || importing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Canvas + transport

    private var canvas: some View {
        WhisperWaveEditingCanvas(
            model: previewModel,
            clips: $clips,
            selectedID: selectedID,
            texts: $texts,
            selectedTextID: $selectedTextID,
            editingTextID: $editingTextID,
            isEditingText: tool == .text,
            allowsFraming: tool == .frame,
            onSelectText: { tool = .text },
            onAddText: { addCanvasText() },
            showsTypeHint: texts.isEmpty && tool != .text
        )
        .frame(minHeight: 100, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var playhead: Binding<Double> {
        Binding(
            get: { min(previewModel.time, max(0.1, totalSeconds)) },
            set: { previewModel.pause(); previewModel.seek($0) }
        )
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                previewModel.togglePlayback()
            } label: {
                Image(systemName: previewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(Color.white, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(WhisperMenuPressStyle())
            .accessibilityLabel(previewModel.isPlaying ? "Pause preview" : "Play video with audio")
            Slider(value: playhead, in: 0...max(0.1, totalSeconds))
                .tint(.white)
                .accessibilityLabel("Wave playhead")
            Text("\(Self.clock(previewModel.time)) / \(Self.clock(totalSeconds))")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
            if previewModel.isPreparing {
                ProgressView().tint(.white).controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
    }

    @ViewBuilder private var errorRow: some View {
        if let error = previewModel.error {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(WhisperBrandGradient.amber)
                Text(error)
                    .font(.system(size: 12))
                    .lineLimit(2)
                Spacer()
                Button("Retry") { rebuildPreview() }
                    .font(.system(size: 12, weight: .bold))
                    .frame(minHeight: 32)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
    }

    // MARK: Tool panel

    private var panel: some View {
        WhisperWaveToolPanel(height: isTyping ? 150 : 244) {
            panelContent
                .id(tool)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .animation(.snappy(duration: 0.28), value: tool)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var panelContent: some View {
        switch tool {
        case .clips: clipsPanel
        case .trim: trimPanel
        case .speed: speedPanel
        case .frame: framePanel
        case .text: textPanel
        case .captions: captionsPanel
        case .audio: audioPanel
        case .beats: beatsPanel
        case .looks: WhisperWaveLookControls(filter: $filter, adjustments: $adjustments, thumbnail: selectedThumb)
        case .effects: WhisperWaveFXControls(fx: $fx, thumbnail: selectedThumb, clips: clips, selectedClipID: selectedID)
        case .face:
            if let selectedID {
                WhisperWaveFaceControls(clips: $clips, clipID: selectedID, thumbnail: selectedThumb, pause: { previewModel.pause() }).id(selectedID)
            } else { noClipHint }
        }
    }

    private var clipsPanel: some View {
        VStack(spacing: 6) {
            Picker("Clip editing layout", selection: $showsTimeline) {
                Text("Timeline").tag(true)
                Text("Arrange clips").tag(false)
            }.pickerStyle(.segmented)
            if showsTimeline {
                ScrollView(.vertical) {
                    WhisperWaveLayerTimeline(clips: clips, texts: texts, music: music, thumbs: thumbs, selectedID: selectedID, selectedTextID: selectedTextID, time: playhead, onClip: { select($0) }, onText: { id in
                        previewModel.pause(); selectedTextID = id; editingTextID = nil; tool = .text
                    }, onAudio: { previewModel.pause(); tool = .audio }, onBackground: { clip in select(clip); tool = .frame })
                }
                HStack(spacing: 18) {
                    Button { if let selected { split(selected) } } label: { Label("Split", systemImage: "scissors") }
                    Button { if let selected { duplicate(selected) } } label: { Image(systemName: "plus.square.on.square") }.accessibilityLabel("Duplicate clip")
                    Button { if let selected { delete(selected) } } label: { Image(systemName: "trash") }.accessibilityLabel("Delete clip")
                    Spacer(minLength: 0)
                    Button { showPicker = true } label: { Label("Add", systemImage: "plus") }
                }.font(.caption.weight(.semibold)).frame(minHeight: 44)
            } else { arrangePanel }
        }
    }

    private var arrangePanel: some View {
        WhisperWaveClipStripPanel(
            clips: $clips,
            selectedID: selectedID,
            thumbs: thumbs,
            maxClips: Self.maxClips,
            onSelect: { select($0) },
            onAdd: { showPicker = true },
            onSplit: { if let clip = selected { split(clip) } },
            onDuplicate: { if let clip = selected { duplicate(clip) } },
            onDelete: { if let clip = selected { delete(clip) } }
        )
    }

    @ViewBuilder private var trimPanel: some View {
        if let clip = selected {
            WhisperWaveTrimPanel(clip: clip, frames: frameStrips[clip.id] ?? [], ordinal: (selectedIndex ?? 0) + 1, count: clips.count, minKept: Self.minKept, snap: beatSnap ? trimSnap(for: clip) : nil) { start, end in
                update(clip.id) { $0.trimStart = start; $0.trimEnd = end }
            }
        } else {
            noClipHint
        }
    }

    @ViewBuilder private var speedPanel: some View {
        if let clip = selected {
            WhisperWaveSpeedPanel(clip: clip) { speed in
                update(clip.id) { $0.speed = speed }
            }
        } else {
            noClipHint
        }
    }

    @ViewBuilder private var framePanel: some View {
        if let clip = selected {
            VStack(spacing: 4) {
                WhisperWaveFramePanel(clip: clip) { change in
                    previewModel.pause()
                    update(clip.id, change)
                }
                if clip.background != nil {
                    WhisperWaveBackgroundRecoveryView {
                        previewModel.pause()
                        update(clip.id) { $0.background = nil }
                        thumbs[clip.id] = nil; frameStrips[clip.id] = nil
                        Task { await hydrateThumbs() }
                    }
                }
            }
        } else {
            noClipHint
        }
    }

    private var textPanel: some View {
        WaveTextEditorSheet(overlays: $texts, duration: totalSeconds, selectedID: $selectedTextID, embedded: true, showsInput: false, autoAddsFirstLayer: false, snapTimes: textSnapTimes, onEditText: { id in
            previewModel.pause()
            editingTextID = id
        }) {
            finishTyping()
        }
    }

    private var captionsPanel: some View {
        WhisperWaveCaptionsPanel(
            captions: $captions,
            generator: captionGenerator,
            hasClips: !clips.isEmpty,
            onGenerate: { generateCaptions() },
            onEditWords: { previewModel.pause(); showCaptionWords = true }
        )
    }

    private var audioPanel: some View {
        WhisperWaveMusicControls(music: $music, volume: $musicVolume, muted: $muteOriginal, duration: previewModel.audioDuration, onChoose: { previewModel.pause(); showMusicPicker = true }, onRestart: { previewModel.seek(0) })
    }

    private var beatsPanel: some View {
        WhisperWaveBeatPanel(
            grid: beatGrid,
            isAnalyzing: analyzingBeats,
            hasMusic: music != nil,
            clips: clips,
            selectedID: selectedID,
            time: previewModel.time,
            snap: $beatSnap,
            every: $beatEvery,
            onSeek: { time in previewModel.pause(); previewModel.seek(time) },
            onSnapCuts: { snapCutsToBeats() },
            onSplitSelected: { if let clip = selected { splitOnBeats(clip) } },
            onChooseSound: { previewModel.pause(); showMusicPicker = true }
        )
    }

    private var noClipHint: some View {
        Text("Select a clip on the Clips detent first.")
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.5))
    }

    // MARK: Dial

    /// Spinning the dial onto Text never raises the keyboard; tapping the
    /// footage or a layer does. Every other detent switches straight over.
    private var dialSelection: Binding<WhisperWaveTool> {
        Binding(
            get: { tool },
            set: { next in
                if next == .text { selectedTextID = nil }
                tool = next
            }
        )
    }

    private var dial: some View {
        WhisperWaveToolDial(items: WhisperWaveTool.allCases, selection: dialSelection, title: { $0.title }, symbol: { $0.systemImage }, isMarked: { isMarked($0) })
            .padding(.bottom, 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// The accent dot on a detent whose tool holds a live edit.
    private func isMarked(_ tool: WhisperWaveTool) -> Bool {
        switch tool {
        case .clips: return clips.count > 1
        case .trim: return selected?.isTrimmed ?? false
        case .speed: return (selected?.speed ?? 1) != 1
        case .frame: return selected?.isReframed ?? false
        case .text: return !texts.isEmpty
        case .captions: return !(captions?.words.isEmpty ?? true)
        case .audio: return music != nil || muteOriginal
        case .beats: return beatSnap
        case .looks: return filter != .none || adjustments != WhisperWaveColorAdjustments()
        case .effects: return fx != nil
        case .face: return selected?.face?.isActive == true || effect.isFace
        }
    }

    private func toolChanged(from old: WhisperWaveTool, to new: WhisperWaveTool) {
        if new == .trim, let clip = selected {
            Task { await ensureFrames(for: clip) }
        }
        if old == .text, new != .text {
            editingTextID = nil
            texts.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.isSticker }
            selectedTextID = nil
        }
    }

    // MARK: Overlays

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white, in: Capsule())
                .padding(.top, 64)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.white).controlSize(.large)
                Text("Adding clips…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .transition(.opacity)
    }

    // MARK: Actions

    /// Everything the compositor may redraw without a rebuild.
    private var liveGradeSnapshot: WhisperWaveLiveGrade.Snapshot {
        var snapshot = WhisperWaveLiveGrade.Snapshot(filter: filter, adjustments: adjustments, fx: fx)
        if let captions { snapshot.captionLayout = .init(y: captions.clampedY, scale: captions.clampedScale) }
        return snapshot
    }

    private func rebuildPreview() {
        WhisperWaveLiveGrade.shared.override = liveGradeSnapshot
        previewModel.rebuild(clips: clips, music: music, volume: musicVolume, muted: muteOriginal, filter: filter, adjustments: adjustments, effect: effect, fx: fx, captions: captions)
    }

    private func pushLiveGrade() {
        WhisperWaveLiveGrade.shared.override = liveGradeSnapshot
        previewModel.refreshFrame()
    }

    // MARK: Captions

    /// Listens to every clip on this iPhone and writes word-timed captions.
    private func generateCaptions() {
        guard !clips.isEmpty, !captionGenerator.isRunning else { return }
        previewModel.pause()
        let snapshot = clips
        Task {
            let result = await captionGenerator.generate(snapshot, keeping: captions)
            guard let result else {
                if captionGenerator.error != nil { Haptics.warning() }
                return
            }
            withAnimation(.snappy(duration: 0.25)) { captions = result }
            Haptics.success()
            show("\(result.words.count) words captioned on this iPhone")
        }
    }

    // MARK: Beats

    private func analyzeBeats() async {
        let token = UUID()
        beatAnalysisToken = token
        analyzingBeats = true
        defer { if beatAnalysisToken == token { analyzingBeats = false } }
        if music != nil {
            guard let local = previewModel.musicLocalURL, musicBeatKey != local.path else { return }
            let map = await WhisperWaveBeatDetector.shared.analyze(local)
            guard !Task.isCancelled else { return }
            musicBeatMap = map
            musicBeatKey = local.path
        } else {
            for clip in clips where beatMaps[clip.url.path] == nil {
                let map = await WhisperWaveBeatDetector.shared.analyze(clip.url)
                guard !Task.isCancelled else { return }
                if let map { beatMaps[clip.url.path] = map }
            }
        }
    }

    /// The Trim tool's magnet while Snap is on.
    private func trimSnap(for clip: WhisperWaveClip) -> (Bool, Double) -> Double {
        { leading, time in snappedTrim(clip, leading: leading, proposed: time) }
    }

    /// Pulls a trim handle onto a beat: with a chosen sound the clip's CUT
    /// (its end on the output clock) lands on a beat; with the clips' own
    /// audio the handle lands on one of that clip's beats.
    private func snappedTrim(_ clip: WhisperWaveClip, leading: Bool, proposed time: Double) -> Double {
        guard beatSnap, let grid = beatGrid, !grid.isEmpty else { return time }
        let speed = max(0.1, clip.speed)
        let tolerance = 0.12 * speed
        switch grid.source {
        case .clips:
            guard let map = beatMaps[clip.url.path] else { return time }
            return WhisperWaveBeatGrid.nearest(in: map.beats, to: time, within: tolerance) ?? time
        case .music:
            let outputStart = WhisperWaveTimeline.start(of: clip.id, in: clips)
            let candidates: [Double] = grid.times.compactMap { beat in
                guard beat > outputStart + 0.05 else { return nil }
                return leading ? clip.trimEnd - (beat - outputStart) * speed : clip.trimStart + (beat - outputStart) * speed
            }
            return WhisperWaveBeatGrid.nearest(in: candidates, to: time, within: tolerance) ?? time
        }
    }

    /// Moves every cut between clips onto the nearest beat (within half a beat).
    private func snapCutsToBeats() {
        guard clips.count > 1 else { show("Add a second clip to snap the cuts"); return }
        guard let grid = beatGrid, !grid.isEmpty else { show("No beat found yet"); return }
        let half = 30 / max(40, grid.bpm)
        var updated = clips
        var moved = 0
        for index in 0..<(updated.count - 1) {
            let clip = updated[index]
            let speed = max(0.1, clip.speed)
            let newEnd: Double?
            switch grid.source {
            case .clips:
                newEnd = beatMaps[clip.url.path].flatMap { WhisperWaveBeatGrid.nearest(in: $0.beats, to: clip.trimEnd, within: half * speed) }
            case .music:
                let start = WhisperWaveTimeline.start(of: clip.id, in: updated)
                newEnd = grid.nearest(to: start + clip.effectiveSeconds, within: half).map { clip.trimStart + ($0 - start) * speed }
            }
            guard let newEnd, abs(newEnd - clip.trimEnd) > 0.01, newEnd - clip.trimStart >= Self.minKept, newEnd <= clip.duration + 0.001 else { continue }
            updated[index].trimEnd = min(clip.duration, newEnd)
            moved += 1
        }
        guard moved > 0 else {
            Haptics.selection()
            show("Every cut is already on a beat")
            return
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { clips = updated }
        Haptics.success()
        show(moved == 1 ? "1 cut moved onto the beat" : "\(moved) cuts moved onto the beat")
    }

    /// Splits the selected clip on every n-th beat inside it.
    private func splitOnBeats(_ clip: WhisperWaveClip) {
        guard let grid = beatGrid, !grid.isEmpty, let idx = clips.firstIndex(where: { $0.id == clip.id }) else { show("No beat found yet"); return }
        let room = Self.maxClips - clips.count
        guard room >= 1 else { show("Up to \(Self.maxClips) clips per wave"); return }
        let speed = max(0.1, clip.speed)
        let outputStart = WhisperWaveTimeline.start(of: clip.id, in: clips)
        let outputEnd = outputStart + clip.effectiveSeconds
        let minOut = Self.minKept / speed
        var cuts: [Double] = []
        var last = outputStart
        for cut in grid.cuts(every: beatEvery) where cut > outputStart + minOut && cut < outputEnd - minOut {
            guard cut - last >= minOut else { continue }
            cuts.append(cut)
            last = cut
        }
        guard !cuts.isEmpty else { show("No beats inside this clip at that spacing"); return }
        let truncated = cuts.count > room
        if truncated { cuts = Array(cuts.prefix(room)) }
        var pieces: [WhisperWaveClip] = []
        var sourceCursor = clip.trimStart
        for cut in cuts + [outputEnd] {
            let sourceCut = min(clip.trimEnd, clip.trimStart + (cut - outputStart) * speed)
            var piece = WhisperWaveClip(url: clip.url, duration: clip.duration, trimStart: sourceCursor, trimEnd: sourceCut, speed: clip.speed, transitionAfter: .cut)
            piece.face = clip.face; piece.background = clip.background; piece.cameraEffect = clip.cameraEffect
            piece.zoom = clip.zoom; piece.offsetX = clip.offsetX; piece.offsetY = clip.offsetY; piece.fillsFrame = clip.fillsFrame
            pieces.append(piece)
            sourceCursor = sourceCut
        }
        pieces[pieces.count - 1].transitionAfter = clip.transitionAfter
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            clips.replaceSubrange(idx...idx, with: pieces)
            selectedID = pieces.first?.id
        }
        if fx?.clipID == clip.id { fx?.clipID = pieces.first?.id }
        for piece in pieces {
            thumbs[piece.id] = thumbs[clip.id]
            frameStrips[piece.id] = frameStrips[clip.id]
        }
        Task {
            for piece in pieces.dropFirst() {
                thumbs[piece.id] = await WhisperWaveClipStudio.thumbnail(url: clip.url, at: piece.trimStart + 0.05)
            }
        }
        Haptics.success()
        show(truncated ? "Split into \(pieces.count) — the wave holds \(Self.maxClips) clips" : "Split into \(pieces.count) on the beat")
    }

    private func addCanvasText() {
        previewModel.pause()
        if isTyping {
            finishTyping()
            return
        }
        var layer = WaveTextOverlay()
        layer.start = 0
        texts.append(layer)
        selectedTextID = layer.id
        editingTextID = layer.id
        tool = .text
    }

    private func finishTyping() {
        editingTextID = nil
        texts.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.isSticker }
        if !texts.contains(where: { $0.id == selectedTextID }) { selectedTextID = nil }
    }

    private func select(_ clip: WhisperWaveClip) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { selectedID = clip.id }
        previewModel.pause()
        previewModel.seek(WhisperWaveTimeline.start(of: clip.id, in: clips))
        if tool == .trim { Task { await ensureFrames(for: clip) } }
    }

    private func update(_ id: UUID, _ change: (inout WhisperWaveClip) -> Void) {
        guard let idx = clips.firstIndex(where: { $0.id == id }) else { return }
        change(&clips[idx])
    }

    /// Splits the selected clip at the playhead into two clips.
    private func split(_ clip: WhisperWaveClip) {
        guard let idx = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        guard clips.count < Self.maxClips else { show("Up to \(Self.maxClips) clips per wave"); return }
        let t = clip.trimStart + (previewModel.time - WhisperWaveTimeline.start(of: clip.id, in: clips)) * clip.speed
        guard t - clip.trimStart >= Self.minKept, clip.trimEnd - t >= Self.minKept else {
            show("Scrub a little further into the clip to split it")
            return
        }
        var first = WhisperWaveClip(url: clip.url, duration: clip.duration, trimStart: clip.trimStart, trimEnd: t, speed: clip.speed, transitionAfter: .cut)
        first.transitionAfter = .cut
        var second = WhisperWaveClip(url: clip.url, duration: clip.duration, trimStart: t, trimEnd: clip.trimEnd, speed: clip.speed, transitionAfter: clip.transitionAfter)
        first.face = clip.face; first.background = clip.background; first.cameraEffect = clip.cameraEffect
        second.face = clip.face; second.background = clip.background; second.cameraEffect = clip.cameraEffect
        first.zoom = clip.zoom; first.offsetX = clip.offsetX; first.offsetY = clip.offsetY; first.fillsFrame = clip.fillsFrame
        second.zoom = clip.zoom; second.offsetX = clip.offsetX; second.offsetY = clip.offsetY; second.fillsFrame = clip.fillsFrame
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            clips.replaceSubrange(idx...idx, with: [first, second])
            selectedID = second.id
        }
        if fx?.clipID == clip.id { fx?.clipID = first.id }
        thumbs[first.id] = thumbs[clip.id]
        frameStrips[first.id] = frameStrips[clip.id]
        Task {
            thumbs[second.id] = await WhisperWaveClipStudio.thumbnail(url: clip.url, at: t)
            frameStrips[second.id] = frameStrips[clip.id]
        }
        Haptics.success()
    }

    private func duplicate(_ clip: WhisperWaveClip) {
        guard clips.count < Self.maxClips, let idx = clips.firstIndex(where: { $0.id == clip.id }) else {
            show("Up to \(Self.maxClips) clips per wave")
            return
        }
        var copy = WhisperWaveClip(url: clip.url, duration: clip.duration, trimStart: clip.trimStart, trimEnd: clip.trimEnd, speed: clip.speed, transitionAfter: clip.transitionAfter)
        copy.face = clip.face; copy.background = clip.background; copy.cameraEffect = clip.cameraEffect
        copy.zoom = clip.zoom; copy.offsetX = clip.offsetX; copy.offsetY = clip.offsetY; copy.fillsFrame = clip.fillsFrame
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            clips.insert(copy, at: idx + 1)
            selectedID = copy.id
        }
        thumbs[copy.id] = thumbs[clip.id]
        frameStrips[copy.id] = frameStrips[clip.id]
        Haptics.rigid()
    }

    private func delete(_ clip: WhisperWaveClip) {
        guard clips.count > 1, let idx = clips.firstIndex(where: { $0.id == clip.id }) else {
            show("A wave needs at least one clip")
            return
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            clips.remove(at: idx)
            selectedID = clips[min(idx, clips.count - 1)].id
        }
        // An effect scoped to the deleted clip widens to the whole wave.
        if fx?.clipID == clip.id { fx?.clipID = nil }
        Haptics.warning()
    }

    private func importPicked(_ items: [PhotosPickerItem]) async {
        importing = true
        defer {
            importing = false
            pickerItems = []
        }
        var added: [WhisperWaveClip] = []
        for item in items {
            guard clips.count + added.count < Self.maxClips else { break }
            guard let movie = try? await item.loadTransferable(type: WhisperPickedMovie.self) else { continue }
            let duration = await WhisperWaveClipStudio.duration(of: movie.url)
            guard duration > 0.2 else { continue }
            let clip = WhisperWaveClip(url: movie.url, duration: duration)
            added.append(clip)
            thumbs[clip.id] = await WhisperWaveClipStudio.thumbnail(url: movie.url, at: 0.1)
        }
        guard !added.isEmpty else {
            show("Couldn't read those videos")
            return
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            clips.append(contentsOf: added)
            selectedID = added.last?.id
        }
        Haptics.success()
    }

    private func hydrateThumbs() async {
        for clip in clips where thumbs[clip.id] == nil {
            thumbs[clip.id] = await WhisperWaveClipStudio.subjectFrames(clip, count: 1).first
        }
        if let first = clips.first { await ensureFrames(for: first) }
    }

    private func ensureFrames(for clip: WhisperWaveClip) async {
        guard frameStrips[clip.id] == nil else { return }
        frameStrips[clip.id] = await WhisperWaveClipStudio.subjectFrames(clip, count: 8)
    }

    private func finish() async {
        guard !clips.isEmpty else { return }
        guard WhisperWaveUploadPolicy.accepts(duration: totalSeconds) else {
            Haptics.warning()
            show("Up to 6 minutes — adjust Trim or Speed. Your clips are unchanged.")
            return
        }
        finishTyping()
        previewModel.pause()
        texts.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        Haptics.success()
        onDone()
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if toast == message { toast = nil }
        }
    }

    // MARK: Formatting

    static func clock(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let m = Int(s) / 60
        let r = s - Double(m * 60)
        if m > 0 { return String(format: "%d:%04.1f", m, r) }
        return String(format: "%.1fs", r)
    }

    static func speedLabel(_ s: Double) -> String {
        if abs(s - s.rounded()) < 0.01 { return "\(Int(s.rounded()))×" }
        if abs(s * 10 - (s * 10).rounded()) < 0.01 { return String(format: "%.1f×", s) }
        return String(format: "%.2f×", s)
    }
}

/// A UIView whose layer is an AVPlayerLayer.
final class WaveClipPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

// MARK: - The clip studio (export)

/// Off-main rendering of a clip timeline into one MP4.
nonisolated enum WhisperWaveClipStudio {
    /// Source duration in seconds (0 on failure).
    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let d = try? await asset.load(.duration) else { return 0 }
        let s = d.seconds
        return s.isFinite ? s : 0
    }

    /// Background-aware trim/tile imagery never silently shows the original room.
    static func subjectFrames(_ clip: WhisperWaveClip, count: Int) async -> [UIImage] {
        guard clip.background != nil || clip.cameraEffect != nil else { return await frames(url: clip.url, count: count) }
        var full = clip
        full.trimStart = 0; full.trimEnd = clip.duration; full.speed = 1; full.transitionAfter = .cut
        guard let built = await makeComposition([full], muteOriginal: true) else { return [] }
        let generator = AVAssetImageGenerator(asset: built.asset)
        generator.videoComposition = built.video
        generator.maximumSize = CGSize(width: 160, height: 284)
        var images: [UIImage] = []
        for index in 0..<count {
            guard !Task.isCancelled else { return [] }
            let at = CMTime(seconds: clip.duration * (Double(index) + 0.5) / Double(count), preferredTimescale: 600)
            if let cg = try? await generator.image(at: at).image { images.append(UIImage(cgImage: cg)) }
        }
        return images
    }

    /// One frame for a clip tile.
    static func thumbnail(url: URL, at seconds: Double) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 240, height: 426)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        guard let cg = try? await gen.image(at: time).image else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Evenly spaced frames for the trim strip.
    static func frames(url: URL, count: Int) async -> [UIImage] {
        let asset = AVURLAsset(url: url)
        guard let d = try? await asset.load(.duration) else { return [] }
        let seconds = d.seconds
        guard seconds.isFinite, seconds > 0 else { return [] }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 160, height: 284)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)
        var out: [UIImage] = []
        for i in 0..<count {
            let t = CMTime(seconds: seconds * (Double(i) + 0.5) / Double(count), preferredTimescale: 600)
            if let cg = try? await gen.image(at: t).image {
                out.append(UIImage(cgImage: cg))
            }
        }
        return out
    }

    /// One placed clip on the composition timeline.
    private struct Placed {
        let track: Int
        let start: CMTime
        let end: CMTime
        let transform: CGAffineTransform
        let transitionOut: WhisperWaveTransition
        let overlapOut: CMTime
    }

    /// Renders the timeline: trims, speeds, and transitions (fade = real
    /// cross-dissolve on two alternating tracks; dip = out through black).
    static func merge(_ clips: [WhisperWaveClip], musicURL: URL? = nil, musicStart: Double = 0, musicVolume: Float = 0.85, muteOriginal: Bool = false, texts: [WaveTextOverlay] = []) async -> URL? {
        guard let built = await makeComposition(clips, musicURL: musicURL, musicStart: musicStart, musicVolume: musicVolume, muteOriginal: muteOriginal, captions: nil) else { return nil }
        if !texts.isEmpty {
            built.video.animationTool = await WhisperWaveStudio.textTool(texts, renderSize: built.video.renderSize, duration: built.asset.duration.seconds)
        }
        return await export(built.asset, videoComposition: built.video, audioMix: built.audio)
    }

    /// Builds an in-memory edit for both AVPlayerItem and export. No video is encoded here.
    @concurrent static func makeComposition(_ clips: [WhisperWaveClip], musicURL: URL? = nil, musicStart: Double = 0, musicVolume: Float = 0.85, muteOriginal: Bool = false, filter: SnapFilter = .none, adjustments: WhisperWaveColorAdjustments = .init(), effect: WhisperAREffect = .none, fx: WhisperWaveFXSetting? = nil, quality: WhisperWaveRenderQuality = .final, texts: [WaveTextOverlay] = [], captions: WhisperWaveCaptions? = nil) async -> (asset: AVMutableComposition, video: AVMutableVideoComposition, audio: AVMutableAudioMix?)? {
        guard !clips.isEmpty, !Task.isCancelled else { return nil }
        let composition = AVMutableComposition()
        guard let videoA = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let videoB = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        let audioA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioB = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let videoTracks: [AVMutableCompositionTrack] = [videoA, videoB]
        let audioTracks: [AVMutableCompositionTrack?] = [audioA, audioB]
        var videoEnds: [CMTime] = [.zero, .zero]
        var audioEnds: [CMTime] = [.zero, .zero]

        var placed: [Placed] = []
        let renderSize = CGSize(width: 1080, height: 1920)
        var cursor = CMTime.zero
        var pendingOverlap = CMTime.zero
        let effective: [Double] = clips.map { $0.effectiveSeconds }

        for (i, clip) in clips.enumerated() {
            guard !Task.isCancelled else { return nil }
            let asset = AVURLAsset(url: clip.url)
            guard let vTrack = try? await asset.loadTracks(withMediaType: .video).first,
                  let assetDuration = try? await asset.load(.duration) else { return nil }
            let transform = (try? await vTrack.load(.preferredTransform)) ?? .identity
            let natural = (try? await vTrack.load(.naturalSize)) ?? CGSize(width: 1080, height: 1920)

            let total = assetDuration.seconds
            guard total.isFinite, total > 0, clip.speed.isFinite, clip.speed >= 0.1 else { return nil }
            let s = max(0, min(clip.trimStart, total))
            let e = clip.trimEnd > 0 ? max(min(clip.trimEnd, total), min(total, s + 0.3)) : total
            guard e - s > 0.15 else { return nil }
            let srcRange = CMTimeRange(
                start: CMTime(seconds: s, preferredTimescale: 600),
                end: CMTime(seconds: e, preferredTimescale: 600)
            )

            let trackIndex = placed.count % 2
            let vt = videoTracks[trackIndex]
            let startAt = CMTimeMaximum(CMTimeSubtract(cursor, pendingOverlap), .zero)

            // Fill the gap on this track so segments never overlap in place.
            if CMTimeCompare(startAt, videoEnds[trackIndex]) > 0 {
                vt.insertEmptyTimeRange(CMTimeRange(start: videoEnds[trackIndex], end: startAt))
            }
            do { try vt.insertTimeRange(srcRange, of: vTrack, at: startAt) } catch { return nil }

            var hasAudio = false
            if !muteOriginal, let aTrack = try? await asset.loadTracks(withMediaType: .audio).first, let at = audioTracks[trackIndex] {
                if CMTimeCompare(startAt, audioEnds[trackIndex]) > 0 {
                    at.insertEmptyTimeRange(CMTimeRange(start: audioEnds[trackIndex], end: startAt))
                }
                do {
                    let available = try await aTrack.load(.timeRange)
                    let audible = CMTimeRangeGetIntersection(srcRange, otherRange: available)
                    if audible.duration.seconds > 0 {
                        try at.insertTimeRange(audible, of: aTrack, at: CMTimeAdd(startAt, CMTimeSubtract(audible.start, srcRange.start)))
                        let audibleEnd = CMTimeAdd(startAt, CMTimeSubtract(audible.end, srcRange.start))
                        let fullEnd = CMTimeAdd(startAt, srcRange.duration)
                        if audibleEnd < fullEnd { at.insertEmptyTimeRange(CMTimeRange(start: audibleEnd, end: fullEnd)) }
                        hasAudio = true
                    }
                } catch { return nil }
            }

            var segDuration = srcRange.duration
            if abs(clip.speed - 1) > 0.01 {
                let scaled = CMTimeMultiplyByFloat64(srcRange.duration, multiplier: 1.0 / clip.speed)
                let inserted = CMTimeRange(start: startAt, duration: srcRange.duration)
                vt.scaleTimeRange(inserted, toDuration: scaled)
                if hasAudio { audioTracks[trackIndex]?.scaleTimeRange(inserted, toDuration: scaled) }
                segDuration = scaled
            }
            let end = CMTimeAdd(startAt, segDuration)
            videoEnds[trackIndex] = end
            if hasAudio { audioEnds[trackIndex] = end }

            // Transition INTO the next clip — capped so neither side loses
            // more than 40% of itself to the overlap.
            var outKind: WhisperWaveTransition = .cut
            var overlapOut = CMTime.zero
            if i < clips.count - 1, clip.transitionAfter != .cut {
                let nextEffective = effective[i + 1]
                let d = min(0.6, segDuration.seconds / 2.5, nextEffective / 2.5)
                if d > 0.12 {
                    outKind = clip.transitionAfter
                    overlapOut = CMTime(seconds: d, preferredTimescale: 600)
                }
            }

            placed.append(Placed(
                track: trackIndex,
                start: startAt,
                end: end,
                transform: WhisperWaveTimeline.transform(clip, naturalSize: natural, preferred: transform, canvas: renderSize),
                transitionOut: outKind,
                overlapOut: overlapOut
            ))
            cursor = end
            pendingOverlap = overlapOut
        }
        guard !placed.isEmpty else { return nil }

        // Instructions: an overlap instruction for every transition, a
        // pass-through instruction for every clip's solo stretch.
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var audioParams: [Int: AVMutableAudioMixInputParameters] = [:]
        func params(for track: Int) -> AVMutableAudioMixInputParameters? {
            guard let at = audioTracks[track] else { return nil }
            if let p = audioParams[track] { return p }
            let p = AVMutableAudioMixInputParameters(track: at)
            audioParams[track] = p
            return p
        }

        let originalGain: Float = musicURL == nil ? 1 : 0.55
        for (i, p) in placed.enumerated() {
            // Alternating tracks must reset gain after an earlier fade-out.
            params(for: p.track)?.setVolume(originalGain, at: p.start)
            var overlapIn = CMTime.zero
            if i > 0, placed[i - 1].transitionOut != .cut {
                overlapIn = placed[i - 1].overlapOut
            }
            if CMTimeCompare(overlapIn, .zero) > 0 {
                let prev = placed[i - 1]
                let range = CMTimeRange(start: p.start, duration: overlapIn)
                let inst = AVMutableVideoCompositionInstruction()
                inst.timeRange = range
                inst.backgroundColor = UIColor.black.cgColor
                let incoming = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTracks[p.track])
                incoming.setTransform(p.transform, at: range.start)
                let outgoing = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTracks[prev.track])
                outgoing.setTransform(prev.transform, at: range.start)
                switch prev.transitionOut {
                case .fade:
                    incoming.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: range)
                    outgoing.setOpacity(1, at: range.start)
                case .dip:
                    let half = CMTimeMultiplyByFloat64(overlapIn, multiplier: 0.5)
                    let firstHalf = CMTimeRange(start: range.start, duration: half)
                    let secondHalf = CMTimeRange(start: CMTimeAdd(range.start, half), duration: half)
                    outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: firstHalf)
                    outgoing.setOpacity(0, at: secondHalf.start)
                    incoming.setOpacity(0, at: range.start)
                    incoming.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: secondHalf)
                case .cut:
                    break
                }
                inst.layerInstructions = [incoming, outgoing]
                instructions.append(inst)
                params(for: prev.track)?.setVolumeRamp(fromStartVolume: originalGain, toEndVolume: 0, timeRange: range)
                params(for: p.track)?.setVolumeRamp(fromStartVolume: 0, toEndVolume: originalGain, timeRange: range)
            }

            let soloStart = CMTimeAdd(p.start, overlapIn)
            let soloEnd = CMTimeSubtract(p.end, p.transitionOut == .cut ? .zero : p.overlapOut)
            if CMTimeCompare(soloEnd, soloStart) > 0 {
                let inst = AVMutableVideoCompositionInstruction()
                inst.timeRange = CMTimeRange(start: soloStart, end: soloEnd)
                inst.backgroundColor = UIColor.black.cgColor
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTracks[p.track])
                layer.setTransform(p.transform, at: soloStart)
                layer.setOpacity(1, at: soloStart)
                inst.layerInstructions = [layer]
                instructions.append(inst)
            }
        }
        guard !instructions.isEmpty else { return nil }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        let textFrames = await WhisperWaveTextFrame.prepare(texts, canvas: renderSize)
        // Captions are timed in each source file; the clips carry them onto the
        // output clock through their trims and speeds, so splits and reorders
        // never touch the words.
        var captionFrames: [WhisperWaveCaptionFrame] = []
        if let captions, !captions.words.isEmpty {
            captionFrames = await WhisperWaveCaptionFrame.prepare(captions, clips: clips, canvas: renderSize)
        }
        // A clip-scoped effect covers that clip's stretch of the output clock,
        // transitions included; a deleted clip falls back to the whole wave.
        var fxWindow: ClosedRange<Double>? = nil
        if let fx, let clipID = fx.clipID, let index = clips.firstIndex(where: { $0.id == clipID }), placed.indices.contains(index) {
            fxWindow = placed[index].start.seconds...placed[index].end.seconds
        }
        var subjects: [WhisperWaveSubjectFrame] = []
        do {
            for (index, clip) in clips.enumerated() where clip.face != nil || clip.background != nil || clip.cameraEffect != nil {
                try Task.checkCancellation()
                let placement = placed[index]
                let range = CMTimeRange(start: placement.start, end: placement.end)
                let subject = try await WhisperWaveSubjectFrame.prepare(clip: clip, trackID: videoTracks[placement.track].trackID, range: range, composition: composition, canvas: renderSize)
                subjects.append(subject)
            }
        } catch { return nil }
        videoComposition.customVideoCompositorClass = WhisperWaveVideoCompositor.self
        videoComposition.instructions = instructions.map { base in
            let active = subjects.filter { CMTimeRangeGetIntersection($0.range, otherRange: base.timeRange).duration.seconds > 0 }
            return WhisperWaveVideoInstruction(base: base, filter: filter, adjustments: adjustments, effect: effect, fx: fx, fxWindow: fxWindow, quality: quality, textFrames: textFrames, captionFrames: captionFrames, captionY: captions?.clampedY ?? 0.74, captionScale: captions?.clampedScale ?? 1, canvas: renderSize, subjects: active)
        }

        var audioMix: AVMutableAudioMix? = nil
        if !audioParams.isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = Array(audioParams.values)
            audioMix = mix
        }

        if let musicURL {
            let musicAsset = AVURLAsset(url: musicURL)
            guard let track = try? await musicAsset.loadTracks(withMediaType: .audio).first,
                  let available = try? await track.load(.timeRange),
                  available.duration.seconds.isFinite, available.duration.seconds > 0.1,
                  let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
            let segments = WhisperWaveTimeline.audioSegments(duration: available.duration.seconds, start: musicStart, length: cursor.seconds)
            do {
                for segment in segments {
                    try destination.insertTimeRange(CMTimeRange(start: CMTimeAdd(available.start, CMTime(seconds: segment.source, preferredTimescale: 600)), duration: CMTime(seconds: segment.length, preferredTimescale: 600)), of: track, at: CMTime(seconds: segment.destination, preferredTimescale: 600))
                }
            } catch { return nil }
            let p = AVMutableAudioMixInputParameters(track: destination)
            p.setVolume(max(0, min(1, musicVolume)), at: .zero)
            let mix = audioMix ?? AVMutableAudioMix()
            mix.inputParameters = mix.inputParameters + [p]
            audioMix = mix
        }
        return (composition, videoComposition, audioMix)
    }

    private static func export(_ asset: AVAsset, videoComposition: AVVideoComposition?, audioMix: AVAudioMix?) async -> URL? {
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wave-clips-\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else { return nil }
        session.videoComposition = videoComposition
        session.audioMix = audioMix
        session.shouldOptimizeForNetworkUse = true
        do {
            try await session.export(to: outURL, as: .mp4)
            return outURL
        } catch {
            return nil
        }
    }
}
