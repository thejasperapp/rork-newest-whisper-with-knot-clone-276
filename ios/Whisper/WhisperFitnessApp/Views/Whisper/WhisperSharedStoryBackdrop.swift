import SwiftUI
import UIKit

/// One background layer for editor preview and export; never includes the post sticker.
struct WhisperSharedStoryBackdrop: View {
    let original: UIImage
    let selection: WhisperStoryBackgroundSelection
    let photo: UIImage?
    let size: CGSize

    var body: some View {
        Color.black
            .frame(width: size.width, height: size.height)
            .overlay {
                switch selection {
                case .color(let hex):
                    (whisperColorFromHex(hex) ?? .black)
                case .blurred, .photo:
                    Image(uiImage: selection == .photo ? (photo ?? original) : original)
                        .resizable().aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .allowsHitTesting(false)
    }
}
