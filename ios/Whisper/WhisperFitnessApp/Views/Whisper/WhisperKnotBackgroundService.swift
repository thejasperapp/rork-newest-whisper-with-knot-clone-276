import Foundation
import Supabase

nonisolated struct WhisperKnotResponsibility: Codable, Identifiable, Sendable {
    let id: String
    let bot: String
    let conversationID: String
    let kind: String
    let title: String
    let instruction: String
    let searchQuery: String
    let minIntervalMinutes: Int
    let maxIntervalMinutes: Int
    let timezone: String
    let quietStart: Int
    let quietEnd: Int
    let endsAt: Double
    let nextRunAt: Double
    let state: String
    let lastRunAt: Double?
    let lastOutcome: String
    let revision: String
    let contact: WhisperKnotContactGrant?
    var nextDate: Date { Date(timeIntervalSince1970: nextRunAt / 1000) }
    var endDate: Date { Date(timeIntervalSince1970: endsAt / 1000) }
}
nonisolated struct WhisperKnotBackgroundMessage: Decodable, Sendable {
    let sequence: Int
    let id: String
    let ruleID: String
    let bot: String
    let conversationID: String
    let text: String
    let createdAt: Double
    let read: Bool
}
nonisolated struct WhisperKnotResponsibilityApproval: Encodable, Sendable {
    let consentVersion = "knot_background_read_report_v1"
    let approvalEpoch: String
    let id: String
    let bot: String
    let conversationID: String
    let kind: String
    let title: String
    let instruction: String
    let searchQuery: String
    let minIntervalMinutes: Int
    let maxIntervalMinutes: Int
    let timezone: String
    let quietStart: Int
    let quietEnd: Int
    let endsAt: Double
    var creatorReadConsent: String? = nil
}

/// Server alarms own unattended work; this client only reviews grants, reads
/// persisted results and acknowledges controls. No saved user session on server.
@MainActor @Observable final class WhisperKnotBackgroundService {
    static let shared = WhisperKnotBackgroundService()
    static let messagesChanged = Notification.Name("WhisperKnotBackgroundMessages")
    private(set) var rules: [WhisperKnotResponsibility] = []
    private(set) var approvalEpoch: String?
    private(set) var unread = 0
    private(set) var busy = false
    var error: String?
    @ObservationIgnored private var generation = AccountStorage.generation
    @ObservationIgnored private var blockedGeneration: UUID?
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var lastMessageSync: Date?
    @ObservationIgnored private var unreadRevision = UUID()
    @ObservationIgnored private var rulesRevision = UUID()
    @ObservationIgnored private var messageRevision = UUID()
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var markingRead = false
    @ObservationIgnored private var confirmedReadIDs = Set<String>()
    // Sequence numbers belong to one backend; retain the old cursor untouched.
    private let cursorKey = "knot_background_message_cursor_v1:\(WhisperKnotBackend.identity)"

