import SwiftUI

/// Mode travel is isolated from the shutter/effects rail. The owner admits every transition.
struct WhisperCaptureModeStrip: View {
    let selected: WhisperCaptureMode
    var disabled: Bool = false
    let onSelect: (WhisperCaptureMode) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var travel: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let pitch = min(90.0, geometry.size.width / 3)
            let index = WhisperCaptureMode.allCases.firstIndex(of: selected) ?? 0
            ZStack {
                ForEach(Array(WhisperCaptureMode.allCases.enumerated()), id: \.element.id) { offset, mode in
                    Button { choose(mode) } label: {
                        Text(mode.rawValue.uppercased()).font(.system(size: 12, weight: .bold))
                            .tracking(0.7).foregroundStyle(.white.opacity(selected == mode ? 1 : 0.48))
                            .frame(width: pitch, height: 44)
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(selected == mode ? .isSelected : [])
                    .position(x: geometry.size.width / 2 + CGFloat(offset - index) * pitch + travel * 0.35, y: 22)
                }
            }
            .frame(width: geometry.size.width, height: 44).clipped().contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 15)
                .updating($travel) { value, state, _ in
                    guard !disabled, abs(value.translation.width) > abs(value.translation.height) else { return }
                    state = value.translation.width
                }
                .onEnded { value in
                    guard !disabled, abs(value.translation.width) > 24, abs(value.translation.width) > abs(value.translation.height) * 1.3 else { return }
                    let next = min(WhisperCaptureMode.allCases.count - 1, max(0, index + (value.translation.width < 0 ? 1 : -1)))
                    choose(WhisperCaptureMode.allCases[next])
                })
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Capture mode")
        }
        .frame(height: 44).disabled(disabled)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: selected)
    }
    private func choose(_ mode: WhisperCaptureMode) {
        guard !disabled, mode != selected else { return }
        Haptics.selection()
        onSelect(mode)
    }
}
