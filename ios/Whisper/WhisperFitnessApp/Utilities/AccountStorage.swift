import Foundation
import UserNotifications

enum AccountStorage {
    private(set) static var generation: UUID = UUID()
    private static let currentUserIDKey = "accountStorage_currentUserID"
    private static var _currentUserID: String = {
        UserDefaults.standard.string(forKey: "accountStorage_currentUserID") ?? "guest"
    }()

    static var currentUserID: String {
        get { _currentUserID }
        set {
            let changed = _currentUserID.lowercased() != newValue.lowercased()
            if changed {
                let reminders = UserDefaults.standard.stringArray(forKey: key("knotReminderIdentifiers")) ?? []
                let center = UNUserNotificationCenter.current()
                center.removePendingNotificationRequests(withIdentifiers: reminders)
                center.removeDeliveredNotifications(withIdentifiers: reminders)
                removeObject(forKey: "knotReminderIdentifiers")
                WhisperMessageCache.clear(owner: _currentUserID)
                WhisperKnotOriginalStore.clear(owner: _currentUserID)
                WhisperKnotPersonaStore.shared.reset()
                NotificationCenter.default.post(name: Notification.Name("WhisperMeetingAccountWillChange"), object: nil)
                generation = UUID()
                WhisperWidgetSync.clearAccountState()
                WhisperExternalRouteStore.shared.accountWillChange(to: newValue)
            }
            _currentUserID = newValue
            UserDefaults.standard.set(newValue, forKey: currentUserIDKey)
            if changed {
                let newOwner = newValue.lowercased()
                let notificationGeneration = generation
                Task {
                    let center = UNUserNotificationCenter.current()
                    let pending = await center.pendingNotificationRequests()
                    guard notificationGeneration == generation else { return }
                    let obsolete = pending.map(\.identifier).filter {
                        ($0.hasPrefix("jasper-calendar:") && !$0.hasPrefix("jasper-calendar:\(newOwner):"))
                        || ($0.hasPrefix("knot-reminder:") && !$0.hasPrefix("knot-reminder:\(newOwner):"))
                    }
                    center.removePendingNotificationRequests(withIdentifiers: obsolete)
                    let delivered = await center.deliveredNotifications()
                    guard notificationGeneration == generation else { return }
                    center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter {
                        $0.hasPrefix("knot-reminder:") && !$0.hasPrefix("knot-reminder:\(newOwner):")
                    })
                }
                WhisperInAppBrowser.shared.dismissForAccountChange()
                WhisperCalendarService.shared.resetForAccountChange()
                WhisperMeetingService.shared.resetMeetingList()
                WhisperBookmarkService.shared.resetForAccountChange()
                WhisperImageCache.removeAll()
                WhisperWavePosterCache.shared.reset()
                WhisperUserService.shared.rehydrateForCurrentAccount()
                WhisperFollowService.shared.resetForCurrentAccount()
                WhisperStoryService.shared.resetForCurrentAccount()
                WhisperStoryDraftService.shared.reloadForCurrentAccount()
                WhisperAccountStatusService.shared.resetForCurrentAccount()
                WhisperPhoneService.shared.resetForCurrentAccount()
                WhisperContactsService.shared.resetForCurrentAccount()
                WhisperMentionsService.shared.stop()
                WhisperNutritionRemoteService.shared.stopRealtimeSync()
                WhisperBackendService.shared.resetMessageAccount()
                WhisperGroupChatService.shared.reloadForCurrentAccount()
                WhisperAlgorithmPreferences.shared.reloadForCurrentAccount()
                WhisperDearEmberService.shared.reloadForCurrentAccount()
                WhisperQuickReplyStore.shared.reloadForCurrentAccount()
                WhisperDMPrivacyService.shared.reloadForCurrentAccount()
                WhisperWhisperLinkService.shared.resetForAccountChange()
                JasperConnectClient.shared.accountDidChange()
                JasperCoachConnect.shared.wipeAll()
            }
        }
    }

    static func key(_ base: String) -> String {
        guard _currentUserID != "guest" else { return base }
        return "\(_currentUserID)_\(base)"
    }

    static func set(_ value: Any, forKey base: String) {
        UserDefaults.standard.set(value, forKey: key(base))
    }

    static func data(forKey base: String) -> Data? {
        UserDefaults.standard.data(forKey: key(base))
    }

    static func string(forKey base: String) -> String? {
        UserDefaults.standard.string(forKey: key(base))
    }

    static func integer(forKey base: String) -> Int {
        UserDefaults.standard.integer(forKey: key(base))
    }

    static func double(forKey base: String) -> Double {
        UserDefaults.standard.double(forKey: key(base))
    }

    static func bool(forKey base: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(base))
    }

    static func object(forKey base: String) -> Any? {
        UserDefaults.standard.object(forKey: key(base))
    }

    static func removeObject(forKey base: String) {
        UserDefaults.standard.removeObject(forKey: key(base))
    }

    static func hasCompletedOnboarding() -> Bool {
        bool(forKey: "hasCompletedOnboarding")
    }

    static func setOnboardingCompleted(_ completed: Bool) {
        set(completed, forKey: "hasCompletedOnboarding")
    }

    /// Nukes EVERY UserDefaults key tied to a real account so a fresh sign-up
    /// can never inherit the previous user's local cache.
    ///
    /// Removes:
    ///   - every key namespaced with `<oldUserID>_` (per-account storage)
    ///   - every Whisper / Whisper / Jasper scoped key written via raw
    ///     `UserDefaults.standard.set(_:forKey:)` (these are NOT namespaced
    ///     and would otherwise leak across accounts)
    ///   - a fixed list of well-known global keys (saved profile, onboarding
    ///     flag, Apple credential id, leaderboard username cache, etc.)
    ///
    /// Device-bound values (APNs token) are intentionally NOT removed — they
    /// belong to the device, get re-registered on next sign-in, and clearing
    /// them would just trigger an extra round-trip.
    static func wipeAllAccountData(forUserID oldUserID: String?, preservingSavedData: Bool = false) {
        WhisperKnotPersonaStore.shared.reset()
        if let oldUserID { WhisperMessageCache.clear(owner: oldUserID); WhisperKnotOriginalStore.clear(owner: oldUserID) }
        if !preservingSavedData, let oldUserID { WhisperStoryDraftService.removeSavedMedia(for: oldUserID) }
        WhisperWidgetSync.clearAccountState()
        let defaults = UserDefaults.standard
        let snapshot = defaults.dictionaryRepresentation()
        for key in snapshot.keys {
            if key == "whisper.apnsToken" || key == "whisper.voipToken" { continue }
            // Durable partner consent belongs to its UUID, not the active login.
            // Its credential stays in Keychain; private runtime data is still reset.
            let connectionPrefixes = ["jasper_connect_meta_v2_", "jasper_coach_tokens_meta_v2_"]
            if connectionPrefixes.contains(where: { prefix in
                key.hasPrefix(prefix) && UUID(uuidString: String(key.dropFirst(prefix.count))) != nil
            }) { continue }
            // Owner-qualified deny records are security decisions, not caches.
            // Preserve failed-revocation IDs so signing out cannot bypass review.
            if key.hasPrefix("jasper_coach_revoked_v2_") ||
               key.hasPrefix("jasper_coach_pending_revoke_v1_") {
                continue
            }
            // Per-account namespaced keys ("<uid>_<base>").
            if let uid = oldUserID,
               uid != "guest",
               !uid.isEmpty,
               key.hasPrefix("\(uid)_") {
                if !preservingSavedData { defaults.removeObject(forKey: key) }
                continue
            }
            // Global Whisper / Whisper / Jasper caches written without the
            // AccountStorage namespacing — drop anything that could carry
            // user-specific data across accounts. This INCLUDES the
            // `whisper.thought.*` IG-Notes cache: if account A posted a
            // thought and then account B signs in on the same device,
            // leaving the cache behind makes account B's bubble inherit
            // account A's text until / unless the server overwrites it.
            // Since the new user may have no remote thought at all, the
            // safe move is to wipe and let `refreshFromServer()` hydrate.
            if key.hasPrefix("whisper.") ||
               key.hasPrefix("whisper_") ||
               key.hasPrefix("jasper_") ||
               key.hasPrefix("jasper.") ||
               key.hasPrefix("ember_") ||
               key.hasPrefix("ember.") {
                defaults.removeObject(forKey: key)
            }
        }
        let fixed = [
            "savedUserProfile",
            "hasCompletedOnboarding",
            "hasCompletedWalkthrough",
            "notificationSetupComplete",
            "appleUserIdentifier",
            "leaderboard_username",
            "userFirstLoginDate",
            "dashboardWidgetOrder",
            "userFitnessProfile",
        ]
        for k in fixed { defaults.removeObject(forKey: k) }
        defaults.synchronize()
    }

    static func clearAccountData() {
        let keys = [
            "hasCompletedOnboarding",
            "notificationSetupComplete",
            "hasCompletedWalkthrough",
            "userFirstLoginDate",
            "workoutSessionHistory",
            "dashboardWidgetOrder",
            "journalEntries",
            "periodTrackingLogs",
            "jasper_nutrition_meals",
            "jasper_nutrition_goals",
            "jasper_nutrition_water",
            "jasper_nutrition_water_date",
            "savedWorkoutPrograms",
            "savedMobilityPrograms",
            "userFitnessProfile",
            "notificationPreferences",
            "smartNotificationsEnabled",
            "checkInStreak",
            "weeklyResultsLastShownWeek",
            "completedWorkoutsToday",
            "completedWorkoutsDate",
            "dashboardPreferences",
            "jasper_achievements",
            "summerEvent_joined",
            "summerEvent_joinDate",
            "summerEvent_workoutsCompleted",
            "summerEvent_challenges",
            "summerEvent_beachStreak",
            "summerEvent_lastBeachWorkout",
            "summerEvent_dismissedPopup",
            "summerEvent_blitzRuns",
            "summerEvent_blitzMinutes",
            "summerEvent_blitzRunCount",
            "summerEvent_blitzStreak",
            "summerEvent_lastBlitzRun",
            "jasper_friends",
            "jasper_friend_requests",
            "jasper_sent_requests",
            "jasper_diet_plans",
            "jasper_macro_survey",
        ]
        for k in keys {
            removeObject(forKey: k)
        }
    }
}
