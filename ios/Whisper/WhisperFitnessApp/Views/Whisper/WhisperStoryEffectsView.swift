import SwiftUI

/// Photo-first effects workspace. Nothing reaches the Story until Done.
struct WhisperStoryEffectsView: View {
    let image: UIImage
    let original: UIImage
    let onApply: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preview: UIImage?
    @State private var generated: UIImage?
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selected: WhisperGridFilter = .normal
    @State private var prompt: String = ""
    @State private var operation: Task<Void, Never>?
    @State private var requestID: UUID = UUID()
    @State private var generation: UUID = AccountStorage.generation
    @State private var isWorking: Bool = false
    @State private var error: String?
    @State private var closed: Bool = false
    @State private var showOriginal: Bool = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            WhisperStoryToolHeader(title: promptFocused ? "Write a prompt" : "Effects", canConfirm: !isWorking, onConfirm: {
                guard !closed, !isWorking, generation == AccountStorage.generation else { return }
                onApply(preview ?? image); close()
            }, onCancel: close)
            GeometryReader { geometry in
                let size = WhisperStoryEditor.stageSize(in: geometry.size)
                Color(white: 0.07)
                    .frame(width: size.width, height: size.height)
                    .overlay {
                        Image(uiImage: showOriginal ? original : preview ?? image).resizable().scaledToFit().allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 24))
                    .overlay {
                        if isWorking { ProgressView("Creating preview…").padding(16).background(.black.opacity(0.7), in: .capsule) }
                    }
                    .overlay(alignment: .bottom) {
                        Button { showOriginal.toggle() } label: {
                            Text(showOriginal ? "Show edit" : "Compare original").font(.caption).padding(.horizontal, 14).frame(minHeight: 44).background(.black.opacity(0.55), in: .capsule)
                        }.padding(12).accessibilityLabel(showOriginal ? "Show edited photo" : "Show original photo")
                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }.padding(.horizontal, 16)
            if let error { Text(error).font(.caption).foregroundStyle(.white.opacity(0.8)).padding(.horizontal, 20) }
            if !promptFocused {
                HStack {
                    Text("Photo looks").font(.subheadline.weight(.semibold))
                    Spacer()
                    if generated != nil || selected != .normal {
                        Button("Reset") { cancelWork(); generated = nil; preview = image; selected = .normal; showOriginal = false }
                            .font(.caption).frame(minHeight: 44)
                    }
                }.padding(.horizontal, 16)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(WhisperGridFilter.allCases, id: \.rawValue) { look in
                            Button { choose(look) } label: {
                                VStack(spacing: 6) {
                                    Image(uiImage: thumbnails[look.rawValue] ?? image).resizable().scaledToFill()
                                        .frame(width: 66, height: 88).clipped().clipShape(.rect(cornerRadius: 10))
                                        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(selected == look ? .white : .clear, lineWidth: 2) }
                                    Text(look.rawValue).font(.caption2).lineLimit(1)
                                }.frame(width: 70)
                            }.disabled(isWorking).accessibilityAddTraits(selected == look ? .isSelected : [])
                        }
                    }
                }.contentMargins(.horizontal, 16)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Change anything about your photo…", text: $prompt, axis: .vertical)
                    .font(.subheadline).lineLimit(1...4).focused($promptFocused)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color(white: 0.13), in: .rect(cornerRadius: 24))
                Button { if isWorking { cancelWork() } else { generate() } } label: {
                    Image(systemName: isWorking ? "stop.fill" : "arrow.up")
                        .font(.system(size: 19, weight: .semibold)).frame(width: 44, height: 44)
                        .foregroundStyle(.black).background(.white, in: .circle)
                }.disabled(!isWorking && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(isWorking ? "Cancel generation" : "Generate photo edit")
            }.padding(.horizontal, 16)
            Text("AI edits send this photo and your prompt for processing. Apply only after reviewing.")
                .font(.caption2).foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 20).padding(.bottom, 8)
        }
        .statusBarHidden(false)
        .foregroundStyle(.white).tint(.white).buttonStyle(.plain)
        .background(Color.black.ignoresSafeArea()).environment(\.colorScheme, .dark)
        .task {
            guard let data = image.jpegData(compressionQuality: 0.7) else { return }
            let thumbs = await Task.detached(priority: .utility) { () -> [String: UIImage] in
                guard let small = WhisperImageCache.decode(data, maxPixelSize: 200) else { return [:] }
                return Dictionary(uniqueKeysWithValues: WhisperGridFilter.allCases.map { ($0.rawValue, $0.bake(small)) })
            }.value
            guard !Task.isCancelled, !closed, generation == AccountStorage.generation else { return }
            thumbnails = thumbs
        }
        .onDisappear { closed = true; cancelWork() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in close() }
        .accessibilityAction(.escape) { if promptFocused { promptFocused = false } else { close() } }
    }

    private func choose(_ look: WhisperGridFilter) {
        guard !isWorking, !closed else { return }
        cancelWork(); error = nil; showOriginal = false
        let source = generated ?? image
        let id = requestID
        isWorking = true
        operation = Task {
            let result = await Task.detached(priority: .userInitiated) { look.rendered(source) }.value
            guard !Task.isCancelled, !closed, id == requestID, generation == AccountStorage.generation else { return }
            isWorking = false
            guard let result else { error = "That photo look couldn't be rendered. Your previous preview is kept."; return }
            selected = look; preview = result
        }
    }

    private func generate() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking, !closed, generation == AccountStorage.generation else { return }
        guard let data = (preview ?? image).jpegData(compressionQuality: 0.85) else { error = "Couldn't prepare this photo."; return }
        cancelWork(); let id = requestID
        error = nil; isWorking = true; promptFocused = false; showOriginal = false
        operation = Task {
            do {
                let bytes = try await WhisperStoryImageEditService.edit(jpeg: data, prompt: String(text.prefix(2000)), aspectRatio: image.size.width / max(1, image.size.height))
                let result = await Task.detached(priority: .userInitiated) { WhisperImageCache.decode(bytes, maxPixelSize: 2048) }.value
                guard !Task.isCancelled, !closed, id == requestID, generation == AccountStorage.generation else { return }
                guard let result else { throw URLError(.cannotDecodeContentData) }
                let sourceRatio = image.size.width / max(1, image.size.height)
                let outputRatio = result.size.width / max(1, result.size.height)
                guard abs(outputRatio / sourceRatio - 1) < 0.03 else {
                    isWorking = false; self.error = "The edit changed your photo's shape. Your original framing is kept; try the prompt again."
                    return
                }
                generated = result; preview = result; selected = .normal; isWorking = false
            } catch {
                guard !Task.isCancelled, !closed, id == requestID, generation == AccountStorage.generation else { return }
                isWorking = false; self.error = "Couldn't create that edit. Your photo is unchanged. Try again or revise the prompt."
            }
        }
    }
    private func cancelWork() { requestID = UUID(); operation?.cancel(); operation = nil; isWorking = false }
    private func close() { closed = true; cancelWork(); dismiss() }
}
