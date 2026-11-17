import Foundation
import MediaPlayer

/// Bridges the system Apple Music player (`MPMusicPlayerController`) into
/// Whisper so the composer can surface "Now Playing" — what the user is
/// actually listening to right now, IG/Snap-style. When the user picks the
/// suggestion, we resolve it through iTunes Search to a `WhisperStoryMusic`
/// (with a 30s `previewURL`) so the rest of the music pipeline — bubble,
/// karaoke lyrics, story background — keeps working unchanged.
///
/// Why iTunes Search resolves it: `MPMediaItem.assetURL` points to a
/// DRM-protected library asset that can't be streamed inside a third-party
/// app, so we map the track → public preview clip instead. The displayed
/// metadata still comes straight from what the user is listening to.
@MainActor
@Observable
final class WhisperNowPlayingService {
    static let shared = WhisperNowPlayingService()

    /// Live snapshot of the system music player. Updated by KVO-style
    /// `MPMusicPlayerController` notifications.
    private(set) var nowPlayingTitle: String?
    private(set) var nowPlayingArtist: String?
    private(set) var nowPlayingArtworkURL: String?
    /// Apple Music catalog ID for the current track, surfaced directly by
    /// `MPMediaItem.playbackStoreID` when the song is streamed from the
    /// catalog. Lets us seed listen-along without a second iTunes lookup.
    private(set) var nowPlayingCatalogID: String?
    /// Current playhead in the system player at the moment of the last
    /// refresh. We stamp this onto the post so viewers can join the song
    /// at roughly the same spot — Instagram-style listen-along.
    private(set) var nowPlayingPlaybackTime: Double = 0
    /// Tracks whether the Apple Music player is currently playing (vs.
    /// paused/stopped) so the picker can hide the row when nothing's on.
    private(set) var isPlaying: Bool = false

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var observersStarted: Bool = false

    private init() {}

    /// Begin observing the system music player. Safe to call repeatedly —
    /// no-op after the first call. Call this when the picker appears.
    func start() {
        guard !observersStarted else {
            refresh()
            return
        }
        observersStarted = true
        let nc = NotificationCenter.default
        nc.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        nc.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        player.beginGeneratingPlaybackNotifications()
        refresh()
    }

    /// Refresh `nowPlayingTitle/Artist/ArtworkURL/isPlaying` from the
    /// system player. Public so the picker can re-poll on appear (some
    /// devices skip the first notification right after permission grant).
    func refresh() {
        let item = player.nowPlayingItem
        nowPlayingTitle = item?.title
        nowPlayingArtist = item?.artist
        // MPMediaItem artwork is an in-memory image, not a URL. We rely on
        // iTunes Search for the artwork URL when resolving to a preview,
        // so leave this nil here — the picker will display a fallback.
        nowPlayingArtworkURL = nil
        let storeID = item?.playbackStoreID
        nowPlayingCatalogID = (storeID?.isEmpty == false) ? storeID : nil
        nowPlayingPlaybackTime = player.currentPlaybackTime.isFinite
            ? max(0, player.currentPlaybackTime) : 0
        isPlaying = player.playbackState == .playing
    }

    /// Whether the picker has a now-playing row to render. Requires that
    /// the user is actively listening to something with both a title and
    /// an artist (otherwise the iTunes lookup would be unreliable).
    var hasNowPlaying: Bool {
        guard let t = nowPlayingTitle?.trimmingCharacters(in: .whitespaces),
              let a = nowPlayingArtist?.trimmingCharacters(in: .whitespaces),
              !t.isEmpty, !a.isEmpty else { return false }
        return isPlaying
    }

    /// Resolves the currently-playing song to a `WhisperStoryMusic` by
    /// searching iTunes Search for the same title/artist. Returns nil if
    /// nothing is playing or no preview exists in the public catalog.
    func resolveCurrentToStoryMusic() async -> WhisperStoryMusic? {
        guard let title = nowPlayingTitle?.trimmingCharacters(in: .whitespaces),
              let artist = nowPlayingArtist?.trimmingCharacters(in: .whitespaces),
              !title.isEmpty, !artist.isEmpty else { return nil }
        // Capture the playhead at the moment of the post so the viewer
        // starts the listen-along roughly where the poster is right now.
        let startSeconds = nowPlayingPlaybackTime
        let catalogID = nowPlayingCatalogID
        let term = "\(title) \(artist)"
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "media", value: "music"),
        ]
        guard let url = comps.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(WhisperStoryMusicResponse.self, from: data)
            // Prefer an exact-artist match if one exists, otherwise take
            // the first result with a previewUrl.
            let exact = decoded.results.first {
                ($0.artistName ?? "").lowercased() == artist.lowercased() &&
                ($0.previewUrl != nil)
            }
            let pick = exact ?? decoded.results.first { $0.previewUrl != nil }
            guard let t = pick,
                  let preview = t.previewUrl,
                  let resolvedTitle = t.trackName,
                  let resolvedArtist = t.artistName else { return nil }
            let art = t.artworkUrl100?
                .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            return WhisperStoryMusic(
                id: "\(t.trackId)",
                title: resolvedTitle,
                artist: resolvedArtist,
                artworkURL: art,
                previewURL: preview,
                startSeconds: startSeconds,
                catalogID: catalogID ?? "\(t.trackId)"
            )
        } catch {
            return nil
        }
    }

    /// Requests Media Library authorization. Returns true if granted.
    /// Picker should call this before showing the now-playing row — on
    /// first launch the user hasn't approved access yet.
    @discardableResult
    func ensureAuthorized() async -> Bool {
        let current = MPMediaLibrary.authorizationStatus()
        if current == .authorized { return true }
        if current == .denied || current == .restricted { return false }
        return await withCheckedContinuation { cont in
            MPMediaLibrary.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }
}
