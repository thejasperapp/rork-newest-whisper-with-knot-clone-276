import CloudKit
import Foundation
import CryptoKit

@Observable
class CloudKitService {
    static let shared = CloudKitService()

    var iCloudAvailable: Bool = false
    var syncStatus: SyncStatus = .idle

    enum SyncStatus {
        case idle
        case syncing
        case synced
        case error(String)
    }

    /// Both simulator and on-device hosted previews may lack private iCloud
    /// permission. A matching bundle ID is not permission: verify the installed
    /// executable's signed CloudKit/container entitlements before constructing
    /// CKContainer, which can raise an Objective-C exception outside Swift catch.
    /// Fully entitled device installs retain the existing container and sync.
    /// Keep this lazy so AuthenticationService initialization cannot touch CloudKit.
    @ObservationIgnored private lazy var container: CKContainer? = {
        #if targetEnvironment(simulator)
        #if DEBUG
        print("[WhisperLaunch] private_icloud_unavailable simulator=true")
        #endif
        return nil
        #else
        guard Bundle.main.bundleIdentifier == "com.mydailywhisper.whisper" else {
            #if DEBUG
            print("[WhisperLaunch] private_icloud_unavailable hosted_identity=true")
            #endif
            return nil
        }
        let identifier = "iCloud.com.mydailywhisper.whisper"
        guard WhisperSignedEntitlements.permitsCloudKit(container: identifier) else {
            #if DEBUG
            print("[WhisperLaunch] private_icloud_unavailable signed_permission=false")
            #endif
            return nil
        }
        return CKContainer(identifier: identifier)
        #endif
    }()
    private let profileRecordType = "UserProfile"
    private let subscriptionRecordType = "SubscriptionData"
    private let workoutRecordType = "WorkoutHistory"
    private let periodRecordType = "PeriodTrackingData"
    private let userDataRecordType = "UserData"
    @ObservationIgnored private var foregroundRestore: Task<Void, Never>?
    private var foregroundGeneration: UUID?
    private var lastForegroundRestoreAttempt: Date?
    // Only confirmed uploads are remembered. Failed writes remain dirty; a
    // later local edit compares against the exact bytes that were uploaded.
    @ObservationIgnored private var uploadedBlobDigests: [String: Data] = [:]
    @ObservationIgnored private var backgroundSave: Task<Void, Never>?
    private var backgroundGeneration: UUID?

    private var privateDB: CKDatabase {
        get throws {
            guard let container else { throw CKError(.missingEntitlement) }
            return container.privateCloudDatabase
        }
    }

    func checkAccountStatus() async -> Bool {
        guard let container else {
            iCloudAvailable = false
            return false
        }
        do {
            let status = try await container.accountStatus()
            iCloudAvailable = status == .available
            return iCloudAvailable
        } catch {
            iCloudAvailable = false
            return false
        }
    }

    private func applyProfile(_ profile: UserProfile, to record: CKRecord, onboarded: Bool) {
        record["userID"] = profile.userID as CKRecordValue
        record["email"] = (profile.email ?? "") as CKRecordValue
        record["displayName"] = (profile.displayName ?? "") as CKRecordValue
        record["givenName"] = (profile.givenName ?? "") as CKRecordValue
        record["familyName"] = (profile.familyName ?? "") as CKRecordValue
        record["authProvider"] = profile.authProvider.rawValue as CKRecordValue
        record["isProUser"] = (profile.isProUser ? 1 : 0) as CKRecordValue
        record["joinDate"] = profile.joinDate as CKRecordValue
        record["hasCompletedProfileSetup"] = (profile.hasCompletedProfileSetup ? 1 : 0) as CKRecordValue
        record["gender"] = (profile.gender?.rawValue ?? "") as CKRecordValue
        record["weightLbs"] = (profile.weightLbs ?? 0) as CKRecordValue
        record["heightInches"] = (profile.heightInches ?? 0) as CKRecordValue
        record["fitnessGoal"] = (profile.fitnessGoal?.rawValue ?? "") as CKRecordValue
        record["profileImageURL"] = (profile.profileImageURL ?? "") as CKRecordValue
        if let dob = profile.dateOfBirth { record["dateOfBirth"] = dob as CKRecordValue }
        record["hasCompletedOnboarding"] = (onboarded ? 1 : 0) as CKRecordValue
    }

