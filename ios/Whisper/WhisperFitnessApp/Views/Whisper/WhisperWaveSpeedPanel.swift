import SwiftUI

/// The Speed tool: preset chips for the classic stops and a ruler for anything
/// in between, 0.25× to 3×. Pitch follows speed, as on the camera.
struct WhisperWaveSpeedPanel: View {
    let clip: WhisperWaveClip
    let onChange: (Double) -> Void
    /// The ruler's in-progress value; committed to the clip when the finger
    /// lifts, so the composition rebuilds once instead of on every tick.
    @State private var draft: Double?

    static let presets: [Double] = [0.5, 1, 1.5, 2, 3]

    private var shown: Double { draft ?? clip.speed }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            presetRow
            WhisperWaveRuler(
                value: Binding(get: { shown }, set: { draft = $0 }),
                range: 0.25...3,
                defaultValue: 1,
                tick: 0.05,
                detents: Self.presets,
                pointsPerUnit: 240,
                label: "Fine speed",
                format: { WhisperWaveClipsEditor.speedLabel($0) },
                onEditingChanged: { editing in
                    guard !editing, let value = draft else { return }
                    draft = nil
                    if abs(value - clip.speed) > 0.001 { onChange(value) }
                }
            )
            .onChange(of: draft) { _, value in
                // A double-tap reset lands outside a drag: commit it directly.
                if let value, value == 1, abs(clip.speed - 1) > 0.001 { draft = nil; onChange(1) }
            }
            Text("Double-tap the ruler for 1× · slower clips keep every frame")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var header: some View {
        HStack {
            Text("Speed")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text("\(WhisperWaveClipsEditor.clock(clip.keptSeconds)) → \(WhisperWaveClipsEditor.clock(clip.keptSeconds / max(0.1, shown)))")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .contentTransition(.numericText())
        }
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(Self.presets, id: \.self) { speed in
                let on = abs(shown - speed) < 0.01
                Button {
                    Haptics.rigid()
                    draft = nil
                    onChange(speed)
                } label: {
                    Text(WhisperWaveClipsEditor.speedLabel(speed))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(on ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                }
                .buttonStyle(WhisperMenuPressStyle())
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }
}
