import SwiftUI
import AVFoundation

/// Select an exact point on the edited timeline, without rendering or downloading its soundtrack.
struct WhisperWaveCoverPicker: View {
    @Environment(\.dismiss) private var dismiss
    let request: WhisperWaveRenderRequest
    let selectedTime: Double
    let onChoose: (Double, UIImage) -> Void
    @State private var model: WhisperWaveCoverModel = WhisperWaveCoverModel()
    @State private var time: Double = 0
    private var duration: Double { WhisperWaveTimeline.duration(request.clips) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                preview
                errorRow
                Text("Slide to choose your cover").font(.subheadline.weight(.semibold))
                WaveCoverScrubber(frames: model.frames, duration: duration, time: $time)
                Text(String(format: "%.2fs / %.2fs", time, duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                confirmButton
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
            .background(.black).navigationTitle("Edit cover").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .task { time = min(selectedTime, max(0, duration - 0.04)); await model.load(request, selectedTime: time) }
            .onChange(of: time) { _, value in model.seek(value) }
            .onDisappear { model.stop() }
        }.preferredColorScheme(.dark).tint(.white)
    }

    private var preview: some View {
        Color.black.overlay {
            if let image = model.image {
                Image(uiImage: image).resizable().scaledToFit().allowsHitTesting(false)
            } else if model.error == nil {
                ProgressView().tint(.white)
            }
        }.clipShape(.rect(cornerRadius: 18))
    }

    @ViewBuilder private var errorRow: some View {
        if let error = model.error {
            Text(error).font(.footnote).foregroundStyle(.secondary)
            Button("Retry") { Task { await model.load(request, selectedTime: time) } }.frame(minHeight: 44)
        }
    }

    private var confirmButton: some View {
        Button {
            guard let image = model.image, let actual = model.imageTime else { return }
            Haptics.success(); onChoose(actual, image)
        } label: {
            Text("Use this cover").font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).frame(height: 50)
                .background(WhisperBrandGradient.diagonal, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.image == nil || model.isSeeking)
        .accessibilityIdentifier("wave.confirmCover")
    }

    static func thumbnail(request: WhisperWaveRenderRequest, time: Double) async -> UIImage? {
        guard let built = await WhisperWaveClipStudio.makeComposition(request.clips, muteOriginal: true, filter: request.filter, adjustments: request.adjustments, effect: request.effect, fx: request.fx, quality: .final, texts: request.texts, captions: request.captions) else { return nil }
        let generator = WhisperWaveCoverModel.generator(asset: built.asset, video: built.video, size: 540)
        guard !Task.isCancelled, let image = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Filmstrip with a finger-following playhead; the whole strip is one drag surface.
private struct WaveCoverScrubber: View {
    let frames: [Int: UIImage]
    let duration: Double
    @Binding var time: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                strip(width: width)
                RoundedRectangle(cornerRadius: 5).fill(.white).frame(width: 5, height: 72)
                    .offset(x: max(0, min(width - 5, width * time / max(0.01, duration))))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let fraction = Double(value.location.x / max(1, width))
                time = max(0, min(duration - 1.0 / 30, fraction * duration))
            })
        }
        .frame(height: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cover frame")
        .accessibilityValue(String(format: "%.1f seconds", time))
        .accessibilityAdjustableAction { direction in
            let step: Double = direction == .increment ? 0.1 : -0.1
            time = min(max(0, time + step), max(0, duration - 0.04))
        }
        .accessibilityIdentifier("wave.coverScrubber")
    }

    private func strip(width: CGFloat) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<10, id: \.self) { index in
                Color.white.opacity(0.08)
                    .frame(width: max(1, (width - 9) / 10), height: 64)
                    .overlay {
                        if let image = frames[index] {
                            Image(uiImage: image).resizable().scaledToFill().allowsHitTesting(false)
                        }
                    }
                    .clipped()
            }
        }.clipShape(.rect(cornerRadius: 12))
    }
}