    @discardableResult
    func saveUserProfile(_ profile: UserProfile, onboarded snapshot: Bool? = nil) async -> Bool {
        let generation = AccountStorage.generation
        guard ownsStorage(profile.userID, generation: generation) else { return false }
        let onboarded = snapshot ?? AccountStorage.hasCompletedOnboarding()
        syncStatus = .syncing
        do {
            let recordID = CKRecord.ID(recordName: "profile_\(profile.userID)")
            let record: CKRecord
            do {
                record = try await privateDB.record(for: recordID)
            } catch {
                record = CKRecord(recordType: profileRecordType, recordID: recordID)
            }

            guard ownsStorage(profile.userID, generation: generation) else { return false }
            applyProfile(profile, to: record, onboarded: onboarded)
            try await privateDB.save(record)
            guard ownsStorage(profile.userID, generation: generation) else { return false }
            syncStatus = .synced
            return true
        } catch let ckError as CKError where ckError.code == .serverRecordChanged {
            guard ownsStorage(profile.userID, generation: generation) else { return false }
            if let serverRecord = ckError.serverRecord {
                applyProfile(profile, to: serverRecord, onboarded: onboarded)
                do {
                    try await privateDB.save(serverRecord)
                    guard ownsStorage(profile.userID, generation: generation) else { return false }
                    syncStatus = .synced
                    return true
                } catch {
                    guard ownsStorage(profile.userID, generation: generation) else { return false }
                    syncStatus = .error("Sync conflict resolved with error")
                }
            } else {
                syncStatus = .error("Sync conflict")
            }
        } catch {
            guard ownsStorage(profile.userID, generation: generation) else { return false }
            syncStatus = .error(error.localizedDescription)
        }
        return false
    }

    func fetchUserProfile(userID: String) async -> UserProfile? {
        guard let record = await fetchProfileRecord(userID: userID) else { return nil }
        return UserProfile.from(record: record)
    }

