import SwiftUI

struct WhisperPersonalWallpaper: View {
    let thread: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var image: UIImage?
    @State private var revision: Int = 0
    @State private var generation: UUID = AccountStorage.generation
    @State private var invalidated: Bool = false

    var body: some View {
        Color.clear.overlay {
            if let image, !invalidated, generation == AccountStorage.generation, contrast != .increased {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill).allowsHitTesting(false)
                    .overlay((scheme == .dark ? Color.black : Color.white).opacity(scheme == .dark ? 0.67 : 0.72))
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
        .task(id: "\(thread)-\(revision)") {
            let owner = AccountStorage.currentUserID
            let data = await WhisperWallpaperStore.shared.load(owner: owner, thread: thread)
            guard !Task.isCancelled, !invalidated, generation == AccountStorage.generation else { return }
            image = data.flatMap(UIImage.init(data:))
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperWallpaperChanged"))) { _ in revision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in invalidated = true; image = nil }
    }
}
