import SwiftUI
import Supabase
import CryptoKit

/// Account-local conversation text and message identities. Shared cards are
/// resolved with current access on reopening; media and live analysis aren't saved.
nonisolated struct WhisperEmberConversation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var updatedAt: Date
    var messages: [Message]
    var botID: String? = nil

    nonisolated struct Message: Codable, Equatable, Sendable {
        let role: String   // "user" | "ember"
        let text: String
        var reaction: String? = nil
        var reactionRevision: Int? = nil
        var reactionRecordedAt: String? = nil
        var sharedPostIDs: [String]? = nil
        var sharedCommunityIDs: [String]? = nil
        var proposals: [WhisperKnotActionProposal]? = nil
        var backgroundMessageID: String? = nil
        var responsibility: WhisperKnotResponsibilityProposal? = nil
        var shell: WhisperKnotShellProposal? = nil
        var calculation: WhisperKnotCalculationReceipt? = nil
        var browserPreview: Bool? = nil
        var replyTo: WhisperKnotReplyReference? = nil
        var interrupted: Bool? = nil
        var clarification: WhisperKnotClarification? = nil
        var clarificationAnswer: String? = nil
        var pillTimeline: [KnotPillTransition]? = nil
        var serverTaskID: String? = nil
        var id: UUID? = nil
        var createdAt: Double? = nil
        var modifiedAt: Double? = nil

        var confirmedReaction: String? {
            guard role == "user", let id, let reaction, let reactionRevision, let reactionRecordedAt,
                  WhisperKnotReaction(messageID: id, emoji: reaction, revision: reactionRevision, recordedAt: reactionRecordedAt).valid else { return nil }
            return reaction
        }
        @MainActor func materialized(conversationID: UUID, bot: String, sourceText: String? = nil) -> Self {
            guard role == "ember", let serverTaskID, UUID(uuidString: serverTaskID) != nil,
                  let id, calculation == nil, clarification == nil else { return self }
            // The saved envelope is data. Parsing creates review cards only;
            // no action, command, navigation or Responsibility is executed.
            let action = WhisperEmberActionParser.parse(text)
            let followup = WhisperEmberEngine.extractFollowups(action.text)
            let message = WhisperKnotMessageSkills.parse(followup.text)
            let blocks = WhisperEmberBlocks.parse(message.text)
            let allActions = Array((action.actions + message.actions).prefix(4))
            let actions = allActions.filter { !($0.kind == .open && ["post", "community", "communities"].contains($0.route ?? "")) }
            let actionPosts = allActions.compactMap { action -> String? in
                guard action.kind == .open, action.route == "post", let id = action.arg, UUID(uuidString: id) != nil else { return nil }
                return id
            }
            var postIDs = message.posts + actionPosts
            var seen = Set<String>()
            postIDs = Array(postIDs.filter { seen.insert($0.lowercased()).inserted }.prefix(3))
            var communityIDs = message.communities
            for action in allActions where action.kind == .open && ["community", "communities"].contains(action.route ?? "") {
                if let arg = action.arg, let community = WhisperCommunity.resolve(topic: arg), !communityIDs.contains(community.id) { communityIDs.append(community.id) }
            }
            var cards = WhisperKnotActionProposal.proposals(actions: actions, requests: message.requests)
            if case .postdraft(let draft) = blocks.block, !cards.contains(where: { $0.kind == .post }), cards.count < 4 {
                let caption = draft.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let tags = (draft.hashtags ?? []).map { "#\($0)" }.filter { !caption.localizedCaseInsensitiveContains($0) }
                cards.append(.init(kind: .post, text: ([caption] + tags).filter { !$0.isEmpty }.joined(separator: "\n"), target: draft.community ?? ""))
            }
            let reviewFallback = cards.isEmpty && message.responsibility == nil ? sourceText.flatMap { WhisperKnotActionProposal.reviewFallback(for: $0) } : nil
            if let reviewFallback { cards.append(reviewFallback) }
            var displayText = WhisperKnotOutput.clean(blocks.text)
            if let reviewFallback {
                displayText = "Nothing has been run. Review the request below" + (reviewFallback.needsDetails ? " and add the exact details before allowing it." : ", then choose whether to allow it.")
            } else if displayText.isEmpty && cards.isEmpty && message.responsibility == nil && postIDs.isEmpty && communityIDs.isEmpty {
                displayText = "I couldn’t provide a usable reply for this request. Check Events for the confirmed steps."
            }
            var value = Self(role: role, text: displayText, serverTaskID: serverTaskID, id: id, createdAt: createdAt, modifiedAt: modifiedAt)
            value.sharedPostIDs = postIDs
            value.sharedCommunityIDs = Array(communityIDs.prefix(3))
            for index in cards.indices { cards[index].id = WhisperEmberHistoryStore.backgroundIdentity("owned-proposal:\(id):\(index)") }
            value.proposals = cards.isEmpty ? nil : cards
            if let spec = message.responsibility {
                var proposal = WhisperKnotResponsibilityProposal(spec: spec, botID: bot, conversationID: conversationID)
                proposal.id = WhisperEmberHistoryStore.backgroundIdentity("owned-responsibility:\(serverTaskID)")
                proposal.createdAt = Date(timeIntervalSince1970: (createdAt ?? 0) / 1000)
                value.responsibility = proposal
            }
            return value
        }
        var restoredProposals: [WhisperKnotActionProposal] {
            let recentOwned = serverTaskID != nil && Date().timeIntervalSince1970 * 1000 - (createdAt ?? 0) < 900000
            return (proposals ?? []).map { recentOwned && $0.state == .pending ? $0 : $0.restored() }
        }
        var restoredResponsibility: WhisperKnotResponsibilityProposal? {
            guard let responsibility else { return nil }
            return serverTaskID != nil && responsibility.reviewable ? responsibility : responsibility.restored()
        }
        func reconcilingReaction(_ other: Self) -> Self {
            var value = self
            if serverTaskID != nil, serverTaskID == other.serverTaskID, id == other.id {
                // Re-reading immutable delivery must not reset a local approval,
                // decline or uncertain receipt into a new pending proposal.
                if let cards = other.proposals, !cards.isEmpty { value.proposals = cards }
                if let proposal = other.responsibility { value.responsibility = proposal }
            }
            let chosen = other.confirmedReaction != nil && (other.reactionRevision ?? 0) > (confirmedReaction != nil ? reactionRevision ?? 0 : 0) ? other : self
            value.reaction = chosen.confirmedReaction
            value.reactionRevision = value.reaction == nil ? nil : chosen.reactionRevision
            value.reactionRecordedAt = value.reaction == nil ? nil : chosen.reactionRecordedAt
            if id == other.id, role == other.role, text == other.text {
                // Reaction-only server snapshots and older clients may omit
                // immutable display metadata. Omission is not a quote deletion.
                if role == "user", value.clarificationAnswer == nil { value.clarificationAnswer = other.clarificationAnswer }
                if role == "user", (other.pillTimeline?.count ?? 0) > (value.pillTimeline?.count ?? 0) { value.pillTimeline = other.pillTimeline }
                if role == "user", value.replyTo == nil, other.replyTo?.valid == true { value.replyTo = other.replyTo }
                if role == "ember", value.clarification == nil, other.clarification?.valid == true { value.clarification = other.clarification }
                if role == "ember", other.interrupted == true { value.interrupted = true }
            }
            return value
        }
    }

    init(id: UUID = UUID(), title: String, updatedAt: Date = Date(), messages: [Message] = []) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

