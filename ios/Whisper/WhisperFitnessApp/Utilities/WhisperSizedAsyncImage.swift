import SwiftUI

/// For an already-sized card/overlay, decode a bucketed display variant rather
/// than the camera original. Full-screen zoom viewers keep their original loader.
struct WhisperSizedAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content
    @Environment(\.displayScale) private var displayScale

    nonisolated static func pixelSize(size: CGSize, scale: CGFloat) -> CGSize {
        func bucket(_ value: CGFloat) -> CGFloat {
            let pixels = value * max(1, scale)
            guard pixels.isFinite else { return 1536 }
            return min(3072, max(128, ceil(pixels / 128) * 128))
        }
        return CGSize(width: bucket(size.width), height: bucket(size.height))
    }

    var body: some View {
        GeometryReader { geometry in
            WhisperCachedAsyncImage(
                url: geometry.size.width > 0 && geometry.size.height > 0 ? url : nil,
                fillPixelSize: Self.pixelSize(size: geometry.size, scale: displayScale),
                content: content
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
