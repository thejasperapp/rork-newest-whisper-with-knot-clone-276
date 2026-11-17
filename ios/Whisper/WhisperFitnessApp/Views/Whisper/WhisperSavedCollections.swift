import SwiftUI

// MARK: - Saved, organized
//
// Instagram's Saved grammar on Whisper's bookmark service: the Saved screen
// opens on COLLECTIONS — "All posts" first, then every folder as a 2-column
// tile wearing a 2×2 mosaic of its covers — and a tap unrolls a collection
// into its 3-column grid. Saving stays one tap; PRESS AND HOLD the bookmark
// (or pick "Save to collection…") to file a post into a folder — a sheet
// with every collection, a check on the current one, and "New collection".
// Collections are the service's existing categories (device-local, per
// account); only the way in and the way they're shown changed.

/// Everything the saved surfaces need to draw a row.
private enum WhisperSavedCover {
    /// First still image URL when there is one; nil for video-only rows.
    static func still(for row: WhisperPostRow) -> URL? {
        (row.media_urls ?? []).compactMap { URL(string: $0) }.first(where: { !WhisperVideo.isVideo($0) })
    }

    static func isWave(_ row: WhisperPostRow) -> Bool {
        (row.is_reel ?? false) || (row.media_urls ?? []).compactMap { URL(string: $0) }.contains(where: { WhisperVideo.isVideo($0) })
    }

    static func accent(_ row: WhisperPostRow) -> Color {
        WhisperPost.color(fromHex: row.accent_hex) ?? Color.gray
    }

    static func symbol(_ row: WhisperPostRow) -> String {
        row.symbol ?? (WhisperPostKind(rawValue: row.kind ?? "")?.icon ?? "sparkles")
    }
}

