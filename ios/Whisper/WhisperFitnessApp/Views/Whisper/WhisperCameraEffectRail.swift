import SwiftUI

/// The same unrestricted centered dial in Stories and Waves. The shutter has its
/// own row, so a horizontal flick never arms recording or vanishes underneath a finger.
struct WhisperCameraEffectRail: View {
    @Binding var selected: WhisperWaveCameraEffect
    let thumbnails: WhisperWaveEffectThumbnails
    var effects: [WhisperWaveCameraEffect] = WhisperWaveCameraEffect.available
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var centeredID: String?
    @State private var selectionTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(effects) { effect in
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { centeredID = effect.id }
                        } label: {
                            VStack(spacing: 4) {
                                WhisperWaveEffectTile(effect: effect, image: thumbnails.images[effect.id], size: 52)
                                    .overlay { Circle().strokeBorder(.white, lineWidth: selected == effect ? 3 : 0) }
                                Text(effect.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                    .foregroundStyle(.white.opacity(selected == effect ? 1 : 0.65))
                            }.frame(width: 68, height: 78)
                        }
                        .buttonStyle(.plain).id(effect.id)
                        .accessibilityLabel(effect.name)
                        .accessibilityAddTraits(selected == effect ? .isSelected : [])
                    }
                }.scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, (geometry.size.width - 68) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .scrollPosition(id: $centeredID, anchor: .center)
            .onChange(of: centeredID) { _, id in
                guard let id, let effect = WhisperWaveCameraEffect(rawValue: id), effect != selected else { return }
                selectionTask?.cancel()
                selectionTask = Task { @MainActor in
                    do { try await Task.sleep(for: .milliseconds(65)) } catch { return }
                    guard centeredID == effect.id else { return }
                    selected = effect
                    Haptics.selection()
                }
            }
            .onChange(of: selected) { _, effect in
                guard centeredID != effect.id else { return }
                centeredID = effect.id
            }
            .onAppear { centeredID = selected.id }
            .onDisappear { selectionTask?.cancel() }
        }.frame(height: 80)
        .accessibilityIdentifier("camera.effects.rail")
    }
}
