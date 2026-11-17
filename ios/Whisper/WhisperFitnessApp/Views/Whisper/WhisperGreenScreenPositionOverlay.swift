import SwiftUI

/// Direct manipulation in normalized output coordinates, shared with the export renderer.
struct WhisperGreenScreenPositionOverlay: View {
    @Binding var background: WhisperWaveBackground?
    @State private var moveOrigin: CGPoint?
    @State private var scaleOrigin: Double?
    @GestureState private var touching: Bool = false

    var body: some View {
        GeometryReader { geometry in
            Color.clear.contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 5)
                    .updating($touching) { _, active, _ in active = true }
                    .onChanged { value in
                        guard var next = background else { return }
                        if moveOrigin == nil { moveOrigin = CGPoint(x: next.subjectX, y: next.subjectY) }
                        guard let origin = moveOrigin else { return }
                        next.subjectX = min(0.7, max(-0.7, origin.x + value.translation.width / max(1, geometry.size.width)))
                        next.subjectY = min(0.7, max(-0.7, origin.y + value.translation.height / max(1, geometry.size.height)))
                        background = next
                    }.onEnded { _ in moveOrigin = nil })
                .simultaneousGesture(MagnifyGesture()
                    .updating($touching) { _, active, _ in active = true }
                    .onChanged { value in
                        guard var next = background else { return }
                        if scaleOrigin == nil { scaleOrigin = next.subjectScale }
                        next.subjectScale = min(1.5, max(0.25, (scaleOrigin ?? 1) * value.magnification))
                        background = next
                    }.onEnded { _ in scaleOrigin = nil })
                .onChange(of: touching) { _, active in if !active { moveOrigin = nil; scaleOrigin = nil } }
                .onChange(of: background?.url) { _, _ in moveOrigin = nil; scaleOrigin = nil }
                .accessibilityLabel("Position person")
                .accessibilityHint("Drag to move or pinch to resize. More adjustments are available beside the background picker.")
                .accessibilityAction(named: "Center person") {
                    background?.subjectX = 0; background?.subjectY = 0; background?.subjectScale = 1
                }
        }
    }
}
