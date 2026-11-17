import SwiftUI

/// Full-screen playback for a saved Story Highlight album. Mirrors the
/// regular story viewer's tap-zone navigation and progress bar, minus the
/// 24h expiry rules.
struct WhisperStoryHighlightViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let album: WhisperStoryHighlightRow

    @State private var highlights = WhisperStoryHighlightsService.shared
    @State private var index: Int = 0
    @State private var progress: Double = 0
    @State private var paused: Bool = false
    @State private var lastTick: Date = Date()
    @Environment(\.scenePhase) private var scenePhase
    @State private var generation: UUID = AccountStorage.generation
    @State private var closed: Bool = false
    @State private var revealedFrameKeys: Set<String> = []
    @State private var readyPhotoCardKeys: Set<String> = []
    private var currentMetadata: WhisperStoryMetadata { WhisperStoryMetadata.decode(current?.metadata) }
    private func cardKey(_ id: String) -> String { "\(current?.id ?? "")|\(id)" }
    private var photoCardsPending: Bool {
        currentMetadata.stickers.contains { $0.isPhotoCard && (!readyPhotoCardKeys.contains(cardKey($0.id)) || ($0.isRevealFrame && !revealedFrameKeys.contains(cardKey($0.id)))) }
    }
    private var playbackPaused: Bool { paused || photoCardsPending || scenePhase != .active || closed || presentEdit || confirmDelete }
    private var canReveal: Bool { !closed && generation == AccountStorage.generation && scenePhase == .active && !paused && !presentEdit && !confirmDelete }
    @State private var dragOffset: CGFloat = 0
    @State private var confirmDelete: Bool = false
    @State private var presentEdit: Bool = false
    /// Plays the saved story's music preview when the upgrade columns
    /// copied one — highlights keep their soundtrack now.
    @State private var player = WhisperStoryMusicPlayer()

    private var duration: Double {
        WhisperStoryMetadata.decode(current?.metadata).musicSelection?.durationSeconds ?? 6
    }

    private var items: [WhisperStoryHighlightItemRow] {
        highlights.items(forAlbumID: album.id)
    }

    private var isOwner: Bool {
        album.user_id == AccountStorage.currentUserID
    }

    private var current: WhisperStoryHighlightItemRow? {
        guard !items.isEmpty, index >= 0, index < items.count else { return nil }
        return items[index]
    }

    var body: some View {
        GeometryReader { geo in
            let stage = WhisperStoryEditor.stageSize(in: geo.size)
            ZStack {
                Color.black.ignoresSafeArea()
                ZStack {
                if let item = current, let url = URL(string: item.image_url) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            ProgressView().tint(.white)
                        }
                    }
                    .frame(width: stage.width, height: stage.height)
                    .clipped()
                    .id(item.id)
                    .transition(.opacity)
                }
                HStack(spacing: 0) {
                    tapZone(width: stage.width / 3) { goPrevious() }
                    tapZone(width: stage.width * 2 / 3) { goNext() }
                }
                .frame(maxHeight: .infinity)

                // Saved sticker layer — highlights carry the full story
                // metadata now, so text / polls / questions / gifs render
                // exactly where the author placed them (display-only).
                if let item = current {
                    let meta = WhisperStoryMetadata.decode(item.metadata)
                    ForEach(meta.stickers) { sticker in
                        let referenceWidth = meta.referenceStageWidth.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? stage.width
                        let key = "\(item.id)|\(sticker.id)"
                        WhisperStoryStickerView(sticker: sticker, stageWidth: referenceWidth, isInteractive: sticker.isPhotoCard,
                            frameRevealed: !sticker.isRevealFrame || revealedFrameKeys.contains(key),
                            onPhotoCardReady: {
                                guard !closed, generation == AccountStorage.generation, current?.id == item.id else { return }
                                readyPhotoCardKeys.insert(key)
                            }, onTap: {
                                guard canReveal, current?.id == item.id, sticker.isRevealFrame else { return }
                                revealedFrameKeys.insert(key); Haptics.tap()
                            })
                            .id(key)
                            .scaleEffect(sticker.scale * stage.width / referenceWidth)
                            .rotationEffect(.radians(sticker.rotation))
                            .position(x: sticker.x * stage.width, y: sticker.y * stage.height)
                            .allowsHitTesting(sticker.isPhotoCard)
                    }
                }
                }.frame(width: stage.width, height: stage.height).clipped()
                VStack(spacing: 8) {
                    progressBar
                    headerRow
                    Spacer()
                    if let item = current, let caption = item.caption, !caption.isEmpty {
                        captionBar(caption)
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
            .offset(y: max(0, dragOffset))
            .gesture(
                DragGesture()
                    .onChanged { v in
                        if v.translation.height > 0 { dragOffset = v.translation.height }
                    }
                    .onEnded { v in
                        if v.translation.height > 120 {
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                        }
                    }
            )
        }
        .task(id: current?.id) {
            // Per-item soundtrack — restart the saved music preview when
            // the segment changes (no-op for flat pre-upgrade items).
            player.stop()
            if !playbackPaused, let item = current, let m = music(for: item) {
                player.play(m)
            }
        }
        .onShake(isEnabled: canReveal && currentMetadata.stickers.contains { $0.isRevealFrame && !revealedFrameKeys.contains(cardKey($0.id)) }) {
            guard canReveal else { return }
            revealedFrameKeys.formUnion(currentMetadata.stickers.filter(\.isRevealFrame).map { cardKey($0.id) })
            Haptics.tap()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            closed = true; paused = true; revealedFrameKeys = []; readyPhotoCardKeys = []; player.stop(); dismiss()
        }
        .onDisappear { player.stop() }
        .onChange(of: playbackPaused) { _, isPaused in
            lastTick = Date()
            if isPaused { player.pause() }
            else if let current, let music = music(for: current) { player.play(music) }
        }
        .task {
            await highlights.refreshItems(highlightID: album.id)
            // Nothing to play — bail instead of sitting on a black screen.
            if items.isEmpty {
                dismiss()
                return
            }
            // Drive progress from THIS task so the loop is cancelled with
            // the view — the old detached timer kept ticking at 30fps
            // forever after the viewer closed.
            paused = false
            lastTick = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                if playbackPaused { lastTick = Date(); continue }
                let now = Date()
                let dt = now.timeIntervalSince(lastTick)
                lastTick = now
                progress += dt / duration
                if progress >= 1 {
                    if index < items.count - 1 {
                        index += 1
                        progress = 0
                    } else {
                        dismiss()
                        return
                    }
                }
            }
        }
        .sheet(isPresented: $presentEdit, onDismiss: {
            // Items may have been added/removed — re-clamp and resume.
            Task {
                await highlights.refreshItems(highlightID: album.id)
                if items.isEmpty {
                    dismiss()
                } else {
                    index = min(index, items.count - 1)
                    progress = 0
                    paused = false
                }
            }
        }) {
            WhisperStoryHighlightBuilderSheet(editing: album)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Delete this item?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let item = current {
                    let albumID = album.id
                    let itemID = item.id
                    Task {
                        await highlights.deleteItem(itemID, fromAlbum: albumID)
                        if items.isEmpty {
                            dismiss()
                        } else {
                            index = min(index, items.count - 1)
                            progress = 0
                            paused = false
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { paused = false }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(1, items.count), id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(height: 2.5)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in
                            Capsule()
                                .fill(.white)
                                .frame(width: g.size.width * fillFraction(for: i))
                        }
                    }
            }
        }
    }

    private func fillFraction(for i: Int) -> CGFloat {
        if i < index { return 1 }
        if i == index { return CGFloat(min(1, progress)) }
        return 0
    }

    /// Builds the playable music model for a saved item — nil for flat
    /// pre-upgrade rows that only copied the title/artist strings.
    private func music(for item: WhisperStoryHighlightItemRow) -> WhisperStoryMusic? {
        guard let preview = item.music_url, !preview.isEmpty,
              let title = item.music_title,
              let artist = item.music_artist else { return nil }
        return WhisperStoryMusic(
            id: item.id + "-music",
            title: title,
            artist: artist,
            artworkURL: item.music_artwork,
            previewURL: preview,
            startSeconds: WhisperStoryMetadata.decode(item.metadata).musicSelection?.startSeconds ?? 0,
            durationSeconds: WhisperStoryMetadata.decode(item.metadata).musicSelection?.durationSeconds
        )
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "bookmark.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text(album.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                if let item = current, let title = item.music_title,
                   let artist = item.music_artist, !title.isEmpty {
                    StoryMusicMarquee(title: title, artist: artist)
                }
            }
            Spacer()
            if isOwner {
                Button {
                    Haptics.tap()
                    paused = true
                    presentEdit = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit highlight")
                Button {
                    Haptics.tap()
                    paused = true
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
            }
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func captionBar(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.45), in: .rect(cornerRadius: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tapZone(width: CGFloat, onTap: @escaping () -> Void) -> some View {
        Color.clear
            .frame(width: width)
            .contentShape(.rect)
            .onTapGesture {
                Haptics.tap()
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.15) {} onPressingChanged: { down in
                paused = down
            }
    }

    private func goPrevious() {
        if index > 0 {
            withAnimation(.easeInOut(duration: 0.15)) {
                index -= 1
                progress = 0
            }
        } else {
            dismiss()
        }
    }

    private func goNext() {
        if index < items.count - 1 {
            withAnimation(.easeInOut(duration: 0.15)) {
                index += 1
                progress = 0
            }
        } else {
            dismiss()
        }
    }

}
