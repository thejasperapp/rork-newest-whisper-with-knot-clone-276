import SwiftUI

/// A drawable first frame while a staged Wave remains paused or buffers.
struct WhisperWavePosterView: View {
    let videoURL: URL
    let coverURL: URL?
    @State private var poster: UIImage? = nil

    var body: some View {
        Color.black
            .overlay {
                if let poster {
                    Image(uiImage: poster).resizable().aspectRatio(contentMode: .fill).allowsHitTesting(false)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .task(id: videoURL) {
                let generation = AccountStorage.generation
                var loaded: UIImage? = nil
                if let coverURL { loaded = await WhisperWavePosterCache.shared.poster(for: coverURL) }
                if loaded == nil { loaded = await WhisperWavePosterCache.shared.poster(for: videoURL) }
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                poster = loaded
            }
    }
}
