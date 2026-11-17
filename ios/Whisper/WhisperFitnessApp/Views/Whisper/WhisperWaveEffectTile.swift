import SwiftUI

struct WhisperWaveEffectTile: View {
    let effect: WhisperWaveCameraEffect
    let image: CGImage?
    var size: CGFloat = 58
    @State private var accessoryImage: CGImage?

    var body: some View {
        Circle().fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                if let icon = accessoryImage {
                    Image(decorative: icon, scale: 1).resizable().scaledToFit().allowsHitTesting(false)
                } else if let image, effect != .none {
                    Image(decorative: image, scale: 1).resizable().scaledToFill().allowsHitTesting(false)
                } else {
                    Image(systemName: effect.symbol).font(.system(size: size * 0.38, weight: .medium)).foregroundStyle(.white)
                }
            }
            .clipShape(.circle)
            .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5) }
            .overlay(alignment: .bottom) {
                if effect.faceKind.accessory != nil {
                    Text("3D").font(.system(size: max(8, size * 0.14), weight: .bold, design: .rounded))
                        .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.8), in: Capsule()).offset(y: 3)
                }
            }
            .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
            .accessibilityHidden(true)
            .task(id: effect) {
                guard let accessory = effect.faceKind.accessory else { accessoryImage = nil; return }
                let icon = await Task.detached(priority: .userInitiated) { WhisperARProcessor.shared.accessoryIcon(accessory) }.value
                guard !Task.isCancelled else { return }
                accessoryImage = icon
            }
    }
}