    init() {
        observer = NotificationCenter.default.addObserver(forName: .init("WhisperMeetingAccountWillChange"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() }
        }
    }
    private func reset() {
        blockedGeneration = AccountStorage.generation
        rules = []; approvalEpoch = nil; unread = 0; error = nil; busy = false; syncing = false; generation = UUID()
        lastMessageSync = nil; unreadRevision = UUID(); rulesRevision = UUID(); messageRevision = UUID(); refreshID = UUID()
        markingRead = false; confirmedReadIDs = []
    }
    private func prepare() {
        guard blockedGeneration != AccountStorage.generation else { return }
        if generation != AccountStorage.generation {
            rules = []; approvalEpoch = nil; unread = 0; error = nil; busy = false; syncing = false
            generation = AccountStorage.generation; blockedGeneration = nil
            lastMessageSync = nil; unreadRevision = UUID(); rulesRevision = UUID(); messageRevision = UUID(); refreshID = UUID()
            markingRead = false; confirmedReadIDs = []
        }
    }
    private nonisolated struct Listing: Decodable, Sendable { let rules: [WhisperKnotResponsibility]; let approvalEpoch: String; let unread: Int }
    private nonisolated struct Deliveries: Decodable, Sendable { let messages: [WhisperKnotBackgroundMessage]; let next: Int; let unread: Int }
    private nonisolated struct Saved: Decodable, Sendable { let rule: WhisperKnotResponsibility }
    private nonisolated struct Acknowledged: Decodable, Sendable { let ok: Bool }
    private nonisolated struct EpochBody: Encodable { let approvalEpoch: String }
    private nonisolated struct ReadBody: Encodable { let conversationID: String; let messageIDs: [String] }
    private nonisolated struct ReadResult: Decodable, Sendable { let ok: Bool; let unread: Int }
    private nonisolated struct ServiceFailure: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    private func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        try Task.checkCancellation()
        let owner = AccountStorage.currentUserID, lease = AccountStorage.generation
        guard owner != "guest", generation == lease else { throw CancellationError() }
        let token = try await SupabaseService.shared.client.auth.session.accessToken
        try Task.checkCancellation()
        guard generation == lease, AccountStorage.generation == lease, AccountStorage.currentUserID == owner else { throw CancellationError() }
        guard let url = URL(string: WhisperKnotBackend.origin + "/knot/background" + path) else { throw CancellationError() }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "X-Whisper-Authorization")
        let configuration = URLSessionConfiguration.ephemeral; configuration.urlCache = nil; configuration.timeoutIntervalForResource = 18
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        // Foundation propagates Task cancellation to this request. Invalidating
        // the session in onCancel can race with task creation and abort the app.
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard generation == lease, AccountStorage.generation == lease, AccountStorage.currentUserID == owner else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse, data.count < 1_000_000 else { throw ServiceFailure("Responsibilities couldn’t load just now.") }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 403,
               (try? JSONDecoder().decode([String: String].self, from: data)["error"]) == "creator_access_required" {
                throw ServiceFailure("Performance monitoring needs Analytics access: a creator or business account, Whisper One, or Creator Studio. Creator scores still require verified or staff access.")
            }
            if http.statusCode == 401 || http.statusCode == 403 { throw ServiceFailure("Please sign in again to manage responsibilities.") }
            if http.statusCode == 409 { throw ServiceFailure("This permission or responsibility changed, ended, or the list is full. Refresh and review the exact rule again.") }
            throw ServiceFailure("Couldn’t confirm this change. Refresh to check what was saved before trying again.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func contactRequest<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        prepare()
        return try await request(path, method: method, body: body)
    }
    func approveContact(_ approval: WhisperKnotContactApproval, ruleID: String) async -> Bool {
        prepare()
        guard !busy, WhisperKnotContextPermission.allowed, !AccountStorage.bool(forKey: "knot_background_pause_pending_v1") else { return false }
        guard !approval.calls || (WhisperKnotVoicePreferences.allowed && !AccountStorage.bool(forKey: "knot_contact_calls_pause_pending_v1")) else {
            error = "Confirm the invitation pause and review Voice & calls before approving call invitations."; return false
        }
        let lease = generation; busy = true; rulesRevision = UUID()
        defer { if generation == lease { busy = false } }
        do {
            let saved: Acknowledged = try await request("/\(ruleID)/contact", method: "POST", body: JSONEncoder().encode(approval))
            guard generation == lease, saved.ok else { return false }
            await refresh(); return true
        } catch is CancellationError { return false } catch {
            if generation == lease { self.error = "Couldn’t confirm contact permission. Refresh before trying again." }
            return false
        }
    }
    func refresh() async {
        prepare(); let lease = generation, revision = rulesRevision, unreadLease = unreadRevision, attempt = UUID()
        refreshID = attempt
        do {
            let result: Listing = try await request("")
            guard generation == lease, lease == AccountStorage.generation,
                  revision == rulesRevision, refreshID == attempt else { return }
            rules = result.rules; approvalEpoch = result.approvalEpoch
            if unreadRevision == unreadLease { unread = result.unread }
            error = nil
        } catch is CancellationError {} catch {
            guard generation == lease, lease == AccountStorage.generation,
                  revision == rulesRevision, refreshID == attempt else { return }
            self.error = "Responsibilities couldn’t refresh. Your last confirmed rules are still shown."
        }
    }
    func syncMessages(force: Bool = false) async {
        prepare(); guard !syncing, generation == AccountStorage.generation else { return }
        if !force, let lastMessageSync, Date().timeIntervalSince(lastMessageSync) < 5,
           !AccountStorage.bool(forKey: "knot_background_pause_pending_v1") { return }
        WhisperEmberHistoryStore.shared.ensureCurrentAccount()
        let lease = generation, revision = messageRevision; syncing = true
        defer { if generation == lease { syncing = false } }
        do {
            if AccountStorage.bool(forKey: "knot_background_pause_pending_v1") {
                try await revokeAll()
                guard generation == lease, lease == AccountStorage.generation else { return }
            }
            var cursor = Int(AccountStorage.string(forKey: cursorKey) ?? "0") ?? 0
            for _ in 0..<8 {
                let unreadLease = unreadRevision
                let page: Deliveries = try await request("/messages?after=\(cursor)")
                guard generation == lease, lease == AccountStorage.generation, revision == messageRevision else { return }
                guard page.next >= cursor, page.messages.allSatisfy({ $0.sequence > cursor && $0.sequence <= page.next }) else { return }
                guard WhisperEmberHistoryStore.shared.mergeBackgroundMessages(page.messages) else { return }
                cursor = page.next
                AccountStorage.set(String(cursor), forKey: cursorKey)
                if unreadRevision == unreadLease { unread = page.unread }
                if !page.messages.isEmpty { NotificationCenter.default.post(name: Self.messagesChanged, object: nil) }
                if page.messages.count < 50 { break }
            }
            lastMessageSync = Date()
        } catch { /* No fake message or read acknowledgment after failed sync. */ }
    }
    func approve(_ approval: WhisperKnotResponsibilityApproval) async -> Bool {
        prepare(); guard !busy, WhisperKnotContextPermission.allowed else { return false }
        guard !AccountStorage.bool(forKey: "knot_background_pause_pending_v1") else {
            error = "Confirm the pending pause in Privacy & context before approving another responsibility."; return false
        }
        busy = true; rulesRevision = UUID()
        let lease = generation
        defer { if generation == lease { busy = false } }
        do {
            let saved: Saved = try await request("", method: "POST", body: JSONEncoder().encode(approval))
            guard generation == lease else { return false }
            rules.removeAll { $0.id == saved.rule.id }; rules.append(saved.rule); error = nil
            await refresh(); return true
        } catch is CancellationError { return false } catch {
            guard generation == lease else { return false }
            self.error = (error as? ServiceFailure)?.errorDescription ?? "Couldn’t confirm this responsibility. Refresh the list before retrying; it may already be saved."
            return false
        }
    }
    func change(_ rule: WhisperKnotResponsibility, action: String) async {
        guard ["pause", "resume", "delete"].contains(action) else { return }
        prepare()
        if action == "resume", !WhisperKnotContextPermission.allowed {
            error = "Review Privacy & context before resuming AI checks."; return
        }
        if action == "resume", AccountStorage.bool(forKey: "knot_background_pause_pending_v1") {
            error = "Confirm the pending pause in Privacy & context before resuming."; return
        }
        if action == "resume", approvalEpoch == nil { error = "Refresh the list and review this responsibility before resuming."; return }
        guard !busy else { return }; busy = true; rulesRevision = UUID()
        if action == "delete" { messageRevision = UUID(); lastMessageSync = nil }
        let lease = generation; defer { if generation == lease { busy = false } }
        do {
            if action == "delete" { let _: Acknowledged = try await request("/" + rule.id, method: "DELETE") }
            else {
                let body = action == "resume" ? try JSONEncoder().encode(EpochBody(approvalEpoch: approvalEpoch ?? "")) : nil
                let _: Saved = try await request("/" + rule.id + "/" + action, method: "POST", body: body)
            }
            if action == "delete" { messageRevision = UUID(); unreadRevision = UUID() }
            await refresh()
        } catch is CancellationError {} catch { if generation == lease { self.error = (error as? ServiceFailure)?.errorDescription ?? "Couldn’t confirm this change. Refresh before trying again." } }
    }
    func revokeAll() async throws {
        prepare(); let lease = generation
        guard generation == AccountStorage.generation, AccountStorage.currentUserID != "guest" else { throw CancellationError() }
        rulesRevision = UUID(); approvalEpoch = nil
        // Keep an ambiguous pause as a durable withdrawal request. Sync retries
        // it before reading more updates or permitting another approval.
        AccountStorage.set(true, forKey: "knot_background_pause_pending_v1")
        let _: Acknowledged = try await request("/revoke", method: "POST")
        guard generation == lease, lease == AccountStorage.generation else { throw CancellationError() }
        AccountStorage.set(false, forKey: "knot_background_pause_pending_v1")
        await refresh()
    }
    func eraseAll() async {
        prepare(); guard !busy else { return }; busy = true; rulesRevision = UUID(); messageRevision = UUID()
        lastMessageSync = nil
        let lease = generation; defer { if generation == lease { busy = false } }
        do {
            let _: Acknowledged = try await request("/erase", method: "DELETE")
            rules = []; approvalEpoch = nil; unread = 0; error = nil; unreadRevision = UUID(); rulesRevision = UUID(); messageRevision = UUID()
            // Cursor is monotonic on the server even after deletion.
        } catch is CancellationError {} catch { if generation == lease { self.error = "Couldn’t confirm deletion. Refresh before trying again." } }
    }
    func markRead(conversationID: UUID, messageIDs: [String]) async {
        prepare(); guard !markingRead, generation == AccountStorage.generation else { return }
        let ids = Array(Set(messageIDs.suffix(400))).filter { !confirmedReadIDs.contains($0) }
        guard !ids.isEmpty else { return }
        let lease = generation, readRevision = UUID()
        markingRead = true; unreadRevision = readRevision
        defer { if generation == lease { markingRead = false } }
        do {
            let result: ReadResult = try await request("/read", method: "POST", body: JSONEncoder().encode(ReadBody(conversationID: conversationID.uuidString.lowercased(), messageIDs: ids)))
            guard generation == lease, unreadRevision == readRevision, result.ok else { return }
            unreadRevision = UUID(); unread = result.unread
            confirmedReadIDs.formUnion(ids)
            if confirmedReadIDs.count > 800 { confirmedReadIDs = Set(ids) }
        } catch { /* A failed read marker must not fabricate a read receipt. */ }
    }
}
