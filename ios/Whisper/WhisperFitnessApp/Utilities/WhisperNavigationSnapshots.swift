import UIKit

/// Memory-only, weak-view snapshots captured before UIKit detaches a page.
/// Rendering detached SwiftUI layers can otherwise produce a blank surface.
@MainActor
final class WhisperNavigationSnapshots: NSObject {
    static let shared = WhisperNavigationSnapshots()
    private let images = NSMapTable<UIView, UIImage>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private var generation: UUID = AccountStorage.generation

    override init() {
        super.init()
        for name in [UIApplication.willResignActiveNotification, UIApplication.didReceiveMemoryWarningNotification, Notification.Name("WhisperMeetingAccountWillChange")] {
            NotificationCenter.default.addObserver(self, selector: #selector(clear), name: name, object: nil)
        }
    }

    @objc func clear() { images.removeAllObjects(); generation = AccountStorage.generation }

    func capture(_ view: UIView, key: UIView? = nil, account: UUID) {
        guard account == AccountStorage.generation, view.window?.isKeyWindow == true, !view.isHidden, view.alpha > 0.01,
              view.bounds.width > 40, view.bounds.height > 40,
              UIApplication.shared.applicationState == .active else { return }
        if generation != AccountStorage.generation { clear() }
        guard let image = Self.captureAttached(view) else { return }
        let cacheKey = key ?? view
        if images.object(forKey: cacheKey) == nil, images.count >= 12,
           let oldest = images.keyEnumerator().nextObject() as? UIView { images.removeObject(forKey: oldest) }
        images.setObject(image, forKey: cacheKey)
    }

    func image(for view: UIView) -> UIImage? {
        guard generation == AccountStorage.generation else { clear(); return nil }
        return images.object(forKey: view)
    }

    /// Never manufacture a successful navigation image from detached SwiftUI layers.
    static func captureAttached(_ view: UIView) -> UIImage? {
        guard let window = view.window, !view.isHidden, view.alpha > 0.01,
              view.bounds.width > 40, view.bounds.height > 40,
              view.convert(view.bounds, to: window).intersects(window.bounds) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(window.screen.scale, 2)
        var succeeded: Bool = false
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
            succeeded = view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        return succeeded ? image : nil
    }

    static func render(_ view: UIView, rect: CGRect? = nil) -> UIImage {
        let scope = rect ?? view.bounds
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(view.window?.screen.scale ?? 2, 2)
        return UIGraphicsImageRenderer(size: scope.size, format: format).image { context in
            context.cgContext.translateBy(x: -scope.minX, y: -scope.minY)
            // drawHierarchy includes SwiftUI's composited content and materials.
            if !view.drawHierarchy(in: view.bounds, afterScreenUpdates: false) {
                view.layer.render(in: context.cgContext)
            }
        }
    }
}
