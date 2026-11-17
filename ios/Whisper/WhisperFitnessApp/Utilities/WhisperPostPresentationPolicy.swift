import Foundation

nonisolated enum WhisperPostPresentationPolicy {
    static func usesMediaCard(kind: WhisperPostKind, isReel: Bool) -> Bool { kind == .grid || isReel }
    static func opensWavePlayer(isReel: Bool, commentID: String?, focusReply: Bool) -> Bool {
        isReel && commentID == nil && !focusReply
    }
}
