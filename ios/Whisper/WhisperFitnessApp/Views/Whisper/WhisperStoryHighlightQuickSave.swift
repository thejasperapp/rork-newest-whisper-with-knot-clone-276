import SwiftUI

/// One-tap "Save to Highlights" sheet opened from the story viewer's new
/// bookmark button. Lists every album with live saved-state, adds the
/// current story with a single tap, and — the piece the old ⋯ submenu was
/// missing — creates a brand-new highlight inline (name it, done) so the
/// flow works even before the user has any albums. Styled for the dark
/// story stage (always presented over the black viewer).
struct WhisperStoryHighlightQuickSave: View {
    @Environment(\.dismiss) private var dismiss
    let story: WhisperStoryRow

    @State private var highlights = WhisperStoryHighlightsService.shared
    @State private var newTitle: String = ""
    @State private var creating: Bool = false
    @State private var busyAlbumID: String?
    /// Albums this story landed in during THIS sheet session — flashes the
    /// row into its saved state instantly.
    @State private var flashedAlbumIDs: Set<String> = []
    @FocusState private var titleFocused: Bool

    private var albums: [WhisperStoryHighlightRow] {
        highlights.albums(forUserID: AccountStorage.currentUserID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 14)
            newHighlightRow
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(albums) { album in
                        albumRow(album)
                    }
                    if albums.isEmpty {
                        emptyHint
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await highlights.refresh(forUserID: AccountStorage.currentUserID)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            storyThumb
            VStack(alignment: .leading, spacing: 3) {
                Text("Save to Highlights")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Keeps this story on your profile after it expires.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
    }

    private var storyThumb: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let url = URL(string: story.image_url) {
                WhisperCachedAsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(width: 42, height: 58)
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
        }
    }

    // MARK: - New highlight (inline creation)

    private var newHighlightRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            TextField(
                "",
                text: $newTitle,
                prompt: Text("New highlight name…").foregroundStyle(.white.opacity(0.45))
            )
            .foregroundStyle(.white)
            .focused($titleFocused)
            .submitLabel(.done)
            .onSubmit { createAndSave() }
            Button {
                createAndSave()
            } label: {
                Group {
                    if creating {
                        ProgressView().tint(.black)
                    } else {
                        Text("Create")
                            .font(.footnote.weight(.bold))
                    }
                }
                .foregroundStyle(.black)
                .frame(height: 30)
                .padding(.horizontal, 14)
                .background(.white, in: Capsule())
                .opacity(trimmedTitle.isEmpty ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(trimmedTitle.isEmpty || creating)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
    }

    private var trimmedTitle: String {
        newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createAndSave() {
        let title = trimmedTitle
        guard !title.isEmpty, !creating else { return }
        creating = true
        titleFocused = false
        Task {
            let album = await highlights.createAlbum(
                title: title,
                coverURL: story.image_url,
                stories: [story]
            )
            await MainActor.run {
                creating = false
                if let album {
                    Haptics.success()
                    newTitle = ""
                    flashedAlbumIDs.insert(album.id)
                } else {
                    Haptics.warning()
                }
            }
        }
    }

    // MARK: - Album rows

    private func albumRow(_ album: WhisperStoryHighlightRow) -> some View {
        let items = highlights.items(forAlbumID: album.id)
        let contains = flashedAlbumIDs.contains(album.id)
            || items.contains { $0.image_url == story.image_url }
        return HStack(spacing: 12) {
            albumCover(album)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(items.count) \(items.count == 1 ? "story" : "stories")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            if contains {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline.weight(.bold))
                    Text("Saved")
                        .font(.footnote.weight(.bold))
                }
                .foregroundStyle(Color(red: 0.36, green: 0.86, blue: 0.72))
            } else {
                Button {
                    save(to: album)
                } label: {
                    Group {
                        if busyAlbumID == album.id {
                            ProgressView().tint(.black)
                        } else {
                            Text("Add")
                                .font(.footnote.weight(.bold))
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(height: 30)
                    .padding(.horizontal, 16)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busyAlbumID != nil)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        }
        .animation(.whisperSnappy, value: contains)
    }

    private func albumCover(_ album: WhisperStoryHighlightRow) -> some View {
        ZStack {
            Color.white.opacity(0.10)
            if let cover = album.cover_url, let url = URL(string: cover) {
                WhisperCachedAsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                Image(systemName: "bookmark.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
    }

    private func save(to album: WhisperStoryHighlightRow) {
        guard busyAlbumID == nil else { return }
        busyAlbumID = album.id
        let s = story
        Task {
            let item = await highlights.addStory(s, toAlbumID: album.id)
            await MainActor.run {
                busyAlbumID = nil
                if item != nil {
                    Haptics.success()
                    flashedAlbumIDs.insert(album.id)
                } else {
                    Haptics.warning()
                }
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            WhisperMeetDoodle(symbol: "bookmark", height: 96)
                .environment(\.colorScheme, .dark)
            Text("No highlights yet")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            Text("Name one above — this story becomes its cover.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}
