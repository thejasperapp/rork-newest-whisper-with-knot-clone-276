import SwiftUI

/// Time-proportional lanes share one clock. Tap clips/layers to edit, drag the ruler to seek, pinch to zoom.
struct WhisperWaveLayerTimeline: View {
    let clips: [WhisperWaveClip]
    let texts: [WaveTextOverlay]
    let music: WhisperStoryMusic?
    let thumbs: [UUID: UIImage]
    let selectedID: UUID?
    let selectedTextID: UUID?
    @Binding var time: Double
    let onClip: (WhisperWaveClip) -> Void
    let onText: (UUID) -> Void
    let onAudio: () -> Void
    let onBackground: (WhisperWaveClip) -> Void
    @State private var zoom: Double = 1
    @State private var initialZoom: Double?
    private var duration: Double { max(0.1, WhisperWaveTimeline.duration(clips)) }
    private var pixels: Double { max(12, 330 / duration) * zoom }
    private var width: Double { duration * pixels }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                ruler
                clipLane
                audioLane
                if !texts.isEmpty { textLanes }
                if clips.contains(where: { $0.background != nil }) { backgroundLane }
            }
            .frame(width: width, alignment: .leading)
            .overlay(alignment: .topLeading) {
                Rectangle().fill(.white).frame(width: 2).offset(x: min(width - 2, max(0, time * pixels)))
                    .allowsHitTesting(false)
            }
            .padding(.vertical, 4)
        }
        .contentMargins(.horizontal, 16)
        .simultaneousGesture(MagnifyGesture().onChanged { value in
            if initialZoom == nil { initialZoom = zoom }
            zoom = min(4, max(0.5, (initialZoom ?? 1) * value.magnification))
        }.onEnded { _ in initialZoom = nil })
        .background(.white.opacity(0.035))
        .accessibilityIdentifier("wave.layerTimeline")
    }

    private var ruler: some View {
        Canvas { context, size in
            let interval = max(1, ceil(60 / pixels))
            for second in stride(from: 0.0, through: duration, by: interval) {
                let x = second * pixels
                var path = Path(); path.move(to: CGPoint(x: x, y: 16)); path.addLine(to: CGPoint(x: x, y: 24))
                context.stroke(path, with: .color(.white.opacity(0.4)), lineWidth: 1)
                context.draw(Text(String(format: "%.0fs", second)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.white.opacity(0.6)), at: CGPoint(x: x + 2, y: 6), anchor: .topLeading)
            }
        }
        .frame(height: 32).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in time = min(duration - 0.02, max(0, value.location.x / pixels)) })
        .accessibilityLabel("Timeline ruler")
        .accessibilityValue(String(format: "%.1f seconds", time))
        .accessibilityAdjustableAction { direction in time = min(duration - 0.02, max(0, time + (direction == .increment ? 0.1 : -0.1))) }
    }

    private var clipLane: some View {
        ZStack(alignment: .leading) {
            ForEach(clips) { clip in
                let start = WhisperWaveTimeline.start(of: clip.id, in: clips)
                let length = max(3, clip.effectiveSeconds * pixels)
                Button { onClip(clip) } label: {
                    Color.white.opacity(0.12)
                        .frame(width: length, height: 44)
                        .overlay { if let image = thumbs[clip.id] { Image(uiImage: image).resizable(resizingMode: .tile).scaledToFill().allowsHitTesting(false) } }
                        .clipShape(.rect(cornerRadius: 5))
                        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(selectedID == clip.id ? WhisperBrandGradient.mint : .white.opacity(0.2), lineWidth: selectedID == clip.id ? 2 : 1) }
                }.buttonStyle(.plain).offset(x: start * pixels)
                    .accessibilityLabel("Select clip, \(Int(clip.effectiveSeconds)) seconds")
            }
        }.frame(width: width, height: 44, alignment: .leading)
    }

    private var audioLane: some View {
        Button(action: onAudio) {
            Label(music?.title ?? "Add audio", systemImage: "music.note")
                .font(.system(size: 10, weight: .semibold)).lineLimit(1)
                .padding(.horizontal, 8).frame(width: width, height: 44, alignment: .leading)
                .background(music == nil ? Color.white.opacity(0.06) : Color.pink.opacity(0.45), in: .rect(cornerRadius: 5))
        }.buttonStyle(.plain).foregroundStyle(.white)
    }

    private var textLanes: some View {
        VStack(spacing: 4) {
            ForEach(texts) { layer in
                let start = min(duration, max(0, layer.start))
                let end = layer.end <= 0 ? duration : min(duration, layer.end)
                HStack(spacing: 0) {
                    Color.clear.frame(width: start * pixels)
                    Button { onText(layer.id) } label: {
                        Text(layer.text.isEmpty ? "Text" : layer.text).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                            .padding(.horizontal, 6).frame(width: max(3, (end - start) * pixels), height: 44, alignment: .leading)
                            .background(Color.orange.opacity(0.45), in: .rect(cornerRadius: 5))
                            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(selectedTextID == layer.id ? .white : .clear, lineWidth: 2) }
                    }.buttonStyle(.plain).foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var backgroundLane: some View {
        ZStack(alignment: .leading) {
            ForEach(clips.filter { $0.background != nil }) { clip in
                Button { onBackground(clip) } label: {
                    Label("Background", systemImage: clip.background?.media == .video ? "video" : "photo")
                        .font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        .padding(.horizontal, 6).frame(width: max(3, clip.effectiveSeconds * pixels), height: 44, alignment: .leading)
                        .background(Color.teal.opacity(0.4), in: .rect(cornerRadius: 5))
                }.buttonStyle(.plain).foregroundStyle(.white).offset(x: WhisperWaveTimeline.start(of: clip.id, in: clips) * pixels)
            }
        }.frame(width: width, height: 44, alignment: .leading)
    }
}
