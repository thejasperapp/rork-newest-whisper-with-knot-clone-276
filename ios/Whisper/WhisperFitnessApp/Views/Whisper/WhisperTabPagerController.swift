import SwiftUI
import UIKit

/// Hosts stay at viewport size. Only their compositing layers move during a drag;
/// the black stage occludes other retained pages, including in the 12-point gap.
final class WhisperTabPagerController: UIViewController {
    private(set) var hosts: [Int: UIHostingController<AnyView>] = [:]
    private var stages: [Int: UIView] = [:]
    private let shutter = UIView()
    weak var pager: WhisperTabPagingState?
    let renderID: UUID = UUID()
    var selection: Int = 0 {
        didSet { if oldValue != selection { hosts[oldValue]?.view.endEditing(true) } }
    }
    var insets: UIEdgeInsets = .zero
    var reduceMotion: Bool = false
    var isInteractive: Bool = true

    override func loadView() {
        view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        shutter.backgroundColor = .black
        shutter.isUserInteractionEnabled = false
        view.addSubview(shutter)
    }

    func updatePage(_ tab: Int, root: AnyView, background: UIColor) {
        loadViewIfNeeded()
        // Retained hosting controllers do not inherit the outer SwiftUI
        // environment. Install the same link routing inside each tab too.
        let root = AnyView(root.modifier(WhisperNotesLinkHandling(handlesIncomingLinks: false)))
        if let host = hosts[tab] {
            host.rootView = root
            host.view.backgroundColor = background
            return
        }
        let host = UIHostingController(rootView: root)
        // Native container safe areas remain available to nested navigation.
        // Keyboard obstruction is forwarded by the outer SwiftUI layout once.
        host.safeAreaRegions = .container
        host.view.backgroundColor = background
        let stage = UIView(frame: view.bounds)
        stage.backgroundColor = background
        stage.clipsToBounds = true
        stage.layer.cornerCurve = .continuous
        stage.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addChild(host)
        view.insertSubview(stage, belowSubview: shutter)
        stage.addSubview(host.view)
        host.view.frame = stage.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.didMove(toParent: self)
        hosts[tab] = host
        stages[tab] = stage
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        shutter.frame = view.bounds
        for (tab, host) in hosts {
            guard let stage = stages[tab] else { continue }
            // Bounds and center stay fixed even when the presentation layer travels.
            if stage.bounds != view.bounds { stage.bounds = view.bounds }
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            if stage.center != center { stage.center = center }
            if host.view.frame != stage.bounds { host.view.frame = stage.bounds }
            let native = view.safeAreaInsets
            let extra = UIEdgeInsets(top: max(0, insets.top - native.top), left: max(0, insets.left - native.left),
                bottom: max(0, insets.bottom - native.bottom), right: max(0, insets.right - native.right))
            if host.additionalSafeAreaInsets != extra { host.additionalSafeAreaInsets = extra }
            // Let UIKit coalesce child layout. Forcing every retained SwiftUI
            // tree to lay out synchronously here multiplies scroll/chrome work.
        }
        renderPositions()
    }

    func renderPositions() {
        guard isViewLoaded else { return }
        let source = pager?.source
        let target = pager?.target
        let progress = pager?.progress ?? 0
        let moving = source != nil && target != nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Resting pages never leave the viewport or change their layout size.
        for (tab, stage) in stages {
            let participating = moving ? (source == tab || target == tab) : tab == selection
            if !participating { view.insertSubview(stage, belowSubview: shutter) }
            stage.layer.setAffineTransform(.identity)
            stage.layer.cornerRadius = 0
            stage.isUserInteractionEnabled = tab == selection && !moving && isInteractive
            stage.accessibilityElementsHidden = tab != selection || moving || !isInteractive
        }
        view.bringSubviewToFront(shutter)
        if moving, let source, let target {
            for tab in [target, source] {
                guard let stage = stages[tab], let pager else { continue }
                view.bringSubviewToFront(stage)
                stage.layer.setAffineTransform(CGAffineTransform(translationX: WhisperTabPagingState.offset(
                    isSource: tab == source, direction: pager.direction, progress: progress, width: view.bounds.width), y: 0))
                stage.layer.cornerRadius = reduceMotion ? 0 : WhisperTabPagingState.cornerRadius(progress: progress, width: view.bounds.width)
            }
        } else if let stage = stages[selection] {
            view.bringSubviewToFront(stage)
        }
        CATransaction.commit()
    }
}
