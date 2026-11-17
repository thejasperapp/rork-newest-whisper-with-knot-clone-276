import SwiftUI
import StoreKit

struct ReviewManager {
    private static let launchCountKey = "appLaunchCount"
    private static let lastReviewVersionKey = "lastReviewRequestVersion"
    private static let requiredLaunches = 5

    static func incrementLaunchCount() {
        let count = UserDefaults.standard.integer(forKey: launchCountKey)
        UserDefaults.standard.set(count + 1, forKey: launchCountKey)
    }

    static func shouldRequestReview() -> Bool {
        let count = UserDefaults.standard.integer(forKey: launchCountKey)
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let lastVersion = UserDefaults.standard.string(forKey: lastReviewVersionKey) ?? ""

        guard count >= requiredLaunches else { return false }
        guard currentVersion != lastVersion else { return false }

        UserDefaults.standard.set(currentVersion, forKey: lastReviewVersionKey)
        return true
    }
}
