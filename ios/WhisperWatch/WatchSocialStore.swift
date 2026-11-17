import Foundation
import SwiftUI
import WatchConnectivity

/// One DM thread row, mirrored from the iPhone (same JSON the widgets read).
nonisolated struct WatchThread: Codable, Hashable, Identifiable {
    let user: String
    let preview: String
    let when: Double
    let fromMe: Bool
    let unread: Bool
    var userID: String? = nil
    var avatar: String? = nil

    var id: String { userID ?? user }
}

nonisolated struct WatchStoryAuthor: Codable, Hashable, Identifiable {
    let name: String
    var userID: String? = nil
    var avatar: String? = nil

    var id: String { userID ?? name }
}

/// One upcoming shared-calendar event.
nonisolated struct WatchEvent: Codable, Hashable, Identifiable {
    let title: String
    let when: Double
    let type: String
    var host: String? = nil
    var link: Bool = false

    var id: String { "\(title)-\(when)" }
}

/// One active coaching client.
nonisolated struct WatchClient: Codable, Hashable, Identifiable {
    let name: String
    var userID: String? = nil
    var avatar: String? = nil
    var since: Double? = nil

    var id: String { userID ?? name }
}

/// Whisper's AI rides the legacy @ember DM account — the wrist always
/// shows Jasper.
func watchDisplayName(_ raw: String) -> String {
    raw.lowercased() == "ember" ? "jasper" : raw
}

/// Receives the iPhone app's compact SOCIAL snapshot over WatchConnectivity
/// (application context — always the latest payload, delivered even when
/// this app was closed) and persists it so the wrist renders instantly on
/// the next launch.
@MainActor
@Observable
final class WatchSocialStore: NSObject, WCSessionDelegate {
    var unread: Int = 0
    var threads: [WatchThread] = []
    var storyAuthors: [WatchStoryAuthor] = []
    var storyCount: Int = 0
    var followers: Int = 0
    var following: Int = 0
    var activityCount: Int = 0
    var activityPreview: String = ""
    var thought: String = ""
    var events: [WatchEvent] = []
    var clients: [WatchClient] = []
    var isCoach: Bool = false
    var lastSynced: Date? = nil

    var hasEverSynced: Bool { lastSynced != nil }

    private static let cacheKey = "whisper_watch_snapshot"

    override init() {
        super.init()
        if let cached = UserDefaults.standard.data(forKey: Self.cacheKey) {
            applySerialized(cached, persist: false)
        }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Payload handling

    /// Applies a plist-serialized payload (the Sendable-safe form the
    /// nonisolated delegate hands across the actor boundary).
    private func applySerialized(_ data: Data, persist: Bool) {
        guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let payload = obj as? [String: Any] else { return }
        apply(payload)
        if persist {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private func apply(_ payload: [String: Any]) {
        // Application context is a complete replacement, never a merge with the previous account.
        unread = 0; storyCount = 0; followers = 0; following = 0; activityCount = 0
        isCoach = false; activityPreview = ""; thought = ""; lastSynced = nil
        threads = []; storyAuthors = []; events = []; clients = []
        guard payload["reset"] as? Bool != true, let owner = payload["owner"] as? String, !owner.isEmpty else { return }
        unread = payload["unread"] as? Int ?? unread
        storyCount = payload["storyCount"] as? Int ?? storyCount
        followers = payload["followers"] as? Int ?? followers
        following = payload["following"] as? Int ?? following
        activityCount = payload["activityCount"] as? Int ?? activityCount
        isCoach = payload["isCoach"] as? Bool ?? isCoach
        activityPreview = payload["activityPreview"] as? String ?? activityPreview
        thought = payload["thought"] as? String ?? thought
        if let t = payload["syncedAt"] as? Double, t > 0 {
            lastSynced = Date(timeIntervalSince1970: t)
        }
        if let data = payload["threads"] as? Data,
           let rows = try? JSONDecoder().decode([WatchThread].self, from: data) {
            threads = rows
        }
        if let data = payload["storyAuthors"] as? Data,
           let rows = try? JSONDecoder().decode([WatchStoryAuthor].self, from: data) {
            storyAuthors = rows
        }
        if let data = payload["calendarEvents"] as? Data,
           let rows = try? JSONDecoder().decode([WatchEvent].self, from: data) {
            let cutoff = Date().timeIntervalSince1970 - 30 * 60
            events = rows.filter { $0.when > cutoff }.sorted { $0.when < $1.when }
        }
        if let data = payload["coachClients"] as? Data,
           let rows = try? JSONDecoder().decode([WatchClient].self, from: data) {
            clients = rows
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // A context can be waiting from before this launch — apply it.
        let context = session.receivedApplicationContext
        guard !context.isEmpty,
              let data = try? PropertyListSerialization.data(fromPropertyList: context, format: .binary, options: 0) else {
            return
        }
        Task { @MainActor in
            self.applySerialized(data, persist: true)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: applicationContext, format: .binary, options: 0) else {
            return
        }
        Task { @MainActor in
            self.applySerialized(data, persist: true)
        }
    }
}
