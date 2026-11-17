import SwiftUI
import Supabase

/// The portrait crosses the seam into one continuous panel containing the entire profile.
/// Keep the content unclipped so story controls and floating notes remain usable.
struct WhisperProfileHeaderCard<Content: View>: View {
    var userID: String? = nil
    var viewportHeight: CGFloat = 0
    var coverTopInset: CGFloat = 0
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @State private var perks = WhisperVerifiedPerksService.shared
    @State private var columnWidth: CGFloat = 0

    private var coverHeight: CGFloat { columnWidth >= 600 ? 210 : 248 }

    private var coverURL: URL? { userID.flatMap { perks.bannerURL(forUserID: $0) } }

    var body: some View {
        VStack(spacing: 0) {
            WhisperTheme.card(scheme)
                .frame(height: coverHeight + max(0, coverTopInset))
                .overlay {
                    if let coverURL {
                        WhisperProfileCoverImage(url: coverURL, offset: userID.map { perks.bannerOffsetY(forUserID: $0) } ?? 0)
                    }
                }
                .clipped()
            VStack(spacing: 16) {
                content()
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 28)
            .frame(minHeight: columnWidth >= 600 ? 0 : max(0, viewportHeight - 224), alignment: .top)
            .modifier(WhisperStoriesForeground())
            .padding(.top, -24)
            .zIndex(1)
        }
        // Bound the shared self/member profile in large iPad windows; split view
        // naturally returns to the compact phone layout using local column width.
        .frame(maxWidth: 720)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidth = $0 }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// Share the crop between the cover and editor. Clamp legacy point-based
/// positioning to the actual image overflow without zooming or exposing edges.
struct WhisperProfileCoverImage: View {
    let url: URL
    var offset: Double = 0
    @State private var loadedImage: UIImage?
    @State private var loadedURL: URL?
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if loadedURL == url, let image = loadedImage {
                    let source = image.size
                    let scale = max(geometry.size.width / max(1, source.width), geometry.size.height / max(1, source.height))
                    let width = source.width * scale
                    let height = source.height * scale
                    let limit = max(0, (height - geometry.size.height) / 2)
                    let safeOffset = offset.isFinite ? max(-limit, min(limit, offset)) : 0
                    Image(uiImage: image).renderingMode(.original).resizable()
                        .frame(width: width, height: height)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + safeOffset)
                } else if failed {
                    Button {
                        retry += 1
                    } label: {
                        Label("Cover couldn't load · Retry", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .padding(12)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    ProgressView().accessibilityLabel("Loading cover photo")
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
        .task(id: "\(url.absoluteString)|\(AccountStorage.generation)|\(retry)") {
            let owner = AccountStorage.currentUserID
            let generation = AccountStorage.generation
            loadedImage = nil
            loadedURL = nil
            failed = false
            if let image = await WhisperImageCache.load(url, maxPixelSize: 1600) {
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                loadedImage = image
                loadedURL = url
                print("[WhisperCover] stage=image-load result=public-success")
                return
            }
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            // getPublicURL only constructs an address; it doesn't establish that
            // the bucket allows anonymous reads. Reuse the viewer's existing RLS
            // permissions for this backend's banner objects, never another host.
            let base = URL(string: SupabaseService.supabaseURL)
            let prefix = "/storage/v1/object/public/banners/"
            if url.host == base?.host, url.path.hasPrefix(prefix) {
                let path = String(url.path.dropFirst(prefix.count))
                do {
                    let data = try await SupabaseService.shared.client.storage.from("banners").download(path: path)
                    try WhisperChatMediaService.checkAccount(owner, generation: generation)
                    try Task.checkCancellation()
                    if let image = WhisperImageCache.decode(data, maxPixelSize: 1600) {
                        loadedImage = image
                        loadedURL = url
                        print("[WhisperCover] stage=image-load result=authenticated-success")
                        return
                    }
                } catch {
                    guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                    print("[WhisperCover] stage=image-load result=failed type=\(String(describing: Swift.type(of: error)))")
                }
            }
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            failed = true
        }
    }
}
