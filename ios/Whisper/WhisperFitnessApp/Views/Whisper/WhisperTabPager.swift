import SwiftUI
import UIKit

/// One container owns all tab render trees. Inactive pages remain laid out behind
/// an opaque stage, rather than parking NavigationStacks outside the window.
struct WhisperTabPager: UIViewControllerRepresentable {
    let pages: [Int: AnyView]
    let selection: Int
    let pager: WhisperTabPagingState
    let insets: EdgeInsets
    let isInteractive: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIViewController(context: Context) -> WhisperTabPagerController {
        WhisperTabPagerController()
    }

    func updateUIViewController(_ controller: WhisperTabPagerController, context: Context) {
        controller.selection = selection
        controller.insets = UIEdgeInsets(top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing)
        controller.reduceMotion = reduceMotion
        controller.isInteractive = isInteractive
        controller.pager = pager
        pager.renderOwner = controller.renderID
        pager.renderPages = { [weak controller] in controller?.renderPositions() }
        pager.adoptSelection = { [weak controller] tab in controller?.selection = tab }
        for tab in WhisperRootTabSwipePolicy.order {
            guard let content = pages[tab] else { continue }
            let active = isInteractive && selection == tab && pager.source == nil && !WhisperAccountTransition.shared.isActive
            var environment = context.environment
            environment.whisperRootChromeActive = active
            let root = AnyView(WhisperHeaderShelfScope(content: content, isSelected: selection == tab)
                .environment(\.self, environment))
            controller.updatePage(tab, root: root, background: tab == 1 ? .black : UIColor(WhisperTheme.surface(scheme)))
        }
        controller.view.setNeedsLayout()
        controller.renderPositions()
    }

    static func dismantleUIViewController(_ controller: WhisperTabPagerController, coordinator: ()) {
        if controller.pager?.renderOwner == controller.renderID {
            controller.pager?.renderPages = nil
            controller.pager?.adoptSelection = nil
            controller.pager?.renderOwner = nil
        }
        controller.pager = nil
    }
}
