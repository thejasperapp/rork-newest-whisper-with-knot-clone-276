import Foundation
import Supabase

/// Syncs only explicit local changes; passive refreshes never overwrite another device's settings.
@MainActor @Observable
final class WhisperPushPreferenceSync {
    static let shared = WhisperPushPreferenceSync()
    private(set) var isSyncing: Bool = false
    private(set) var lastError: String?
    private(set) var teamsPrivacyError: String?
    private(set) var newPostSyncError: String?
    private(set) var revision: UInt64 = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    private let client = SupabaseService.shared.client
    private let pendingKey = "whisper.push.pending.v1"
    private let importedKey = "whisper.push.imported.v1"
    private let groupPendingKey = "whisper.push.groupPending.v1"
    private let groupImportedKey = "whisper.push.groupImported.v1"

    static let fields: [String: String] = [
        "master_enabled": "whisper.push", "quiet_mode": "whisper.quiet",
        "dms": "whisper.push.dm", "mentions": "whisper.push.mention",
        "likes": "whisper.push.like", "comments": "whisper.push.comment",
        "follows": "whisper.push.follow", "story_responses": "whisper.push.storyResponse",
        "missed_calls": "whisper.push.calls"
    ]

    private init() {
        NotificationCenter.default.addObserver(forName: Notification.Name("WhisperMeetingAccountWillChange"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.task?.cancel()
                self?.task = nil
                self?.isSyncing = false
                self?.lastError = nil
                self?.teamsPrivacyError = nil
                self?.newPostSyncError = nil
                self?.revision &+= 1
            }
        }
    }

    func changed(storageKey: String, value: Bool) {
        if storageKey == "whisper.push.newPost" {
            AccountStorage.set(value, forKey: "whisper.push.newPost.pending.v1")
            refresh()
            return
        }
        guard let field = Self.fields.first(where: { $0.value == storageKey })?.key else { return }
        var pending = pendingValues(pendingKey)
        pending[field] = value
        AccountStorage.set(pending, forKey: pendingKey)
        refresh()
    }

    func groupChanged(id: String, muted: Bool) {
        var pending = pendingValues(groupPendingKey)
        pending[id.lowercased()] = muted
        AccountStorage.set(pending, forKey: groupPendingKey)
        refresh()
    }

