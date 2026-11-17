import CoreGraphics

/// The rounded foreground reveals an unmoving, undimmed predecessor.
nonisolated enum WhisperBackRevealStyle {
    static func progress(translation: CGFloat, width: CGFloat) -> CGFloat {
        guard translation.isFinite, width.isFinite, width > 0 else { return 0 }
        return min(1, max(0, translation / width))
    }
    static func radius(topInset: CGFloat, progress: CGFloat) -> CGFloat {
        let radius: CGFloat = topInset >= 59 ? 55 : (topInset >= 47 ? 47 : (topInset > 24 ? 41 : 18))
        return radius * min(1, max(0, progress) * 6)
    }
    static func predecessorOffset(width: CGFloat, progress: CGFloat) -> CGFloat {
        0
    }
    static func scrim(progress: CGFloat) -> CGFloat { 0 }
}
