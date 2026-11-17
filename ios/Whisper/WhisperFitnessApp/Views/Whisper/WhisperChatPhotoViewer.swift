import SwiftUI
import Photos

// MARK: - The photo moment in a chat
//
// Tap a photo in a thread and it lifts onto its own screen — the reference
// grammar exactly: the picture's own colors blurred into a pale backdrop, a
// header with ✕ · the sender's avatar · "You" / their name · how long ago,
// then save · add-to-story · forward; the photo centered with soft corners
// (pinch to zoom, drag down to let go, swipe sideways through a set); and a
// "Reply…" bar on its own layer at the bottom that quotes THIS photo.

/// One photo in the viewer — the message row it rides in and its URL.
struct WhisperChatPhotoItem: Identifiable, Hashable {
    let message: WhisperMessageRow
    let url: URL
    var id: String { message.id }
}

/// Everything the viewer needs to open.
struct WhisperChatPhotoViewerContext: Identifiable {
    let id = UUID()
    let items: [WhisperChatPhotoItem]
    let startIndex: Int
    /// "You" for my photos, "@name" for theirs.
    let senderLabel: String
    let senderUsername: String
    let senderAvatarURL: URL?
    let isMine: Bool
}

struct WhisperChatPhotoViewer: View {
    let context: WhisperChatPhotoViewerContext
    /// Send a reply that quotes the given photo message.
    let onReply: (WhisperMessageRow, String) -> Void
    /// Forward the photo message to someone else.
    let onForward: (WhisperMessageRow) -> Void
    /// The camera disc — reply with a photo of your own.
    let onPickPhoto: () -> Void
    /// The host unmounts the viewer (it lives in the thread's own layer so
    /// it fades, never slides).
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var index: Int
    @State private var shown: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var replyText: String = ""
    @FocusState private var replyFocused: Bool
    @State private var toast: String?
    @State private var storyHandoff: StoryHandoff?
    @State private var busy: Bool = false

    private struct StoryHandoff: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    init(
        context: WhisperChatPhotoViewerContext,
        onReply: @escaping (WhisperMessageRow, String) -> Void,
        onForward: @escaping (WhisperMessageRow) -> Void,
        onPickPhoto: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.context = context
        self.onReply = onReply
        self.onForward = onForward
        self.onPickPhoto = onPickPhoto
        self.onClose = onClose
        let clamped = context.items.isEmpty ? 0 : max(0, min(context.startIndex, context.items.count - 1))
        self._index = State(initialValue: clamped)
    }

