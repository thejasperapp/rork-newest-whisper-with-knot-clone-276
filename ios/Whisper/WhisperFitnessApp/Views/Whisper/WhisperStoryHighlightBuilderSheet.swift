import SwiftUI

/// Sheet for creating a new Story Highlight album — or editing an existing
/// one. Create mode titles the album and picks from the user's active
/// stories. Edit mode additionally shows the highlight's current items
/// (tap to keep / remove), lets more active stories be added, and offers
/// a cover picker.
struct WhisperStoryHighlightBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Non-nil when editing an existing highlight.
    let editingAlbum: WhisperStoryHighlightRow?

    init(editing album: WhisperStoryHighlightRow? = nil) {
        self.editingAlbum = album
    }

    @State private var stories = WhisperStoryService.shared
    @State private var highlights = WhisperStoryHighlightsService.shared

    @State private var title: String = ""
    /// Active-story IDs selected to add.
    @State private var selected: Set<String> = []
    /// Existing item IDs the user is keeping (edit mode).
    @State private var keptItemIDs: Set<String> = []
    /// Explicitly chosen cover image URL.
    @State private var coverURL: String?
    @State private var saving: Bool = false
    @State private var error: String?
    @State private var hydrated: Bool = false

    private var isEditing: Bool { editingAlbum != nil }

    private var existingItems: [WhisperStoryHighlightItemRow] {
        guard let album = editingAlbum else { return [] }
        return highlights.items(forAlbumID: album.id)
    }

    private var myStories: [WhisperStoryRow] { stories.myStories() }

    /// Active stories not already inside the album (dedup by image URL).
    private var addableStories: [WhisperStoryRow] {
        guard isEditing else { return myStories }
        let existingURLs = Set(existingItems.map { $0.image_url })
        return myStories.filter { !existingURLs.contains($0.image_url) }
    }

    private var chosen: [WhisperStoryRow] {
        addableStories.filter { selected.contains($0.id) }
    }

    /// Cover candidates: kept existing items first, then newly added stories.
    private var coverCandidates: [String] {
        var urls: [String] = existingItems
            .filter { keptItemIDs.contains($0.id) }
            .map { $0.image_url }
        urls.append(contentsOf: chosen.map { $0.image_url })
        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }

    private var canSave: Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !saving else { return false }
        if isEditing {
            return keptItemIDs.count + selected.count >= 1
        }
        return !selected.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        titleField
                        if isEditing {
                            currentItemsSection
                            coverSection
                        }
                        Text(isEditing ? "Add from active stories" : "Choose stories")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .padding(.horizontal, 16)
                        if addableStories.isEmpty {
                            if isEditing {
                                Text("No new active stories to add — post a story and it'll show up here.")
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    .padding(.horizontal, 16)
                            } else {
                                emptyState
                            }
                        } else {
                            grid
                        }
                        if let error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 16)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle(isEditing ? "Edit highlight" : "New highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .disabled(!canSave)
                    .foregroundStyle(canSave ? WhisperTheme.ink(colorScheme) : WhisperTheme.muted(colorScheme))
                }
            }
            .task {
                guard !hydrated else { return }
                hydrated = true
                if let album = editingAlbum {
                    title = album.title
                    coverURL = album.cover_url
                    await highlights.refreshItems(highlightID: album.id)
                    keptItemIDs = Set(highlights.items(forAlbumID: album.id).map { $0.id })
                }
                await stories.fetch()
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("e.g. PR day", text: $title)
                .font(.body)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Edit mode: current items

    /// Grid of the highlight's existing items. Tap toggles keep/remove —
    /// removed items dim with a minus badge and get deleted on Save.
    private var currentItemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("In this highlight")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                Text("Tap to remove")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 16)
            let columns = [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ]
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(existingItems) { item in
                    itemTile(for: item)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func itemTile(for item: WhisperStoryHighlightItemRow) -> some View {
        let isKept = keptItemIDs.contains(item.id)
        let url = URL(string: item.image_url)
        Button {
            Haptics.tap()
            if isKept {
                keptItemIDs.remove(item.id)
            } else {
                keptItemIDs.insert(item.id)
            }
        } label: {
            Color(.secondarySystemBackground)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let url {
                        WhisperCachedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Color.gray.opacity(0.2)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
                .clipShape(.rect(cornerRadius: 10))
                .opacity(isKept ? 1 : 0.35)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isKept ? "checkmark.circle.fill" : "minus.circle.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(isKept ? .white : .red)
                        .shadow(radius: 2)
                        .padding(6)
                        .symbolEffect(.bounce, value: isKept)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isKept ? WhisperTheme.ink(colorScheme) : .clear, lineWidth: 2)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Edit mode: cover picker

    /// Horizontal strip of kept items — tap one to make it the highlight's
    /// cover circle on the profile.
    @ViewBuilder
    private var coverSection: some View {
        let candidates = coverCandidates
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cover")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(candidates, id: \.self) { urlString in
                            coverSwatch(urlString)
                        }
                    }
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
            }
        }
    }

    @ViewBuilder
    private func coverSwatch(_ urlString: String) -> some View {
        // First candidate is the implicit default when nothing was chosen.
        let effective = coverURL ?? coverCandidates.first
        let isOn = effective == urlString
        Button {
            Haptics.tap()
            coverURL = urlString
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(
                        isOn ? WhisperTheme.ink(colorScheme) : WhisperTheme.hairline(colorScheme),
                        lineWidth: isOn ? 2.5 : 1
                    )
                    .frame(width: 64, height: 64)
                Circle()
                    .fill(WhisperTheme.card(colorScheme))
                    .frame(width: 56, height: 56)
                    .overlay {
                        if let url = URL(string: urlString) {
                            WhisperCachedAsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    Color.gray.opacity(0.2)
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .allowsHitTesting(false)
                        }
                    }
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.black.opacity(0.55), in: Circle())
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add stories grid

    private var grid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(addableStories) { s in
                tile(for: s)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func tile(for s: WhisperStoryRow) -> some View {
        let isSelected = selected.contains(s.id)
        let url = URL(string: s.image_url)
        Button {
            Haptics.tap()
            if isSelected {
                selected.remove(s.id)
            } else {
                selected.insert(s.id)
            }
        } label: {
            Color(.secondarySystemBackground)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let url {
                        WhisperCachedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Color.gray.opacity(0.2)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.85))
                        .shadow(radius: 2)
                        .padding(6)
                        .symbolEffect(.bounce, value: isSelected)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? WhisperTheme.ink(colorScheme) : .clear, lineWidth: 2)
                }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        WhisperEmptyState(
            icon: "bookmark",
            title: "No active stories",
            message: "Post a story first — then come back to save it into a highlight that lives on your profile forever."
        )
        .padding(.horizontal, 16)
    }

    private func save() async {
        guard canSave else { return }
        saving = true
        error = nil

        if let album = editingAlbum {
            // 1. Rename if the title changed.
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != album.title {
                await highlights.rename(albumID: album.id, title: trimmed)
            }
            // 2. Delete items the user deselected (snapshot first — the
            //    service array mutates as we delete).
            let toRemove = existingItems.filter { !keptItemIDs.contains($0.id) }
            for item in toRemove {
                await highlights.deleteItem(item.id, fromAlbum: album.id)
            }
            // 3. Append newly chosen stories.
            for s in chosen {
                _ = await highlights.addStory(s, toAlbumID: album.id)
            }
            // 4. Apply the cover — explicit pick, else first remaining item.
            let finalCover = coverURL ?? coverCandidates.first
            if let cover = finalCover, cover != album.cover_url {
                await highlights.setCover(albumID: album.id, coverURL: cover)
            }
            await highlights.refreshItems(highlightID: album.id)
            saving = false
            Haptics.success()
            dismiss()
            return
        }

        let cover = chosen.first?.image_url
        let result = await highlights.createAlbum(title: title, coverURL: cover, stories: chosen)
        saving = false
        if result != nil {
            Haptics.success()
            dismiss()
        } else {
            error = highlights.lastError ?? "Couldn't create highlight."
        }
    }
}
