import SwiftUI
import UIKit

/// Scroll compaction is separate from visibility: capture owners can still
/// hide and lock navigation without a scroll callback bringing it back.
@Observable
@MainActor
final class WhisperTabBarVisibility {
    static let shared = WhisperTabBarVisibility()
    var isHidden: Bool = false
    private(set) var isCollapsed: Bool = false

    func collapse() {
        guard !isLocked, !isHidden else { return }
        isCollapsed = true
    }

    func expand() { isCollapsed = false }
    /// A full-screen layer (the story camera) OWNS the screen — while it's
    /// locked, scroll surfaces and tab switches can't bring the bar back.
    private(set) var isLocked: Bool = false

    private init() {}

    func set(hidden: Bool) {
        if isLocked && !hidden { return }
        guard isHidden != hidden else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isHidden = hidden
        }
    }

    /// Hide the bar and refuse every re-show until `unlock()`.
    func lockHidden() {
        isLocked = true
        set(hidden: true)
    }

    /// Release the lock and bring the bar back.
    func unlock() {
        isLocked = false
        expand()
        set(hidden: false)
    }
}

/// Root-only scroll tracking shelves local headers and compacts bottom tabs.
/// Inactive mounted pages and programmatic scrolls cannot change navigation.
private struct WhisperHidesTabBarOnScroll: ViewModifier {
    var reservesHeaderSpace: Bool = true
    var scrollsUnderStatusBar: Bool = false
    @Environment(\.whisperRootChromeActive) private var isActive
    @Environment(\.whisperHeaderShelf) private var shelf
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var userScrolling: Bool = false
    @State private var travel: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .contentMargins(.top, (reservesHeaderSpace ? (shelf?.height ?? 0) : 0) + (scrollsUnderStatusBar ? WhisperSafeArea.top : 0), for: .scrollContent)
            .ignoresSafeArea(.container, edges: scrollsUnderStatusBar ? .top : [])
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                min(max(0, geo.contentOffset.y + geo.contentInsets.top), max(0, geo.contentSize.height + geo.contentInsets.top + geo.contentInsets.bottom - geo.containerSize.height))
            } action: { oldValue, newValue in
                if isActive { shelf?.updateOverlap(newValue) }
                let enabled = isActive && !voiceOver && userScrolling
                shelf?.update(old: oldValue, new: newValue, enabled: enabled)
                guard enabled else { return }
                if newValue <= 1 {
                    travel = 0
                    WhisperTabBarVisibility.shared.expand()
                } else {
                    let delta = newValue - oldValue
                    if delta.sign != travel.sign { travel = 0 }
                    travel += delta
                    if travel < -10 {
                        WhisperTabBarVisibility.shared.expand()
                        travel = 0
                    } else if travel > 18 {
                        WhisperTabBarVisibility.shared.collapse()
                        travel = 0
                    }
                }
            }
            .onScrollPhaseChange { _, phase in
                userScrolling = phase == .interacting || phase == .decelerating
                if !userScrolling { shelf?.resetTravel(); travel = 0 }
            }
    }
}

private struct WhisperRootChromeActiveKey: EnvironmentKey {
    static let defaultValue: Bool = true
}
extension EnvironmentValues {
    var whisperRootChromeActive: Bool {
        get { self[WhisperRootChromeActiveKey.self] }
        set { self[WhisperRootChromeActiveKey.self] = newValue }
    }
}

extension View {
    /// Shelves the local header and collapses root tabs during user scrolling.
    func whisperHidesTabBarOnScroll(reservesHeaderSpace: Bool = true, scrollsUnderStatusBar: Bool = false) -> some View {
        modifier(WhisperHidesTabBarOnScroll(reservesHeaderSpace: reservesHeaderSpace, scrollsUnderStatusBar: scrollsUnderStatusBar))
    }

    /// Pins bottom-overlay content (the Jasper docks) right above the
    /// custom tab bar, regardless of how the host view's safe area
    /// resolved. Some hosts (NavigationStack roots) swallow the tab bar's
    /// `safeAreaInset`, so a fixed padding either floats too high or hides
    /// the pill underneath the bar. This modifier MEASURES where the host's
    /// bottom edge actually sits on screen and pads exactly the difference.
    func whisperPinnedAboveTabBar() -> some View {
        modifier(WhisperPinnedAboveTabBar())
    }
}

/// Compact chrome retains a full 44-point hit row and unchanged icon sizes.
enum WhisperTabBarMetrics {
    static let verticalPadding: CGFloat = 6
    static let barHeight: CGFloat = 44 + verticalPadding * 2 + 4

    /// The window's own bottom safe inset (home indicator) — UIKit truth,
    /// independent of how far SwiftUI propagated any `safeAreaInset`.
    @MainActor
    static var windowBottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }
}

private struct WhisperPinnedAboveTabBar: ViewModifier {
    @Environment(\.whisperHasBottomBar) private var hasBottomBar
    /// Live distance from the host view's bottom edge to the physical
    /// screen bottom (0 until the first layout pass lands).
    @State private var baseGap: CGFloat = 0

    func body(content: Content) -> some View {
        let barVisible = hasBottomBar && !WhisperTabBarVisibility.shared.isHidden
        let home = WhisperTabBarMetrics.windowBottomInset
        // Where the dock's bottom edge should sit, measured from the
        // physical screen bottom.
        let wanted: CGFloat = barVisible
            ? home + WhisperTabBarMetrics.barHeight + 6
            : home + 12
        let pad = max(6, wanted - baseGap)
        content
            .padding(.bottom, pad)
            .background {
                // Probe: bottom-aligned overlays keep their bottom edge on
                // the host's bottom edge no matter the padding, so this
                // measurement never feeds back into itself.
                GeometryReader { geo in
                    let maxY = geo.frame(in: .global).maxY
                    Color.clear
                        .onChange(of: maxY, initial: true) { _, newValue in
                            let height = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.bounds.height ?? newValue
                            let gap = height - newValue
                            if abs(gap - baseGap) > 0.5 {
                                baseGap = max(0, gap)
                            }
                        }
                }
            }
    }
}