    private var current: WhisperChatPhotoItem? {
        context.items.indices.contains(index) ? context.items[index] : nil
    }

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }

    /// How far the card has traveled toward dismissal, 0…1.
    private var dismissProgress: CGFloat {
        min(1, max(0, dragOffset.height) / 320)
    }

    var body: some View {
        ZStack {
            backdrop
                .opacity(shown ? 1 - Double(dismissProgress) * 0.9 : 0)

            VStack(spacing: 0) {
                header
                    .opacity(1 - Double(dismissProgress) * 1.6)
                stage
                replyBar
                    .opacity(1 - Double(dismissProgress) * 1.6)
            }
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.94)

            if let toast {
                Text(toast)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(ink, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 70)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: shown)
        .animation(.spring(response: 0.3), value: toast == nil)
        .onAppear {
            shown = true
        }
        .fullScreenCover(item: $storyHandoff) { handoff in
            WhisperStoryEditor(
                image: handoff.image,
                initialStickers: [],
                onPosted: { storyHandoff = nil }
            )
        }
    }

    // MARK: Backdrop

    /// The photo's own colors, blurred into a pale wash (light) or a deep one
    /// (dark) — the picture sits in its own light.
    private var backdrop: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            if let current {
                WhisperCachedAsyncImage(url: current.url, maxPixelSize: 256) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
                .ignoresSafeArea()
                .blur(radius: 70)
                .saturation(1.2)
                .opacity(colorScheme == .dark ? 0.55 : 0.5)
                .id(current.id)
                .transition(.opacity)
            }
            (colorScheme == .dark ? Color.black.opacity(0.35) : WhisperTheme.surface(colorScheme).opacity(0.55))
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.3), value: index)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(ink)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .buttonStyle(WhisperMenuPressStyle())
            .accessibilityLabel("Close")

            WhisperAvatar(username: context.senderUsername, size: 40, imageURL: context.senderAvatarURL, ring: false)

            VStack(alignment: .leading, spacing: 1) {
                Text(context.senderLabel)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                if let stamp = timeAgo {
                    Text(stamp)
                        .font(.system(size: 15))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            headerTool("arrow.down", label: "Save to Photos") { Task { await saveToPhotos() } }
            headerTool("plus.circle", label: "Add to story") { Task { await addToStory() } }
            headerTool("paperplane", label: "Forward") {
                guard let current else { return }
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onForward(current.message) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func headerTool(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(ink)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(WhisperMenuPressStyle())
        .disabled(busy)
        .accessibilityLabel(label)
    }

    private var timeAgo: String? {
        guard let current, let date = WhisperBackendService.parseISO(current.message.created_at) else { return nil }
        return WhisperChatPhotoViewerFormatters.relative.localizedString(for: date, relativeTo: Date())
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { geo in
            Group {
                if context.items.count > 1 {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(Array(context.items.enumerated()), id: \.element.id) { i, item in
                                photo(item, in: geo.size).id(i)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: Binding<Int?>(get: { index }, set: { value in
                        if let value, context.items.indices.contains(value) { index = value }
                    }))
                    .scrollDisabled(zoom > 1.05)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .overlay(alignment: .top) {
                        Text("\(index + 1) / \(context.items.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ink.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(WhisperTheme.card(colorScheme).opacity(0.85), in: Capsule())
                            .padding(.top, 6)
                    }
                } else if let current {
                    photo(current, in: geo.size)
                }
            }
            .offset(dragOffset)
            .scaleEffect(1 - dismissProgress * 0.12)
            .simultaneousGesture(dismissDrag)
        }
        .onChange(of: index) { _, _ in zoom = 1; dragOffset = .zero }
    }

    private func photo(_ item: WhisperChatPhotoItem, in size: CGSize) -> some View {
        WhisperPostPhotoPage(
            url: item.url,
            isActive: current?.id == item.id,
            onZoomChanged: { isZoomed in
                guard current?.id == item.id else { return }
                zoom = isZoomed ? 2 : 1
                if isZoomed { dragOffset = .zero }
            },
            onDismiss: { close() },
            onSingleTap: { if replyFocused { replyFocused = false } }
        )
        .frame(width: size.width, height: size.height)
    }

    /// Drag DOWN lets go — the picture follows the finger, the light fades,
    /// release past the threshold (or a flick) closes; otherwise it springs
    /// back. Sideways drags belong to the pager.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard zoom <= 1.05 else { return }
                let t = value.translation
                guard abs(t.height) > abs(t.width) * 1.1 || dragOffset != .zero else { return }
                dragOffset = CGSize(width: t.width * 0.4, height: max(0, t.height))
            }
            .onEnded { value in
                guard zoom <= 1.05 else { dragOffset = .zero; return }
                guard dragOffset != .zero else { return }
                if value.translation.height > 140 || value.predictedEndTranslation.height > 300 {
                    close()
                } else {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { dragOffset = .zero }
                }
            }
    }

    // MARK: Reply bar

    /// The bottom layer — a camera disc (reply with a photo of your own), the
    /// "Reply…" field, and the send disc once you've typed.
    private var replyBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onPickPhoto() }
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(width: 44, height: 44)
                    .background(ink, in: Circle())
            }
            .buttonStyle(WhisperMenuPressStyle())
            .accessibilityLabel("Reply with a photo")

            HStack(spacing: 8) {
                TextField("Reply…", text: $replyText, axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundStyle(ink)
                    .focused($replyFocused)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit { sendReply() }
                if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        sendReply()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(WhisperTheme.surface(colorScheme))
                            .frame(width: 30, height: 30)
                            .background(ink, in: Circle())
                    }
                    .buttonStyle(WhisperMenuPressStyle())
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .accessibilityLabel("Send reply")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .modifier(WhisperControlGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: replyText.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background {
            // The bottom layer — the bar sits on its own quiet plate, not on
            // the picture.
            (colorScheme == .dark ? Color.black.opacity(0.35) : WhisperTheme.surface(colorScheme).opacity(0.7))
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: Actions

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let current else { return }
        Haptics.success()
        replyText = ""
        replyFocused = false
        onReply(current.message, text)
        close()
    }

    private func close() {
        replyFocused = false
        shown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onClose() }
    }

    private func loadImage() async -> UIImage? {
        guard let current else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: current.url) else { return nil }
        return UIImage(data: data)
    }

    private func saveToPhotos() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        guard let image = await loadImage() else {
            showToast("Couldn't load the photo")
            return
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            showToast("Allow Photos access in Settings to save")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            Haptics.success()
            showToast("Saved to Photos")
        } catch {
            showToast("Couldn't save the photo")
        }
    }

    private func addToStory() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        guard let image = await loadImage() else {
            showToast("Couldn't load the photo")
            return
        }
        storyHandoff = StoryHandoff(image: image)
    }

    private func showToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            if toast == text { toast = nil }
        }
    }
}

