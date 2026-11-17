import SwiftUI
import CoreImage

/// The Effects tool: six families on chips, live-rendered tiles of the
/// footage wearing each effect, a strength dial, a speed dial for the
/// animated ones, and a whole-wave / this-clip switch. Everything renders on
/// the video above the moment it is tapped.
struct WhisperWaveFXControls: View {
    @Binding var fx: WhisperWaveFXSetting?
    let thumbnail: UIImage?
    let clips: [WhisperWaveClip]
    let selectedClipID: UUID?
    @State private var category: WhisperWaveFXCategory
    @State private var previews: [WhisperWaveFX: UIImage] = [:]
    @State private var previewSource: UIImage?
    @State private var renderToken: UUID = UUID()

    init(fx: Binding<WhisperWaveFXSetting?>, thumbnail: UIImage?, clips: [WhisperWaveClip], selectedClipID: UUID?) {
        self._fx = fx
        self.thumbnail = thumbnail
        self.clips = clips
        self.selectedClipID = selectedClipID
        self._category = State(initialValue: fx.wrappedValue?.kind.category ?? .camera)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            familyRow
            tileStrip
            dials
        }
        .foregroundStyle(.white)
        .task(id: TileKey(category: category, thumbnail: thumbnail)) { await renderPreviews() }
    }

    // MARK: Families

    private var familyRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(WhisperWaveFXCategory.allCases) { family in
                        WhisperWavePanelChip(title: family.title, systemImage: family == .ai ? "sparkle" : nil, selected: category == family) {
                            category = family
                        }
                    }
                }
            }
            if fx != nil, clips.count > 1 {
                rangeChip
            }
        }
        .frame(height: 28)
    }

    /// Whole wave ↔ the selected clip. Shown only when there is a choice.
    private var rangeChip: some View {
        let scoped = fx?.clipID
        let index = scoped.flatMap { id in clips.firstIndex { $0.id == id } }
        let title: String = scoped == nil ? "Whole wave" : (scoped == selectedClipID ? "This clip" : "Clip \((index ?? 0) + 1)")
        return WhisperWavePanelChip(title: title, systemImage: scoped == nil ? "rectangle.stack" : "rectangle", selected: scoped != nil) {
            guard var current = fx else { return }
            if current.clipID == nil || current.clipID != selectedClipID {
                current.clipID = selectedClipID
            } else {
                current.clipID = nil
            }
            fx = current
        }
        .accessibilityLabel("Effect range: \(title)")
    }

    // MARK: Tiles

    private var tileStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                WhisperWavePreviewTile(title: "None", image: thumbnail, selected: fx == nil, systemImage: "circle.slash") {
                    fx = nil
                }
                ForEach(category.effects) { kind in
                    WhisperWavePreviewTile(title: kind.name, image: previews[kind] ?? thumbnail, selected: fx?.kind == kind, systemImage: kind.systemImage) {
                        choose(kind)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 84)
    }

    private func choose(_ kind: WhisperWaveFX) {
        if let current = fx, current.kind == kind { return }
        fx = WhisperWaveFXSetting(kind: kind, intensity: fx?.intensity ?? 0.7, speed: fx?.speed ?? 1, clipID: fx?.clipID)
    }

    // MARK: Dials

    @ViewBuilder private var dials: some View {
        if let current = fx {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 14) {
                    if current.kind.usesIntensity {
                        WhisperWaveRuler(
                            value: Binding(get: { fx?.intensity ?? 0.7 }, set: { v in fx?.intensity = v }),
                            range: 0...1, defaultValue: 0.7, tick: 0.05, detents: [0.5, 1], pointsPerUnit: 200,
                            label: current.kind.intensityLabel
                        )
                    }
                    if current.kind.isAnimated {
                        WhisperWaveRuler(
                            value: Binding(get: { fx?.speed ?? 1 }, set: { v in fx?.speed = v }),
                            range: 0.5...2, defaultValue: 1, tick: 0.05, detents: [1], pointsPerUnit: 160,
                            label: "Speed", format: { String(format: "%.2f×", $0) }
                        )
                    }
                    if !current.kind.usesIntensity, !current.kind.isAnimated {
                        hint("\(current.kind.name) has no dials · it renders live on the video above")
                    }
                }
                .frame(height: 44)
                if current.kind.flashes {
                    Label("Contains flashing light", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WhisperBrandGradient.amber)
                } else if current.kind.usesPersonSegmentation {
                    Label("Reads the person in frame on this device · nothing is uploaded", systemImage: "lock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        } else {
            hint("Pick an effect · it renders live on the video above")
                .frame(height: 44)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Previews

    private struct TileKey: Equatable {
        let category: WhisperWaveFXCategory
        let thumbnail: UIImage?
    }

    private func renderPreviews() async {
        guard let thumbnail else { return }
        // A different clip's frame invalidates every tile.
        if previewSource !== thumbnail {
            previews = [:]
            previewSource = thumbnail
        }
        let kinds = category.effects.filter { previews[$0] == nil }
        guard !kinds.isEmpty else { return }
        let token = UUID()
        renderToken = token
        let worker = Task.detached(priority: .utility) { () -> [WhisperWaveFX: UIImage] in
            guard let cg = thumbnail.cgImage else { return [:] }
            let context = CIContext(options: [.cacheIntermediates: false])
            var source = CIImage(cgImage: cg)
            let scale = min(1, 200 / max(1, source.extent.width))
            if scale < 1 { source = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
            let extent = source.extent
            var result: [WhisperWaveFX: UIImage] = [:]
            for kind in kinds {
                if Task.isCancelled { break }
                let setting = WhisperWaveFXSetting(kind: kind, intensity: 0.8, speed: 1)
                let output = WhisperWaveFXRenderer.shared.render(source, fx: setting, time: WhisperWaveFXRenderer.shared.previewTime(for: kind), quality: .preview)
                if let image = context.createCGImage(output, from: extent) {
                    result[kind] = UIImage(cgImage: image)
                }
            }
            return result
        }
        let images = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard token == renderToken, !Task.isCancelled else { return }
        previews.merge(images) { _, new in new }
    }
}
