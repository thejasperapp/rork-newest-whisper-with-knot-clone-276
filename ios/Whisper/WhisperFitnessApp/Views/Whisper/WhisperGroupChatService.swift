import Foundation
import SwiftUI
import Supabase
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

// MARK: - Models

nonisolated struct WhisperGroupMember: Codable, Sendable, Hashable, Identifiable {
    let user_id: String
    let username: String
    let profile_image_url: String?
    nonisolated var id: String { user_id }
}

nonisolated struct WhisperGroup: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var members: [WhisperGroupMember]
    var createdAt: Date
    /// The creator's user id (lowercased). Owners rename, add, remove, and
    /// delete; everyone else can leave. Nil for groups saved before the
    /// registry existed — those treat the local account as the owner.
    var ownerID: String? = nil
    var avatarPath: String? = nil
}

/// The web registry row (`whisper_group_threads`, supabase/business-plus.sql)
/// — one durable roster per group so members survive across devices and
/// both platforms agree on who's in the room.
nonisolated struct WhisperGroupRegistryRow: Codable, Sendable {
    let id: String
    var name: String
    let owner_id: String
    var member_ids: [String]
    var member_usernames: [String]
    var business_id: String?
    let created_at: String?
    var avatar_path: String? = nil
}

/// A quoted reply riding a group message body — plain-text friendly so every
/// client (and the inbox preview) still reads it: `↩ @name: "quoted…"\n\nreply`.
nonisolated struct WhisperGroupReplyQuote: Sendable, Hashable {
    let username: String
    let text: String
}

/// Group chats — cross-platform with web on the SAME wire.
///
/// Every group message fans out as N individual `whisper_messages` rows (one
/// per recipient) with the body prefixed `::wg-v1::{groupID}::{name}::{body}`.
/// On top of the wire sits a durable REGISTRY (`whisper_group_threads`) that
/// web already writes — this service now reads and writes it too, so a group
/// made on the phone shows up on the web inbox with its roster, and renames /
/// adds / removes made anywhere land everywhere. The local list is the cache
/// and the fallback when the table hasn't been migrated yet.
@MainActor
@Observable
final class WhisperGroupChatService {
    static let shared = WhisperGroupChatService()

    nonisolated static let headerPrefix = "::wg-v1::"

    var groups: [WhisperGroup] = []
    var lastError: String?
    private(set) var inboxSummaries: [UUID: WhisperGroupInboxSummary] = [:]
    private(set) var inboxHasMore = false
    private(set) var inboxLoading = false
    private(set) var inboxError: String?
    private(set) var inboxRetryOlder = false
    private(set) var hasLoadedInbox = false
    var inboxContinuationID: String { inboxNext?.id ?? "end" }
    @ObservationIgnored private var lastInboxFetch: Date?
    @ObservationIgnored private var inboxNext: WhisperHistoryCursor?
    @ObservationIgnored private var inboxPages = 1
    @ObservationIgnored private var inboxTask: Task<Void, Never>?
    @ObservationIgnored private var inboxTaskOlder = false
    @ObservationIgnored private var inboxRequest = UUID()
    @ObservationIgnored private var inboxRevision = UUID()
    @ObservationIgnored private var inboxRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var syncToken: UUID?
    @ObservationIgnored private var registryTask: Task<Void, Never>?
    @ObservationIgnored private var lastSync: Date = .distantPast
    @ObservationIgnored private var avatarRevisions: [UUID: UUID] = [:]
    @ObservationIgnored private var deletionOperations: [UUID: UUID] = [:]
    private(set) var activeRegistryIDs: Set<UUID> = []
    /// Pinned message per group (group id → message id), device-local.
    private(set) var pinned: [String: String] = [:]
    /// Groups muted on this phone (no inbox emphasis, no haptics).
    private(set) var muted: Set<String> = []
    /// Groups this account left — hidden locally (the registry is owner-controlled).
    private(set) var left: Set<String> = []
    /// True once the registry answered (or declined) this session.
    private(set) var registryChecked: Bool = false
    /// True when the registry table exists — enables owner tools.
    private(set) var registryAvailable: Bool = false

    /// PER-GROUP MESSAGE INDEX CACHE. `messages(forGroup:)` walks every
    /// member's whole thread — and the inbox asked for it once per group row
    /// on EVERY render (plus the open group thread on every keystroke), which
    /// is what made the app crawl once groups carried photos and a few
    /// hundred rows. The index is now rebuilt only when the underlying raw
    /// threads actually change (cheap signature: per-member row count + last
    /// row id + the hidden-count), otherwise served from memory. Observation
    /// is ignored so serving from cache inside a view body never re-renders.
    @ObservationIgnored private var messageIndex: [String: (signature: String, rows: [WhisperMessageRow])] = [:]

    private let storageKey = "whisper.groups.v1"
    private let pinnedKey = "whisper.groups.pinned.v1"
    private let mutedKey = "whisper.groups.muted.v1"
    private let leftKey = "whisper.groups.left.v1"

    private var client: SupabaseClient { SupabaseService.shared.client }
    private var currentUID: String { AccountStorage.currentUserID.lowercased() }
    private var currentUsername: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    private init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        pinned = [:]; muted = []; left = []; messageIndex = [:]
        if let data = AccountStorage.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([WhisperGroup].self, from: data) {
            groups = decoded.sorted { $0.createdAt > $1.createdAt }
        } else {
            groups = []
        }
        if let data = AccountStorage.data(forKey: pinnedKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            pinned = decoded
        }
        if let data = AccountStorage.data(forKey: mutedKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            muted = Set(decoded.map { $0.lowercased() })
        }
        if let data = AccountStorage.data(forKey: leftKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            left = Set(decoded.map { $0.lowercased() })
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        AccountStorage.set(data, forKey: storageKey)
    }