/// One saved post's cover — a still when it has one, the wave's play tile
/// otherwise, the accent gradient as the last resort.
struct WhisperSavedCoverTile: View {
    let row: WhisperPostRow
    var cornerRadius: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let url = WhisperSavedCover.still(for: row) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            fallback
                        }
                    }
                    .allowsHitTesting(false)
                } else {
                    fallback
                }
            }
            .overlay(alignment: .topTrailing) {
                if WhisperSavedCover.isWave(row) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .padding(6)
                } else if (row.media_urls?.count ?? 0) > 1 {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .padding(6)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(.rect)
    }

    private var fallback: some View {
        let accent = WhisperSavedCover.accent(row)
        return LinearGradient(
            colors: [accent.opacity(0.95), accent.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: WhisperSavedCover.isWave(row) ? "play.fill" : WhisperSavedCover.symbol(row))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// MARK: - The collections screen

/// The Saved screen's body: collection tiles, or the grid of one collection.
struct WhisperSavedCollectionsView: View {
    /// Every bookmarked row, newest save first.
    let rows: [WhisperPostRow]
    let loading: Bool
    let onOpen: (WhisperPostRow) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var bookmarks = WhisperBookmarkService.shared
    @State private var backTransition: WhisperBackAction = WhisperBackAction()
    @State private var openCollection: String?
    @State private var presentNew: Bool = false
    @State private var newName: String = ""
    @State private var confirmDelete: String?

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }

    /// Folders in the service, "All" excluded (it gets its own tile).
    private var folders: [String] {
        bookmarks.categories.filter { $0 != "All" }
    }

    private func rows(in collection: String) -> [WhisperPostRow] {
        if collection == "All" { return rows }
        return rows.filter { bookmarks.category(forPostID: $0.id) == collection }
    }

    var body: some View {
        Group {
            if let openCollection {
                collectionGrid(openCollection)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                tiles
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .whisperEdgeBack(isEnabled: openCollection != nil, revealPresentation: false, controller: backTransition) { backTransition.perform { openCollection = nil } }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: openCollection)
        .alert("New collection", isPresented: $presentNew) {
            TextField("Collection name", text: $newName)
            Button("Create") {
                let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !n.isEmpty else { return }
                bookmarks.addCategory(n)
                Haptics.success()
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        } message: {
            Text("Only you can see your collections.")
        }
        .alert("Delete this collection?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let name = confirmDelete {
                    bookmarks.removeCategory(name)
                    if openCollection == name { openCollection = nil }
                }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("The posts stay saved — they move back to All posts.")
        }
    }

    // MARK: Tiles

    @ViewBuilder
    private var tiles: some View {
        if loading && rows.isEmpty {
            ProgressView()
                .tint(ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
        } else if rows.isEmpty && folders.isEmpty {
            WhisperEmptyState(
                icon: "bookmark",
                title: "Nothing saved yet",
                message: "Tap the bookmark under any post or wave to save it here. Press and hold it to file it into a collection."
            )
            .padding(.horizontal, 16)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Collections")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(muted)
                        .tracking(0.3)
                    Spacer()
                    Button {
                        Haptics.tap()
                        newName = ""
                        presentNew = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("New")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(WhisperTheme.card(colorScheme), in: Capsule())
                        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75) }
                    }
                    .buttonStyle(WhisperMenuPressStyle())
                }
                .padding(.horizontal, 16)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    collectionTile("All", title: "All posts", rows: rows)
                    ForEach(folders, id: \.self) { name in
                        collectionTile(name, title: name, rows: rows(in: name))
                            .contextMenu {
                                Button(role: .destructive) {
                                    confirmDelete = name
                                } label: {
                                    Label("Delete collection", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func collectionTile(_ key: String, title: String, rows: [WhisperPostRow]) -> some View {
        Button {
            Haptics.tap()
            backTransition.captureLocalPredecessor()
            openCollection = key
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                mosaic(rows)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Text(rows.count == 1 ? "1 post" : "\(rows.count) posts")
                        .font(.system(size: 13))
                        .foregroundStyle(muted)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(WhisperMenuPressStyle())
        .accessibilityLabel("\(title), \(rows.count) posts")
    }

    /// Up to four covers in a 2×2; fewer covers fill what they can.
    private func mosaic(_ rows: [WhisperPostRow]) -> some View {
        let covers = Array(rows.prefix(4))
        return ZStack {
            WhisperTheme.card(colorScheme)
            if covers.isEmpty {
                Image(systemName: "bookmark")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(muted)
            } else if covers.count == 1 {
                WhisperSavedCoverTile(row: covers[0])
            } else {
                Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                    GridRow {
                        WhisperSavedCoverTile(row: covers[0])
                        if covers.count > 1 { WhisperSavedCoverTile(row: covers[1]) } else { Color.clear }
                    }
                    GridRow {
                        if covers.count > 2 { WhisperSavedCoverTile(row: covers[2]) } else { Color.clear }
                        if covers.count > 3 { WhisperSavedCoverTile(row: covers[3]) } else { Color.clear }
                    }
                }
            }
        }
    }

    // MARK: One collection

    private func collectionGrid(_ key: String) -> some View {
        let list = rows(in: key)
        let title = key == "All" ? "All posts" : key
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    backTransition.perform { openCollection = nil }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Saved")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(ink)
                    .contentShape(.rect)
                }
                .buttonStyle(WhisperMenuPressStyle())
                Spacer()
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
                Spacer()
                Text(list.count == 1 ? "1 post" : "\(list.count) posts")
                    .font(.system(size: 13))
                    .foregroundStyle(muted)
            }
            .padding(.horizontal, 16)

            if list.isEmpty {
                WhisperEmptyState(
                    icon: "folder",
                    title: "Nothing here yet",
                    message: "Press and hold the bookmark under a post to file it into \(title)."
                )
                .padding(.horizontal, 16)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    ForEach(list, id: \.id) { row in
                        Button {
                            Haptics.tap()
                            onOpen(row)
                        } label: {
                            WhisperSavedCoverTile(row: row)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Section("Move to") {
                                ForEach(bookmarks.categories, id: \.self) { name in
                                    Button {
                                        Haptics.tap()
                                        bookmarks.setCategory(name, forPostID: row.id)
                                    } label: {
                                        Label(name == "All" ? "All posts" : name, systemImage: bookmarks.category(forPostID: row.id) == name ? "checkmark" : "folder")
                                    }
                                }
                            }
                            Button(role: .destructive) {
                                Task { _ = await bookmarks.toggle(postID: row.id) }
                            } label: {
                                Label("Unsave", systemImage: "bookmark.slash")
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Save to collection

/// Instagram's "Save to collection" sheet — every collection with a check on
/// the one this post is in, and "New collection" inline. Picking a folder
/// also saves the post if it wasn't saved yet.
struct WhisperSaveToCollectionSheet: View {
    let postID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var bookmarks = WhisperBookmarkService.shared
    @State private var creating: Bool = false
    @State private var newName: String = ""
    @FocusState private var nameFocused: Bool

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var current: String { bookmarks.category(forPostID: postID) }
    private var folders: [String] { bookmarks.categories.filter { $0 != "All" } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Save to collection")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ink)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 0) {
                    row(name: "All", title: "All posts", icon: "bookmark", count: bookmarks.bookmarkedPostIDs.count)
                    ForEach(folders, id: \.self) { name in
                        divider
                        row(name: name, title: name, icon: "folder", count: bookmarks.categoryByPostID.values.filter { $0 == name }.count)
                    }
                    divider
                    if creating {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(ink)
                                .frame(width: 40, height: 40)
                                .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            TextField("Collection name", text: $newName)
                                .font(.system(size: 15))
                                .foregroundStyle(ink)
                                .focused($nameFocused)
                                .submitLabel(.done)
                                .onSubmit { createAndFile() }
                            Button {
                                createAndFile()
                            } label: {
                                Text("Create")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(ink, in: Capsule())
                            }
                            .buttonStyle(WhisperMenuPressStyle())
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .opacity(newName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .onAppear { nameFocused = true }
                    } else {
                        Button {
                            Haptics.tap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { creating = true }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(ink)
                                    .frame(width: 40, height: 40)
                                    .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text("New collection")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(ink)
                                Spacer()
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(WhisperMenuPressStyle())
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var divider: some View {
        Rectangle()
            .fill(WhisperTheme.hairline(colorScheme))
            .frame(height: 0.5)
            .padding(.leading, 70)
    }

    private func row(name: String, title: String, icon: String, count: Int) -> some View {
        let selected = current == name && bookmarks.isBookmarked(postID)
        return Button {
            file(into: name)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(ink)
                    .frame(width: 40, height: 40)
                    .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ink)
                    Text(count == 1 ? "1 post" : "\(count) posts")
                        .font(.system(size: 12.5))
                        .foregroundStyle(muted)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ink)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(WhisperMenuPressStyle())
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: selected)
    }

    private func file(into name: String) {
        Haptics.success()
        bookmarks.setCategory(name, forPostID: postID)
        if !bookmarks.isBookmarked(postID) {
            Task { _ = await bookmarks.toggle(postID: postID) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
    }

    private func createAndFile() {
        let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        bookmarks.addCategory(n)
        newName = ""
        creating = false
        file(into: n)
    }
}
