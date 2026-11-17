import SwiftUI
import LiveKit

/// Renders a LiveKit `VideoTrack` inside SwiftUI. Wraps LiveKit's
/// UIKit `VideoView` and re-binds the track whenever the LiveKit
/// service publishes a new local / remote track.
struct WhisperCallVideoView: UIViewRepresentable {
    enum Source { case local, remote }

    let source: Source
    var mirror: Bool = false

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.layoutMode = .fill
        view.mirrorMode = mirror ? .mirror : .auto
        attachTrack(to: view)
        // Re-bind on track changes (remote join, camera enable/disable).
        if source == .remote {
            WhisperLiveKitService.shared.onRemoteVideoTrackChanged = { [weak view] track in
                guard let view else { return }
                view.track = track
            }
        }
        return view
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        uiView.mirrorMode = mirror ? .mirror : .auto
        attachTrack(to: uiView)
    }

    static func dismantleUIView(_ uiView: VideoView, coordinator: ()) {
        uiView.track = nil
    }

    private func attachTrack(to view: VideoView) {
        let track: VideoTrack? = source == .local
            ? WhisperLiveKitService.shared.localVideoTrack
            : WhisperLiveKitService.shared.remoteVideoTrack
        view.track = track
    }
}
