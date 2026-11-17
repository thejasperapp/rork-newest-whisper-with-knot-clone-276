import SwiftUI

/// The visual rail follows the finger independently of the expensive camera recipe.
struct WhisperStoryCaptureRail<Shutter: View>: View {
    @Binding var selected: WhisperWaveCameraEffect
    let thumbnails: WhisperWaveEffectThumbnails
    let effects: [WhisperWaveCameraEffect]
    let expanded: Bool
    let locked: Bool
    let onScrub: () -> Void
    @ViewBuilder let shutter: () -> Shutter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragging: Bool = false
    @State private var position: CGFloat = 0
    @State private var origin: CGFloat? = nil
    @State private var selectionTask: Task<Void, Never>?
    private let pitch: CGFloat = 76
    private var selectedIndex: Int { effects.firstIndex(of: selected) ?? 0 }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if expanded {
                    ForEach(Array(effects.enumerated()), id: \.element.id) { index, effect in
                        let displacement = (CGFloat(index) - position) * pitch
                        if abs(displacement) < geometry.size.width / 2 + pitch * 2 {
                            Button { settle(index) } label: {
                                WhisperWaveEffectTile(effect: effect, image: thumbnails.images[effect.id], size: 46)
                                    .frame(width: 56, height: 64).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .opacity(min(1, max(0, (abs(displacement) - 24) / 24)))
                            .scaleEffect(1 + 0.10 * max(0, 1 - abs(displacement) / pitch))
                            .allowsHitTesting(!locked && abs(displacement) > 40)
                            .position(x: geometry.size.width / 2 + displacement, y: geometry.size.height / 2)
                            .accessibilityLabel("Select \(effect.name) effect")
                            .accessibilityHidden(locked || abs(displacement) > geometry.size.width / 2 || abs(displacement) < 40)
                        }
                    }
                }
                shutter().position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped().contentShape(.rect)
            .simultaneousGesture(DragGesture(minimumDistance: 12)
                .updating($dragging) { _, state, _ in state = true }
                .onChanged { value in
                    guard expanded, !locked, abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                    if origin == nil { origin = position; onScrub() }
                    guard let origin else { return }
                    let raw = origin - value.translation.width / pitch
                    let edge = min(CGFloat(max(0, effects.count - 1)), max(0, raw))
                    position = edge + (raw - edge) * 0.18
                    let next = bounded(Int(position.rounded()))
                    guard effects.indices.contains(next), effects[next] != selected else { selectionTask?.cancel(); return }
                    selectionTask?.cancel()
                    selectionTask = Task {
                        do { try await Task.sleep(for: .milliseconds(65)) } catch { return }
                        guard !Task.isCancelled, !locked else { return }
                        selected = effects[next]
                    }
                }
                .onEnded { value in
                    guard let origin else { return }
                    let projected = value.translation.width + (value.predictedEndTranslation.width - value.translation.width) * 0.20
                    settle(bounded(Int((origin - projected / pitch).rounded())))
                })
            .onChange(of: dragging) { _, active in
                if !active, origin != nil { cancelTravel() }
            }
            .onChange(of: selected) { _, _ in
                guard origin == nil else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) { position = CGFloat(selectedIndex) }
            }
            .onChange(of: locked) { _, locked in if locked { cancelTravel() } }
            .onChange(of: expanded) { _, expanded in if !expanded { cancelTravel() } }
            .onChange(of: geometry.size) { _, _ in cancelTravel() }
            .onAppear { position = CGFloat(selectedIndex) }
            .onDisappear { selectionTask?.cancel(); origin = nil }
        }.frame(height: 120)
    }
    private func bounded(_ value: Int) -> Int { min(max(0, value), max(0, effects.count - 1)) }
    private func settle(_ index: Int) {
        selectionTask?.cancel()
        guard !locked, effects.indices.contains(index) else { cancelTravel(); return }
        origin = nil
        if selected != effects[index] { selected = effects[index]; Haptics.selection() }
        withAnimation(reduceMotion ? nil : .interpolatingSpring(stiffness: 300, damping: 32)) { position = CGFloat(index) }
    }
    private func cancelTravel() {
        selectionTask?.cancel(); origin = nil
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { position = CGFloat(selectedIndex) }
    }
}
