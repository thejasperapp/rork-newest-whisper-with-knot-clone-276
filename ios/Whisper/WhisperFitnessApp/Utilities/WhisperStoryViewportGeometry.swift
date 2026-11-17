import CoreGraphics

/// Presentation-local rectangles; keyboard movement never resizes the Story document.
nonisolated struct WhisperStoryViewportGeometry: Equatable {
    let workspace: CGRect
    let controls: CGRect

    init(bounds: CGRect, safeFrame: CGRect, keyboardFrame: CGRect) {
        let safe = bounds.intersection(safeFrame)
        workspace = safe.isNull ? bounds : safe
        let keyboard = bounds.intersection(keyboardFrame)
        let hasDockedKeyboard = !keyboard.isNull && keyboard.height > 0
            && keyboard.maxY >= bounds.maxY - 1
            && keyboard.width >= bounds.width - 1
        let controlsBottom = hasDockedKeyboard ? min(workspace.maxY, keyboard.minY) : workspace.maxY
        controls = CGRect(x: workspace.minX, y: workspace.minY, width: workspace.width,
                          height: max(0, controlsBottom - workspace.minY))
    }
}
