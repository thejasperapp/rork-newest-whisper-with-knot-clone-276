import SwiftUI

/// The Beats tool: the sound's pulse as a strip of bars with a tick on every
/// beat (taller on downbeats), the clip cuts drawn over it so you can see
/// which cuts land on the beat, a BPM readout, a Snap switch that makes trim
/// handles and text timing magnetic, and two one-tap montage moves — move
/// every cut onto the nearest beat, or split the selected clip on the beats.
struct WhisperWaveBeatPanel: View {
    let grid: WhisperWaveBeatGrid?
    let isAnalyzing: Bool
    let hasMusic: Bool
    let clips: [WhisperWaveClip]
    let selectedID: UUID?
    let time: Double
    @Binding var snap: Bool
    @Binding var every: Int
    let onSeek: (Double) -> Void
    let onSnapCuts: () -> Void
    let onSplitSelected: () -> Void
    let onChooseSound: () -> Void

    private static let steps: [Int] = [1, 2, 4, 8]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let grid, !grid.isEmpty {
                WaveBeatStrip(grid: grid, cuts: cutTimes, time: time, onSeek: onSeek)
                    .frame(height: 56)
                actions
                Text(snap ? "Trim handles and text timing snap to the nearest beat." : "Snap is off — handles move freely.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            } else if isAnalyzing {
                HStack(spacing: 10) {
                    ProgressView().tint(.white).controlSize(.small)
                    Text("Listening for the beat on this iPhone…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(height: 56)
            } else {
                emptyState
            }
        }
        .foregroundStyle(.white)
    }

    private var subtitle: String {
        if let grid, !grid.isEmpty {
            let bpm = "\(Int(grid.bpm.rounded())) BPM"
            return grid.isSteady ? "\(bpm) · from \(grid.sourceLabel)" : "≈\(bpm) · faint pulse in \(grid.sourceLabel)"
        }
        if isAnalyzing { return "Finding the beat…" }
        return hasMusic ? "No steady beat in this sound" : "No sound chosen yet"
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Beats")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            if let grid, !grid.isEmpty {
                WhisperWavePanelChip(title: snap ? "Snap on" : "Snap off", systemImage: "arrow.left.and.line.vertical.and.arrow.right", selected: snap) {
                    snap.toggle()
                }
                .accessibilityLabel(snap ? "Beat snapping on" : "Beat snapping off")
            }
        }
        .frame(height: 40)
    }

    /// Output-clock start of every clip after the first — the cuts.
    private var cutTimes: [Double] {
        clips.dropFirst().map { WhisperWaveTimeline.start(of: $0.id, in: clips) }
    }

    private var actions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                WhisperWavePanelChip(title: "Snap cuts", systemImage: "scissors", selected: false) { onSnapCuts() }
                    .accessibilityHint("Moves every cut onto the nearest beat")
                WhisperWavePanelChip(title: "Split clip", systemImage: "rectangle.split.3x1", selected: false) { onSplitSelected() }
                    .disabled(selectedID == nil)
                    .opacity(selectedID == nil ? 0.5 : 1)
                    .accessibilityHint("Splits the selected clip on the beats")
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, 2)
                Text("Every")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                ForEach(Self.steps, id: \.self) { step in
                    WhisperWavePanelChip(title: step == 1 ? "beat" : "\(step)", selected: every == step) { every = step }
                        .accessibilityLabel(step == 1 ? "Every beat" : "Every \(step) beats")
                }
            }
        }
        .frame(height: 28)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hasMusic
                 ? "This sound has no pulse Whisper can lock onto. Try another, or cut freely."
                 : "Choose a sound and Whisper finds its beat right here on your iPhone — then cuts, trims and text can snap to it. Without a sound it listens to your clips' own audio.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            WhisperWavePanelChip(title: hasMusic ? "Change sound" : "Choose a sound", systemImage: "music.note", selected: !hasMusic) {
                onChooseSound()
            }
        }
    }
}

/// The pulse strip: energy bars behind a tick per beat, the cuts in the brand
/// accent, and the playhead. Drag anywhere to scrub.
private struct WaveBeatStrip: View {
    let grid: WhisperWaveBeatGrid
    let cuts: [Double]
    let time: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            Canvas { context, size in
                let duration = max(0.1, grid.duration)
                context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12), with: .color(.white.opacity(0.06)))
                let bars = grid.envelope
                if !bars.isEmpty {
                    let barWidth = size.width / CGFloat(bars.count)
                    for (index, value) in bars.enumerated() {
                        let height = max(2, CGFloat(value) * (size.height - 14))
                        let rect = CGRect(x: CGFloat(index) * barWidth + 0.5, y: (size.height - height) / 2, width: max(0.5, barWidth - 1), height: height)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.white.opacity(0.22)))
                    }
                }
                for beat in grid.beats where beat.time >= 0 && beat.time <= duration {
                    let x = CGFloat(beat.time / duration) * size.width
                    let tall = beat.isDownbeat
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: tall ? 4 : size.height * 0.28))
                    path.addLine(to: CGPoint(x: x, y: tall ? size.height - 4 : size.height * 0.72))
                    context.stroke(path, with: .color(.white.opacity(tall ? 0.9 : 0.5)), lineWidth: tall ? 1.5 : 1)
                }
                for cut in cuts where cut > 0 && cut < duration {
                    let x = CGFloat(cut / duration) * size.width
                    let onBeat = grid.nearest(to: cut, within: 0.06) != nil
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(onBeat ? WhisperBrandGradient.amber : WhisperBrandGradient.rose), lineWidth: 2)
                    var marker = Path()
                    marker.move(to: CGPoint(x: x - 4, y: 0))
                    marker.addLine(to: CGPoint(x: x + 4, y: 0))
                    marker.addLine(to: CGPoint(x: x, y: 5))
                    marker.closeSubpath()
                    context.fill(marker, with: .color(onBeat ? WhisperBrandGradient.amber : WhisperBrandGradient.rose))
                }
                let head = CGFloat(min(max(0, time), duration) / duration) * size.width
                let playhead = Path(roundedRect: CGRect(x: head - 1, y: 2, width: 2, height: size.height - 4), cornerRadius: 1)
                context.fill(playhead, with: .color(.white))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeek(Double(min(max(0, value.location.x), width) / width) * grid.duration)
                    }
                    .onEnded { _ in Haptics.selection() }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Beat strip, \(grid.beats.count) beats")
        .accessibilityValue("\(Int(grid.bpm.rounded())) beats per minute")
    }
}
