import CoreGraphics

/// Shared bounds and axis decisions for enlarged-media navigation.
nonisolated enum WhisperPhotoPagingPolicy {
    static func index(_ proposed: Int, count: Int) -> Int? {
        count > 0 ? min(max(0, proposed), count - 1) : nil
    }

    static func isVertical(_ translation: CGSize) -> Bool {
        translation.width.isFinite && translation.height.isFinite
            && abs(translation.height) > abs(translation.width) * 1.25
    }

    static func clamp(_ proposed: CGSize, image: CGSize, viewport: CGSize, scale: CGFloat) -> CGSize {
        guard image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0,
              scale.isFinite, proposed.width.isFinite, proposed.height.isFinite else { return .zero }
        let fit = min(viewport.width / image.width, viewport.height / image.height)
        let x = max(0, (image.width * fit * max(1, scale) - viewport.width) / 2)
        let y = max(0, (image.height * fit * max(1, scale) - viewport.height) / 2)
        return CGSize(width: min(x, max(-x, proposed.width)), height: min(y, max(-y, proposed.height)))
    }
}
