import SwiftUI
import PhotosUI

/// Draft-only photo-card authoring. Done is the sole canvas mutation point.
struct WhisperStoryPhotoCardEditor: View {
    let layout: WhisperStoryPhotoLayout
    let existing: WhisperStorySticker?
    let onDone: (WhisperStorySticker) -> Void
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WhisperStorySticker
    @State private var items: [PhotosPickerItem] = []
    @State private var prepared: Data?
    @State private var preview: UIImage?
    @State private var isPicking: Bool = false
    @State private var didPresentInitialPicker: Bool = false
    @State private var isPreparing: Bool = false
    @State private var isSaving: Bool = false
    @State private var error: String?
    @State private var closed: Bool = false
    @State private var generation: UUID = AccountStorage.generation
    @State private var selectionID: UUID = UUID()
    @State private var uploadURL: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var confirmDiscard: Bool = false
    @FocusState private var captionFocused: Bool

    init(layout: WhisperStoryPhotoLayout, existing: WhisperStorySticker? = nil, onClose: (() -> Void)? = nil, onDone: @escaping (WhisperStorySticker) -> Void) {
        self.layout = layout
        self.existing = existing
        self.onDone = onDone
        self.onClose = onClose
        var layer = existing ?? WhisperStorySticker(kind: .photo)
        if existing == nil {
            layer.photoLayout = layout == .strip ? "strip" : "frame"
            layer.cardWidthFraction = layout == .strip ? 0.26 : 0.58
            layer.mediaAspectRatio = layout == .strip ? 0.26 : 0.8
            layer.photoFrame = false
            layer.shape = "rect"
            layer.style = 0
            layer.text = ""
            layer.frameReveal = layout == .frame
            // This is the frame's creation time, not invented EXIF capture metadata.
            if layout == .frame { layer.frameTimestamp = ISO8601DateFormatter().string(from: .now) }
        }
        _draft = State(initialValue: layer)
    }

    private var isStrip: Bool { layout == .strip }
    private var valid: Bool { !closed && !Task.isCancelled && generation == AccountStorage.generation }
    private var hasMedia: Bool { prepared != nil || draft.imageURL != nil }
    private var hasChanges: Bool { prepared != nil || (existing.map { $0 != draft } ?? !(draft.text ?? "").isEmpty) }
    private var caption: Binding<String> {
        Binding(get: { draft.text ?? "" }, set: { draft.text = String($0.prefix(160)) })
    }