    private func fetchProfileRecord(userID: String) async -> CKRecord? {
        let predicate = NSPredicate(format: "userID == %@", userID)
        let query = CKQuery(recordType: profileRecordType, predicate: predicate)
        do {
            let (results, _) = try await privateDB.records(matching: query, resultsLimit: 1)
            for (_, result) in results {
                if let record = try? result.get() {
                    return record
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    func saveSubscriptionStatus(userID: String, isProUser: Bool, productID: String?, expirationDate: Date?) async {
        syncStatus = .syncing
        do {
            let recordID = CKRecord.ID(recordName: "sub_\(userID)")
            let record: CKRecord
            do {
                record = try await privateDB.record(for: recordID)
            } catch {
                record = CKRecord(recordType: subscriptionRecordType, recordID: recordID)
            }

            record["userID"] = userID as CKRecordValue
            record["isProUser"] = (isProUser ? 1 : 0) as CKRecordValue
            record["productID"] = (productID ?? "") as CKRecordValue
            if let exp = expirationDate {
                record["expirationDate"] = exp as CKRecordValue
            }
            record["lastUpdated"] = Date() as CKRecordValue

            try await privateDB.save(record)
            syncStatus = .synced
        } catch {
            syncStatus = .error(error.localizedDescription)
        }
    }

    func fetchSubscriptionStatus(userID: String) async -> Bool {
        do {
            let predicate = NSPredicate(format: "userID == %@", userID)
            let query = CKQuery(recordType: subscriptionRecordType, predicate: predicate)
            let (results, _) = try await privateDB.records(matching: query, resultsLimit: 1)
            if let first = results.first, let record = try? first.1.get() {
                return (record["isProUser"] as? Int ?? 0) == 1
            }
        } catch {}
        return false
    }

    func saveWorkoutSession(_ session: WorkoutSessionRecord, userID: String) async {
        do {
            let record = CKRecord(recordType: workoutRecordType)
            record["userID"] = userID as CKRecordValue
            record["dayName"] = session.dayName as CKRecordValue
            record["focus"] = session.focus as CKRecordValue
            record["duration"] = session.duration as CKRecordValue
            record["date"] = session.date as CKRecordValue
            record["averageHeartRate"] = session.averageHeartRate as CKRecordValue
            try await privateDB.save(record)
        } catch {}
    }

    func savePeriodLogs(_ logs: [PeriodLog], userID: String) async {
        syncStatus = .syncing
        do {
            let predicate = NSPredicate(format: "userID == %@", userID)
            let query = CKQuery(recordType: periodRecordType, predicate: predicate)
            let record: CKRecord

            let (results, _) = try await privateDB.records(matching: query, resultsLimit: 1)
            if let first = results.first, let existing = try? first.1.get() {
                record = existing
            } else {
                record = CKRecord(recordType: periodRecordType)
            }

            record["userID"] = userID as CKRecordValue
            if let data = try? JSONEncoder().encode(logs) {
                record["logsData"] = data as CKRecordValue
            }
            record["lastUpdated"] = Date() as CKRecordValue

            try await privateDB.save(record)
            syncStatus = .synced
        } catch {
            syncStatus = .error(error.localizedDescription)
        }
    }

    func fetchPeriodLogs(userID: String) async -> [PeriodLog]? {
        do {
            let predicate = NSPredicate(format: "userID == %@", userID)
            let query = CKQuery(recordType: periodRecordType, predicate: predicate)
            let (results, _) = try await privateDB.records(matching: query, resultsLimit: 1)
            if let first = results.first, let record = try? first.1.get() {
                if let data = record["logsData"] as? Data,
                   let logs = try? JSONDecoder().decode([PeriodLog].self, from: data) {
                    return logs
                }
            }
        } catch {}
        return nil
    }

    // MARK: - Comprehensive User Data Sync

    private let allSyncKeys: [(key: String, storageKey: String)] = [
        ("nutritionMeals", "jasper_nutrition_meals"),
        ("nutritionGoals", "jasper_nutrition_goals"),
        ("nutritionWater", "jasper_nutrition_water"),
        ("nutritionWaterDate", "jasper_nutrition_water_date"),
        ("workoutHistory", "workoutSessionHistory"),
        ("journalEntries", "journalEntries"),
        ("workoutPrograms", "savedWorkoutPrograms"),
        ("mobilityPrograms", "savedMobilityPrograms"),
        ("fitnessProfile", "userFitnessProfile"),
        ("dashboardWidgetOrder", "dashboardWidgetOrder"),
        ("dashboardPreferences", "dashboardPreferences"),
        ("notificationPreferences", "notificationPreferences"),
        ("periodTrackingLogs", "periodTrackingLogs"),
        ("weekCheckIns", "weekCheckIns"),
        ("savedMeals", "savedMeals"),
        ("achievements", "jasper_achievements"),
        ("summerEventChallenges", "summerEvent_challenges"),
        ("friends", "jasper_friends"),
        ("blitzRuns", "summerEvent_blitzRuns"),
    ]

    /// Automatic saves share work. Profile/blob signatures are acknowledged
    /// only after successful writes, never before. Manual sync stays available.
    func saveBackgroundSnapshot(_ profile: UserProfile) async {
        let generation = AccountStorage.generation
        let userID = profile.userID
        guard ownsStorage(userID, generation: generation) else { return }
        if backgroundGeneration == generation, let backgroundSave {
            await backgroundSave.value
            return
        }
        backgroundSave?.cancel()
        backgroundGeneration = generation
        let task = Task {
            await self.saveAllUserData(userID: userID)
            guard self.ownsStorage(userID, generation: generation) else { return }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try? encoder.encode(profile)
            let onboarded = AccountStorage.hasCompletedOnboarding()
            let digest = data.map { Data(SHA256.hash(data: $0 + Data([onboarded ? 1 : 0]))) }
            let key = "\(generation)|\(userID.lowercased())|profile"
            if let digest, self.uploadedBlobDigests[key] == digest { return }
            let uploaded = await self.saveUserProfile(profile, onboarded: onboarded)
            guard self.ownsStorage(userID, generation: generation) else { return }
            if uploaded, let digest { self.uploadedBlobDigests[key] = digest }
        }
        backgroundSave = task
        await task.value
        if backgroundSave == task { backgroundSave = nil }
    }

    func saveAllUserData(userID: String) async {
        let generation = AccountStorage.generation
        guard ownsStorage(userID, generation: generation), await checkAccountStatus(), ownsStorage(userID, generation: generation) else { return }
        syncStatus = .syncing
        await withTaskGroup(of: Void.self) { group in
            for entry in allSyncKeys {
                group.addTask {
                    await self.saveUserDataBlob(userID: userID, key: entry.key, storageKey: entry.storageKey)
                }
            }
        }
        guard ownsStorage(userID, generation: generation) else { return }
        await saveUserSettings(userID: userID)
        guard ownsStorage(userID, generation: generation) else { return }
        syncStatus = .synced
    }

    /// Automatic foreground recovery is coalesced and attempted at most every
    /// three minutes per account generation. Explicit restores remain unthrottled.
    func restoreAllUserDataIfStale(userID: String, maxAge: TimeInterval = 180) async {
        let generation = AccountStorage.generation
        guard ownsStorage(userID, generation: generation) else { return }
        if foregroundGeneration == generation {
            if let foregroundRestore { await foregroundRestore.value; return }
            if let lastForegroundRestoreAttempt, Date().timeIntervalSince(lastForegroundRestoreAttempt) < maxAge { return }
        } else {
            foregroundRestore?.cancel()
            uploadedBlobDigests = [:]
        }
        foregroundGeneration = generation
        lastForegroundRestoreAttempt = Date()
        let task = Task { await self.restoreAllUserData(userID: userID) }
        foregroundRestore = task
        await task.value
        if foregroundRestore == task { foregroundRestore = nil }
    }

    func restoreAllUserData(userID: String) async {
        let generation = AccountStorage.generation
        guard ownsStorage(userID, generation: generation), await checkAccountStatus(), ownsStorage(userID, generation: generation) else { return }
        syncStatus = .syncing
        await withTaskGroup(of: Void.self) { group in
            for entry in allSyncKeys {
                group.addTask {
                    await self.restoreUserDataBlob(userID: userID, key: entry.key, storageKey: entry.storageKey)
                }
            }
        }
        guard ownsStorage(userID, generation: generation) else { return }
        await restoreUserSettings(userID: userID)
        guard ownsStorage(userID, generation: generation) else { return }
        syncStatus = .synced
    }

    func initialSyncAfterAccountCreation(userID: String, profile: UserProfile) async {
        guard await checkAccountStatus() else { return }
        syncStatus = .syncing
        await saveUserProfile(profile)
        await saveSubscriptionStatus(userID: userID, isProUser: profile.isProUser, productID: "PremiumTier", expirationDate: nil)
        await saveAllUserData(userID: userID)
        syncStatus = .synced
    }

    private let settingsRecordType = "UserSettings"

    private func saveUserSettings(userID: String) async {
        let generation = AccountStorage.generation
        guard ownsStorage(userID, generation: generation) else { return }
        let settingsDict: [String: Any] = [
                "totalMeditationMinutes": AccountStorage.integer(forKey: "totalMeditationMinutes"),
                "meditationSessionCount": AccountStorage.integer(forKey: "meditationSessionCount"),
                "meditationStreak": AccountStorage.integer(forKey: "meditationStreak"),
                "lastMeditationDate": AccountStorage.double(forKey: "lastMeditationDate"),
                "checkInStreak": AccountStorage.integer(forKey: "checkInStreak"),
                "lastCheckInDate": AccountStorage.double(forKey: "lastCheckInDate"),
                "weekCheckInsStart": AccountStorage.double(forKey: "weekCheckInsStart"),
                "hapticsEnabled": AccountStorage.bool(forKey: "hapticsEnabled"),
                "soundEffectsEnabled": AccountStorage.bool(forKey: "soundEffectsEnabled"),
                "useMetricUnits": AccountStorage.bool(forKey: "useMetricUnits"),
                "appearanceMode": AccountStorage.integer(forKey: "appearanceMode"),
                "smartNotificationsEnabled": AccountStorage.bool(forKey: "smartNotificationsEnabled"),
                "hasCompletedOnboarding": AccountStorage.bool(forKey: "hasCompletedOnboarding"),
                "hasCompletedWalkthrough": AccountStorage.bool(forKey: "hasCompletedWalkthrough"),
                "notificationSetupComplete": AccountStorage.bool(forKey: "notificationSetupComplete"),
                "emberTTSEnabled": AccountStorage.bool(forKey: "emberTTSEnabled"),
                "emberVoiceOption": AccountStorage.string(forKey: "emberVoiceOption") ?? "",
                "emberFreeQuestionCount": AccountStorage.integer(forKey: "emberFreeQuestionCount"),
                "userFirstLoginDate": AccountStorage.double(forKey: "userFirstLoginDate"),
            ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: settingsDict, options: [.sortedKeys]) else { return }
        let digestKey = "\(generation)|\(userID.lowercased())|settings"
        let digest = Data(SHA256.hash(data: jsonData))
        guard uploadedBlobDigests[digestKey] != digest else { return }
        do {
            let recordID = CKRecord.ID(recordName: "\(userID)_settings")
            let record: CKRecord
            do {
                record = try await privateDB.record(for: recordID)
            } catch {
                record = CKRecord(recordType: settingsRecordType, recordID: recordID)
            }
            guard ownsStorage(userID, generation: generation) else { return }
            record["userID"] = userID as CKRecordValue
            record["settingsBlob"] = jsonData as CKRecordValue
            record["lastUpdated"] = Date() as CKRecordValue
            do {
                try await privateDB.save(record)
            } catch let conflict as CKError where conflict.code == .serverRecordChanged {
                guard ownsStorage(userID, generation: generation), let serverRecord = conflict.serverRecord else { return }
                // Retry the SAME complete snapshot, not a reduced set of settings.
                serverRecord["userID"] = userID as CKRecordValue
                serverRecord["settingsBlob"] = jsonData as CKRecordValue
                serverRecord["lastUpdated"] = Date() as CKRecordValue
                try await privateDB.save(serverRecord)
            }
            guard ownsStorage(userID, generation: generation) else { return }
            uploadedBlobDigests[digestKey] = digest
        } catch {
            // No acknowledgment: retry the dirty snapshot next time.
        }
    }

    private func restoreUserSettings(userID: String) async {
        let generation = AccountStorage.generation
        guard ownsStorage(userID, generation: generation) else { return }
        do {
            let recordID = CKRecord.ID(recordName: "\(userID)_settings")
            let record = try await privateDB.record(for: recordID)
            guard ownsStorage(userID, generation: generation) else { return }
            guard let data = record["settingsBlob"] as? Data,
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let cloudDate = record["lastUpdated"] as? Date
            let localModKey = "userSettings_lastModified"
            let localModDate = UserDefaults.standard.object(forKey: AccountStorage.key(localModKey)) as? Date
            if let cloudDate, let localModDate, cloudDate <= localModDate { return }

            if let v = dict["totalMeditationMinutes"] as? Int { AccountStorage.set(v, forKey: "totalMeditationMinutes") }
            if let v = dict["meditationSessionCount"] as? Int { AccountStorage.set(v, forKey: "meditationSessionCount") }
            if let v = dict["meditationStreak"] as? Int { AccountStorage.set(v, forKey: "meditationStreak") }
            if let v = dict["lastMeditationDate"] as? Double, v > 0 { AccountStorage.set(v, forKey: "lastMeditationDate") }
            if let v = dict["checkInStreak"] as? Int { AccountStorage.set(v, forKey: "checkInStreak") }
            if let v = dict["lastCheckInDate"] as? Double, v > 0 { AccountStorage.set(v, forKey: "lastCheckInDate") }
            if let v = dict["weekCheckInsStart"] as? Double, v > 0 { AccountStorage.set(v, forKey: "weekCheckInsStart") }
            if let v = dict["hapticsEnabled"] as? Bool { AccountStorage.set(v, forKey: "hapticsEnabled") }
            if let v = dict["soundEffectsEnabled"] as? Bool { AccountStorage.set(v, forKey: "soundEffectsEnabled") }
            if let v = dict["useMetricUnits"] as? Bool { AccountStorage.set(v, forKey: "useMetricUnits") }
            if let v = dict["appearanceMode"] as? Int { AccountStorage.set(v, forKey: "appearanceMode") }
            if let v = dict["smartNotificationsEnabled"] as? Bool { AccountStorage.set(v, forKey: "smartNotificationsEnabled") }
            if let v = dict["hasCompletedOnboarding"] as? Bool { AccountStorage.set(v, forKey: "hasCompletedOnboarding") }
            if let v = dict["hasCompletedWalkthrough"] as? Bool { AccountStorage.set(v, forKey: "hasCompletedWalkthrough") }
            if let v = dict["notificationSetupComplete"] as? Bool { AccountStorage.set(v, forKey: "notificationSetupComplete") }
            if let v = dict["emberTTSEnabled"] as? Bool { AccountStorage.set(v, forKey: "emberTTSEnabled") }
            if let v = dict["emberVoiceOption"] as? String, !v.isEmpty { AccountStorage.set(v, forKey: "emberVoiceOption") }
            if let v = dict["emberFreeQuestionCount"] as? Int { AccountStorage.set(v, forKey: "emberFreeQuestionCount") }
            if let v = dict["userFirstLoginDate"] as? Double, v > 0 { AccountStorage.set(v, forKey: "userFirstLoginDate") }
        } catch {}
    }

    func saveUserDataBlob(userID: String, key: String, storageKey: String) async {
        let generation = AccountStorage.generation
        guard ownsStorage(userID, generation: generation) else { return }
        guard let data = AccountStorage.data(forKey: storageKey), !data.isEmpty else { return }
        let digestKey = "\(generation)|\(userID.lowercased())|\(key)"
        let digest = Data(SHA256.hash(data: data))
        guard uploadedBlobDigests[digestKey] != digest else { return }
        do {
            let recordID = CKRecord.ID(recordName: "\(userID)_\(key)")
            let record: CKRecord
            do {
                record = try await privateDB.record(for: recordID)
            } catch {
                record = CKRecord(recordType: userDataRecordType, recordID: recordID)
            }
            guard ownsStorage(userID, generation: generation) else { return }
            record["userID"] = userID as CKRecordValue
            record["dataKey"] = key as CKRecordValue
            if data.count > 900_000 {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(key)_\(userID).dat")
                try data.write(to: tempURL)
                record["dataAsset"] = CKAsset(fileURL: tempURL)
                record["dataBlob"] = nil
            } else {
                record["dataBlob"] = data as CKRecordValue
                record["dataAsset"] = nil
            }
            record["lastUpdated"] = Date() as CKRecordValue
            try await privateDB.save(record)
            guard ownsStorage(userID, generation: generation) else { return }
            uploadedBlobDigests[digestKey] = digest
            AccountStorage.set(Date(), forKey: "\(storageKey)_lastModified")
        } catch let ckError as CKError where ckError.code == .serverRecordChanged {
            if let serverRecord = ckError.serverRecord {
                guard ownsStorage(userID, generation: generation) else { return }
                if data.count > 900_000 {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(key)_\(userID).dat")
                    try? data.write(to: tempURL)
                    serverRecord["dataAsset"] = CKAsset(fileURL: tempURL)
                    serverRecord["dataBlob"] = nil
                } else {
                    serverRecord["dataBlob"] = data as CKRecordValue
                    serverRecord["dataAsset"] = nil
                }
                serverRecord["lastUpdated"] = Date() as CKRecordValue
                do {
                    try await privateDB.save(serverRecord)
                    guard ownsStorage(userID, generation: generation) else { return }
                    uploadedBlobDigests[digestKey] = digest
                    AccountStorage.set(Date(), forKey: "\(storageKey)_lastModified")
                } catch {
                    // Leave it dirty for the next automatic or explicit save.
                }
            }
        } catch {}
    }

    private func restoreUserDataBlob(userID: String, key: String, storageKey: String) async {
        let generation = AccountStorage.generation
        guard ownsStorage(userID, generation: generation) else { return }
        do {
            let recordID = CKRecord.ID(recordName: "\(userID)_\(key)")
            let record = try await privateDB.record(for: recordID)
            guard ownsStorage(userID, generation: generation) else { return }
            var cloudData: Data?
            if let asset = record["dataAsset"] as? CKAsset, let url = asset.fileURL {
                cloudData = try? Data(contentsOf: url)
            }
            if cloudData == nil || cloudData?.isEmpty == true {
                cloudData = record["dataBlob"] as? Data
            }
            guard let validCloudData = cloudData, !validCloudData.isEmpty else { return }
            let localData = AccountStorage.data(forKey: storageKey)
            if localData == nil || localData?.isEmpty == true {
                AccountStorage.set(validCloudData, forKey: storageKey)
            } else if let cloudDate = record["lastUpdated"] as? Date {
                let localModKey = "\(storageKey)_lastModified"
                let localModDate = UserDefaults.standard.object(forKey: AccountStorage.key(localModKey)) as? Date
                if localModDate == nil || cloudDate > localModDate! {
                    AccountStorage.set(validCloudData, forKey: storageKey)
                }
            }
        } catch {}
    }

    private func ownsStorage(_ userID: String, generation: UUID) -> Bool {
        !Task.isCancelled && generation == AccountStorage.generation
            && userID.caseInsensitiveCompare(AccountStorage.currentUserID) == .orderedSame
    }

    func saveLocalDataToCloud(userID: String) async {
        await saveAllUserData(userID: userID)
    }

}
