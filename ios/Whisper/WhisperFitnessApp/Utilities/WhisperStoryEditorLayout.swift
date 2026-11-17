import CoreGraphics

/// Geometry inside the presentation's safe area. The footer never covers the media stage.
nonisolated struct WhisperStoryEditorLayout {
    let stage: CGRect
    let footer: CGRect

    init(viewport: CGSize) {
        let width = max(1, viewport.width)
        let height = max(1, viewport.height)
        let footerHeight: CGFloat = min(80, height * 0.25)
        let availableHeight = max(1, height - footerHeight - 4)
        let stageWidth = min(width, availableHeight * 9 / 16)
        let stageHeight = stageWidth * 16 / 9
        stage = CGRect(x: (width - stageWidth) / 2, y: 4, width: stageWidth, height: stageHeight)
        footer = CGRect(x: 0, y: height - footerHeight, width: width, height: footerHeight)
    }
}
