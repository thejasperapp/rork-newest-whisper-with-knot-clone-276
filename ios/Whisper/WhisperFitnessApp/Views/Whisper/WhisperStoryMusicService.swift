import Foundation
import AVFoundation
import MusicKit

/// Music attachment for stories. Uses Apple's free iTunes Search API
/// (no key required) — returns 30-second `previewUrl` mp3s, artwork, title,
/// and artist for songs with an available preview.
nonisolated struct WhisperStoryMusic: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: String?
    let previewURL: String
    /// User-chosen start offset in seconds (0…30) so the picked slice plays
    /// during the story rather than always the iTunes default preview slice.
    var startSeconds: Double = 0
    /// Apple Music catalog song ID. When present *and* the viewer has an
    /// active Apple Music subscription, the player streams the full track
    /// via `ApplicationMusicPlayer` (Instagram-style listen-along). When
    /// nil — or when the viewer isn't subscribed — playback falls back to
    /// the 30-second iTunes `previewURL` clip so the bubble still plays.
    var catalogID: String? = nil
    var durationSeconds: Double? = nil
    var previewDuration: Double? = nil

    var storySelection: WhisperStoryMusicSelection? {
        durationSeconds.map { WhisperStoryMusicSelection(startSeconds: startSeconds, durationSeconds: $0, availableDuration: previewDuration ?? 30) }
    }

    var storyPreview: WhisperStoryMusic {
        var copy = self
        copy.catalogID = nil
        return copy
    }
}

nonisolated struct WhisperStoryMusicTrack: Decodable, Sendable {
    let trackId: Int
    let trackName: String?
    let artistName: String?
    let artworkUrl100: String?
    let previewUrl: String?
}

nonisolated struct WhisperStoryMusicResponse: Decodable, Sendable {
    let results: [WhisperStoryMusicTrack]
}

/// One entry of Apple's most-played chart feed (RSS JSON) — ids only; the
/// 30-second previews come from a follow-up lookup.
nonisolated struct WhisperAppleChartEntry: Decodable, Sendable {
    let id: String
}

nonisolated struct WhisperAppleChartFeed: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        let results: [WhisperAppleChartEntry]
    }
    let feed: Body
}

/// A lenient lookup row — the lookup endpoint can interleave collection
/// rows, so every field is optional and non-songs are skipped.
nonisolated struct WhisperAppleLookupTrack: Decodable, Sendable {
    let wrapperType: String?
    let trackId: Int?
    let trackName: String?
    let artistName: String?
    let artworkUrl100: String?
    let previewUrl: String?
}

nonisolated struct WhisperAppleLookupResponse: Decodable, Sendable {
    let results: [WhisperAppleLookupTrack]
}

/// Free iTunes Search API client. Endpoints are public and rate-limited per IP.
@MainActor
@Observable
final class WhisperStoryMusicService {
    static let shared = WhisperStoryMusicService()

    var trending: [WhisperStoryMusic] = []
    var results: [WhisperStoryMusic] = []
    var isSearching: Bool = false
    var lastError: String?

    private init() {}

    /// The catalog's POPULAR shelf — what people are actually playing right
    /// now. Apple's most-played chart (the public RSS JSON, no key) gives the
    /// ranked ids; one lookup call adds the 30-second previews the chart
    /// doesn't carry. The old "top hits" search was a keyword match, not a
    /// chart — it surfaced songs literally titled "Top Hits". Falls back to
    /// that search only if the chart can't be reached.
    func loadTrending() async {
        isSearching = true
        defer { isSearching = false }
        if let chart = await Self.fetchMostPlayed(limit: 50), !chart.isEmpty {
            trending = chart
            return
        }
        await search("top hits", into: \.trending)
    }

