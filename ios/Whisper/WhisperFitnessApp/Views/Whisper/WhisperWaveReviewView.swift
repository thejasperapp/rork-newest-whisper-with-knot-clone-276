import SwiftUI

/// Full edited playback, including animated text, without an intermediate MP4 export.
struct WhisperWaveReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let request: WhisperWaveRenderRequest
    @State private var model: WhisperWavePreviewModel = WhisperWavePreviewModel()
    private var duration: Double { WhisperWaveTimeline.duration(request.clips) }
    var body: some View {
        VStack(spacing: 12) {
            HStack { Button("Close") { dismiss() }.frame(minHeight: 44); Spacer(); Text("Preview").font(.headline); Spacer(); Text("9:16").font(.caption) }
            WaveTimelinePlayerView(player: model.player).aspectRatio(9 / 16, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 18)).frame(maxHeight: .infinity)
            if model.isPreparing { ProgressView("Preparing preview").tint(.white) }
            if let error = model.error { Text(error).font(.footnote); Button("Retry") { prepare() }.frame(minHeight: 44) }
            HStack {
                Button { model.togglePlayback() } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                Slider(value: Binding(get: { model.time }, set: { model.pause(); model.seek($0) }), in: 0...max(0.1, duration))
                    .accessibilityLabel("Preview playhead")
                Text(String(format: "%.1fs", model.time)).font(.caption.monospacedDigit())
            }
        }.padding(.horizontal, 16).padding(.bottom, 16).background(.black).foregroundStyle(.white).tint(.white)
            .preferredColorScheme(.dark)
            .task { model.activate(); prepare() }.onDisappear { model.stop() }
    }
    private func prepare() {
        model.rebuild(clips: request.clips, music: request.music, volume: request.volume, muted: request.muted, filter: request.filter, adjustments: request.adjustments, effect: request.effect, fx: request.fx, texts: request.texts, captions: request.captions)
    }
}
