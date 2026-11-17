import SwiftUI

/// Per-device bell follow for individual posts — when on, the user
/// gets a local banner for every new top-level reply on that thread.
/// Stored in `UserDefaults` so it survives relaunches without a
/// dedicated backend table.
@MainActor
@Observable
final class WhisperPostSubscriptionService {
    static let shared = WhisperPostSubscriptionService()

    private let key = "whisper.postSubscriptions.v1"
    private(set) var subscribed: Set<String> = []

    private init() {
        if let arr = UserDefaults.standard.array(forKey: key) as? [String] {
            subscribed = Set(arr.map { $0.lowercased() })
        }
    }

    func isSubscribed(_ postID: String) -> Bool {
        subscribed.contains(postID.lowercased())
    }

    /// Toggles the bell. Returns the new state.
    @discardableResult
    func toggle(_ postID: String) -> Bool {
        let key = postID.lowercased()
        if subscribed.contains(key) {
            subscribed.remove(key)
        } else {
            subscribed.insert(key)
        }
        UserDefaults.standard.set(Array(subscribed), forKey: self.key)
        return subscribed.contains(key)
    }
}