/// Formatters the viewer shares — created once.
enum WhisperChatPhotoViewerFormatters {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.dateTimeStyle = .numeric
        return f
    }()
}

// MARK: - The fanned photo stack
//
// Several photos sent together read as ONE scattered stack — the reference:
// each photo leans a few degrees the other way, overlapping down the diagonal
// with a soft shadow, the newest on top. Tap any photo to open the viewer on
// it. The wire is untouched (one message per photo); only the rendering
// gathers a run of photos from one sender.

struct WhisperChatPhotoStack: View {
    let urls: [URL]
    let mine: Bool
    let onTap: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let cardWidth: CGFloat = 168
    private let cardHeight: CGFloat = 210
    private let maxShown: Int = 4

    private var shown: [URL] { Array(urls.prefix(maxShown)) }
    private var hidden: Int { max(0, urls.count - maxShown) }

    /// Each photo steps down the diagonal and tilts the other way from its
    /// neighbour — the same fan whether it's your side or theirs (mirrored).
    private func placement(_ i: Int) -> (offset: CGSize, angle: Double) {
        let n = shown.count
        let step: CGFloat = n == 2 ? 62 : 44
        let centerShift: CGFloat = CGFloat(n - 1) * step / 2
        let dx: CGFloat = (CGFloat(i) * step - centerShift) * (mine ? -1 : 1)
        let dy: CGFloat = CGFloat(i) * step * 0.85 - CGFloat(n - 1) * step * 0.85 / 2
        let base: Double = n == 2 ? 7 : 5
        let angle: Double = (i % 2 == 0 ? -base : base) * (mine ? -1 : 1)
        return (CGSize(width: dx, height: dy), angle)
    }

    private var stackSize: CGSize {
        let n = CGFloat(shown.count)
        let step: CGFloat = shown.count == 2 ? 62 : 44
        return CGSize(width: cardWidth + (n - 1) * step + 24, height: cardHeight + (n - 1) * step * 0.85 + 24)
    }

    var body: some View {
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, url in
                let place = placement(i)
                Button {
                    Haptics.tap()
                    onTap(i)
                } label: {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            WhisperTheme.card(colorScheme)
                        }
                    }
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0.5), lineWidth: 1)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if i == shown.count - 1, hidden > 0 {
                            Text("+\(hidden)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.55), in: Capsule())
                                .padding(10)
                        }
                    }
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.16), radius: 14, y: 8)
                }
                .buttonStyle(WhisperMenuPressStyle())
                .rotationEffect(.degrees(place.angle))
                .offset(place.offset)
                .zIndex(Double(i))
                .accessibilityLabel("Photo \(i + 1) of \(urls.count)")
            }
        }
        .frame(width: stackSize.width, height: stackSize.height)
    }
}
