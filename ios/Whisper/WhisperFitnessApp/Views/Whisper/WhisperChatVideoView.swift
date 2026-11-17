import SwiftUI
import AVKit

/// Tap-to-play chat attachment. Playback never starts while merely scrolling a thread.
struct WhisperChatVideoView: View {
    let url: URL
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer? = nil
    @State private var failed: Bool = false
    @State private var statusObservation: NSKeyValueObservation?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else {
                Button {
                    failed = false
                    let next = AVPlayer(url: url)
                    player = next
                    statusObservation = next.currentItem?.observe(\.status, options: [.initial, .new]) { item, _ in
                        let didFail = item.status == .failed
                        Task { @MainActor in
                            guard didFail, player === next else { return }
                            next.pause()
                            player = nil
                            failed = true
                            statusObservation = nil
                        }
                    }
                    next.play()
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "play.circle.fill").font(.system(size: 48))
                        Text(failed ? "Try video again" : "Play video").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 240, height: 300)
        .clipShape(.rect(cornerRadius: 18))
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { event in
            guard let item = event.object as? AVPlayerItem, item === player?.currentItem else { return }
            player?.pause()
            player = nil
            failed = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player?.pause() }
        }
        .onScrollVisibilityChange(threshold: 0.1) { visible in if !visible { player?.pause() } }
        .onDisappear { player?.pause(); player = nil; statusObservation = nil }
        .accessibilityLabel("Video attachment")
    }
}
