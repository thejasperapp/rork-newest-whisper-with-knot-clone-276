import SwiftUI
import UIKit

/// Uses the existing wave typography renderer for both preview and delivered media.
enum WhisperFlickCanvas {
    static func overlay(_ text: WaveTextOverlay, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let root = CALayer()
            root.frame = CGRect(origin: .zero, size: size)
            root.addSublayer(WhisperWaveStudio.textLayerGroup(text, renderSize: size))
            root.render(in: context.cgContext)
        }
    }

    static func photoData(_ source: UIImage, text: WaveTextOverlay) async -> Data? {
        let scale = min(1, 1440 / max(1, source.size.width), 2560 / max(1, source.size.height))
        let size = CGSize(width: max(1, source.size.width * scale), height: max(1, source.size.height * scale))
        // The shared typography layer is main-actor-owned; bitmap drawing and
        // JPEG compression run on the serial preparation actor, not the UI.
        let caption = text.text.isEmpty ? nil : overlay(text, size: size)
        return await WhisperFlickPreparation.shared.photo(source, caption: caption, size: size)
    }
}

struct WhisperFlickTextPreview: View, Equatable {
    let text: WaveTextOverlay
    let aspect: CGFloat
    private var centered: WaveTextOverlay {
        var value = text
        value.y = 0.5
        return value
    }
    var body: some View {
        if !text.text.isEmpty {
            GeometryReader { proxy in
                WhisperFlickCaptionArtwork(text: centered, aspect: aspect).equatable()
                    .offset(y: proxy.size.height * (text.y - 0.5))
            }.allowsHitTesting(false)
        }
    }
}

/// Moving the caption repositions the existing bitmap instead of re-rasterizing
/// its typography on every drag update or unrelated composer state change.
private struct WhisperFlickCaptionArtwork: View, Equatable {
    let text: WaveTextOverlay
    let aspect: CGFloat
    var body: some View {
        let width = min(780, 1560 * max(0.1, aspect))
        Image(uiImage: WhisperFlickCanvas.overlay(text, size: CGSize(width: width, height: width / max(0.1, aspect))))
            .resizable().scaledToFit()
    }
}

actor WhisperFlickPreparation {
    static let shared = WhisperFlickPreparation()

    func photo(_ source: UIImage, caption: UIImage?, size: CGSize) -> Data? {
        autoreleasepool {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1; format.opaque = true
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                source.draw(in: CGRect(origin: .zero, size: size))
                caption?.draw(in: CGRect(origin: .zero, size: size))
            }.jpegData(compressionQuality: 0.8)
        }
    }

    func fileData(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 12_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        return try Data(contentsOf: url)
    }

    func base64(_ data: Data) -> String { data.base64EncodedString() }
}

/// Shared story chrome; tapping a ring opens the same story flow used by feed avatars.
struct WhisperFlickAvatar: View {
    let username: String
    var size: CGFloat = 46
    var imageURL: URL? = nil
    var opensStories = true
    @State private var stories = WhisperStoryService.shared
    @State private var showingStories = false
    private var groupIndex: Int? {
        stories.storiesByUser().firstIndex { $0.username.lowercased() == username.lowercased() }
    }
    private var unseen: Bool {
        guard let groupIndex else { return false }
        return stories.hasUnseenStories(userID: stories.storiesByUser()[groupIndex].userID)
    }
    private var portrait: some View {
        WhisperAvatarChrome(username: username, size: size, imageURL: imageURL,
                            storyRing: groupIndex != nil, gradientRing: unseen)
    }
    var body: some View {
        Group {
            if opensStories, groupIndex != nil {
                Button { Haptics.tap(); showingStories = true } label: { portrait }
                    .buttonStyle(.plain).accessibilityLabel("View @\(username)'s story")
            } else { portrait }
        }
        .fullScreenCover(isPresented: $showingStories) {
            let ordered = stories.storiesByUser().map { Array($0.all.reversed()) }
            if let groupIndex, ordered.indices.contains(groupIndex) {
                WhisperStoryViewer(groups: ordered, startGroup: groupIndex, startIndex: stories.firstUnseenIndex(in: ordered[groupIndex]))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in showingStories = false }
    }
}