/// Account-scoped local history with durable server sync shared by native and web.
/// Keeps recent conversations plus dirty work; restored metadata is display-only.
@Observable
final class WhisperEmberHistoryStore {
    static let shared = WhisperEmberHistoryStore()
    private static let storageKey = "whisper_ember_history_v1"
    private static let maxConversations = 40

    private(set) var conversations: [WhisperEmberConversation] = []

    static let changed = Notification.Name("WhisperKnotHistoryChanged")
    private static let deletedKey = "knot_history_deleted_v1"
    private static let dirtyKey = "knot_history_dirty_v1"
    private static let pendingDeleteKey = "knot_history_pending_delete_v1"
    // Preserve the prior authority's marker; a new origin is not an import grant.
    private static let backendKey = "knot_history_backend_v2:\(WhisperKnotBackend.identity)"
    private var pendingDeletes: Set<UUID> = []
    private var deleted: Set<UUID> = []
    private var dirty: Set<UUID> = []
    private var syncing = false
    private var syncAgain = false
    private var remoteVersions: [UUID: Double] = [:]
    private var scheduled: Task<Void, Never>?
    private(set) var syncError: String?
    private var ownerGeneration: UUID = AccountStorage.generation
    init() { load() }

    func clearForAccountChange() { scheduled?.cancel(); conversations = []; deleted = []; pendingDeletes = []; dirty = []; remoteVersions = [:]; syncError = nil }
    func reloadForCurrentAccount() { remoteVersions = [:]; ownerGeneration = AccountStorage.generation; load() }
    func ensureCurrentAccount() {
        if ownerGeneration != AccountStorage.generation { reloadForCurrentAccount() }
    }

