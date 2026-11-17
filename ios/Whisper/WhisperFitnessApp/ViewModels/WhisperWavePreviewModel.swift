import AVFoundation
import Observation

/// Rebuilds only the playback composition. Editing never exports or re-encodes source videos.
@MainActor @Observable
final class WhisperWavePreviewModel {
    let player: AVPlayer = AVPlayer()
    var time: Double = 0
    var isPlaying: Bool = false
    var isPreparing: Bool = false
    var error: String?
    var audioDuration: Double = 0
    /// The chosen sound as a readable local file, for beat analysis.
    var musicLocalURL: URL?
    private var operation: UUID = UUID()
    private var task: Task<Void, Never>?
    private var observer: Any?
    private var statusObserver: NSKeyValueObservation?
    private var cachedMusic: (remote: String, local: URL)?
    private var length: Double = 0
    private var isVisible: Bool = true
    private var isSeeking: Bool = false
    private var seekOperation: UUID = UUID()
    private var refreshPending: Bool = false

    func rebuild(clips: [WhisperWaveClip], music: WhisperStoryMusic?, volume: Double, muted: Bool, filter: SnapFilter = .none, adjustments: WhisperWaveColorAdjustments = .init(), effect: WhisperAREffect = .none, fx: WhisperWaveFXSetting? = nil, texts: [WaveTextOverlay] = [], captions: WhisperWaveCaptions? = nil) {
        task?.cancel()
        operation = UUID()
        let token = operation
        isPreparing = true
        error = nil
        player.pause()
        task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard let self, self.isVisible else { return }
            var local: URL?
            if let music {
                if let cached = self.cachedMusic, cached.remote == music.previewURL { local = cached.local }
                else if let remote = URL(string: music.previewURL) {
                    local = await WhisperWaveStudio.localCopy(of: remote)
                    guard token == self.operation, !Task.isCancelled else {
                        if let local, local != remote { try? FileManager.default.removeItem(at: local) }
                        return
                    }
                    self.clearMusic()
                    if let local { self.cachedMusic = (music.previewURL, local) }
                }
                guard let local else { self.fail("Couldn't load this sound. Choose it again or remove it.", token: token); return }
                self.audioDuration = await WhisperWaveClipStudio.duration(of: local)
                if self.musicLocalURL != local { self.musicLocalURL = local }
            } else {
                self.audioDuration = 0
                if self.musicLocalURL != nil { self.musicLocalURL = nil }
            }
            guard !Task.isCancelled, token == self.operation else { return }
            let built = await WhisperWaveClipStudio.makeComposition(clips, musicURL: local, musicStart: music?.startSeconds ?? 0, musicVolume: Float(volume), muteOriginal: muted, filter: filter, adjustments: adjustments, effect: effect, fx: fx, quality: .preview, texts: texts, captions: captions)
            guard token == self.operation, !Task.isCancelled, self.isVisible else { return }
            guard let built else { self.fail("Preview couldn't load every clip, background and sound. Replace missing media or retry; your edit is safe.", token: token); return }
            let item = AVPlayerItem(asset: built.asset)
            item.videoComposition = built.video
            item.audioMix = built.audio
            self.length = WhisperWaveTimeline.duration(clips)
            self.statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let failed = item.status == .failed
                Task { @MainActor [weak self] in
                    guard failed else { return }
                    self?.fail("A video frame or person cutout couldn't render. Retry, or adjust Face / Green Screen. Your original clips are safe.", token: token)
                }
            }
            self.player.replaceCurrentItem(with: item)
            self.player.isMuted = false
            self.player.actionAtItemEnd = .pause
            self.isPreparing = false
            if self.observer == nil {
                self.observer = self.player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 15, preferredTimescale: 600), queue: .main) { [weak self] value in
                    Task { @MainActor [weak self] in
                        guard let self, self.isVisible, !self.isPreparing, !self.isSeeking else { return }
                        self.time = value.seconds.isFinite ? value.seconds : 0
                        if self.time >= self.length - 0.04 && self.isPlaying { self.seek(0) }
                    }
                }
            }
            self.seek(min(self.time, max(0, self.length - 0.05)))
        }
    }

    func seek(_ seconds: Double) {
        time = min(max(0, seconds), max(0, length - 0.02))
        let token = operation
        seekOperation = UUID()
        let seekToken = seekOperation
        isSeeking = true
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: CMTime(seconds: 1.0 / 30, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 1.0 / 30, preferredTimescale: 600)) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, seekToken == self.seekOperation else { return }
                self.isSeeking = false
                guard finished, token == self.operation, self.isVisible, self.isPlaying, !self.isPreparing else { return }
                self.player.play()
            }
        }
    }

    /// Redraws the paused frame through the compositor after a live-grade
    /// change. Reassigning a copy of the video composition is what makes
    /// AVPlayer re-render at the current time; playback redraws on its own.
    /// Coalesced to one redraw per ~30 ms so a fast dial drag never queues.
    func refreshFrame() {
        guard !isPreparing, !isPlaying, error == nil, player.currentItem != nil, !refreshPending else { return }
        refreshPending = true
        let token = operation
        Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
            guard let self else { return }
            self.refreshPending = false
            guard token == self.operation, self.isVisible, !self.isPlaying, let item = self.player.currentItem, let composition = item.videoComposition else { return }
            item.videoComposition = composition.mutableCopy() as? AVVideoComposition
        }
    }

    func togglePlayback() {
        guard !isPreparing, error == nil else { return }
        isPlaying.toggle()
        if isPlaying { player.play() } else { player.pause() }
    }

    func pause() { isPlaying = false; player.pause() }
    func activate() { isVisible = true }
    func stop() {
        isVisible = false
        operation = UUID()
        task?.cancel(); task = nil
        seekOperation = UUID(); isSeeking = false
        pause()
        if let observer { player.removeTimeObserver(observer) }
        observer = nil; statusObserver = nil
        player.replaceCurrentItem(with: nil)
        musicLocalURL = nil
        clearMusic()
    }

    private func fail(_ message: String, token: UUID) {
        guard token == operation, isVisible else { return }
        isPreparing = false; error = message; pause()
    }

    private func clearMusic() {
        if let cachedMusic, cachedMusic.local.absoluteString != cachedMusic.remote { try? FileManager.default.removeItem(at: cachedMusic.local) }
        cachedMusic = nil
    }
}
