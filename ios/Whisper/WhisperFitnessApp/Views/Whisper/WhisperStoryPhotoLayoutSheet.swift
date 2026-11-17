import SwiftUI
import PhotosUI

struct WhisperStoryPhotoLayoutSheet: View {
    let layout: WhisperStoryPhotoLayout
    let stageWidth: Double
    let onDone: ([WhisperStorySticker]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PhotosPickerItem] = []
    @State private var photos: [UIImage] = []
    @State private var prepared: [Data] = []
    @State private var loading: Bool = false
    @State private var saving: Bool = false
    @State private var error: String?
    @State private var generation: UUID = AccountStorage.generation
    @State private var closed: Bool = false
    @State private var uploadTask: Task<Void, Never>?
    @State private var batchID: String = UUID().uuidString
    @State private var urls: [Int: String] = [:]

    var body: some View {
        if layout == .frame || layout == .strip {
            WhisperStoryPhotoCardEditor(layout: layout) { onDone([$0]) }
        } else { standardLayout }
    }

    private var standardLayout: some View {
        VStack(spacing: 0) {
            WhisperStoryToolHeader(title: layout.title, confirmation: "Add", canConfirm: !loading && !saving && prepared.count == layout.cells.count, onConfirm: {
                uploadTask = Task { await add() }
            }, onCancel: { closed = true; uploadTask?.cancel(); dismiss() })
            ScrollView {
                VStack(spacing: 18) {
                    GeometryReader { geo in
                        ZStack {
                            Color(white: 0.10)
                            ForEach(Array(layout.cells.enumerated()), id: \.offset) { index, cell in
                                Color(white: 0.24).frame(width: cell.width * geo.size.width, height: cell.height * geo.size.height)
                                    .overlay {
                                        if photos.indices.contains(index) { Image(uiImage: photos[index]).resizable().scaledToFill().allowsHitTesting(false) }
                                        else { Text("\(index + 1)").foregroundStyle(.white.opacity(0.5)) }
                                    }.clipped().padding(layout == .frame || layout == .strip ? 4 : 0)
                                    .padding(.bottom, layout == .frame || layout == .strip ? 14 : 0)
                                    .background(layout == .frame || layout == .strip ? Color.white : .clear)
                                    .position(x: cell.midX * geo.size.width, y: cell.midY * geo.size.height)
                            }
                        }
                    }.aspectRatio(9.0 / 16.0, contentMode: .fit).frame(maxWidth: 280).clipShape(.rect(cornerRadius: 24))
                    Text("Choose \(layout.cells.count) photos in order. Each photo remains editable.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    PhotosPicker(selection: $items, maxSelectionCount: layout.cells.count, selectionBehavior: .ordered, matching: .images) {
                        Label(photos.isEmpty ? "Choose photos" : "Change photos", systemImage: "photo.on.rectangle.angled").frame(minHeight: 44)
                    }.disabled(loading || saving)
                    if loading || saving { ProgressView(saving ? "Adding photos…" : "Preparing photos…") }
                    if let error { Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center) }
                }.padding(20)
            }
        }
        .presentationDetents([.large]).environment(\.colorScheme, .dark).interactiveDismissDisabled(saving)
        .task(id: items) { await prepare() }
        .onDisappear { closed = true; uploadTask?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in closed = true; uploadTask?.cancel(); photos = []; prepared = []; dismiss() }
    }
    private var valid: Bool { !closed && !Task.isCancelled && generation == AccountStorage.generation }
    private func prepare() async {
        guard valid else { return }
        prepared = []; photos = []; urls = [:]; batchID = UUID().uuidString
        guard !items.isEmpty else { return }
        loading = true; error = nil
        defer { loading = false }
        var nextData: [Data] = []; var nextPhotos: [UIImage] = []
        do {
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self), valid else { return }
                let result = await Task.detached(priority: .userInitiated) { WhisperImageCache.decode(data, maxPixelSize: 1600)?.jpegData(compressionQuality: 0.9) }.value
                guard valid else { return }
                guard let result, let image = UIImage(data: result) else { throw CocoaError(.fileReadCorruptFile) }
                nextData.append(result); nextPhotos.append(image)
            }
            guard valid else { return }; prepared = nextData; photos = nextPhotos
        } catch { if valid { self.error = "Couldn't load all photos. Choose them again to retry." } }
    }
    private func add() async {
        guard valid, prepared.count == layout.cells.count, !saving else { return }
        saving = true; error = nil
        defer { saving = false }
        for (index, data) in prepared.enumerated() {
            guard valid else { return }
            if urls[index] == nil {
                let result = await WhisperBackendService.shared.uploadMedia(datas: [data], postID: "layout-\(batchID)-\(index)")
                guard valid else { return }
                guard let url = result.first else { error = "Couldn't add all photos. Tap Add to retry; your selection is kept."; return }
                urls[index] = url
            }
        }
        guard valid else { return }
        let ordered = prepared.indices.compactMap { urls[$0] }
        guard ordered.count == prepared.count else { return }
        onDone(layout.stickers(urls: ordered, stageWidth: stageWidth)); dismiss()
    }
}