    private func load() {
        pendingDeletes = Set(((AccountStorage.object(forKey: Self.pendingDeleteKey) as? [String]) ?? []).compactMap(UUID.init(uuidString:)))
        deleted = Set(((AccountStorage.object(forKey: Self.deletedKey) as? [String]) ?? []).compactMap(UUID.init(uuidString:)))
        dirty = Set(((AccountStorage.object(forKey: Self.dirtyKey) as? [String]) ?? []).compactMap(UUID.init(uuidString:)))
        guard let data = AccountStorage.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([WhisperEmberConversation].self, from: data) else {
            conversations = []
            return
        }
        conversations = decoded.filter { !deleted.contains($0.id) }.sorted { $0.updatedAt > $1.updatedAt }
        for index in conversations.indices {
            var migrated = false
            for m in conversations[index].messages.indices {
                let background = conversations[index].messages[m].backgroundMessageID.map(Self.backgroundIdentity)
                if conversations[index].messages[m].id == nil || (background != nil && conversations[index].messages[m].id != background) {
                    conversations[index].messages[m].id = background ?? UUID(); migrated = true
                    let time = conversations[index].updatedAt.timeIntervalSince1970 * 1000 - Double(conversations[index].messages.count - m)
                    conversations[index].messages[m].createdAt = time
                    conversations[index].messages[m].modifiedAt = time
                }
            }
            if migrated { dirty.insert(conversations[index].id) }
        }
        persist()
    }

