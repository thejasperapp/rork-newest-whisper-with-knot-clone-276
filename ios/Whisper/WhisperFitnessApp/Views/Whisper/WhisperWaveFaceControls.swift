import SwiftUI
import CoreImage

/// Face-aware options remain independent of camera looks and the green-screen layer.
struct WhisperWaveFaceControls: View {
    @Binding var clips: [WhisperWaveClip]
    let clipID: UUID
    let thumbnail: UIImage?
    let pause: () -> Void
    @State private var previews: [WhisperWaveFaceSetting.Kind: UIImage] = [:]
    @State private var notice: String?
    private var setting: WhisperWaveFaceSetting { clips.first { $0.id == clipID }?.face ?? .init() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Face studio", systemImage: "face.smiling").font(.subheadline.weight(.semibold))
                Spacer()
                if clips.count > 1 {
                    Button("Apply to all") {
                        pause(); let value = setting
                        for index in clips.indices { clips[index].face = value }
                        Haptics.selection()
                    }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WhisperWaveFaceSetting.Kind.available) { kind in
                        WhisperWavePreviewTile(title: kind.title + (kind.accessory == nil ? "" : " · 3D"), image: previews[kind] ?? thumbnail, selected: setting.kind == kind, systemImage: kind.symbol) {
                            pause(); update { $0.select(kind) }; Haptics.selection()
                        }
                    }
                }
            }.contentMargins(.horizontal, 4).frame(height: 84)
            HStack(spacing: 16) {
                WhisperWaveRuler(value: value(\.amount), range: 0...1, defaultValue: setting.kind.defaultAmount, tick: 0.05, detents: [0, 1], pointsPerUnit: 200, label: "Effect amount")
                WhisperWaveRuler(value: value(\.smoothing), range: 0...1, defaultValue: 0, tick: 0.05, detents: [0], pointsPerUnit: 200, label: "Face smoothing")
            }.frame(height: 44)
            Text(notice ?? (setting.uses3D ? "3D accessories follow visible faces in your clip." : "Follows visible faces on this device · best facing the camera"))
                .font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .task(id: thumbnail) { await prepareTiles() }
    }

    private func value(_ key: WritableKeyPath<WhisperWaveFaceSetting, Double>) -> Binding<Double> {
        Binding(get: { setting[keyPath: key] }, set: { value in pause(); update { $0[keyPath: key] = value } })
    }
    private func update(_ change: (inout WhisperWaveFaceSetting) -> Void) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        var next = setting; change(&next); clips[index].face = next
    }
    private func prepareTiles() async {
        previews = [:]; notice = nil
        guard let thumbnail, let cg = thumbnail.cgImage else { return }
        let worker = Task.detached(priority: .utility) { () -> (images: [WhisperWaveFaceSetting.Kind: UIImage], notice: String?) in
            let image = CIImage(cgImage: cg)
            let context = CIContext(options: [.cacheIntermediates: false])
            var result: [WhisperWaveFaceSetting.Kind: UIImage] = [:]
            guard let faces = try? WhisperWaveFaceRenderer.detect(image) else {
                return (result, "Face previews couldn't load. Try playback or another frame.")
            }
            var hadFailure = false
            for kind in WhisperWaveFaceSetting.Kind.available {
                guard !Task.isCancelled else { break }
                autoreleasepool {
                    if faces.isEmpty, let accessory = kind.accessory {
                        if let icon = WhisperARProcessor.shared.accessoryIcon(accessory) { result[kind] = UIImage(cgImage: icon) }
                        else { hadFailure = true }
                    } else if let output = try? WhisperWaveFaceRenderer.render(image, setting: .current(kind), observations: faces, time: 0.6),
                              let frame = context.createCGImage(output, from: image.extent) {
                        result[kind] = UIImage(cgImage: frame)
                    } else { hadFailure = true }
                }
            }
            let message: String? = hadFailure ? "Some previews couldn't load. Try playback or another frame." : (faces.isEmpty ? "No face in this frame. Play a frame with a visible face." : nil)
            return (result, message)
        }
        let rendered = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled else { return }
        previews = rendered.images
        notice = rendered.notice
    }
}
