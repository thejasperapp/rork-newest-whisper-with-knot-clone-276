import SwiftUI

/// The Audio tool: choose a sound, dial where the song starts, balance it
/// against the original audio, and keep or drop the original sound.
struct WhisperWaveMusicControls: View {
    @Binding var music: WhisperStoryMusic?
    @Binding var volume: Double
    @Binding var muted: Bool
    let duration: Double
    let onChoose: () -> Void
    let onRestart: () -> Void

    private var available: Double { max(0.1, duration - 0.1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if music != nil {
                startDial
                mixRow
            } else {
                emptyState
            }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Audio")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(music?.title ?? "No sound added")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            WhisperWavePanelChip(title: music == nil ? "Choose a sound" : "Change", systemImage: "music.note", selected: music == nil) {
                onChoose()
            }
            if music != nil {
                WhisperWavePanelIconButton(systemImage: "xmark", label: "Remove sound") { music = nil }
            }
        }
        .frame(height: 40)
    }

    private var startDial: some View {
        WhisperWaveRuler(
            value: Binding(get: { min(music?.startSeconds ?? 0, available) }, set: { music?.startSeconds = $0 }),
            range: 0...available,
            defaultValue: 0,
            tick: 0.25,
            detents: stride(from: 0, through: available, by: 5).map { $0 },
            pointsPerUnit: 40,
            label: "Song starts at",
            format: { "\(WhisperWaveClipsEditor.clock($0)) of \(WhisperWaveClipsEditor.clock(duration))" },
            onEditingChanged: { editing in if !editing { onRestart() } }
        )
        .frame(height: 44)
        .disabled(duration <= 0.1)
        .opacity(duration <= 0.1 ? 0.4 : 1)
    }

    private var mixRow: some View {
        HStack(spacing: 14) {
            WhisperWaveRuler(value: $volume, range: 0...1, defaultValue: 0.85, tick: 0.05, detents: [0.5, 1], pointsPerUnit: 200, label: "Music volume")
                .frame(height: 44)
            WhisperWavePanelChip(title: muted ? "Original off" : "Original on", systemImage: muted ? "speaker.slash" : "speaker.wave.2", selected: !muted) {
                muted.toggle()
            }
            .accessibilityLabel(muted ? "Original video sound off" : "Original video sound on")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a sound from the library, then dial where it starts. Your video's own audio stays unless you switch it off.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
            WhisperWavePanelChip(title: muted ? "Original sound off" : "Original sound on", systemImage: muted ? "speaker.slash" : "speaker.wave.2", selected: !muted) {
                muted.toggle()
            }
        }
    }
}