    private func persist() {
        guard ownerGeneration == AccountStorage.generation else { return }
        AccountStorage.set(pendingDeletes.map(\.uuidString), forKey: Self.pendingDeleteKey)
        AccountStorage.set(deleted.map(\.uuidString), forKey: Self.deletedKey)
        AccountStorage.set(dirty.map(\.uuidString), forKey: Self.dirtyKey)
        let recent = Set(conversations.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.maxConversations).map(\.id))
        let trimmed = conversations.filter { recent.contains($0.id) || dirty.contains($0.id) }.sorted { $0.updatedAt > $1.updatedAt }
        conversations = trimmed
        if let data = try? JSONEncoder().encode(trimmed) {
            AccountStorage.set(data, forKey: Self.storageKey)
        }
    }

    /// Saves (inserts or updates) a conversation from a set of turns. Derives a
    /// title from the first user message. No-op for empty threads.
    func save(id: UUID, messages: [WhisperEmberConversation.Message], botID: String? = nil) {
        guard ownerGeneration == AccountStorage.generation, !deleted.contains(id) else { return }
        let existing = conversations.first { $0.id == id }?.messages ?? []
        let now = Date().timeIntervalSince1970 * 1000
        let messages = messages.map { raw in
            var m = raw
            if m.id == nil { m.id = UUID() }
            if m.createdAt == nil { m.createdAt = now }
            if let old = existing.first(where: { $0.id == m.id }) {
                if old.serverTaskID != nil {
                    return old.reconcilingReaction(m)
                }
                // A covered view cannot turn an older snapshot into a new edit.
                if (m.modifiedAt ?? m.createdAt ?? 0) < (old.modifiedAt ?? old.createdAt ?? 0) {
                    var merged = old.reconcilingReaction(m)
                    if merged != old { merged.modifiedAt = max(now, (old.modifiedAt ?? 0) + 1) }
                    return merged
                }
                m = m.reconcilingReaction(old)
                m.modifiedAt = old.modifiedAt
                if m != old { m.modifiedAt = now }
            } else if m.modifiedAt == nil { m.modifiedAt = m.createdAt }
            return m
        }
        let meaningful = messages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.responsibility != nil || $0.shell != nil || $0.calculation?.valid == true }
        guard !meaningful.isEmpty else { return }
        let title = Self.deriveTitle(from: meaningful)
        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            // Preserve deliveries imported while the visible session was covered.
            let known = Set(messages.compactMap(\.id))
            let unseen = conversations[idx].messages.filter { !known.contains($0.id ?? UUID()) }
            let merged = (messages + unseen).sorted { ($0.createdAt ?? 0) < ($1.createdAt ?? 0) }
            guard merged != conversations[idx].messages else { return }
            conversations[idx].messages = merged
            conversations[idx].title = title
            conversations[idx].updatedAt = Date()
        } else {
            conversations.insert(
                WhisperEmberConversation(id: id, title: title, updatedAt: Date(), messages: messages),
                at: 0
            )
        }
        if let index = conversations.firstIndex(where: { $0.id == id }), let botID {
            conversations[index].botID = botID
        }
        dirty.insert(id); persist(); scheduleSync()
    }

    /// Import persisted assistant deliveries, never synthetic local progress.
    /// A stable server identity makes repeated pages/device restarts idempotent.
    @discardableResult
    func mergeBackgroundMessages(_ deliveries: [WhisperKnotBackgroundMessage]) -> Bool {
        guard ownerGeneration == AccountStorage.generation else { return false }
        var changed = false
        for delivery in deliveries {
            guard let id = UUID(uuidString: delivery.conversationID), !deleted.contains(id), let bot = WhisperKnotBot(rawValue: delivery.bot) else { continue }
            if let index = conversations.firstIndex(where: { $0.id == id }) {
                let existingBot = conversations[index].botID ?? "main"
                guard existingBot == bot.rawValue,
                      !conversations[index].messages.contains(where: { $0.backgroundMessageID == delivery.id }) else { continue }
                conversations[index].messages.append(.init(role: "ember", text: delivery.text, backgroundMessageID: delivery.id, id: Self.backgroundIdentity(delivery.id), createdAt: delivery.createdAt, modifiedAt: delivery.createdAt))
                conversations[index].updatedAt = max(conversations[index].updatedAt, Date(timeIntervalSince1970: delivery.createdAt / 1000))
                dirty.insert(id); changed = true
            } else {
                var conversation = WhisperEmberConversation(id: id, title: "Updates from \(bot.displayName)", updatedAt: Date(timeIntervalSince1970: delivery.createdAt / 1000), messages: [.init(role: "ember", text: delivery.text, backgroundMessageID: delivery.id, id: Self.backgroundIdentity(delivery.id), createdAt: delivery.createdAt, modifiedAt: delivery.createdAt)])
                conversation.botID = bot.rawValue; conversations.append(conversation); dirty.insert(id); changed = true
            }
        }
        if changed { persist(); scheduleSync() }
        return true
    }

    func ongoingConversation(for bot: WhisperKnotBot) -> WhisperEmberConversation? {
        conversations.sorted { $0.updatedAt > $1.updatedAt }.first {
            $0.botID == bot.rawValue || (bot == .main && $0.botID == nil)
        }
    }

    /// Update only the original persisted command identity, even after its view closed.
    func updateShell(_ shell: WhisperKnotShellProposal) {
        guard ownerGeneration == AccountStorage.generation,
              let id = UUID(uuidString: shell.spec.conversationID),
              let index = conversations.firstIndex(where: { $0.id == id && ($0.botID ?? "main") == shell.spec.bot }),
              let message = conversations[index].messages.firstIndex(where: { $0.shell?.id == shell.id }) else { return }
        let previous = conversations[index].messages[message].shell
        var merged = shell
        if let previous {
            if let result = shell.result {
                if !result.canReplace(previous.result) { merged.result = previous.result; merged.state = previous.state }
            } else if previous.result != nil {
                merged.result = previous.result; merged.state = previous.state
            }
            merged.continued = merged.continued || previous.continued
        }
        conversations[index].messages[message].shell = merged
        conversations[index].messages[message].modifiedAt = Date().timeIntervalSince1970 * 1000
        dirty.insert(id); persist(); scheduleSync()
    }

    func delete(_ id: UUID) {
        guard ownerGeneration == AccountStorage.generation else { return }
        WhisperKnotOriginalStore.delete(conversationID: id)
        deleted.insert(id); pendingDeletes.insert(id); dirty.remove(id)
        conversations.removeAll { $0.id == id }
        persist(); scheduleSync()
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    private func scheduleSync() {
        scheduled?.cancel()
        scheduled = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            scheduled = nil
            await sync()
        }
    }

    static func backgroundIdentity(_ value: String) -> UUID {
        let hex = SHA256.hash(data: Data(("background:" + value).utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        let chars = Array(hex)
        let formatted = [String(chars[0..<8]), String(chars[8..<12]), String(chars[12..<16]), String(chars[16..<20]), String(chars[20..<32])].joined(separator: "-")
        return UUID(uuidString: formatted)!
    }

    /// Merge private display history. No restored message supplies execution consent.
    func sync() async {
        ensureCurrentAccount()
        guard WhisperKnotBackend.syncRetainedHistory else { return }
        if syncing { syncAgain = true; return }
        guard UUID(uuidString: AccountStorage.currentUserID) != nil else { return }
        syncing = true; syncAgain = false
        let generation = ownerGeneration
        defer {
            syncing = false
            if syncAgain { syncAgain = false; scheduleSync() }
        }
        func check() throws {
            try Task.checkCancellation()
            guard generation == AccountStorage.generation else { throw CancellationError() }
        }
        do {
            let auth = try await SupabaseService.shared.client.auth.session
            try check()
            guard auth.user.id.uuidString.lowercased() == AccountStorage.currentUserID.lowercased() else { throw HistoryFailure.unavailable }
            let token = auth.accessToken
            if AccountStorage.string(forKey: Self.backendKey) != WhisperKnotBackend.identity {
                // Keep old snapshots, dirty work and deletion evidence local until
                // continuity is approved. Do not upload or delete on a new authority
                // merely because its URL changed, or overwrite the old marker.
                guard conversations.isEmpty, dirty.isEmpty, deleted.isEmpty, pendingDeletes.isEmpty else {
                    throw HistoryFailure.continuityRequired
                }
                remoteVersions = [:]
                AccountStorage.set(WhisperKnotBackend.identity, forKey: Self.backendKey)
            }
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
                try check()
                let url = URL(string: WhisperKnotBackend.origin + "/knot/conversations" + path)!
                var r = URLRequest(url: url); r.httpMethod = method; r.httpBody = body; r.timeoutInterval = 20
                r.setValue("Bearer \(token)", forHTTPHeaderField: "X-Whisper-Authorization")
                r.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let (data, response) = try await session.data(for: r)
                try check()
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 410 { throw HistoryFailure.deleted }
                guard (200..<300).contains(code), data.count < 1_000_000 else { throw HistoryFailure.unavailable }
                return data
            }
            for id in Array(pendingDeletes) {
                _ = try await request("/" + id.uuidString.lowercased(), method: "DELETE")
                pendingDeletes.remove(id); persist()
            }
            struct Header: Decodable { let id: UUID; let botID: String; let title: String; let updatedAt: Double; let deleted: Bool }
            struct Index: Decodable { let conversations: [Header]; let next: String? }
            struct Cursor: Decodable { let after: Double; let afterID: String }
            struct Page: Decodable { let messages: [WhisperEmberConversation.Message]; let next: Cursor? }
            struct Upload: Encodable { let botID: String; let title: String; let messages: [WhisperEmberConversation.Message] }
            var headers: [Header] = [], cursor: String?
            repeat {
                let data = try await request(cursor.map { "?after=" + $0 } ?? "")
                let page = try JSONDecoder().decode(Index.self, from: data)
                headers += page.conversations; cursor = page.next
                guard headers.count <= 10000 else { throw HistoryFailure.unavailable }
            } while cursor != nil
            for header in headers where header.deleted {
                if !deleted.contains(header.id) { WhisperKnotOriginalStore.delete(conversationID: header.id) }
                deleted.insert(header.id); pendingDeletes.remove(header.id); dirty.remove(header.id)
            }
            conversations.removeAll { deleted.contains($0.id) }; persist()
            var incomplete = false
            for header in headers.filter({ !$0.deleted }).sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(Self.maxConversations) {
                guard !deleted.contains(header.id) else { continue }
                if remoteVersions[header.id] == header.updatedAt && conversations.contains(where: { $0.id == header.id }) { continue }
                var remote: [WhisperEmberConversation.Message] = [], after: Cursor?
                do {
                    repeat {
                        let query = after.map { "?after=\($0.after)&afterID=\($0.afterID)" } ?? ""
                        let data = try await request("/" + header.id.uuidString.lowercased() + query)
                        let page = try JSONDecoder().decode(Page.self, from: data)
                        remote += page.messages; after = page.next
                        guard remote.count <= 20000 else { throw HistoryFailure.unavailable }
                    } while after != nil
                    let sources = Dictionary(remote.compactMap { message -> (String, String)? in
                        guard message.role == "user", let id = message.id else { return nil }
                        return (id.uuidString.lowercased(), message.text)
                    }, uniquingKeysWith: { first, _ in first })
                    remote = remote.map { $0.materialized(conversationID: header.id, bot: header.botID, sourceText: $0.serverTaskID.flatMap { sources[$0.lowercased()] }) }
                } catch HistoryFailure.deleted {
                    WhisperKnotOriginalStore.delete(conversationID: header.id)
                    deleted.insert(header.id); dirty.remove(header.id); pendingDeletes.remove(header.id)
                    conversations.removeAll { $0.id == header.id }; persist(); continue
                } catch {
                    try check()
                    // One unavailable remote thread must not strand local uploads.
                    // Keep its old snapshot/version and retry on the next sync.
                    incomplete = true; continue
                }
                guard !deleted.contains(header.id) else { continue }
                let index = conversations.firstIndex { $0.id == header.id }
                var merged: [UUID: WhisperEmberConversation.Message] = [:]
                for message in remote { if let id = message.id { merged[id] = message } }
                for local in index.map({ conversations[$0].messages }) ?? [] {
                    if let id = local.id {
                        if let remote = merged[id] {
                            var message = remote.serverTaskID != nil ? remote.reconcilingReaction(local) : (local.modifiedAt ?? 0) >= (remote.modifiedAt ?? 0) ? local.reconcilingReaction(remote) : remote.reconcilingReaction(local)
                            if message.replyTo != remote.replyTo || message.interrupted != remote.interrupted {
                                message.modifiedAt = max(Date().timeIntervalSince1970 * 1000, max(local.modifiedAt ?? 0, remote.modifiedAt ?? 0) + 1)
                                dirty.insert(header.id)
                            }
                            merged[id] = message
                        } else { merged[id] = local.reconcilingReaction(local) }
                    }
                }
                let local = index.map { conversations[$0] }
                var conversation = WhisperEmberConversation(id: header.id, title: dirty.contains(header.id) ? local?.title ?? header.title : header.title, updatedAt: max(local?.updatedAt ?? .distantPast, Date(timeIntervalSince1970: header.updatedAt / 1000)), messages: merged.values.sorted { ($0.createdAt ?? 0, $0.id?.uuidString ?? "") < ($1.createdAt ?? 0, $1.id?.uuidString ?? "") })
                conversation.botID = header.botID
                if let index { conversations[index] = conversation } else { conversations.append(conversation) }
                persist()
                remoteVersions[header.id] = header.updatedAt
            }
            // Dirty snapshots are cleared only if no local edit happened during upload.
            for id in Array(dirty) {
                guard !deleted.contains(id), let snapshot = conversations.first(where: { $0.id == id }) else { continue }
                do {
                    for message in snapshot.messages {
                        try check()
                        if message.serverTaskID != nil { continue }
                        guard !deleted.contains(id) else { break }
                        let encodedMessage = try JSONEncoder().encode(message)
                        guard encodedMessage.count <= 100000 else { throw HistoryFailure.unavailable }
                        let body = try JSONEncoder().encode(Upload(botID: snapshot.botID ?? "main", title: snapshot.title, messages: [message]))
                        guard body.count <= 256000 else { throw HistoryFailure.unavailable }
                        _ = try await request("/" + id.uuidString.lowercased(), method: "POST", body: body)
                    }
                    if conversations.first(where: { $0.id == id }) == snapshot { dirty.remove(id) }
                } catch HistoryFailure.deleted { WhisperKnotOriginalStore.delete(conversationID: id); deleted.insert(id); dirty.remove(id); conversations.removeAll { $0.id == id } }
                catch {
                    try check()
                    // Leave this snapshot dirty, but still save other threads.
                    incomplete = true
                }
                persist()
            }
            try check()
            syncError = incomplete ? "Some chats haven’t synced across devices yet. Pull to refresh to retry." : nil
            persist()
            NotificationCenter.default.post(name: Self.changed, object: nil)
        } catch {
            guard generation == AccountStorage.generation else { return }
            if let failure = error as? HistoryFailure, case .continuityRequired = failure {
                syncError = "Your saved chats are safe on this device. Moving them to the updated service is not enabled yet."
            } else {
                syncError = "Your chats are kept here. Pull to refresh to retry syncing."
            }
            persist()
            NotificationCenter.default.post(name: Self.changed, object: nil)
        }
    }
    private enum HistoryFailure: Error { case deleted, unavailable, continuityRequired }

    func isDeleted(_ id: UUID) -> Bool { deleted.contains(id) }

    func conversation(_ id: UUID) -> WhisperEmberConversation? {
        conversations.first { $0.id == id }
    }

    private static func deriveTitle(from messages: [WhisperEmberConversation.Message]) -> String {
        let firstUser = messages.first { $0.role == "user" }?.text ?? messages.first?.responsibility?.spec.title ?? messages.first?.text ?? "New chat"
        let clean = firstUser.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.count > 48 ? String(clean.prefix(48)) + "…" : clean
    }
}