    private func persistSmall() {
        if let data = try? JSONEncoder().encode(pinned) { AccountStorage.set(data, forKey: pinnedKey) }
        if let data = try? JSONEncoder().encode(Array(muted)) { AccountStorage.set(data, forKey: mutedKey) }
        if let data = try? JSONEncoder().encode(Array(left)) { AccountStorage.set(data, forKey: leftKey) }
    }

    /// Re-read everything for a freshly switched account.
    func reloadForCurrentAccount() {
        registryTask?.cancel(); registryTask = nil
        inboxTask?.cancel(); inboxTask = nil; inboxRefreshTask?.cancel(); inboxRefreshTask = nil
        inboxRequest = UUID(); inboxRevision = UUID(); inboxNext = nil; inboxPages = 1
        inboxSummaries = [:]; inboxHasMore = false; inboxLoading = false; inboxError = nil; hasLoadedInbox = false; lastInboxFetch = nil
        syncToken = nil; lastSync = .distantPast; avatarRevisions = [:]; deletionOperations = [:]
        registryChecked = false; registryAvailable = false; activeRegistryIDs = []; lastError = nil
        load()
    }

    /// Independent group-list authority. History windows never determine full
    /// unread counts or whether a quiet group remains discoverable.
    func inboxNeedsRefresh(maxAge: TimeInterval) -> Bool {
        inboxError != nil || lastInboxFetch.map { Date().timeIntervalSince($0) >= maxAge } ?? true
    }

    func fetchInboxSummaries(older: Bool = false) async {
        guard UUID(uuidString: currentUID) != nil, !Task.isCancelled else { return }
        let owner = currentUID; let generation = AccountStorage.generation
        if let inboxTask {
            let wasOlder = inboxTaskOlder
            await inboxTask.value
            guard !Task.isCancelled, owner == currentUID, generation == AccountStorage.generation else { return }
            if older || !wasOlder { return }
            await fetchInboxSummaries(); return
        }
        guard !older || inboxNext != nil else { return }
        let request = UUID(); inboxRequest = request
        let revision = inboxRevision
        let cursor = older ? inboxNext : nil
        let pages = older ? 1 : inboxPages
        let hidden = Array(WhisperBackendService.shared.locallyDeletedMessageIDs).filter { UUID(uuidString: $0) != nil }
        inboxLoading = true; inboxError = nil; inboxRetryOlder = older
        let task = Task { @MainActor in
            defer { if self.inboxRequest == request { self.inboxTask = nil; self.inboxLoading = false } }
            do {
                var result: [UUID: WhisperGroupInboxSummary] = [:]
                var next = cursor
                for _ in 0..<pages {
                    try WhisperChatMediaService.checkAccount(owner, generation: generation)
                    let rows: [WhisperGroupInboxSummary] = try await self.client.rpc("whisper_group_summaries_v1",
                        params: WhisperInboxSummaryParams(p_before_at: next?.createdAt, p_before_id: next?.id, p_hidden_ids: hidden)).execute().value
                    try WhisperChatMediaService.checkAccount(owner, generation: generation)
                    guard self.inboxRequest == request, self.inboxRevision == revision else { return }
                    let page = WhisperGroupInboxPaging.page(rows)
                    for row in page.rows where result[row.group_id] == nil { result[row.group_id] = row }
                    next = page.next
                    if next == nil { break }
                }
                if older {
                    for (id, row) in result where self.inboxSummaries[id] == nil { self.inboxSummaries[id] = row }
                    self.inboxPages += 1
                } else { self.inboxSummaries = result }
                self.inboxNext = next; self.inboxHasMore = next != nil; self.hasLoadedInbox = true
                if !older { self.lastInboxFetch = Date() }
                // Only observed endpoints are inferred for legacy groups. The
                // verified registry always owns current rosters and send access.
                var discovered = self.groups
                for row in result.values {
                    guard let parsed = Self.parse(row.last_message.body) else { continue }
                    let members = row.participants.map { WhisperGroupMember(user_id: $0.user_id, username: $0.username ?? "member", profile_image_url: nil) }
                    if let i = discovered.firstIndex(where: { $0.id == row.group_id }) {
                        if discovered[i].ownerID == nil {
                            discovered[i].name = parsed.name
                            for member in members where !discovered[i].members.contains(where: { $0.user_id.lowercased() == member.user_id.lowercased() }) { discovered[i].members.append(member) }
                        }
                    } else {
                        discovered.append(WhisperGroup(id: row.group_id, name: parsed.name, members: members,
                            createdAt: WhisperBackendService.parseISO(row.last_created_at) ?? .distantPast))
                    }
                }
                self.groups = discovered; self.persist()
            } catch {
                guard !Task.isCancelled, self.inboxRequest == request, self.inboxRevision == revision,
                      generation == AccountStorage.generation, owner == self.currentUID else { return }
                self.inboxError = older ? "More groups couldn’t load just now." : "Groups couldn’t refresh just now."
            }
        }
        inboxTaskOlder = older; inboxTask = task
        await task.value
    }

