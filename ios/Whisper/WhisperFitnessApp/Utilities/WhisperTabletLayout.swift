import SwiftUI

/// Matches the website's viewport breakpoints, not the physical device's screen size.
nonisolated struct WhisperTabletLayout: Equatable {
    let width: CGFloat
    let isPad: Bool
    let fullBleed: Bool
    var hasSidebar: Bool { isPad && width >= 1024 && !fullBleed }
    var hasRightRail: Bool { isPad && width >= 1280 && !fullBleed }
    var hasBottomBar: Bool { !isPad || width < 1024 }
    var contentWidth: CGFloat {
        guard isPad, !fullBleed else { return width }
        return min(640, max(0, width - (hasSidebar ? 260 : 0) - (hasRightRail ? 320 : 0) - (width >= 640 ? 32 : 0)))
    }
}

private struct WhisperBottomBarKey: EnvironmentKey { static let defaultValue: Bool = true }
extension EnvironmentValues {
    var whisperHasBottomBar: Bool {
        get { self[WhisperBottomBarKey.self] }
        set { self[WhisperBottomBarKey.self] = newValue }
    }
}
