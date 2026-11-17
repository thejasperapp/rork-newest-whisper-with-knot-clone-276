import SwiftUI

struct WhisperStoryStarterPreview: View {
    let starter: WhisperStoryStarter
    var showsBackground: Bool = true
    var photo: UIImage? = nil
    @State private var layers: [WhisperStorySticker] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if showsBackground {
                    Color(hex: starter.backgroundHex)
                    if let photo {
                        Color.clear.overlay { Image(uiImage: photo).resizable().scaledToFill().allowsHitTesting(false) }.clipped()
                        Color.black.opacity(0.3)
                    } else {
                        Rectangle().fill(.white.opacity(0.06)).frame(width: geo.size.width * 0.46).rotationEffect(.degrees(-18)).offset(x: geo.size.width * 0.24)
                    }
                }
                ZStack {
                    ForEach(layers) { sticker in
                        WhisperStoryStickerView(sticker: sticker, stageWidth: 390)
                            .scaleEffect(sticker.scale)
                            .rotationEffect(.radians(sticker.rotation))
                            .position(x: sticker.x * 390, y: sticker.y * 390 * 16 / 9)
                    }
                }.frame(width: 390, height: 390 * 16 / 9)
                    .scaleEffect(geo.size.width / 390)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
        .onAppear { if layers.isEmpty { layers = starter.stickers() } }
        .onChange(of: starter) { _, value in layers = value.stickers() }
    }
}
