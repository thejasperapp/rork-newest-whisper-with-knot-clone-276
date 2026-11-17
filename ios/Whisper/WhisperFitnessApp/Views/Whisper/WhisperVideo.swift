import SwiftUI
import AVKit

/// Lightweight helpers + view for inline video playback inside Whisper feed,
/// reels, and explore. Detects video URLs by file extension and streams them
/// with `AVPlayer`, auto-looping and muted-by-default so the feed behaves like
/// Instagram Reels.
nonisolated enum WhisperVideo {
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "m3u8", "webm", "hls"
    ]

    static func isVideo(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return true }
        // Supabase storage sometimes drops the extension into the query.
        let path = url.absoluteString.lowercased()
        return videoExtensions.contains { path.contains(".\($0)?") }
    }
}

/// Whether inline media on this surface may play. The root shell flips it
/// off for tabs that stay mounted but hidden (opacity 0), which never fire
/// `onDisappear`, so feed videos otherwise kept decoding behind other tabs.
struct WhisperMediaActiveKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var whisperMediaActive: Bool {
        get { self[WhisperMediaActiveKey.self] }
        set { self[WhisperMediaActiveKey.self] = newValue }
    }
}

/// Inline auto-looping video player. Pauses when scrolled offscreen via
/// `.onDisappear`, when the hosting surface goes inactive, or when the app
/// leaves the foreground; resumes on the way back. Tap toggles mute.
struct WhisperVideoView: View {
    let url: URL
    var autoplay: Bool = true
    var startsMuted: Bool = true
    var showsControls: Bool = false
    var showsMuteButton: Bool = true

    @Environment(\.whisperMediaActive) private var surfaceActive
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer = AVPlayer()
    @State private var looper: NSObjectProtocol?
    @State private var muted: Bool = true
    @State private var onScreen: Bool = false

    private var shouldPlay: Bool { autoplay && onScreen && surfaceActive && scenePhase == .active }

    var body: some View {
        ZStack {
            VideoPlayer(player: player)
                .disabled(!showsControls)
                .allowsHitTesting(showsControls)
            if !showsControls && showsMuteButton {
                // Mute toggle in bottom-right
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            Haptics.tap()
                            muted.toggle()
                            player.isMuted = muted
                        } label: {
                            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.black.opacity(0.55), in: Circle())
                                .padding(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear {
            onScreen = true
            prepareItemIfNeeded()
            applyPlayback()
        }
        .onDisappear {
            onScreen = false
            player.pause()
        }
        .onChange(of: shouldPlay) { _, _ in applyPlayback() }
        .onChange(of: url) { _, _ in
            player.replaceCurrentItem(with: nil)
            prepareItemIfNeeded()
            applyPlayback()
        }
    }

    /// Reuses the existing item when the card re-mounts for the same URL so
    /// scrolling back does not re-download and restart the clip.
    private func prepareItemIfNeeded() {
        if let current = (player.currentItem?.asset as? AVURLAsset)?.url, current == url { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = startsMuted
        muted = startsMuted
        player.actionAtItemEnd = .none
        if let l = looper {
            NotificationCenter.default.removeObserver(l)
        }
        let target = player
        looper = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            // Only fires while playing, so looping never wakes a paused clip.
            target.seek(to: .zero)
            target.play()
        }
    }

    private func applyPlayback() {
        if shouldPlay {
            if player.timeControlStatus != .playing { player.play() }
        } else {
            player.pause()
        }
    }
}
