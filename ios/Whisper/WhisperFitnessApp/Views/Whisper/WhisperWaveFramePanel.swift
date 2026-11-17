import SwiftUI

/// The Frame tool: fit or fill the 9:16 canvas, dial the zoom, and reset.
/// The footage itself is pinched and dragged directly on the canvas.
struct WhisperWaveFramePanel: View {
    let clip: WhisperWaveClip
    let onChange: ((inout WhisperWaveClip) -> Void) -> Void
    /// In-progress zoom from the ruler, committed when the finger lifts.
    @State private var draftZoom: Double?

    private var isDefault: Bool { !clip.fillsFrame && clip.zoom == 1 && clip.offsetX == 0 && clip.offsetY == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 8) {
                WhisperWavePanelChip(title: "Fit", systemImage: "arrow.down.right.and.arrow.up.left", selected: !clip.fillsFrame) {
                    onChange { $0.fillsFrame = false; $0.zoom = 1; $0.offsetX = 0; $0.offsetY = 0 }
                }
                WhisperWavePanelChip(title: "Fill", systemImage: "arrow.up.left.and.arrow.down.right", selected: clip.fillsFrame) {
                    onChange { $0.fillsFrame = true; $0.zoom = 1; $0.offsetX = 0; $0.offsetY = 0 }
                }
                Spacer()
            }
            WhisperWaveRuler(
                value: Binding(get: { draftZoom ?? clip.zoom }, set: { draftZoom = $0 }),
                range: 1...4,
                defaultValue: 1,
                tick: 0.05,
                detents: [1, 2, 3, 4],
                pointsPerUnit: 200,
                label: "Zoom",
                format: { String(format: "%.2f×", $0) },
                onEditingChanged: { editing in
                    guard !editing, let zoom = draftZoom else { return }
                    draftZoom = nil
                    if abs(zoom - clip.zoom) > 0.001 { onChange { $0.zoom = zoom } }
                }
            )
            .onChange(of: draftZoom) { _, value in
                if let value, value == 1, abs(clip.zoom - 1) > 0.001 { draftZoom = nil; onChange { $0.zoom = 1 } }
            }
            Text("Pinch and drag the video to reframe it")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var header: some View {
        HStack {
            Text("Frame")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            if !isDefault {
                WhisperWavePanelIconButton(systemImage: "arrow.counterclockwise", label: "Reset framing") {
                    onChange { $0.fillsFrame = false; $0.zoom = 1; $0.offsetX = 0; $0.offsetY = 0 }
                }
            }
        }
        .frame(height: 40)
    }
}