    nonisolated private static func fetchMostPlayed(limit: Int) async -> [WhisperStoryMusic]? {
        guard let feedURL = URL(string: "https://rss.applemarketingtools.com/api/v2/us/music/most-played/\(limit)/songs.json") else {
            return nil
        }
        do {
            let (feedData, _) = try await URLSession.shared.data(from: feedURL)
            let feed = try JSONDecoder().decode(WhisperAppleChartFeed.self, from: feedData)
            let ids = feed.feed.results.map(\.id).filter { !$0.isEmpty }
            guard !ids.isEmpty else { return nil }

            var comps = URLComponents(string: "https://itunes.apple.com/lookup")!
            comps.queryItems = [
                URLQueryItem(name: "id", value: ids.joined(separator: ",")),
                URLQueryItem(name: "entity", value: "song"),
            ]
            guard let lookupURL = comps.url else { return nil }
            let (lookupData, _) = try await URLSession.shared.data(from: lookupURL)
            let decoded = try JSONDecoder().decode(WhisperAppleLookupResponse.self, from: lookupData)

            var byID: [String: WhisperStoryMusic] = [:]
            for t in decoded.results {
                guard t.wrapperType == nil || t.wrapperType == "track",
                      let trackId = t.trackId,
                      let preview = t.previewUrl,
                      let title = t.trackName,
                      let artist = t.artistName else { continue }
                let art = t.artworkUrl100?
                    .replacingOccurrences(of: "100x100bb", with: "600x600bb")
                byID["\(trackId)"] = WhisperStoryMusic(
                    id: "\(trackId)",
                    title: title,
                    artist: artist,
                    artworkURL: art,
                    previewURL: preview,
                    catalogID: "\(trackId)"
                )
            }
            // Keep the chart's own order — #1 first.
            return ids.compactMap { byID[$0] }
        } catch {
            return nil
        }
    }

    func search(_ term: String) async {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        await search(term, into: \.results)
    }

    private func search(_ term: String, into keyPath: ReferenceWritableKeyPath<WhisperStoryMusicService, [WhisperStoryMusic]>) async {
        lastError = nil
        isSearching = true
        defer { isSearching = false }
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "40"),
            URLQueryItem(name: "media", value: "music"),
        ]
        guard let url = comps.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(WhisperStoryMusicResponse.self, from: data)
            let mapped: [WhisperStoryMusic] = decoded.results.compactMap { t in
                guard let preview = t.previewUrl,
                      let title = t.trackName,
                      let artist = t.artistName else { return nil }
                // Up the artwork resolution from 100x100 → 600x600 in the
                // URL — iTunes returns the small one by default.
                let art = t.artworkUrl100?
                    .replacingOccurrences(of: "100x100bb", with: "600x600bb")
                return WhisperStoryMusic(
                    id: "\(t.trackId)",
                    title: title,
                    artist: artist,
                    artworkURL: art,
                    previewURL: preview,
                    catalogID: "\(t.trackId)"
                )
            }
            guard !Task.isCancelled else { return }
            self[keyPath: keyPath] = mapped
            lastError = nil
        } catch {
            guard !Task.isCancelled else { return }
            lastError = "Couldn't load songs. Check your connection and try again."
        }
    }
}

/// Tiny AVPlayer wrapper used by both the picker (preview-on-tap) and the
/// story viewer (background music for an open story).
@MainActor
@Observable
final class WhisperStoryMusicPlayer {
    /// App-wide player for POST music lines — one shared instance so two
    /// posts can never play over each other (story surfaces keep their own
    /// per-view players).
    static let shared = WhisperStoryMusicPlayer()

    private var player: AVPlayer?
    private var timeObserver: Any?
    var nowPlayingID: String?
    var isPlaying: Bool = false
    /// Current playhead in seconds (live-updated via a periodic observer).
    /// Drives the karaoke lyric sync on the thought lyrics sheet so the
    /// active line stays anchored to the actual audio rather than a free-
    /// running timer.
    var currentTime: Double = 0
    /// Duration of the loaded item in seconds (typically ~30 for iTunes
    /// previews). 0 until the AVPlayerItem reports a valid duration.
    var duration: Double = 0

    /// When true, the live `currentTime` is being driven by Apple Music's
    /// full-track player instead of the AVPlayer preview. Surface this in
    /// the UI so we can show a small "Listen on Apple Music" badge.
    var isListenAlong: Bool = false
    private let listenAlong = AppleMusicListenAlongPlayer.shared
    private var listenAlongPoll: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var playbackOperation: UUID = UUID()
    private var currentMusic: WhisperStoryMusic?
    private let listenAlongOwner: UUID = UUID()

