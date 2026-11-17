import SwiftUI

/// Instagram's "Add audio" browser, Whisper-built — the REAL audio selector
/// for waves (the old picker was the story music search, i.e. Apple's
/// catalog for everything). Five shelves:
///
/// - FOR YOU — your saved sounds first, then what's trending on Whisper,
///   then catalog picks.
/// - TRENDING — Whisper sounds ranked by how many waves wear them.
/// - SAVED — your favorites (the bookmark on any row or sound page).
/// - ORIGINAL — every wave's own audio, reusable as a sound (TikTok's
///   "original sound" loop; credits the creator on every platform).
/// - SONGS — the iTunes catalog search (30-second previews), as before.
///
/// Every row previews on tap of the play glyph, saves with the bookmark, and
/// USES the sound on tap of the row — the recorder / composer receives a
/// `WhisperStoryMusic` and the publish path writes it onto the shared caption
/// meta wire exactly like before.
struct WhisperAudioPickerSheet: View {
    /// The sound currently attached (shows the "Remove" row).
    var current: WhisperStoryMusic? = nil
    let onPick: (WhisperStoryMusic) -> Void
    var onRemove: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Shelf = .forYou
    @State private var query: String = ""
    @State private var backend = WhisperBackendService.shared
    @State private var saved = WhisperSavedSounds.shared
    @State private var catalog = WhisperStoryMusicService.shared
    @State private var player = WhisperStoryMusicPlayer.shared
    @State private var searchTask: Task<Void, Never>?

    enum Shelf: String, CaseIterable, Identifiable {
        case forYou = "For you"
        case trending = "Trending"
        case saved = "Saved"
        case original = "Original"
        case songs = "Songs"
        var id: String { rawValue }
    }

    private static let brand: LinearGradient = WhisperBrandGradient.diagonal

    /// Every loaded wave — the pool Whisper sounds are counted from.
    private var pool: [WhisperPost] {
        backend.posts
            .map { row in
                WhisperRootView.mapRowToPost(row, fallbackUsername: backend.postAuthorProfiles[row.user_id]?.username)
            }
            .filter { $0.isReel || $0.mediaURLs.contains(where: { WhisperVideo.isVideo($0) }) }
    }

    /// TRENDING — Whisper sounds ranked by the waves wearing them, then the
    /// chart's most-played songs fill the shelf. The room is small right now;
    /// a shelf of only already-used sounds is three rows deep, so the songs
    /// people are actually playing carry it until Whisper sounds do.
    private var trending: [(sound: WhisperStoryMusic, count: Int)] {
        var seen = Set<String>()
        var out: [(WhisperStoryMusic, Int)] = []
        for t in WhisperWaveSound.trending(in: pool, limit: 40) where !seen.contains(t.sound.id) {
            seen.insert(t.sound.id)
            out.append((t.sound, t.count))
        }
        for song in catalog.trending where !seen.contains(song.id) {
            seen.insert(song.id)
            out.append((song, WhisperWaveSound.waves(using: song, in: pool).count))
        }
        return out.map { (sound: $0.0, count: $0.1) }
    }

    private var originals: [(sound: WhisperStoryMusic, count: Int)] {
        var seen = Set<String>()
        var out: [(WhisperStoryMusic, Int)] = []
        for post in pool.sorted(by: { $0.likes > $1.likes }) {
            let s = WhisperWaveSound.original(of: post)
            guard !s.previewURL.isEmpty, !seen.contains(s.id) else { continue }
            seen.insert(s.id)
            out.append((s, WhisperWaveSound.waves(using: s, in: pool).count))
        }
        return out.map { (sound: $0.0, count: $0.1) }
    }

    /// FOR YOU — your saved sounds first, then the POPULAR MUSIC people are
    /// playing right now (the chart's top dozen), then Whisper's own trending
    /// sounds, then the rest of the chart.
    private var forYou: [(sound: WhisperStoryMusic, count: Int)] {
        var seen = Set<String>()
        var out: [(WhisperStoryMusic, Int)] = []
        for s in saved.sounds.prefix(4) where !seen.contains(s.id) {
            seen.insert(s.id)
            out.append((s, WhisperWaveSound.waves(using: s, in: pool).count))
        }
        for song in catalog.trending.prefix(12) where !seen.contains(song.id) {
            seen.insert(song.id)
            out.append((song, WhisperWaveSound.waves(using: song, in: pool).count))
        }
        for t in WhisperWaveSound.trending(in: pool, limit: 40) where !seen.contains(t.sound.id) {
            seen.insert(t.sound.id)
            out.append((t.sound, t.count))
        }
        for song in catalog.trending.dropFirst(12) where !seen.contains(song.id) {
            seen.insert(song.id)
            out.append((song, 0))
        }
        return out.map { (sound: $0.0, count: $0.1) }
    }

    private var savedRows: [(sound: WhisperStoryMusic, count: Int)] {
        saved.sounds.map { (sound: $0, count: WhisperWaveSound.waves(using: $0, in: pool).count) }
    }

    private var songRows: [(sound: WhisperStoryMusic, count: Int)] {
        let list = query.trimmingCharacters(in: .whitespaces).isEmpty ? catalog.trending : catalog.results
        return list.map { (sound: $0, count: WhisperWaveSound.waves(using: $0, in: pool).count) }
    }