    func invalidateInboxSummaries(removingMessageIDs: Set<String> = []) {
        if !removingMessageIDs.isEmpty {
            inboxSummaries = inboxSummaries.filter { !removingMessageIDs.contains($0.value.last_message_id.lowercased()) }
        }
        inboxRevision = UUID(); inboxRequest = UUID()
        inboxTask?.cancel(); inboxTask = nil; inboxLoading = false
        inboxRefreshTask?.cancel()
        let generation = AccountStorage.generation
        inboxRefreshTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            await self.fetchInboxSummaries()
        }
    }

    // MARK: - Registry sync

    /// Pulls my registry rows (owner or member — RLS scopes the select) and
    /// merges them over the local cache: server names/rosters win, local-only
    /// groups stay. A missing table just leaves the local list in charge.
    func syncRegistry(force: Bool = false) async {
        if let registryTask { await registryTask.value; return }
        guard UUID(uuidString: currentUID) != nil,
              force || Date().timeIntervalSince(lastSync) > 4 else { return }
        let task = Task { await refreshRegistry() }
        registryTask = task
        await task.value
        if registryTask == task { registryTask = nil }
    }

    private func refreshRegistry() async {
        let account = currentUID
        let generation = AccountStorage.generation
        let token = UUID(); syncToken = token
        let photoRevisions = avatarRevisions
        defer { if syncToken == token { syncToken = nil } }
        do {
            let rows: [WhisperGroupRegistryRow] = try await client
                .from("whisper_group_threads")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            let owners = await fetchProfiles(ids: rows.map(\.owner_id))
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            let ownerNames = Dictionary(owners.map { ($0.user_id.lowercased(), $0.username) }, uniquingKeysWith: { a, _ in a })
            var merged = groups
            for row in rows {
                guard let uuid = UUID(uuidString: row.id) else { continue }
                var members: [WhisperGroupMember] = []
                for (idx, memberID) in row.member_ids.enumerated() {
                    let uname = idx < row.member_usernames.count ? row.member_usernames[idx] : "member"
                    members.append(WhisperGroupMember(user_id: memberID, username: uname, profile_image_url: nil))
                }
                // The owner isn't stored in member_ids — everyone but me is a
                // recipient, so the owner joins the local roster when I'm not them.
                if row.owner_id.lowercased() != currentUID,
                   !members.contains(where: { $0.user_id.lowercased() == row.owner_id.lowercased() }) {
                    let ownerName = ownerNames[row.owner_id.lowercased()] ?? groups.first(where: { $0.id == uuid })?.members.first(where: { $0.user_id.lowercased() == row.owner_id.lowercased() })?.username ?? String(row.owner_id.prefix(8))
                    members.append(WhisperGroupMember(user_id: row.owner_id, username: ownerName, profile_image_url: nil))
                }
                members.removeAll { $0.user_id.lowercased() == currentUID }
                let created = row.created_at.flatMap { WhisperBackendService.parseISO($0) } ?? Date()
                let next = WhisperGroup(id: uuid, name: row.name, members: members, createdAt: created, ownerID: row.owner_id.lowercased(), avatarPath: row.avatar_path)
                if let i = merged.firstIndex(where: { $0.id == uuid }) {
                    // Keep any avatar URLs the local copy already resolved.
                    var carried = next
                    if photoRevisions[uuid] != avatarRevisions[uuid] { carried.avatarPath = merged[i].avatarPath }
                    carried.members = carried.members.map { m in
                        if let local = merged[i].members.first(where: { $0.user_id.lowercased() == m.user_id.lowercased() }),
                           local.profile_image_url != nil {
                            return WhisperGroupMember(user_id: m.user_id, username: m.username, profile_image_url: local.profile_image_url)
                        }
                        return m
                    }
                    merged[i] = carried
                } else {
                    merged.append(next)
                }
            }
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            activeRegistryIDs = Set(rows.compactMap { UUID(uuidString: $0.id) })
            registryAvailable = true; registryChecked = true; lastError = nil; lastSync = Date()
            groups = merged.sorted { $0.createdAt > $1.createdAt }
            persist()
            await hydrateAvatars()
        } catch {
            guard !Task.isCancelled, syncToken == token, currentUID == account, AccountStorage.generation == generation else { return }
            registryChecked = true
            lastError = "Couldn't refresh your groups. Pull to refresh to try again."
            print("[Groups] registry refresh failed")
        }
    }

    /// One batched `whisper_profiles` read for a set of user ids.
    private func fetchProfiles(ids: [String]) async -> [WhisperUserRow] {
        let unique = Array(Set(ids.map { $0.lowercased() })).prefix(60)
        guard !unique.isEmpty else { return [] }
        do {
            let rows: [WhisperUserRow] = try await client
                .from("whisper_profiles")
                .select()
                .in("user_id", values: Array(unique))
                .execute()
                .value
            return rows
        } catch {
            return []
        }
    }

    private func ownerUsername(_ ownerID: String) async -> String {
        if let cached = groups.flatMap(\.members).first(where: { $0.user_id.lowercased() == ownerID.lowercased() }) {
            return cached.username
        }
        if let profile = await fetchProfiles(ids: [ownerID]).first {
            return profile.username
        }
        return "owner"
    }

    /// Fills in missing member avatars + usernames from the profile table (one batched read).
    private func hydrateAvatars() async {
        let missing = groups.flatMap(\.members)
            .filter { $0.profile_image_url == nil || $0.username == "member" || $0.username == "owner" }
            .map(\.user_id)
        guard !missing.isEmpty else { return }
        let account = currentUID; let generation = AccountStorage.generation
        let rows = await fetchProfiles(ids: missing)
        guard currentUID == account, AccountStorage.generation == generation, !rows.isEmpty else { return }
        var byID: [String: WhisperUserRow] = [:]
        for r in rows { byID[r.user_id.lowercased()] = r }
        groups = groups.map { g in
            var g = g
            g.members = g.members.map { m in
                guard let row = byID[m.user_id.lowercased()] else { return m }
                return WhisperGroupMember(
                    user_id: m.user_id,
                    username: (m.username == "member" || m.username == "owner") ? row.username : m.username,
                    profile_image_url: m.profile_image_url ?? row.profile_image_url
                )
            }
            return g
        }
        persist()
    }

    // MARK: - Visibility / roles

    /// Groups to show in the inbox — everything I haven't left.
    var visibleGroups: [WhisperGroup] {
        groups.filter { !left.contains($0.id.uuidString.lowercased()) }
    }

    func isOwner(_ group: WhisperGroup) -> Bool {
        guard let owner = group.ownerID else { return false }
        return owner.lowercased() == currentUID
    }

    func isMuted(_ group: WhisperGroup) -> Bool { muted.contains(group.id.uuidString.lowercased()) }

    func toggleMute(_ group: WhisperGroup) {
        let key = group.id.uuidString.lowercased()
        if muted.contains(key) { muted.remove(key) } else { muted.insert(key) }
        persistSmall()
        WhisperPushPreferenceSync.shared.groupChanged(id: key, muted: muted.contains(key))
    }

    func applySyncedMutes(_ values: Set<String>) {
        muted = values
        persistSmall()
    }

    func pinnedMessageID(for group: WhisperGroup) -> String? { pinned[group.id.uuidString.lowercased()] }

    func pin(_ messageID: String?, in group: WhisperGroup) {
        let key = group.id.uuidString.lowercased()
        if let messageID { pinned[key] = messageID } else { pinned.removeValue(forKey: key) }
        persistSmall()
    }

    // MARK: - CRUD

    @discardableResult
    func createGroup(name: String, members: [WhisperGroupMember]) async throws -> WhisperGroup {
        let account = currentUID; let generation = AccountStorage.generation
        var seen: Set<String> = [account]
        let dedupedMembers = members.filter { seen.insert($0.user_id.lowercased()).inserted }
        let group = WhisperGroup(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Group chat" : String(name.replacingOccurrences(of: "::", with: "·").prefix(80)),
            members: dedupedMembers,
            createdAt: Date(),
            ownerID: currentUID
        )
        await syncRegistry(force: true)
        try await writeRegistry(group)
        try WhisperChatMediaService.checkAccount(account, generation: generation)
        groups.insert(group, at: 0)
        activeRegistryIDs.insert(group.id)
        persist()
        _ = await sendMessage(toGroup: group, body: "created the group \"\(group.name)\"")
        try WhisperChatMediaService.checkAccount(account, generation: generation)
        return group
    }

    private func writeRegistry(_ group: WhisperGroup) async throws {
        let row = WhisperGroupRegistryRow(
            id: group.id.uuidString.lowercased(),
            name: group.name,
            owner_id: currentUID,
            member_ids: group.members.map { $0.user_id.lowercased() },
            member_usernames: group.members.map(\.username),
            business_id: nil,
            created_at: ISO8601DateFormatter().string(from: group.createdAt)
        )
        let saved: [WhisperGroupRegistryRow] = try await client.from("whisper_group_threads").insert(row).select().execute().value
        guard saved.contains(where: { $0.id.lowercased() == group.id.uuidString.lowercased() }) else {
            throw NSError(domain: "Groups", code: 1, userInfo: [NSLocalizedDescriptionKey: "Group creation wasn't confirmed. Try again."])
        }
    }

    private func updateRegistry(_ group: WhisperGroup, previous: WhisperGroup) async -> Bool {
        struct Patch: Encodable { let name: String; let member_ids: [String]; let member_usernames: [String] }
        let account = currentUID; let generation = AccountStorage.generation
        lastError = nil
        do {
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            let session = try await client.auth.session
            guard session.user.id.uuidString.lowercased() == account else { throw CancellationError() }
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            let saved: [WhisperGroupRegistryRow] = try await client
                .from("whisper_group_threads")
                .update(Patch(
                    name: group.name,
                    member_ids: group.members.map { $0.user_id.lowercased() },
                    member_usernames: group.members.map(\.username)
                ))
                .eq("id", value: group.id.uuidString.lowercased())
                .eq("owner_id", value: account)
                .eq("member_ids", value: "{" + previous.members.map { $0.user_id.lowercased() }.joined(separator: ",") + "}")
                .eq("name", value: previous.name)
                .select().execute().value
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            guard saved.contains(where: { $0.id.lowercased() == group.id.uuidString.lowercased() }) else {
                lastError = "The group changed or your access changed. Refresh and try again."
                return false
            }
            return true
        } catch {
            guard currentUID == account, AccountStorage.generation == generation else { return false }
            lastError = "Couldn't confirm the change. Refresh the group before retrying."
            print("[Groups] registry update failed")
            return false
        }
    }

    private func replace(_ group: WhisperGroup) {
        if let i = groups.firstIndex(where: { $0.id == group.id }) {
            groups[i] = group
        } else {
            groups.insert(group, at: 0)
        }
        persist()
    }

    /// Owner-only rename — announced on the wire (web's exact phrase) so every
    /// member's thread header follows.
    func rename(_ group: WhisperGroup, to name: String) async -> WhisperGroup {
        let trimmed = String(name.replacingOccurrences(of: "::", with: "·").trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !trimmed.isEmpty, isOwner(group) else { return group }
        var next = group
        next.name = trimmed
        guard await updateRegistry(next, previous: group) else { return group }
        replace(next)
        _ = await sendMessage(toGroup: next, body: "renamed the group to “\(trimmed)”")
        return next
    }

    /// Owner-only add — the newcomers get the announcement too.
    func addMembers(_ group: WhisperGroup, _ people: [WhisperGroupMember]) async -> WhisperGroup {
        let account = currentUID; let generation = AccountStorage.generation
        guard isOwner(group) else { lastError = "Only the group owner can add people."; return group }
        lastError = nil
        do {
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            let rows: [WhisperGroupRegistryRow] = try await client.from("whisper_group_threads")
                .select().eq("id", value: group.id.uuidString.lowercased()).limit(1).execute().value
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            guard let row = rows.first, row.owner_id.lowercased() == account else {
                lastError = "This group is no longer available to manage."; return group
            }
            let roster = row.member_ids.enumerated().map { index, id in
                WhisperGroupMember(user_id: id, username: index < row.member_usernames.count ? row.member_usernames[index] : "member", profile_image_url: group.members.first { $0.user_id.lowercased() == id.lowercased() }?.profile_image_url)
            }
            let current = WhisperGroup(id: group.id, name: row.name, members: roster, createdAt: group.createdAt, ownerID: account, avatarPath: row.avatar_path)
            var seen = Set(row.member_ids.map { $0.lowercased() }); seen.insert(account)
            let fresh = people.filter { UUID(uuidString: $0.user_id) != nil && seen.insert($0.user_id.lowercased()).inserted }
            guard !fresh.isEmpty else { replace(current); return current }
            var next = current; next.members.append(contentsOf: fresh)
            guard await updateRegistry(next, previous: current) else { return group }
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            // Invalidate an older in-flight registry read before adopting this confirmed roster.
            registryTask?.cancel(); registryTask = nil; syncToken = nil; lastSync = .distantPast
            replace(next)
            _ = await sendMessage(toGroup: next, body: "added \(fresh.map { "@\($0.username)" }.joined(separator: ", "))")
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            return next
        } catch {
            guard account == currentUID, generation == AccountStorage.generation else { return group }
            lastError = "Couldn't confirm the member update. Refresh and try again."
            return group
        }
    }

    /// Owner-only remove — they stop receiving new messages; their history stays theirs.
    func removeMember(_ group: WhisperGroup, _ member: WhisperGroupMember) async -> WhisperGroup {
        guard isOwner(group) else { return group }
        var next = group
        next.members.removeAll { $0.user_id.lowercased() == member.user_id.lowercased() }
        guard await updateRegistry(next, previous: group) else { return group }
        replace(next)
        _ = await sendMessage(toGroup: next, body: "removed @\(member.username)")
        return next
    }

    /// Device-only hide, not a server membership removal or Meet invitation revocation.
    func leave(_ group: WhisperGroup) async {
        left.insert(group.id.uuidString.lowercased())
        persistSmall()
    }

    /// Only acknowledge deletion after a returned server row; local hiding cannot trigger Meet revocation.
    func deleteGroup(_ id: UUID) async -> Bool {
        let account = currentUID; let generation = AccountStorage.generation
        guard let group = group(byID: id), isOwner(group) else {
            lastError = "This group is no longer available to delete from this account. Refresh and try again."
            return false
        }
        guard deletionOperations[id] == nil else {
            lastError = "Group deletion is already being checked. Please wait before retrying."
            return false
        }
        let token = UUID(); deletionOperations[id] = token
        defer { if deletionOperations[id] == token { deletionOperations[id] = nil } }
        lastError = nil
        do {
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            let session = try await client.auth.session
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            guard session.user.id.uuidString.lowercased() == account,
                  let base = URL(string: SupabaseService.supabaseURL),
                  var components = URLComponents(url: base.appendingPathComponent("rest/v1/whisper_group_threads"), resolvingAgainstBaseURL: false) else { throw CancellationError() }
            components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())"),
                                     URLQueryItem(name: "owner_id", value: "eq.\(account)"),
                                     URLQueryItem(name: "select", value: "id")]
            guard let url = components.url else { throw CancellationError() }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"; request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
            request.setValue(SupabaseService.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            guard client.auth.currentSession?.user.id.uuidString.lowercased() == account else { throw CancellationError() }
            struct DeletedRow: Decodable { let id: UUID }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let deleted = try? JSONDecoder().decode([DeletedRow].self, from: data),
                  deleted.count == 1, deleted.first?.id == id else {
                lastError = "Group deletion wasn't confirmed. Refresh before retrying; invitation revocation has not been confirmed here."
                return false
            }
            registryTask?.cancel(); registryTask = nil; syncToken = nil; lastSync = .distantPast
            activeRegistryIDs.remove(id)
            left.insert(id.uuidString.lowercased()); persistSmall()
            inboxSummaries.removeValue(forKey: id)
            invalidateInboxSummaries()
            groups.removeAll { $0.id == id }
            persist()
            return true
        } catch {
            guard currentUID == account, AccountStorage.generation == generation else { return false }
            lastError = "Couldn't confirm group deletion. Refresh before retrying; hiding a group does not revoke its Meet invitations."
            return false
        }
    }

    func group(byID id: UUID) -> WhisperGroup? {
        groups.first { $0.id == id }
    }

    func setPhoto(_ item: PhotosPickerItem, in group: WhisperGroup) async throws {
        let account = currentUID; let generation = AccountStorage.generation
        guard isOwner(group) else { throw WhisperGroupPhotoFailure.ownerOnly }
        guard let raw = try await item.loadTransferable(type: Data.self) else { throw WhisperGroupPhotoFailure.unreadable }
        guard raw.count <= 30 * 1024 * 1024 else { throw WhisperGroupPhotoFailure.tooLarge }
        let jpeg = try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(raw as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 640
                  ] as CFDictionary) else { throw WhisperChatMediaService.Failure.unreadable }
            let data = NSMutableData()
            guard let writer = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw WhisperChatMediaService.Failure.unreadable }
            CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            guard CGImageDestinationFinalize(writer) else { throw WhisperChatMediaService.Failure.unreadable }
            return data as Data
        }.value
        try WhisperChatMediaService.checkAccount(account, generation: generation)
        let path = "\(group.id.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        guard jpeg.count <= 1024 * 1024 else { throw WhisperGroupPhotoFailure.tooLarge }
        do {
            try await client.storage.from("whisper-group-avatars").upload(path: path, file: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: false))
        } catch {
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            print("[Groups] picture upload failed code=\((error as NSError).code)")
            throw WhisperGroupPhotoFailure.upload
        }
        try WhisperChatMediaService.checkAccount(account, generation: generation)
        try await saveAvatarPath(path, in: group, account: account, generation: generation)
    }

    func removePhoto(in group: WhisperGroup) async throws {
        try await saveAvatarPath(nil, in: group, account: currentUID, generation: AccountStorage.generation)
    }

    private func saveAvatarPath(_ path: String?, in group: WhisperGroup, account: String, generation: UUID) async throws {
        guard isOwner(group) else { throw WhisperGroupPhotoFailure.ownerOnly }
        try WhisperChatMediaService.checkAccount(account, generation: generation)
        let patch: [String: AnyJSON] = ["avatar_path": path.map { .string($0) } ?? .null]
        var confirmed = false
        do {
            let saved: [WhisperGroupAvatarReceipt] = try await client.from("whisper_group_threads")
                .update(patch).eq("id", value: group.id.uuidString.lowercased()).eq("owner_id", value: account)
                .select("id,avatar_path").execute().value
            confirmed = saved.contains { $0.id == group.id && $0.avatar_path == path }
        } catch {
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            // A lost PATCH reply does not mean the write failed. Reconcile without writing twice.
            let rows: [WhisperGroupAvatarReceipt]? = try? await client.from("whisper_group_threads")
                .select("id,avatar_path").eq("id", value: group.id.uuidString.lowercased()).execute().value
            confirmed = rows?.contains { $0.id == group.id && $0.avatar_path == path } == true
        }
        try WhisperChatMediaService.checkAccount(account, generation: generation)
        guard confirmed else { throw WhisperGroupPhotoFailure.confirmation }
        avatarRevisions[group.id] = UUID()
        var next = self.group(byID: group.id) ?? group
        next.avatarPath = path
        replace(next)
    }

    // MARK: - Sending

    /// Sends a single message to every group member via parallel
    /// `whisper_messages` inserts. Returns `true` if at least one recipient
    /// accepted the row.
    @discardableResult
    func sendMessage(toGroup group: WhisperGroup, body: String) async -> Bool {
        let accountID = AccountStorage.currentUserID
        let generation = AccountStorage.generation
        await syncRegistry(force: true)
        guard (try? WhisperChatMediaService.checkAccount(accountID, generation: generation)) != nil,
              activeRegistryIDs.contains(group.id), let group = self.group(byID: group.id), lastError == nil else { return false }
        let payload = "\(Self.headerPrefix)\(group.id.uuidString)::\(group.name)::\(body)"
        let logicalID = UUID()
        var recipients = group.members
        // The owner isn't stored in member_ids on the registry — a member's
        // send must still reach them.
        if let owner = group.ownerID, owner != currentUID,
           !recipients.contains(where: { $0.user_id.lowercased() == owner }) {
            recipients.append(WhisperGroupMember(user_id: owner, username: "owner", profile_image_url: nil))
        }
        recipients.removeAll { $0.user_id.lowercased() == currentUID }
        guard !recipients.isEmpty else { return false }
        return await withTaskGroup(of: Bool.self) { tg in
            for member in recipients {
                tg.addTask { @MainActor in
                    guard (try? WhisperChatMediaService.checkAccount(accountID, generation: generation)) != nil else { return false }
                    return await WhisperBackendService.shared.sendMessage(
                        toUserID: member.user_id,
                        toUsername: member.username,
                        body: payload,
                        messageID: UUID(),
                        logicalGroupMessageID: logicalID
                    )
                }
            }
            var anyOK = false
            for await ok in tg { anyOK = anyOK || ok }
            return anyOK
        }
    }

    /// Share-sheet receipts are kept for this open tray, so retries skip confirmed members.
    func sendShare(toGroup original: WhisperGroup, body: String, delivered: Set<String>,
                   messageIDForMember: (String) -> UUID) async -> (complete: Bool, delivered: Set<String>) {
        let accountID = AccountStorage.currentUserID
        let generation = AccountStorage.generation
        await syncRegistry(force: true)
        guard (try? WhisperChatMediaService.checkAccount(accountID, generation: generation)) != nil,
              activeRegistryIDs.contains(original.id), let group = self.group(byID: original.id), lastError == nil else {
            return (false, delivered)
        }
        var recipients = group.members
        if let owner = group.ownerID, !recipients.contains(where: { $0.user_id.lowercased() == owner.lowercased() }) {
            recipients.append(WhisperGroupMember(user_id: owner, username: "owner", profile_image_url: nil))
        }
        var seen: Set<String> = []
        recipients = recipients.filter { $0.user_id.lowercased() != accountID.lowercased() && seen.insert($0.user_id.lowercased()).inserted }
        guard !recipients.isEmpty else { return (false, delivered) }
        // Keep the envelope stable across retries even if the registry's display name changes.
        let payload = "\(Self.headerPrefix)\(group.id.uuidString)::\(original.name)::\(body)"
        let logicalID = messageIDForMember("logical-group-message")
        var receipts = delivered
        for member in recipients where !receipts.contains(member.user_id.lowercased()) {
            guard (try? WhisperChatMediaService.checkAccount(accountID, generation: generation)) != nil else { return (false, receipts) }
            let ok = await WhisperBackendService.shared.sendMessage(toUserID: member.user_id, toUsername: member.username, body: payload, requiresConfirmedDelivery: true,
                                                                   messageID: messageIDForMember(member.user_id), logicalGroupMessageID: logicalID)
            guard (try? WhisperChatMediaService.checkAccount(accountID, generation: generation)) != nil else { return (false, receipts) }
            if ok { receipts.insert(member.user_id.lowercased()) }
        }
        return (recipients.allSatisfy { receipts.contains($0.user_id.lowercased()) }, receipts)
    }

    /// Builds the plain-text reply-quote prefix every client can read. The
    /// quoted line is the message's FRIENDLY line ("Shared a wave · caption",
    /// "Photo", or its text) — never raw card wire, so a reply to a card
    /// can't decode as the card itself. Inner quotes become apostrophes so
    /// the `"…"` framing parses on every client.
    static func replyBody(quoting quoted: WhisperMessageRow, with text: String) -> String {
        let snippet = WhisperChatReply.quoteText(for: quoted.body)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\"", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = snippet.count > 90 ? String(snippet.prefix(90)) + "…" : snippet
        return "↩ @\(quoted.from_username): \"\(clipped)\"\n\n\(text)"
    }

    /// Every RAW fan-out row behind a collapsed group message: my own sends
    /// exist once per recipient (same sender + text within the same ~10s
    /// bucket); someone else's message is the single row they sent me.
    private func fanoutRows(for msg: WhisperMessageRow, in group: WhisperGroup) -> [WhisperMessageRow] {
        let backend = WhisperBackendService.shared
        // Former recipients still have authorized delivery rows. The current
        // roster must not truncate receipts or the sender’s unsend targets.
        let memberIDs = Set(backend.conversations.keys)
        let sender = msg.from_user_id.lowercased()
        let bucket = msg.created_at.map { String($0.prefix(18)) } ?? msg.id
        var targets: [WhisperMessageRow] = []
        var seen = Set<String>()
        for memberID in Set(memberIDs) {
            for row in backend.conversations[memberID] ?? [] {
                guard row.from_user_id.lowercased() == sender,
                      let parsed = Self.parse(row.body), parsed.groupID == group.id else { continue }
                let rowBucket = row.created_at.map { String($0.prefix(18)) } ?? row.id
                let event = WhisperMeetMessageIdentity.eventID(in: msg.body)
                let sameEvent = event != nil && event == WhisperMeetMessageIdentity.eventID(in: parsed.body)
                let sameIdentity = msg.logical_group_message_id != nil && msg.logical_group_message_id == row.logical_group_message_id
                let legacyMatch = msg.logical_group_message_id == nil && row.logical_group_message_id == nil && (sameEvent || (parsed.body == msg.body && rowBucket == bucket))
                guard row.id == msg.id || sameIdentity || legacyMatch else { continue }
                if seen.insert(row.id).inserted { targets.append(row) }
            }
        }
        return targets.isEmpty ? [msg] : targets
    }

    /// Unsends one of MY group messages everywhere: every fan-out row that
    /// carries it (one per recipient) is deleted, so it leaves every member's
    /// thread. `msg` is the collapsed row from `messages(forGroup:)`.
    func unsend(_ msg: WhisperMessageRow, in group: WhisperGroup) async {
        guard msg.from_user_id.lowercased() == currentUID else { return }
        let generation = AccountStorage.generation
        var removed = Set<String>()
        for row in fanoutRows(for: msg, in: group) {
            guard generation == AccountStorage.generation else { return }
            if await WhisperBackendService.shared.unsendMessage(row) { removed.insert(row.id.lowercased()) }
        }
        guard generation == AccountStorage.generation else { return }
        invalidateInboxSummaries(removingMessageIDs: removed)
    }

    /// "Delete for me" — hides every raw row behind the message on this
    /// device only (my own sends have one row per recipient; hiding just one
    /// would leave the bubble standing).
    func hideLocally(_ msg: WhisperMessageRow, in group: WhisperGroup) {
        let backend = WhisperBackendService.shared
        let rows = fanoutRows(for: msg, in: group)
        for row in rows { backend.hideMessageLocally(row.id) }
        invalidateInboxSummaries(removingMessageIDs: Set(rows.map { $0.id.lowercased() }))
    }

    // MARK: - Parsing

    /// Returns the `(groupID, name, body)` triple if `raw` is a group payload.
    nonisolated static func parse(_ raw: String) -> (groupID: UUID, name: String, body: String)? {
        guard raw.hasPrefix(headerPrefix) else { return nil }
        let rest = String(raw.dropFirst(headerPrefix.count))
        let parts = rest.components(separatedBy: "::")
        guard parts.count >= 3,
              let id = UUID(uuidString: parts[0]) else { return nil }
        let name = parts[1]
        let body = parts.dropFirst(2).joined(separator: "::")
        return (id, name, body)
    }

    /// Roster events both platforms announce on the wire — rendered as quiet
    /// system lines instead of bubbles.
    nonisolated static func isSystemLine(_ body: String) -> Bool {
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return b.hasPrefix("created the group")
            || b.hasPrefix("renamed the group to")
            || b.hasPrefix("added @")
            || b.hasPrefix("removed @")
            || b == "left the group"
    }

    /// Splits a `↩ @name: "quote"\n\nreply` body into its quote and text.
    nonisolated static func splitReply(_ body: String) -> (quote: WhisperGroupReplyQuote?, text: String) {
        guard body.hasPrefix("↩ @") else { return (nil, body) }
        guard let colon = body.firstIndex(of: ":") else { return (nil, body) }
        let name = String(body[body.index(body.startIndex, offsetBy: 3)..<colon])
        let afterColon = body[body.index(after: colon)...]
        guard let openQuote = afterColon.firstIndex(of: "\""),
              let closeQuote = afterColon[afterColon.index(after: openQuote)...].firstIndex(of: "\"") else { return (nil, body) }
        let quoted = String(afterColon[afterColon.index(after: openQuote)..<closeQuote])
        let rest = String(afterColon[afterColon.index(after: closeQuote)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (WhisperGroupReplyQuote(username: name, text: quoted), rest)
    }

    /// Messages that belong to `group` — pulled from the backend's per-user
    /// conversation cache (each member's thread carries a copy), fan-out
    /// duplicates of my own sends collapsed into one bubble.
    func messages(forGroup group: WhisperGroup) -> [WhisperMessageRow] {
        let backend = WhisperBackendService.shared
        let members = Set(backend.conversations.keys)

        // Cheap change signature over the RAW threads (no filtering/sorting).
        var signature = "h:\(backend.locallyDeletedMessageIDs.count)"
        for memberID in members.sorted() {
            let raw = backend.conversations[memberID] ?? []
            signature += "|\(memberID):\(raw.hashValue)"
        }
        let cacheKey = group.id.uuidString.lowercased()
        if let cached = messageIndex[cacheKey], cached.signature == signature {
            return cached.rows
        }

        var seenIDs = Set<String>()
        var seenFanout = Set<String>()
        var collected: [WhisperMessageRow] = []
        // Match the server’s earliest-copy representative regardless of which
        // recipient dictionary happens to be visited first.
        let rawRows = members.flatMap { backend.messages(with: $0) }.sorted {
            (WhisperBackendService.parseISO($0.created_at) ?? .distantPast, $0.id) <
            (WhisperBackendService.parseISO($1.created_at) ?? .distantPast, $1.id)
        }
        for row in rawRows {
                guard row.from_user_id.lowercased() == currentUID || row.to_user_id.lowercased() == currentUID,
                      let parsed = Self.parse(row.body), parsed.groupID == group.id else { continue }
                guard seenIDs.insert(row.id).inserted else { continue }
                // Meet fanout uses the event identity, not recipient-specific JSON or timestamp buckets.
                let key = WhisperGroupHistory.identity(row)
                guard seenFanout.insert(key).inserted else { continue }
                collected.append(WhisperMessageRow(
                    id: row.id,
                    from_user_id: row.from_user_id,
                    from_username: row.from_username,
                    to_user_id: row.to_user_id,
                    to_username: row.to_username,
                    body: parsed.body,
                    created_at: row.created_at,
                    read_at: row.read_at,
                    logical_group_message_id: row.logical_group_message_id
                ))
        }
        let sorted = collected.sorted { ($0.created_at ?? "", $0.id) < ($1.created_at ?? "", $1.id) }
        messageIndex[cacheKey] = (signature, sorted)
        return sorted
    }

    /// Only actual recipient receipts on the sender's visible fanout rows count as Seen.
    func readers(of message: WhisperMessageRow, in group: WhisperGroup) -> [WhisperGroupMember] {
        guard message.from_user_id.lowercased() == currentUID else { return [] }
        var seen: Set<String> = []
        return fanoutRows(for: message, in: group).compactMap { row in
            let recipient = row.to_user_id.lowercased()
            guard row.read_at.flatMap(WhisperBackendService.parseISO) != nil,
                  recipient != currentUID, seen.insert(recipient).inserted else { return nil }
            return group.members.first { $0.user_id.lowercased() == recipient }
                ?? WhisperGroupMember(user_id: recipient, username: row.to_username, profile_image_url: nil)
        }.sorted { $0.user_id < $1.user_id }
    }

    func unreadIDs(in group: WhisperGroup) -> [String] {
        WhisperMessageReadScope.unreadIDs(rows: WhisperBackendService.shared.conversations.values.flatMap { $0 }, recipient: currentUID, groupID: group.id)
    }

    func isUnread(_ group: WhisperGroup) -> Bool {
        !isMuted(group) && (hasLoadedInbox ? (inboxSummaries[group.id]?.unread_count ?? 0) > 0 : !unreadIDs(in: group).isEmpty)
    }

    func markRead(_ group: WhisperGroup) async {
        let generation = AccountStorage.generation
        let ids = unreadIDs(in: group)
        await WhisperBackendService.shared.markMessageIDsRead(ids)
        guard generation == AccountStorage.generation else { return }
        if !ids.isEmpty { invalidateInboxSummaries() }
    }

    /// Most recent message in a group, used for the inbox row preview.
    func lastMessage(forGroup group: WhisperGroup) -> (body: String, date: Date)? {
        if hasLoadedInbox {
            guard let row = inboxSummaries[group.id], let parsed = Self.parse(row.last_message.body) else { return nil }
            return (parsed.body, WhisperBackendService.parseISO(row.last_created_at) ?? .distantPast)
        }
        let msgs = messages(forGroup: group)
        guard let last = msgs.last else { return nil }
        let date = last.created_at.flatMap { WhisperBackendService.parseISO($0) } ?? Date()
        return (last.body, date)
    }
}
