import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

/// A retained, system-owned library inside the capture shell. Selection never publishes.
struct WhisperCapturePostLibraryView: View {
    @Binding var items: [PhotosPickerItem]
    let capturedPhoto: UIImage?
    let isActive: Bool
    let onClose: () -> Void
    let onCamera: () -> Void
    let onClearCapture: () -> Void
    let onNext: () -> Void
    @State private var preview: UIImage?
    @State private var previewIssue: String?
    @State private var previewLoading: Bool = false
    @State private var retryRevision: Int = 0
    @State private var previewOperation: UUID = UUID()

    private var hasVideo: Bool {
        items.contains { item in item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) } }
    }
    private var validSelection: Bool { capturedPhoto != nil || (!items.isEmpty && (!hasVideo || items.count == 1)) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Close creation")
                    Spacer()
                    Text("New post").font(.headline)
                    Spacer()
                    Button("Next", action: onNext).font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44).disabled(!validSelection)
                }.padding(.horizontal, 8)
                Color.black
                    .frame(height: max(90, min(geometry.size.width, geometry.size.height * 0.42)))
                    .overlay {
                        if let preview = capturedPhoto ?? preview {
                            Image(uiImage: preview).resizable().scaledToFit().allowsHitTesting(false)
                        } else if previewLoading {
                            ProgressView().tint(.white)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: hasVideo ? "video" : "photo.on.rectangle").font(.largeTitle)
                                Text(previewIssue ?? (hasVideo ? "Video selected · preview on Next" : "Choose photos or one video"))
                                    .font(.subheadline).multilineTextAlignment(.center)
                                if previewIssue != nil { Button("Retry preview") { retryRevision += 1 }.frame(minHeight: 44) }
                            }.foregroundStyle(.white.opacity(0.7)).padding(16)
                        }
                    }.clipped()
                HStack {
                    Button(action: onCamera) { Label("Camera", systemImage: "camera").frame(minHeight: 44) }
                    Spacer()
                    Text(capturedPhoto != nil ? "Captured photo" : items.isEmpty ? "Your library" : "\(items.count) selected").font(.caption)
                    if !items.isEmpty || capturedPhoto != nil { Button("Clear") { items = []; onClearCapture() }.frame(minHeight: 44) }
                }.font(.subheadline).padding(.horizontal, 16)
                if hasVideo && items.count > 1 {
                    Text("Choose up to 10 photos or one video, not a mixture.")
                        .font(.caption).foregroundStyle(.orange).padding(.horizontal, 16)
                }
                PhotosPicker(selection: $items, maxSelectionCount: 10, selectionBehavior: .continuousAndOrdered,
                             matching: .any(of: [.images, .videos])) { Text("Library") }
                    .photosPickerStyle(.inline)
                    .photosPickerDisabledCapabilities(.selectionActions)
                    .photosPickerAccessoryVisibility(.hidden, edges: .bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(.black)
        }
        .foregroundStyle(.white)
        .task(id: items) { if isActive { await loadPreview() } }
        .task(id: isActive) { if isActive, preview == nil { await loadPreview() } }
        .task(id: retryRevision) { if retryRevision > 0, isActive { await loadPreview() } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            previewOperation = UUID(); preview = nil; previewIssue = nil; previewLoading = false
        }
    }

    private func loadPreview() async {
        let operation = UUID(); previewOperation = operation
        preview = nil; previewIssue = nil
        guard let item = items.last else { previewLoading = false; return }
        // Avoid downloading a whole movie for a decorative gallery preview.
        guard !item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) else {
            previewLoading = false; return
        }
        let generation = AccountStorage.generation
        let selection = items
        previewLoading = true
        defer { if operation == previewOperation, selection == items, generation == AccountStorage.generation { previewLoading = false } }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), data.count <= 32 * 1024 * 1024 else {
                throw CocoaError(.fileReadTooLarge)
            }
            let image: UIImage? = await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1000
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: thumbnail)
            }.value
            guard !Task.isCancelled, operation == previewOperation, generation == AccountStorage.generation, selection == items else { return }
            preview = image
            if image == nil { previewIssue = "Preview unavailable. You can retry or continue to review your post." }
        } catch {
            guard !Task.isCancelled, operation == previewOperation, generation == AccountStorage.generation, selection == items else { return }
            previewIssue = "Couldn't load this preview. Retry or choose another photo."
        }
    }
}