    func play(_ music: WhisperStoryMusic) {
        if currentMusic == music, isListenAlong, listenAlong.isOwned(by: listenAlongOwner) {
            listenAlong.resume()
            isPlaying = true
            return
        }
        if currentMusic == music, player != nil {
            if let length = music.durationSeconds, currentTime >= music.startSeconds + length - 0.1 { return }
            player?.play()
            isPlaying = true
            return
        }
        stop()
        currentMusic = music
        let operation = playbackOperation
        // Try the Apple Music listen-along path first when we have a
        // catalog ID. Fall back to the AVPlayer preview clip on any miss
        // (no auth, no subscription, song not in catalog, network error).
        if let catalog = music.catalogID {
            listenAlong.claim(owner: listenAlongOwner)
            startupTask = Task { @MainActor in
                let ready = await listenAlong.ensureReady()
                guard !Task.isCancelled, operation == playbackOperation, listenAlong.isOwned(by: listenAlongOwner) else { return }
                let started = ready ? await listenAlong.play(catalogID: catalog, startSeconds: music.startSeconds, shouldContinue: { operation == self.playbackOperation }) : false
                guard !Task.isCancelled, operation == playbackOperation, listenAlong.isOwned(by: listenAlongOwner) else { return }
                if started {
                    removeTimeObserver()
                    player?.pause()
                    player = nil
                    nowPlayingID = music.id
                    isPlaying = true
                    isListenAlong = true
                    startListenAlongPolling()
                } else {
                    playPreview(music)
                }
            }
            return
        }
        playPreview(music)
    }

    /// AVPlayer preview-clip path — the original 30s playback that ships
    /// for songs without a catalog ID or viewers without an Apple Music
    /// subscription. Same behaviour as before the listen-along addition.
    private func playPreview(_ music: WhisperStoryMusic) {
        guard let url = URL(string: music.previewURL) else { return }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.volume = 1.0
        if let length = music.durationSeconds {
            item.forwardPlaybackEndTime = CMTime(seconds: music.startSeconds + length, preferredTimescale: 600)
        }
        removeTimeObserver()
        player?.pause()
        player = p
        currentMusic = music
        nowPlayingID = music.id
        isListenAlong = false
        if music.startSeconds > 0 {
            p.seek(to: CMTime(seconds: music.startSeconds, preferredTimescale: 600))
        }
        attachTimeObserver()
        p.play()
        isPlaying = true
    }

    /// Mirrors the Apple Music player's playhead onto `currentTime` so the
    /// karaoke lyric sync and on-screen progress UI stay one driver away
    /// from the audio source of truth.
    private func startListenAlongPolling() {
        listenAlongPoll?.cancel()
        listenAlongPoll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isListenAlong, self.listenAlong.isOwned(by: self.listenAlongOwner) else { return }
                self.currentTime = self.listenAlong.currentTime
                self.duration = self.listenAlong.duration
                self.isPlaying = self.listenAlong.isPlaying
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stop() {
        playbackOperation = UUID()
        startupTask?.cancel(); startupTask = nil
        currentMusic = nil
        removeTimeObserver()
        listenAlongPoll?.cancel()
        listenAlongPoll = nil
        if listenAlong.isOwned(by: listenAlongOwner) {
            listenAlong.stop()
        }
        isListenAlong = false
        player?.pause()
        player = nil
        nowPlayingID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    func toggle(_ music: WhisperStoryMusic) {
        if nowPlayingID == music.id && isPlaying {
            pause()
        } else {
            play(music)
        }
    }

    /// Pauses playback without tearing down the player — keeps the time
    /// observer alive so `currentTime` retains its value (lyrics freeze
    /// in place rather than jumping back to 0).
    func pause() {
        if startupTask != nil, !isListenAlong, player == nil {
            stop()
            return
        }
        if isListenAlong, listenAlong.isOwned(by: listenAlongOwner) {
            listenAlong.pause()
        }
        player?.pause()
        isPlaying = false
    }

    private func attachTimeObserver() {
        removeTimeObserver()
        guard let p = player else { return }
        let interval = CMTime(seconds: 0.08, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                guard self.player === p else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                if let music = self.currentMusic, let length = music.durationSeconds,
                   self.currentTime >= music.startSeconds + length - 0.1 {
                    self.pause()
                }
                if let d = self.player?.currentItem?.duration.seconds, d.isFinite, d > 0 {
                    self.duration = d
                }
            }
        }
    }

    private func removeTimeObserver() {
        if let obs = timeObserver, let p = player {
            p.removeTimeObserver(obs)
        }
        timeObserver = nil
    }
}