    /// The active shelf, filtered by the search box (Songs searches the catalog).
    private var rows: [(sound: WhisperStoryMusic, count: Int)] {
        let base: [(sound: WhisperStoryMusic, count: Int)]
        switch tab {
        case .forYou: base = forYou
        case .trending: base = trending
        case .saved: base = savedRows
        case .original: base = originals
        case .songs: return songRows
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { $0.sound.title.lowercased().contains(q) || $0.sound.artist.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            shelves
            if let current {
                currentRow(current)
            }
            list
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            if catalog.trending.isEmpty { await catalog.loadTrending() }
            if backend.posts.isEmpty { await backend.fetchPosts() }
        }
        .onChange(of: query) { _, q in
            guard tab == .songs else { return }
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await catalog.search(q)
            }
        }
        .onDisappear { player.stop() }
    }

    // MARK: - Chrome

    private var header: some View {
        ZStack {
            Text("Add audio")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            HStack {
                Spacer()
                Button {
                    Haptics.tap()
                    player.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            TextField(tab == .songs ? "Search songs" : "Search sounds", text: $query)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    if tab == .songs { Task { await catalog.search(query) } }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var shelves: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Shelf.allCases) { shelf in
                    Button {
                        Haptics.tap()
                        withAnimation(.easeOut(duration: 0.15)) { tab = shelf }
                        if shelf == .songs, !query.isEmpty { Task { await catalog.search(query) } }
                    } label: {
                        Text(shelf.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tab == shelf ? .black : .white)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(tab == shelf ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.10)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// The sound already on the wave — with Remove.
    private func currentRow(_ sound: WhisperStoryMusic) -> some View {
        HStack(spacing: 12) {
            artwork(sound, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("On this wave")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.5))
                Text(WhisperWaveSound.label(sound))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let onRemove {
                Button {
                    Haptics.tap()
                    onRemove()
                    dismiss()
                } label: {
                    Text("Remove")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if tab == .songs && catalog.isSearching {
                    ProgressView().tint(.white).padding(.top, 30)
                } else if tab == .songs, let error = catalog.lastError, rows.isEmpty {
                    VStack(spacing: 12) {
                        Text("Songs couldn't load").font(.headline)
                        Text(error).font(.subheadline).multilineTextAlignment(.center)
                        Button("Try again") {
                            Task {
                                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { await catalog.loadTrending() }
                                else { await catalog.search(query) }
                            }
                        }.frame(minHeight: 44)
                    }.foregroundStyle(.white).padding(24)
                } else if rows.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.sound.id) { index, row in
                        soundRow(row.sound, count: row.count, rank: tab == .trending ? index + 1 : nil)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            WhisperMeetDoodle(symbol: tab == .saved ? "bookmark" : "waveform", height: 120)
                .environment(\.colorScheme, .dark)
            Text(emptyTitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            Text(emptyBody)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var emptyTitle: String {
        switch tab {
        case .saved: return "No saved sounds yet"
        case .songs: return query.isEmpty ? "No songs available yet" : "No songs found"
        case .original: return "No original sounds yet"
        default: return "Nothing here yet"
        }
    }

    private var emptyBody: String {
        switch tab {
        case .saved: return "Tap the bookmark on any sound — here, on a wave, or on a sound page — to keep it for later."
        case .songs: return "Try an artist or a song title."
        case .original: return "Every wave posted with its own audio becomes a reusable sound."
        default: return "Sounds show up as waves land on Whisper."
        }
    }

    private func soundRow(_ sound: WhisperStoryMusic, count: Int, rank: Int?) -> some View {
        let playing = player.nowPlayingID == sound.id && player.isPlaying
        let isOriginal = WhisperWaveSound.isOriginal(sound)
        return HStack(spacing: 12) {
            Button {
                guard !sound.previewURL.isEmpty else { return }
                Haptics.tap()
                player.toggle(sound)
            } label: {
                ZStack {
                    artwork(sound, size: 52)
                    if !sound.previewURL.isEmpty {
                        Circle()
                            .fill(.black.opacity(playing ? 0.55 : 0.35))
                            .frame(width: 28, height: 28)
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Pause preview" : "Play preview")

            Button {
                Haptics.success()
                player.stop()
                onPick(sound)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let rank, rank <= 3 {
                            Text("#\(rank)")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .frame(height: 18)
                                .background(Self.brand, in: Capsule())
                        }
                        Text(isOriginal ? "Original sound" : sound.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        if isOriginal {
                            WhisperAvatar(username: sound.artist, size: 14, ring: false)
                        }
                        Text(sound.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                        if count > 0 {
                            Text("· \(count == 1 ? "1 wave" : "\(count.formatted()) waves")")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                saved.toggle(sound)
            } label: {
                Image(systemName: saved.isSaved(sound) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 44)
                    .contentShape(.rect)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(saved.isSaved(sound) ? "Remove from saved" : "Save sound")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(playing ? Color.white.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func artwork(_ sound: WhisperStoryMusic, size: CGFloat) -> some View {
        ZStack {
            if let art = sound.artworkURL, let url = URL(string: art) {
                WhisperCachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: artFallback(sound)
                    }
                }
            } else {
                artFallback(sound)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
    }

    private func artFallback(_ sound: WhisperStoryMusic) -> some View {
        ZStack {
            Self.brand.opacity(0.85)
            if WhisperWaveSound.isOriginal(sound) {
                WhisperAvatar(username: sound.artist, size: 28, ring: false)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}
