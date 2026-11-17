import SwiftUI

struct WhisperWaveEffectCarousel<Shutter: View>: View {
    @Binding var selected: WhisperWaveCameraEffect
    let thumbnails: WhisperWaveEffectThumbnails
    let showsEffects: Bool
    let isRecording: Bool
    @ViewBuilder let shutter: () -> Shutter

    var body: some View {
        VStack(spacing: 6) {
            if showsEffects && !isRecording {
                WhisperCameraEffectRail(selected: $selected, thumbnails: thumbnails)
            }
            shutter().frame(height: 116)
        }
    }
}
