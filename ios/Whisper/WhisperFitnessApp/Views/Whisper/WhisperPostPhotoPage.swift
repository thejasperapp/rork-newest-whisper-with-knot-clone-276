import SwiftUI
import UIKit

/// One native zoom surface per photo; carousel and dismissal only own fit-size drags.
struct WhisperPostPhotoPage: View {
    let url: URL
    let isActive: Bool
    let onZoomChanged: (Bool) -> Void
    let onDismiss: () -> Void
    var onSingleTap: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var loadedURL: URL?
    @State private var failed = false
    @State private var retryID = UUID()

    var body: some View {
        GeometryReader { geometry in
            Group {
                if WhisperVideo.isVideo(url) {
                    WhisperVideoView(url: url, autoplay: isActive, showsControls: true)
                        .environment(\.whisperMediaActive, isActive)
                } else if let image, loadedURL == url {
                    WhisperPhotoZoomSurface(image: image, isActive: isActive,
                                            reduceMotion: reduceMotion,
                                            onZoomChanged: onZoomChanged, onSingleTap: onSingleTap)
                } else if failed {
                    VStack(spacing: 14) {
                        ContentUnavailableView("Photo unavailable", systemImage: "photo",
                                               description: Text("Check your connection and try again."))
                        Button("Try again") { retryID = UUID() }.buttonStyle(.bordered)
                    }
                } else {
                    WhisperPhotoLoader()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: "\(url.absoluteString)|\(retryID)|\(isActive)") {
            guard !WhisperVideo.isVideo(url) else { return }
            guard isActive else { image = nil; loadedURL = nil; failed = false; return }
            let generation = AccountStorage.generation
            failed = false
            let result = await WhisperImageCache.load(url, maxPixelSize: 4096)
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            image = result; loadedURL = url; failed = result == nil
        }
    }
}
