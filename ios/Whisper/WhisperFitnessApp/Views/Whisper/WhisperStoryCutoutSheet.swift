import SwiftUI
import PhotosUI

struct WhisperStoryCutoutSheet: View {
    let onDone: (WhisperStorySticker) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var png: Data?
    @State private var preview: UIImage?
    @State private var loading: Bool = false
    @State private var saving: Bool = false
    @State private var error: String?
    @State private var generation: UUID = AccountStorage.generation
    @State private var closed: Bool = false
    @State private var uploadTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            WhisperStoryToolHeader(title: "Cutouts", confirmation: "Add", canConfirm: png != nil && !loading && !saving, onConfirm: {
                uploadTask = Task { await add() }
            }, onCancel: { closed = true; uploadTask?.cancel(); dismiss() })
            ScrollView {
                VStack(spacing: 22) {
                    Color(white: 0.16).aspectRatio(1, contentMode: .fit).frame(maxWidth: 320)
                        .overlay {
                            if let preview { Image(uiImage: preview).resizable().scaledToFit().padding(20).allowsHitTesting(false) }
                            else { WhisperAttachmentIllustration(id: "draw", symbol: "scissors").scaleEffect(2).frame(width: 90, height: 90) }
                        }.clipShape(.rect(cornerRadius: 24))
                    Text("Make a cutout").font(.headline)
                    Text("Pick a photo with a clear subject. Preview the cutout, then tap Add. The original photo stays on your device.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    PhotosPicker(selection: $item, matching: .images) { Label("Choose photo", systemImage: "photo").frame(minHeight: 44) }.disabled(loading || saving)
                    if loading || saving { ProgressView(loading ? "Finding the subject…" : "Adding cutout…") }
                    if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                }.padding(20)
            }
        }.presentationDetents([.large]).environment(\.colorScheme, .dark).interactiveDismissDisabled(saving)
        .task(id: item) { await prepare() }
        .onDisappear { closed = true; uploadTask?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in closed = true; uploadTask?.cancel(); png = nil; preview = nil; dismiss() }
    }
    private var valid: Bool { !closed && !Task.isCancelled && generation == AccountStorage.generation }
    private func prepare() async {
        guard let item, valid else { return }
        loading = true; error = nil; png = nil; preview = nil
        defer { loading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), valid else { return }
            let result = try await Task.detached(priority: .userInitiated) { try WhisperStoryCutoutService.makePNG(from: data) }.value
            guard valid else { return }; png = result; preview = UIImage(data: result)
        } catch { if valid { self.error = "Couldn't separate a subject in this photo on this device. Try a clearer photo." } }
    }
    private func add() async {
        guard valid, let png, !saving else { return }; saving = true; error = nil
        defer { saving = false }
        let url = await WhisperBackendService.shared.uploadStoryCutout(png, id: UUID())
        guard valid else { return }
        guard let url else { error = "Couldn't upload the cutout. Tap Add to retry."; return }
        onDone(WhisperStorySticker(kind: .sticker, scale: 1.8, imageURL: url)); dismiss()
    }
}
