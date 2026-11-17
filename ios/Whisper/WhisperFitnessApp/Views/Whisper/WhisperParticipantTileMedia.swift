import SwiftUI

/// Shared bounds-owned media surface for meeting and group-call participant tiles.
struct WhisperParticipantTileMedia: View {
    let participant: WhisperLiveRTCService.ParticipantInfo
    let isSelf: Bool
    let avatarURL: URL?
    let avatarSize: CGFloat
    let trackNonce: Int
    var videoHidden: Bool = false
    var fit: Bool = false

    var body: some View {
        Color(white: 0.09)
            .overlay {
                if participant.hasVideo && !videoHidden {
                    WhisperLiveVideoView(
                        source: isSelf ? .local : .remote(peerId: participant.peerId),
                        mirror: isSelf && WhisperLiveRTCService.shared.isFrontCamera && !participant.isScreenSharing,
                        fit: participant.isScreenSharing || fit,
                        trackNonce: trackNonce
                    )
                } else {
                    WhisperVideoAvatarBackdrop(username: participant.name, imageURL: avatarURL, avatarSize: avatarSize)
                }
            }
            .clipped()
    }
}
