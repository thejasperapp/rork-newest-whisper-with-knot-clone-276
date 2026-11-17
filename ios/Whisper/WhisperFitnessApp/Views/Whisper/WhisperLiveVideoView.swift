import SwiftUI
import WebRTC

/// A bounds-owned WebRTC renderer. Video never participates in the parent layout.
struct WhisperLiveVideoView: View {
    enum Source { case local, remote(peerId: String) }
    let source: Source
    var mirror: Bool = false
    var fit: Bool = false
    var trackNonce: Int = 0

    var body: some View {
        Color.black.overlay {
            VideoContainer(source: source, mirror: mirror, fit: fit, trackNonce: trackNonce)
                .allowsHitTesting(false)
        }.clipped()
    }
}

private struct VideoContainer: UIViewRepresentable {
    let source: WhisperLiveVideoView.Source
    let mirror: Bool
    let fit: Bool
    let trackNonce: Int

    final class Coordinator {
        var track: RTCVideoTrack?
        func bind(_ next: RTCVideoTrack?, to host: RendererHost) {
            guard track !== next else { return }
            track?.remove(host.renderer)
            host.renderer.renderFrame(nil)
            track = next
            next?.add(host.renderer)
        }
    }

    final class RendererHost: UIView {
        #if arch(arm64)
        let renderer = RTCMTLVideoView(frame: .zero)
        #else
        let renderer = RTCEAGLVideoView(frame: .zero)
        #endif
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            clipsToBounds = true
            addSubview(renderer)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            // Bounds/center remain valid even when the child is mirrored.
            renderer.bounds = CGRect(origin: .zero, size: bounds.size)
            renderer.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> RendererHost {
        let host = RendererHost(frame: .zero)
        updateUIView(host, context: context)
        return host
    }
    func updateUIView(_ host: RendererHost, context: Context) {
        #if arch(arm64)
        host.renderer.videoContentMode = fit ? .scaleAspectFit : .scaleAspectFill
        #else
        host.renderer.contentMode = fit ? .scaleAspectFit : .scaleAspectFill
        #endif
        host.renderer.transform = mirror ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        let service = WhisperLiveRTCService.shared
        let track: RTCVideoTrack?
        switch source {
        case .local: track = service.localVideoTrack
        case .remote(let peerId): track = service.remoteVideoTracks[peerId]
        }
        context.coordinator.bind(track, to: host)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RendererHost, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
    static func dismantleUIView(_ host: RendererHost, coordinator: Coordinator) {
        coordinator.bind(nil, to: host)
    }
}
