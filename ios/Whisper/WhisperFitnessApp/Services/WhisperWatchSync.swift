import Foundation
import WatchConnectivity

/// Ships the same compact SOCIAL snapshot the widgets read — DM threads,
/// story authors, activity, follower counts, the thought, shared-calendar
/// events, and the coach's client roster — to the Apple Watch app over
/// WatchConnectivity. `updateApplicationContext` keeps only the latest
/// payload and delivers it even when the watch app is closed, which is
/// exactly the freshness model the wrist needs.
@MainActor
final class WhisperWatchSync: NSObject, WCSessionDelegate {
    static let shared = WhisperWatchSync()

    private var pendingPush = false

    private override init() { super.init() }

    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default
    }

    /// Pushes the current App Group snapshot to the watch — activates the
    /// session lazily on first use and retries after activation completes.
    func pushSoon() {
        guard let s = session else { return }
        if s.delegate !== self { s.delegate = self }
        if s.activationState == .activated {
            push(over: s)
        } else {
            pendingPush = true
            s.activate()
        }
    }

    private func push(over s: WCSession) {
        guard s.activationState == .activated else { return }
        guard let d = WhisperWidgetSnapshotDefaults(suiteName: WhisperWidgetSync.suite) else { return }
        var payload: [String: Any] = [
            "owner": d.string(forKey: "whisper_session_user_id") ?? "",
            "reset": d.string(forKey: "whisper_session_user_id") == nil,
            "unread": d.integer(forKey: "whisper_unread_dm_count"),
            "storyCount": d.integer(forKey: "whisper_active_story_count"),
            "followers": d.integer(forKey: "whisper_followers"),
            "following": d.integer(forKey: "whisper_following"),
            "activityCount": d.integer(forKey: "whisper_activity_count"),
            "isCoach": d.bool(forKey: "whisper_is_coach"),
            "syncedAt": Date().timeIntervalSince1970
        ]
        if let threads = d.data(forKey: "whisper_top_threads") { payload["threads"] = threads }
        if let authors = d.data(forKey: "whisper_story_authors") { payload["storyAuthors"] = authors }
        if let events = d.data(forKey: "whisper_calendar_events") { payload["calendarEvents"] = events }
        if let clients = d.data(forKey: "whisper_coach_clients") { payload["coachClients"] = clients }
        if let preview = d.string(forKey: "whisper_activity_preview"), !preview.isEmpty {
            payload["activityPreview"] = preview
        }
        if let thought = d.string(forKey: "whisper_my_thought"), !thought.isEmpty {
            payload["thought"] = thought
        }
        do {
            try s.updateApplicationContext(payload)
        } catch {
            // Not paired / watch app not installed — nothing to do.
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            guard self.pendingPush else { return }
            self.pendingPush = false
            if let s = self.session { self.push(over: s) }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so pushes keep flowing after the user switches watches.
        session.activate()
    }
}