/// THE CHAT HISTORY DRAWER — Whisper's design language, not the assistant's
/// glow canvas: the surface color, hairlines, the Jasper icon in the header,
/// an ink "New chat" pill, conversations grouped under quiet uppercase
/// kickers (TODAY · YESTERDAY · THIS WEEK · EARLIER), the current chat marked
/// with an ink dot, and swipe/long-press to delete.
struct WhisperEmberHistoryDrawer: View {
    let store: WhisperEmberHistoryStore
    let currentID: UUID
    let onNewChat: () -> Void
    let onSelect: (WhisperEmberConversation) -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var query: String = ""
    @State private var confirmDelete: WhisperEmberConversation?

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }

    private struct Group: Identifiable {
        let id: String
        let title: String
        let items: [WhisperEmberConversation]
    }

    private var filtered: [WhisperEmberConversation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.conversations }
        return store.conversations.filter { convo in
            convo.title.lowercased().contains(q) || convo.messages.contains { $0.text.lowercased().contains(q) }
        }
    }

    private var groups: [Group] {
        let cal = Calendar.current
        let now = Date()
        var today: [WhisperEmberConversation] = []
        var yesterday: [WhisperEmberConversation] = []
        var week: [WhisperEmberConversation] = []
        var earlier: [WhisperEmberConversation] = []
        for convo in filtered {
            if cal.isDateInToday(convo.updatedAt) {
                today.append(convo)
            } else if cal.isDateInYesterday(convo.updatedAt) {
                yesterday.append(convo)
            } else if convo.updatedAt > now.addingTimeInterval(-7 * 86_400) {
                week.append(convo)
            } else {
                earlier.append(convo)
            }
        }
        var out: [Group] = []
        if !today.isEmpty { out.append(Group(id: "today", title: "Today", items: today)) }
        if !yesterday.isEmpty { out.append(Group(id: "yesterday", title: "Yesterday", items: yesterday)) }
        if !week.isEmpty { out.append(Group(id: "week", title: "This week", items: week)) }
        if !earlier.isEmpty { out.append(Group(id: "earlier", title: "Earlier", items: earlier)) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let error = store.syncError {
                Text(error).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                Button("Retry syncing") { Task { await store.sync() } }.padding(.horizontal, 16)
            }
            newChatButton
            if store.conversations.count > 4 {
                searchField
            }
            if store.conversations.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                ScrollView { WhisperEmptyState(icon: "magnifyingglass", title: "No matching chats", message: "Try a different search.", isCard: false, compact: true) }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.title.uppercased())
                                    .font(.system(size: 11, weight: .black))
                                    .tracking(1.2)
                                    .foregroundStyle(muted)
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 4)
                                ForEach(group.items) { convo in
                                    row(convo)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(width: 0.5).ignoresSafeArea()
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.16), radius: 24, x: 8)
        .ignoresSafeArea(edges: .vertical)
        .task { await store.sync() }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete chat", role: .destructive) {
                if let c = confirmDelete { store.delete(c.id) }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Your chats")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ink)
                Text(store.conversations.isEmpty ? "Knot" : "\(store.conversations.count) with Knot")
                    .font(.caption)
                    .foregroundStyle(muted)
            }
            Spacer()
            Button {
                Haptics.tap()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ink)
                    .frame(width: 32, height: 32)
                    .background(WhisperTheme.card(colorScheme), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close history")
        }
        .padding(.horizontal, 16)
        .padding(.top, 68)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(height: 0.5)
        }
    }

    private var newChatButton: some View {
        Button {
            Haptics.tap()
            onNewChat()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .semibold))
                Text("New chat")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }
            .foregroundStyle(WhisperTheme.surface(colorScheme))
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(ink, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(muted)
            TextField("Search chats", text: $query)
                .font(.system(size: 14))
                .foregroundStyle(ink)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75) }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            WhisperMeetDoodle(symbol: "bubble.left.and.text.bubble.right", height: 144)
            Text("No chats yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
            Text("Your conversations with Knot will show up here.")
                .font(.caption)
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.top, 48)
    }

    private func row(_ convo: WhisperEmberConversation) -> some View {
        let isCurrent = convo.id == currentID
        let preview = convo.messages.last(where: { $0.role == "ember" })?.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            Haptics.tap()
            onSelect(convo)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(isCurrent ? ink : Color.clear)
                    .frame(width: 6, height: 6)
                    .padding(.top, 7)
                VStack(alignment: .leading, spacing: 3) {
                    Text(convo.title)
                        .font(.system(size: 14.5, weight: isCurrent ? .bold : .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    if let preview, !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 12.5))
                            .foregroundStyle(muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                Text(convo.updatedAt, format: .relative(presentation: .named))
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(isCurrent ? WhisperTheme.card(colorScheme) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                confirmDelete = convo
            } label: {
                Label("Delete chat", systemImage: "trash")
            }
        }
    }
}
