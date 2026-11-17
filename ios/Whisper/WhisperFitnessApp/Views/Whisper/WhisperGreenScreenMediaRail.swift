import SwiftUI
import PhotosUI

/// Session-only background history: no automatic access to the user's photo library.
struct WhisperGreenScreenMediaRail: View {
    @Binding var background: WhisperWaveBackground?
    @Binding var isImporting: Bool
    var locked: Bool = false
    @State private var item: PhotosPickerItem?
    @State private var showsPicker: Bool = false
    @State private var showsAdjustments: Bool = false
    @State private var choices: [WhisperWaveBackground] = []
    @State private var thumbnails: [URL: UIImage] = [:]
    @State private var error: String?
    @State private var operation: UUID = UUID()
    @State private var closed: Bool = false

    var body: some View {
        VStack(spacing: 5) {
            Text(background == nil ? "Add a photo or video for your background" : "Pinch to resize · drag to move")
                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5).background(.black.opacity(0.5), in: .capsule)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Button { showsPicker = true } label: {
                        Group {
                            if isImporting { ProgressView().tint(.white) }
                            else { Image(systemName: "plus").font(.title2) }
                        }.frame(width: 48, height: 64).background(.white.opacity(0.2), in: .rect(cornerRadius: 10))
                    }.accessibilityLabel("Choose background photo or video")
                    ForEach(choices, id: \.url) { choice in
                        Button { background = choice; Haptics.selection() } label: {
                            Color(white: 0.18).frame(width: 48, height: 64)
                                .overlay {
                                    if let image = thumbnails[choice.url] { Image(uiImage: image).resizable().scaledToFill().allowsHitTesting(false) }
                                    else { Image(systemName: choice.media == .video ? "video" : "photo") }
                                }.clipShape(.rect(cornerRadius: 10))
                                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(background?.url == choice.url ? 1 : 0.25), lineWidth: 2) }
                                .overlay(alignment: .bottomTrailing) { if choice.media == .video { Image(systemName: "play.fill").font(.caption2).padding(5) } }
                        }.accessibilityLabel(choice.media == .video ? "Use video background" : "Use photo background")
                    }
                    if background != nil {
                        Button { showsAdjustments = true } label: {
                            Image(systemName: "slider.horizontal.3").frame(width: 48, height: 64).background(.black.opacity(0.4), in: .rect(cornerRadius: 10))
                        }.accessibilityLabel("Adjust cutout and background")
                        Button { background = nil } label: {
                            Image(systemName: "xmark").frame(width: 48, height: 64).background(.black.opacity(0.4), in: .rect(cornerRadius: 10))
                        }.accessibilityLabel("Remove green screen")
                    }
                }.buttonStyle(.plain).foregroundStyle(.white).disabled(locked || isImporting)
            }.contentMargins(.horizontal, 16)
        }
        .photosPicker(isPresented: $showsPicker, selection: $item, matching: .any(of: [.images, .videos]))
        .task(id: item) { await importMedia() }
        .onAppear { closed = false }
        .onDisappear { closed = true; operation = UUID(); isImporting = false }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            closed = true; operation = UUID(); item = nil; choices = []; thumbnails = [:]; showsPicker = false; showsAdjustments = false; isImporting = false
        }
        .sheet(isPresented: $showsAdjustments) {
            NavigationStack {
                WhisperWaveBackgroundControls(background: $background, pause: {})
                    .padding(.horizontal, 16).background(Color.black)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsAdjustments = false } } }
            }.presentationDetents([.medium, .large]).presentationContentInteraction(.scrolls)
        }
        .alert("Couldn't open background", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Choose again") { showsPicker = true }
            Button("Cancel", role: .cancel) {}
        } message: { Text(error ?? "Please try another photo or video.") }
    }

    private func importMedia() async {
        guard let item, !closed, !locked else { return }
        let token = UUID(); operation = token
        let generation = AccountStorage.generation
        isImporting = true
        defer { if token == operation { isImporting = false; self.item = nil } }
        do {
            let imported = try await WhisperWaveBackgroundImporter.load(item)
            guard !closed, !Task.isCancelled, token == operation, generation == AccountStorage.generation else {
                try? FileManager.default.removeItem(at: imported.url); return
            }
            background = imported
            choices.removeAll { $0.url == imported.url }; choices.insert(imported, at: 0)
            choices = Array(choices.prefix(8))
            let image: UIImage?
            if imported.media == .photo {
                image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: imported.url.path)?.preparingThumbnail(of: CGSize(width: 120, height: 160)) }.value
            } else { image = await WhisperStoryPoster.firstFrame(of: imported.url) }
            guard !closed, !Task.isCancelled, token == operation, generation == AccountStorage.generation else { return }
            if let image { thumbnails[imported.url] = image }
            thumbnails = thumbnails.filter { url, _ in choices.contains { $0.url == url } }
            Haptics.success()
        } catch {
            guard !closed, !Task.isCancelled, token == operation, generation == AccountStorage.generation else { return }
            self.error = "Your previous background is unchanged. Try that photo or video again."
        }
    }
}
