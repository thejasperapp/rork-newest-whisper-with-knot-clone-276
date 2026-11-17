import SwiftUI

/// Widget entry to Imagine. Generation is explicit and never sends a DM automatically.
struct WhisperImagineDestinationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var prompt: String = ""
    @State private var image: UIImage?
    @State private var busy: Bool = false
    @State private var error: String?
    @State private var work: Task<Void, Never>?
    @State private var confirmClose: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Imagine with Jasper", systemImage: "sparkles").font(.title2.bold())
                    Text("Describe an image. Nothing is shared until you choose to share it.").foregroundStyle(.secondary)
                    TextField("Describe your image…", text: $prompt, axis: .vertical)
                        .lineLimit(3...8).padding(16).background(.quaternary, in: .rect(cornerRadius: 20)).disabled(busy)
                    Button(busy ? "Imagining…" : "Imagine") { generate() }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(busy || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if busy { ProgressView().frame(maxWidth: .infinity).padding(40) }
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(.rect(cornerRadius: 24))
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Jasper Imagine", image: Image(uiImage: image))) {
                            Label("Share image", systemImage: "square.and.arrow.up")
                        }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }
                    if let error { Text(error).foregroundStyle(.secondary) }
                }.padding(.horizontal, 20).padding(.vertical, 16)
            }
            .navigationTitle("Imagine").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { requestClose() }.disabled(busy) } }
            .whisperEdgeBack(isEnabled: !busy, requiresDecision: image != nil || !prompt.isEmpty) { requestClose() }
            .confirmationDialog("Leave Imagine?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: { Text("Share your generated image before leaving if you want to keep it.") }
        }
        .interactiveDismissDisabled(busy || image != nil || !prompt.isEmpty)
        .onDisappear { work?.cancel() }
    }

    private func requestClose() { if image != nil || !prompt.isEmpty { confirmClose = true } else { dismiss() } }
    private func generate() {
        let generation = AccountStorage.generation
        busy = true; error = nil
        work = Task {
            defer { busy = false }
            do {
                let data = try await OpenAIService().generateImage(prompt: prompt)
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                guard let result = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                image = result
            } catch { if !Task.isCancelled { self.error = "Couldn't create this image. Please try again." } }
        }
    }
}