    func refresh() {
        guard task == nil, UUID(uuidString: AccountStorage.currentUserID) != nil else { return }
        let owner = AccountStorage.currentUserID.lowercased()
        let generation = AccountStorage.generation
        isSyncing = true
        lastError = nil
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.owns(owner, generation) {
                    self.task = nil
                    self.isSyncing = false
                    self.revision &+= 1
                }
            }
            do {
                repeat {
                    guard self.owns(owner, generation) else { return }
                    try await self.syncPreferences(owner: owner, generation: generation)
                    guard self.owns(owner, generation) else { return }
                    try await self.syncGroups(owner: owner, generation: generation)
                    do {
                        try await self.syncNewPosts(owner: owner, generation: generation)
                        if self.owns(owner, generation) { self.newPostSyncError = nil }
                    } catch {
                        if self.owns(owner, generation) { self.newPostSyncError = "Return-to-posting alerts haven't synced. Your New posts choice is saved on this device." }
                    }
                    do {
                        try await self.syncTeamsPrivacy(owner: owner, generation: generation)
                        if self.owns(owner, generation) { self.teamsPrivacyError = nil }
                    } catch {
                        if self.owns(owner, generation) { self.teamsPrivacyError = "Team invitation privacy hasn't synced. Your choices are saved on this device." }
                    }
                } while self.owns(owner, generation) && (!self.pendingValues(self.pendingKey).isEmpty || !self.pendingValues(self.groupPendingKey).isEmpty || (self.newPostSyncError == nil && AccountStorage.object(forKey: "whisper.push.newPost.pending.v1") != nil))
            } catch {
                guard self.owns(owner, generation) else { return }
                self.lastError = "Background preferences haven't synced. Your choices are saved on this device."
            }
        }
    }

    private func owns(_ owner: String, _ generation: UUID) -> Bool {
        !Task.isCancelled && AccountStorage.generation == generation
            && AccountStorage.currentUserID.lowercased() == owner
    }

    private func pendingValues(_ key: String) -> [String: Bool] {
        AccountStorage.object(forKey: key) as? [String: Bool] ?? [:]
    }

    private func syncNewPosts(owner: String, generation: UUID) async throws {
        let pendingKey = "whisper.push.newPost.pending.v1"
        let importedKey = "whisper.push.newPost.imported.v1"
        if !AccountStorage.bool(forKey: importedKey), AccountStorage.object(forKey: pendingKey) == nil,
           AccountStorage.object(forKey: "whisper.push.newPost") as? Bool == false {
            AccountStorage.set(false, forKey: pendingKey)
        }
        repeat {
            guard owns(owner, generation) else { return }
            let pending = AccountStorage.object(forKey: pendingKey) as? Bool
            var params: [String: AnyJSON] = ["p_owner": .string(owner)]
            if let pending { params["p_enabled"] = .bool(pending) }
            let result: [String: Bool] = try await client.rpc("whisper_new_post_preference", params: params).execute().value
            guard owns(owner, generation) else { return }
            guard let enabled = result["new_posts"], result["rollout_enabled"] != nil,
                  pending == nil || pending == enabled else { throw WhisperTeamsInvitationService.Failure.unavailable }
            if (AccountStorage.object(forKey: pendingKey) as? Bool) == pending {
                AccountStorage.removeObject(forKey: pendingKey)
                AccountStorage.set(enabled, forKey: "whisper.push.newPost")
            }
            AccountStorage.set(result["rollout_enabled"] ?? false, forKey: "whisper.push.newPost.remoteReady.v1")
            AccountStorage.set(true, forKey: importedKey)
        } while owns(owner, generation) && AccountStorage.object(forKey: pendingKey) != nil
    }

    private func syncPreferences(owner: String, generation: UUID) async throws {
        if !AccountStorage.bool(forKey: importedKey) {
            var pending = pendingValues(pendingKey)
            // Initial migration carries opt-outs/quiet mode only, preserving remote opt-outs.
            for (field, key) in Self.fields where pending[field] == nil {
                if let value = AccountStorage.object(forKey: key) as? Bool,
                   value == (field == "quiet_mode") { pending[field] = value }
            }
            AccountStorage.set(pending, forKey: pendingKey)
        }
        repeat {
            let pending = pendingValues(pendingKey)
            if !pending.isEmpty {
                let patch = pending.mapValues { AnyJSON.bool($0) }
                let _: [String: AnyJSON] = try await client.rpc("whisper_update_push_preferences",
                    params: ["p_owner": AnyJSON.string(owner), "p_patch": .object(patch)]).execute().value
                guard owns(owner, generation) else { return }
                var remaining = pendingValues(pendingKey)
                for (field, value) in pending where remaining[field] == value { remaining.removeValue(forKey: field) }
                AccountStorage.set(remaining, forKey: pendingKey)
            }
            guard owns(owner, generation) else { return }
            let rows: [[String: Bool]] = try await client.from("whisper_notification_prefs")
                .select(Self.fields.keys.sorted().joined(separator: ","))
                .eq("user_id", value: owner).limit(1).execute().value
            guard owns(owner, generation) else { return }
            let remaining = pendingValues(pendingKey)
            for (field, value) in rows.first ?? [:] where remaining[field] == nil {
                if let key = Self.fields[field] { AccountStorage.set(value, forKey: key) }
            }
            AccountStorage.set(true, forKey: importedKey)
        } while !pendingValues(pendingKey).isEmpty
    }

    private func syncTeamsPrivacy(owner: String, generation: UUID) async throws {
        let privacy = WhisperDMPrivacyService.shared
        let installationKey = "whisper.teams.privacy.installation.v1"
        let installation = AccountStorage.string(forKey: installationKey) ?? UUID().uuidString.lowercased()
        AccountStorage.set(installation, forKey: installationKey)
        while owns(owner, generation) {
            let isPrivate = privacy.isPrivate, approved = privacy.approved, denied = privacy.denied
            guard approved.count <= 2000, denied.count <= 2000 else { throw WhisperTeamsInvitationService.Failure.unavailable }
            let revisionKey = "whisper.teams.privacy.revision.v1"
            let revision = AccountStorage.integer(forKey: revisionKey) + 1
            AccountStorage.set(revision, forKey: revisionKey)
            let payload: [String: AnyJSON] = ["p_owner": .string(owner), "p_installation": .string(installation),
                "p_revision": .integer(revision), "p_private": .bool(isPrivate),
                "p_approved": .array(approved.filter { UUID(uuidString: $0) != nil }.sorted().map { .string($0) }),
                "p_denied": .array(denied.filter { UUID(uuidString: $0) != nil }.sorted().map { .string($0) })]
            _ = try await WhisperTeamsInvitationService.perform("whisper_social_teams_privacy", params: payload)
            guard owns(owner, generation) else { return }
            if isPrivate == privacy.isPrivate, approved == privacy.approved, denied == privacy.denied { return }
        }
    }

    private func syncGroups(owner: String, generation: UUID) async throws {
        if !AccountStorage.bool(forKey: groupImportedKey) {
            var pending = pendingValues(groupPendingKey)
            for id in WhisperGroupChatService.shared.muted where pending[id] == nil { pending[id] = true }
            AccountStorage.set(pending, forKey: groupPendingKey)
        }
        repeat {
            let pending = pendingValues(groupPendingKey)
            if !pending.isEmpty {
                let rows = pending.compactMap { id, muted -> [String: AnyJSON]? in
                    guard UUID(uuidString: id) != nil else { return nil }
                    return ["user_id": .string(owner), "group_id": .string(id), "muted": .bool(muted)]
                }
                if !rows.isEmpty {
                    do {
                        try await client.from("whisper_push_group_mutes").upsert(rows, onConflict: "user_id,group_id").execute()
                    } catch let error as PostgrestError where error.code == "23503" {
                        // A deleted group must not poison the entire pending batch.
                        for row in rows {
                            guard owns(owner, generation) else { return }
                            do {
                                try await client.from("whisper_push_group_mutes").upsert(row, onConflict: "user_id,group_id").execute()
                            } catch let rowError as PostgrestError where rowError.code == "23503" {
                                continue
                            }
                        }
                    }
                }
                guard owns(owner, generation) else { return }
                var remaining = pendingValues(groupPendingKey)
                for (id, value) in pending where remaining[id] == value { remaining.removeValue(forKey: id) }
                AccountStorage.set(remaining, forKey: groupPendingKey)
            }
            let rows: [WhisperPushGroupMute] = try await client.from("whisper_push_group_mutes")
                .select("group_id,muted").eq("user_id", value: owner).execute().value
            guard owns(owner, generation) else { return }
            var mutes = Dictionary(uniqueKeysWithValues: rows.map { ($0.group_id.lowercased(), $0.muted) })
            mutes.merge(pendingValues(groupPendingKey)) { _, pending in pending }
            WhisperGroupChatService.shared.applySyncedMutes(Set(mutes.filter(\.value).map(\.key)))
            AccountStorage.set(true, forKey: groupImportedKey)
        } while !pendingValues(groupPendingKey).isEmpty
        // A settings change can arrive while group settings are in flight.
        if !pendingValues(pendingKey).isEmpty { try await syncPreferences(owner: owner, generation: generation) }
    }
}
