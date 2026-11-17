import Foundation
import MusicKit
import MediaPlayer

/// Apple Music "listen-along" player. When the viewer has an active Apple
/// Music subscription, we stream the **full** track via `ApplicationMusicPlayer`
/// — so a Whisper music bubble plays the whole song with synced lyrics,
/// not a 30s preview clip. Falls back to a no-op (caller swaps in AVPlayer
/// preview) when authorization is missing or the user isn't subscribed.
///
/// Why this exists separately from `WhisperStoryMusicPlayer`:
/// `ApplicationMusicPlayer` is a system singleton with its own queue and
/// playhead. Wrapping it here keeps the existing AVPlayer preview path
/// untouched and lets the caller (`WhisperStoryMusicPlayer`) choose which
/// engine to use per-song depending on what we know about the track.
@MainActor
@Observable
final class AppleMusicListenAlongPlayer {
    static let shared = AppleMusicListenAlongPlayer()

    /// Whether the runtime has confirmed the user can play full Apple Music
    /// catalog content (auth granted + active subscription). Cached so the
    /// caller can branch without awaiting on every play call.
    private(set) var canPlayFullTracks: Bool = false
    /// The catalog ID currently loaded into the system music player —
    /// nil when nothing is playing through this engine.
    private(set) var nowPlayingCatalogID: String?
    private(set) var isPlaying: Bool = false
    /// Live playhead in seconds, sampled ~10×/sec while playing so the
    /// karaoke lyric sync can lock onto it just like the AVPlayer path.
    private(set) var currentTime: Double = 0
    /// Track duration in seconds once the catalog metadata resolves.
    private(set) var duration: Double = 0

    private let player = ApplicationMusicPlayer.shared
    private var pollTask: Task<Void, Never>?
    private var playOperation: UUID = UUID()
    private var ownerToken: UUID?
    private var resumeTask: Task<Void, Never>?

    func claim(owner: UUID) {
        if ownerToken != owner { stop(); ownerToken = owner }
    }
    func isOwned(by owner: UUID) -> Bool { ownerToken == owner }

    private init() {}

    /// Asks for MusicKit authorization (separate from the Media Library
    /// auth used by `WhisperNowPlayingService`) and re-checks subscription.
    /// Cheap to call repeatedly — short-circuits once authorized.
    @discardableResult
    func ensureReady() async -> Bool {
        let status: MusicAuthorization.Status
        switch MusicAuthorization.currentStatus {
        case .authorized:
            status = .authorized
        case .notDetermined:
            status = await MusicAuthorization.request()
        default:
            status = MusicAuthorization.currentStatus
        }
        guard status == .authorized else {
            canPlayFullTracks = false
            return false
        }
        do {
            let sub = try await MusicSubscription.current
            canPlayFullTracks = sub.canPlayCatalogContent
        } catch {
            canPlayFullTracks = false
        }
        return canPlayFullTracks
    }

    /// Plays the catalog track identified by `catalogID`, seeking to
    /// `startSeconds` first so listeners join at the same point Instagram-
    /// style. Returns false if anything failed — the caller should fall
    /// back to the AVPlayer preview clip in that case.
    @discardableResult
    func play(catalogID: String, startSeconds: Double, shouldContinue: () -> Bool = { true }) async -> Bool {
        guard canPlayFullTracks, !Task.isCancelled, shouldContinue() else { return false }
        let operation = UUID(); playOperation = operation
        func isCurrent() -> Bool { playOperation == operation && !Task.isCancelled && shouldContinue() }
        do {
            let request = MusicCatalogResourceRequest<Song>(
                matching: \.id,
                equalTo: MusicItemID(catalogID)
            )
            let response = try await request.response()
            guard isCurrent(), let song = response.items.first else { return false }
            duration = song.duration ?? 0
            player.queue = [song]
            try await player.prepareToPlay()
            guard isCurrent() else { if playOperation == operation { stop() }; return false }
            if startSeconds > 0.5 {
                player.playbackTime = startSeconds
            }
            try await player.play()
            guard isCurrent() else { if playOperation == operation { stop() }; return false }
            nowPlayingCatalogID = catalogID
            isPlaying = true
            startPolling()
            return true
        } catch {
            guard playOperation == operation else { return false }
            player.stop()
            nowPlayingCatalogID = nil
            isPlaying = false
            return false
        }
    }

    func pause() {
        resumeTask?.cancel()
        player.pause()
        isPlaying = false
    }

    func resume() {
        let operation = playOperation
        resumeTask?.cancel()
        resumeTask = Task {
            guard !Task.isCancelled, operation == playOperation else { return }
            do {
                try await player.play()
                guard !Task.isCancelled, operation == playOperation else { return }
                isPlaying = true
            } catch { if operation == playOperation { isPlaying = false } }
        }
    }

    func stop() {
        ownerToken = nil
        resumeTask?.cancel(); resumeTask = nil
        playOperation = UUID()
        pollTask?.cancel()
        pollTask = nil
        player.stop()
        nowPlayingCatalogID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    /// Samples `player.playbackTime` on a fast cadence so the karaoke
    /// sweep stays anchored to the real playhead without subscribing to
    /// Combine publishers (which carry MainActor edge cases).
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.currentTime = self.player.playbackTime
                self.isPlaying = self.player.state.playbackStatus == .playing
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
