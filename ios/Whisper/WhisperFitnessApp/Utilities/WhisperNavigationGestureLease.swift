import UIKit

/// Scoped adapters must not fall through to an unguarded native pop when an editor is busy.
@MainActor
final class WhisperNavigationGestureLease {
    private final class Entry {
        weak var navigation: UINavigationController?
        let edgeEnabled: Bool
        let contentEnabled: Bool
        var owners: Set<UUID> = []
        init(_ navigation: UINavigationController) {
            self.navigation = navigation
            edgeEnabled = navigation.interactivePopGestureRecognizer?.isEnabled ?? false
            if #available(iOS 26.0, *) { contentEnabled = navigation.interactiveContentPopGestureRecognizer?.isEnabled ?? false }
            else { contentEnabled = false }
        }
    }
    private static var entries: [ObjectIdentifier: Entry] = [:]
    private let id = UUID()
    private var key: ObjectIdentifier?

    func acquire(_ navigation: UINavigationController) {
        let next = ObjectIdentifier(navigation)
        guard key != next else { return }
        release()
        let entry = Self.entries[next] ?? Entry(navigation)
        entry.owners.insert(id); Self.entries[next] = entry; key = next
        navigation.interactivePopGestureRecognizer?.isEnabled = false
        if #available(iOS 26.0, *) { navigation.interactiveContentPopGestureRecognizer?.isEnabled = false }
    }

    func release() {
        guard let key, let entry = Self.entries[key] else { self.key = nil; return }
        self.key = nil; entry.owners.remove(id)
        guard entry.owners.isEmpty else { return }
        entry.navigation?.interactivePopGestureRecognizer?.isEnabled = entry.edgeEnabled
        if #available(iOS 26.0, *) { entry.navigation?.interactiveContentPopGestureRecognizer?.isEnabled = entry.contentEnabled }
        Self.entries.removeValue(forKey: key)
    }
}