    var body: some View {
        VStack(spacing: 0) {
            WhisperStoryToolHeader(title: onClose == nil ? layout.title : "", inline: onClose != nil, canConfirm: hasMedia && !isPreparing && !isSaving && !isPicking, onConfirm: {
                guard !isSaving, !isPreparing, valid else { return }
                isSaving = true; captionFocused = false
                saveTask = Task { await save() }
            }, onCancel: requestClose)
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 16) {
                        if !isStrip {
                            Text("Your photo reveals on shake or tap.").font(.caption).foregroundStyle(.white.opacity(0.85))
                        }
                        if hasMedia {
                            WhisperStoryPhotoCardView(sticker: draft, stageWidth: min(390, max(240, geo.size.width - 32)), localImage: preview, caption: caption, captionFocus: $captionFocused)
                                .padding(.horizontal, 16).disabled(isSaving)
                        } else {
                            Image(systemName: isStrip ? "rectangle.split.1x3" : "photo.artframe")
                                .font(.system(size: 64, weight: .ultraLight)).foregroundStyle(.white.opacity(0.7))
                                .frame(height: 180)
                            Text(isStrip ? "Choose up to 4 photos in order." : "Choose a photo to frame.")
                                .font(.subheadline).foregroundStyle(.white)
                        }
                        if isPreparing || isSaving { ProgressView(isSaving ? "Adding photo…" : "Preparing photos…").tint(.white).foregroundStyle(.white) }
                        if let error { Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.horizontal, 20) }
                        Button { captionFocused = false; isPicking = true } label: {
                            Label(hasMedia ? "Change photos" : "Choose photos", systemImage: "photo.on.rectangle").padding(.horizontal, 18).frame(minHeight: 44)
                                .background(.white.opacity(0.1), in: .capsule)
                        }.font(.subheadline.weight(.medium)).foregroundStyle(.white).disabled(isPreparing || isSaving)

                        if isStrip, hasMedia { stylePicker.disabled(isSaving) }
                        if !isStrip, hasMedia, onClose == nil {
                            Text("The date records when this frame was created. Reveal is a visual effect, not extra privacy; older versions may show the photo immediately.")
                                .font(.caption2).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center).padding(.horizontal, 28)
                        }
                    }.padding(.vertical, 20).frame(maxWidth: .infinity, minHeight: geo.size.height)
                }.scrollDismissesKeyboard(.interactively)
            }
        }
        .buttonStyle(.plain).environment(\.colorScheme, .dark)
        .interactiveDismissDisabled(hasChanges || isSaving)
        .photosPicker(isPresented: $isPicking, selection: $items, maxSelectionCount: isStrip ? 4 : 1, selectionBehavior: .ordered, matching: .images)
        .task(id: items) { await prepareSelection() }
        .onAppear {
            if !didPresentInitialPicker {
                didPresentInitialPicker = true
                if existing == nil && !hasMedia { isPicking = true }
            }
        }
        .onChange(of: isPicking) { _, picking in
            if !picking, valid, hasMedia, !isPreparing { captionFocused = true }
        }
        .onChange(of: items) { _, selection in isPreparing = !selection.isEmpty }
        .onDisappear { if !isPicking { closed = true; saveTask?.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            closed = true; saveTask?.cancel(); prepared = nil; preview = nil; finishPresentation()
        }
        .confirmationDialog("Discard photo-card changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { close() }
            Button("Keep editing", role: .cancel) {}
        } message: { Text("Your Story and the original photos stay unchanged.") }
        .accessibilityAction(.escape) { requestClose() }
    }

    private var stylePicker: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { value in
                Button { draft.style = value; Haptics.tap() } label: {
                    Text(["Classic", "Mono", "Pastel"][value]).font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(.white.opacity(draft.style == value ? 0.22 : 0.06), in: .capsule)
                }.accessibilityAddTraits(draft.style == value ? .isSelected : [])
            }
        }.foregroundStyle(.white)
    }

    private func requestClose() { if hasChanges || isSaving { confirmDiscard = true } else { close() } }
    private func close() { closed = true; captionFocused = false; saveTask?.cancel(); finishPresentation() }
    private func finishPresentation() { if let onClose { onClose() } else { dismiss() } }

    private func prepareSelection() async {
        guard valid, !items.isEmpty else { return }
        let request = UUID(); selectionID = request
        isPreparing = true; error = nil
        defer { if selectionID == request { isPreparing = false } }
        let selected = items
        do {
            var data: [Data] = []
            for item in selected {
                guard let bytes = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                guard valid, selectionID == request else { return }
                // Downsample each selection before retaining the next full-resolution transfer.
                let small = await Task.detached(priority: .userInitiated) {
                    WhisperImageCache.decode(bytes, maxPixelSize: 1600)?.jpegData(compressionQuality: 0.93)
                }.value
                guard valid, selectionID == request else { return }
                guard let small else { throw CocoaError(.fileReadCorruptFile) }
                data.append(small)
            }
            let strip = isStrip
            let result = await Task.detached(priority: .userInitiated) { WhisperStoryPhotoCardRenderer.prepare(data, strip: strip) }.value
            guard valid, selectionID == request else { return }
            guard let result, let image = UIImage(data: result) else { throw CocoaError(.fileReadCorruptFile) }
            prepared = result; preview = image; uploadURL = nil
            draft.mediaAspectRatio = isStrip ? image.size.width / max(1, image.size.height) : 0.8
            draft.mediaCount = data.count
            captionFocused = !isPicking
        } catch {
            guard valid, selectionID == request else { return }
            self.error = "Couldn't prepare those photos. Your previous selection is kept; choose again to retry."
        }
    }

    private func save() async {
        defer { isSaving = false }
        guard valid, hasMedia, !isPreparing else { return }
        if let prepared, uploadURL == nil {
            if isStrip {
                uploadURL = await WhisperBackendService.shared.uploadStoryCutout(prepared, id: UUID())
            } else {
                uploadURL = await WhisperBackendService.shared.uploadMedia(datas: [prepared], postID: "story-frame-\(UUID().uuidString)").first
            }
            guard valid else { return }
            guard uploadURL != nil else { error = "Couldn't add this photo. Your caption and selection are kept. Tap Done to retry."; return }
        }
        if let uploadURL { draft.imageURL = uploadURL }
        guard valid, !confirmDiscard, draft.imageURL != nil else { return }
        closed = true
        onDone(draft)
        finishPresentation()
    }
}
