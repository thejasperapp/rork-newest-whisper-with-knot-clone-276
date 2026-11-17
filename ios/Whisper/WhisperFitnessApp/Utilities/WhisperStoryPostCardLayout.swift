import Foundation

nonisolated enum WhisperStoryPostCardLayout {
    static func size(sticker: WhisperStorySticker, stageWidth: CGFloat) -> CGSize {
        guard let fraction = sticker.cardWidthFraction, fraction.isFinite,
              let aspect = sticker.mediaAspectRatio, aspect.isFinite, aspect > 0,
              stageWidth.isFinite, stageWidth > 0 else { return CGSize(width: 250, height: 312) }
        let width = stageWidth * min(0.94, max(0.3, fraction))
        let height = width / aspect
        let maxHeight = stageWidth * 16 / 9 * 0.72
        let factor = min(1, maxHeight / height)
        return CGSize(width: width * factor, height: height * factor)
    }
}
