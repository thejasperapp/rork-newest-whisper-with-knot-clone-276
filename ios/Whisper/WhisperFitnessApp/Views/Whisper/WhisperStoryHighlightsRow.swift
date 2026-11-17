import SwiftUI

/// Instagram-style row of saved Story Highlight circles. Appears on the
/// profile between the action row and the tab bar.
///
/// - On my own profile, the first circle is a `+` that opens the builder
///   sheet to create a new highlight from any of my current/active stories.
/// - Tapping a highlight opens the highlight viewer.
/// - Long-press on a highlight (owner only) opens an edit menu.
struct WhisperStoryHighlightsRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let userID: String
    let isMe: Bool

    @State private var highlights = WhisperStoryHighlightsService.shared
    @State private var presentBuilder: Bool = false
    @State private var presentViewer: WhisperStoryHighlightRow?
    @State private var editTarget: WhisperStoryHighlightRow?
    @State private var renameTarget: WhisperStoryHighlightRow?
    @State private var renameText: String = ""
    @State private var confirmDelete: WhisperStoryHighlightRow?

    private let circle: CGFloat = 64
    private let ring: CGFloat = 72

    private var albums: [WhisperStoryHighlightRow] {
        highlights.albums(forUserID: userID)
    }

    var body: some View {
        Group {
            if !albums.isEmpty || isMe {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        if isMe { newButton }
                        ForEach(albums) { album in
                            bubble(for: album)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
            }
        }
        .task { await highlights.refresh(forUserID: userID) }
        .sheet(isPresented: $presentBuilder) {
            WhisperStoryHighlightBuilderSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editTarget) { album in
            WhisperStoryHighlightBuilderSheet(editing: album)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $presentViewer) { album in
            WhisperStoryHighlightViewer(album: album)
        }
        .alert("Rename highlight", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Save") {
                if let target = renameTarget {
                    let newTitle = renameText
                    Task { await highlights.rename(albumID: target.id, title: newTitle) }
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .alert("Delete highlight?", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let target = confirmDelete {
                    Task { await highlights.deleteAlbum(target.id) }
                }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("This will remove the highlight for everyone. The original stories are not affected.")
        }
    }

    private var newButton: some View {
        Button {
            Haptics.tap()
            presentBuilder = true
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        .frame(width: ring, height: ring)
                    Circle()
                        .fill(WhisperTheme.card(colorScheme))
                        .frame(width: circle, height: circle)
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                Text("New")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                    .frame(maxWidth: ring + 8)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func bubble(for album: WhisperStoryHighlightRow) -> some View {
        let items = highlights.items(forAlbumID: album.id)
        let cover = album.cover_url ?? items.first?.image_url
        let url = cover.flatMap(URL.init(string:))
        Button {
            Haptics.tap()
            presentViewer = album
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(WhisperTheme.ink(colorScheme), lineWidth: 1.5)
                        .frame(width: ring, height: ring)
                    Circle()
                        .fill(WhisperTheme.card(colorScheme))
                        .frame(width: circle, height: circle)
                        .overlay {
                            if let url {
                                WhisperCachedAsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().aspectRatio(contentMode: .fill)
                                    default:
                                        Image(systemName: "bookmark.fill")
                                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    }
                                }
                                .frame(width: circle, height: circle)
                                .clipShape(Circle())
                                .allowsHitTesting(false)
                            } else {
                                Image(systemName: "bookmark.fill")
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                }
                Text(album.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                    .frame(maxWidth: ring + 8)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isMe {
                Button {
                    editTarget = album
                } label: {
                    Label("Edit highlight", systemImage: "square.and.pencil")
                }
                Button {
                    renameText = album.title
                    renameTarget = album
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    confirmDelete = album
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
