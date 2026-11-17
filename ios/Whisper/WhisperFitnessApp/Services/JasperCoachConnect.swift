import Foundation
import Security
import Supabase

// MARK: - Model

/// One coach-held Jasper Connect token for one coached client.
///
/// Minted through explicit REST authorization as the own-account
/// connection, but with `client_user_id` — Jasper validates the active coach grant
/// server-side and the token resolves to the CLIENT's data graph.
///
/// `app_name` is canonical per holder (re-authorizing the same name ROTATES
/// the previous token), so every client gets a distinct name
/// ("Whisper Coach · <uid8>") — minting client B's token can never kill
/// client A's, and can never rotate the coach's own "Whisper" connection.
nonisolated struct JasperCoachAccess: Codable, Equatable {
    let clientUID: String      // lowercased auth uid of the coached client
    let coachUID: String       // who minted it — guards against stale sign-ins
    let tokenID: UUID          // jasper_connect_tokens.id — needed for revoke
    let tokenPrefix: String    // "jc_12345678" — safe to display
    let appName: String
    let scopes: [String]
    let username: String?      // the CLIENT's Jasper @handle, when resolved
    let displayName: String?
    let linked: Bool?          // §8.4 — true = grant resolved a different owner
    let mintedAt: Date
    /// Phase 2: true when the mint granted write scopes (read & write coach
    /// grant). Optional so metadata persisted before Phase 2 still decodes;
    /// mutable so a server-side downgrade (read-only answer on a write) can
    /// flip it off without re-minting.
    var canWrite: Bool? = nil

    var hasFullAccess: Bool { scopes.contains("all") }
    var scopeSummary: String {
        if hasFullAccess { return "Full access" }
        return canWrite == true ? "\(scopes.count) scopes · read & write" : "\(scopes.count) scopes"
    }
    /// False ⇒ the client has no Jasper profile yet (empty graph) — reads
    /// will legitimately return nothing.
    var hasJasperProfile: Bool { username != nil || linked == true }
}

// MARK: - Keychain (one raw token per coached client)

private enum JasperCoachKeychain {
    private static let service = "jasper.connect.coach"

    static func save(_ token: String, clientUID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: AccountStorage.currentUserID.lowercased() + ":" + clientUID,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(clientUID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: AccountStorage.currentUserID.lowercased() + ":" + clientUID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear(clientUID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: AccountStorage.currentUserID.lowercased() + ":" + clientUID,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Vault

/// Per-client Jasper Connect access for coaches.
///
/// A standing client grant permits initial access. Revoked access stays
/// blocked until explicit reconnection; writes are never replayed.
@MainActor
@Observable
final class JasperCoachConnect {
    static let shared = JasperCoachConnect()

    /// Token metadata per client uid (raw tokens live in the Keychain).
    private(set) var accessByClient: [String: JasperCoachAccess] = [:]
    /// Last successful live snapshot per client (5-minute freshness).
    private(set) var snapshots: [String: JasperLiveSnapshot] = [:]
    /// Parsed one-call dashboards per client (60s freshness — the published
    /// polling cap for `GET /v1/dashboard` is once a minute per client).
    private(set) var dashboards: [String: JasperClientDashboard] = [:]
    /// Human-readable reason the last read/mint failed, per client.
    private(set) var lastErrors: [String: String] = [:]
    @ObservationIgnored private var inFlight: [String: Task<JasperLiveSnapshot?, Never>] = [:]
    @ObservationIgnored private var dashboardInFlight: [String: Task<JasperClientDashboard?, Never>] = [:]

    private var metaKey: String { "jasper_coach_tokens_meta_v2_" + AccountStorage.currentUserID.lowercased() }
    @ObservationIgnored private var mintTasks: [String: Task<JasperCoachAccess, Error>] = [:]
    private var accessEpoch: UUID = UUID()
    private var revokedKey: String { "jasper_coach_revoked_v2_" + AccountStorage.currentUserID.lowercased() }
    private var pendingRevokeKey: String { "jasper_coach_pending_revoke_v1_" + AccountStorage.currentUserID.lowercased() }
    private(set) var revokingClients: Set<String> = []

    private func check(_ context: JasperAccountSession, epoch: UUID) throws {
        try context.check()
        guard epoch == accessEpoch else { throw CancellationError() }
    }

    private func invalidateFlights() {
        accessEpoch = UUID()
        mintTasks.values.forEach { $0.cancel() }
        mintTasks.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        dashboardInFlight.values.forEach { $0.cancel() }
        dashboardInFlight.removeAll()
    }

    func reconnect(forClient rawUID: String) async throws {
        let context = try await JasperAccountSession.current()
        let uid = Self.normalize(rawUID)
        guard !revokingClients.contains(uid) else { throw JasperConnectError.server("Revocation is still in progress.") }
        if (UserDefaults.standard.dictionary(forKey: pendingRevokeKey) as? [String: String])?[uid] != nil {
            guard await revokeAccess(forClient: uid) else {
                throw JasperConnectError.server("Couldn't confirm revocation. Retry before reconnecting.")
            }
            try context.check()
        }
        var revoked = Set(UserDefaults.standard.stringArray(forKey: revokedKey) ?? [])
        revoked.remove(uid)
        UserDefaults.standard.set(Array(revoked), forKey: revokedKey)
        try context.check()
        _ = try await access(forClient: uid)
    }

    func owns(token: String) -> Bool {
        accessByClient.contains { uid, access in
            access.coachUID == AccountStorage.currentUserID.lowercased()
                && !(UserDefaults.standard.stringArray(forKey: revokedKey) ?? []).contains(uid)
                && JasperCoachKeychain.load(clientUID: uid) == token
        }
    }

    /// Read scopes requested for coach tokens — everything except
    /// `read:blood` (sensitive; needs an explicit client opt-in, and Jasper
    /// now also excludes blood from coach `all` server-side). `read:photos`
    /// yields metadata only on coach tokens — the photo bytes stay in
    /// Jasper's private storage. If the deployed RPC predates `p_scopes` we
    /// retry without it and store whatever scopes Jasper actually granted.
    nonisolated static let coachReadScopes: [String] = [
        "read:profile", "read:workouts", "read:nutrition", "read:sleep",
        "read:vitals", "read:body", "read:bioage", "read:goals",
        "read:events", "read:charts", "read:preferences", "read:photos",
    ]

    /// Phase 2 write scopes, requested WITH the reads. A read & write grant
    /// mints them (coach tools unlock); a read-only grant — including a
    /// read & write invite the client accepted as view-only (Aug 2026
    /// consent toggle; downgrade only, never upgrade) — rejects them and we
    /// fall back to reads automatically. NEVER `write:body`, `write:blood`,
    /// or `write:preferences` — those stay client-only.
    nonisolated static let coachWriteScopes: [String] = [
        "write:workouts", "write:nutrition", "write:goals", "write:charts",
    ]

    private init() {
        restore()
    }

    // MARK: Access / minting

    /// Returns (minting on first use) the coach's token for this client.
    /// Throws with Jasper's own reason when there's no active grant.
    func access(forClient rawClientUID: String) async throws -> JasperCoachAccess {
        let uid = Self.normalize(rawClientUID)
        let context = try await JasperAccountSession.current()
        let epoch = accessEpoch
        if (UserDefaults.standard.stringArray(forKey: revokedKey) ?? []).contains(uid) { throw JasperConnectError.revoked }
        if let running = mintTasks[uid] {
            let result = try await running.value
            try context.check()
            guard epoch == accessEpoch else { throw CancellationError() }
            return result
        }
        let task = Task<JasperCoachAccess, Error> { try await self.accessUncached(uid: uid, context: context, epoch: epoch) }
        mintTasks[uid] = task
        defer { if epoch == accessEpoch { mintTasks[uid] = nil } }
        let result = try await task.value
        try check(context, epoch: epoch)
        return result
    }

    private func accessUncached(uid: String, context: JasperAccountSession, epoch: UUID) async throws -> JasperCoachAccess {
        try context.check()
        guard epoch == accessEpoch else { throw CancellationError() }
        let coachUID = context.ownerID
        if let cached = accessByClient[uid], cached.coachUID == coachUID,
           JasperCoachKeychain.load(clientUID: uid) != nil {
            return cached
        }
        // Stale entry from a different sign-in (or a lost Keychain row) —
        // never reuse another account's token.
        if accessByClient[uid] != nil { throw JasperConnectError.notConnected }

        let body = try await mint(uid: uid, context: context)
        try context.check()
        guard epoch == accessEpoch else { throw CancellationError() }
        guard body["ok"] as? Bool == true,
              let raw = body["token"] as? String,
              let idString = body["id"] as? String,
              let tokenID = UUID(uuidString: idString), raw.hasPrefix("jc_"),
              let scopes = body["scopes"] as? [String],
              scopes.allSatisfy({ (Self.coachReadScopes + Self.coachWriteScopes).contains($0) }) else {
            let message = (body["error"] as? String) ?? "Jasper didn't return a client token."
            let hint = body["hint"] as? String
            throw JasperConnectError.server([message, hint].compactMap { $0 }.joined(separator: " "))
        }
        let user = body["user"] as? [String: Any]
        let access = JasperCoachAccess(
            clientUID: uid,
            coachUID: coachUID,
            tokenID: tokenID,
            tokenPrefix: (body["token_prefix"] as? String) ?? String(raw.prefix(11)),
            appName: (body["app_name"] as? String) ?? Self.appName(for: uid),
            scopes: scopes,
            username: user?["username"] as? String,
            displayName: user?["display_name"] as? String,
            linked: user?["linked"] as? Bool,
            mintedAt: Date(),
            canWrite: scopes.contains { $0 == "all" || $0.hasPrefix("write:") }
        )
        JasperCoachKeychain.save(raw, clientUID: uid)
        accessByClient[uid] = access
        persist()
        // A fresh token starts a fresh journal position — the first dashboard
        // read positions the change-feed cursor (guide §06); nothing is replayed.
        JasperEventPush.shared.forget(uid: uid)
        return access
    }

    /// One authorize pass, most-capable first: reads + writes (read & write
    /// grants mint them → coach tools unlock), falling back to reads-only
    /// when Jasper answers "needs read_write" (read-only grants can still
    /// mint reads), and finally to an unscoped call if the deployed RPC
    /// predates `p_scopes` (PostgREST matches the exact parameter set). The
    /// response's `scopes` array stays the source of truth either way.
    private func mint(uid: String, context: JasperAccountSession) async throws -> [String: Any] {
        func authorize(_ scopes: [String]) async throws -> [String: Any] {
            try await JasperConnectClient.shared.authorize(appName: Self.appName(for: uid), scopes: scopes,
                                                          clientID: uid, context: context)
        }
        do {
            let body = try await authorize(Self.coachReadScopes + Self.coachWriteScopes)
            // Some rejections come back 200 with { ok:false, error, hint }.
            if body["ok"] as? Bool != true, Self.isReadOnlyGrantAnswer(body) {
                return try await authorize(Self.coachReadScopes)
            }
            return body
        } catch JasperConnectError.server(let message) where Self.isReadOnlyGrantMessage(message) {
            return try await authorize(Self.coachReadScopes)
        }
    }

    /// "read_write" / "read-only" answers from authorize or a write — the
    /// grant is alive but read-only, not dead.
    nonisolated private static func isReadOnlyGrantMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("read_write") || lower.contains("read-only")
            || lower.contains("read_only") || lower.contains("readonly")
    }

    nonisolated private static func isReadOnlyGrantAnswer(_ body: [String: Any]) -> Bool {
        let text = [(body["error"] as? String), (body["hint"] as? String)]
            .compactMap { $0 }.joined(separator: " ")
        return isReadOnlyGrantMessage(text)
    }

    /// Distinct per client — see the type comment on rotation semantics.
    nonisolated private static func appName(for uid: String) -> String {
        "Whisper Coach · \(String(uid.prefix(8)))"
    }

    // MARK: Reads

    /// GET /v1/<resource> as this client. A 401 means the token died remotely
    /// — client revoked it in Jasper, a rotation elsewhere, or (Jasper now
    /// re-verifies the standing grant on EVERY call) the coaching grant
    /// itself ended. The grant may still be live, so we re-mint ONCE and
    /// retry; if the grant is dead the re-mint fails with Jasper's own
    /// reason, which `friendlyMintMessage` surfaces honestly.
    func read(forClient rawClientUID: String, _ resource: String,
              since: Date? = nil, limit: Int? = nil,
              extraQuery: [URLQueryItem] = []) async throws -> Data {
        let context = try await JasperAccountSession.current()
        let epoch = accessEpoch
        let uid = Self.normalize(rawClientUID)
        var query: [URLQueryItem] = []
        if let since { query.append(URLQueryItem(name: "since", value: ISO8601DateFormatter().string(from: since))) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        query.append(contentsOf: extraQuery)

        let (_, token) = try await credentials(forClient: uid)
        try check(context, epoch: epoch)
        do {
            let data = try await JasperConnectClient.shared.dataRequest(
                path: "/v1/\(resource)", query: query, method: "GET",
                payload: nil, overrideToken: token)
            try check(context, epoch: epoch)
            // Render specs ride along with coach reads too — same store.
            JasperLookStore.shared.ingest(resource: resource, envelope: data)
            return data
        } catch JasperConnectError.revoked {
            try check(context, epoch: epoch)
            drop(uid)
            throw JasperConnectError.revoked
        }
    }

    // MARK: Writes (Phase 2 — read & write grants only)

    /// POST /v1/<resource> as this client — coach tools (assign programs,
    /// log meal/water corrections, goal entries, inbox cards). One deliberate
    /// attempt per call: `client_id` is record identity (upsert), the
    /// Idempotency-Key is the retry protection (guide §05) — a caller letting
    /// the coach retry the SAME change passes the key it used first; nothing
    /// here retries on its own. A 401 drops the credential (never re-mints);
    /// a read-only answer (grant downgraded after mint — Jasper re-verifies
    /// the grant on EVERY call) flips `canWrite` off locally and surfaces a
    /// coach-actionable message.
    @discardableResult
    func write(forClient rawClientUID: String, resource: String,
               payload: [String: Any], idempotencyKey: String = UUID().uuidString) async throws -> JasperWriteReceipt {
        let context = try await JasperAccountSession.current()
        let epoch = accessEpoch
        let uid = Self.normalize(rawClientUID)
        var body = payload
        if body["client_id"] == nil { body["client_id"] = UUID().uuidString }   // record identity, not retry protection

        func send(_ token: String) async throws -> JasperWriteReceipt {
            let data = try await JasperConnectClient.shared.dataRequest(
                path: "/v1/\(resource)", method: "POST", payload: body, overrideToken: token,
                idempotencyKey: idempotencyKey)
            return try JSONDecoder().decode(JasperWriteReceipt.self, from: data)
        }

        let (_, token) = try await credentials(forClient: uid)
        try check(context, epoch: epoch)
        do {
            let result = try await send(token)
            try check(context, epoch: epoch)
            return result
        } catch JasperConnectError.revoked {
            try check(context, epoch: epoch)
            drop(uid)
            throw JasperConnectError.revoked
        } catch JasperConnectError.server(let message) where Self.isReadOnlyGrantMessage(message) {
            try check(context, epoch: epoch)
            markReadOnly(uid)
            throw JasperConnectError.server("This coaching grant is read-only — ask the client to switch coach access to read & write in Jasper, then try again.")
        }
    }

    /// DELETE /v1/<resource>?id=… — the undo behind every coach write
    /// (Jasper emits a deletion event so the client's apps stay truthful).
    /// Charts: only Whisper's own posts are deletable. One Idempotency-Key
    /// per deliberate attempt, same as `write`.
    func delete(forClient rawClientUID: String, resource: String, id: String,
                idempotencyKey: String = UUID().uuidString) async throws {
        let context = try await JasperAccountSession.current()
        let epoch = accessEpoch
        let uid = Self.normalize(rawClientUID)
        let query = [URLQueryItem(name: "id", value: id)]
        do {
            let (_, token) = try await credentials(forClient: uid)
            try check(context, epoch: epoch)
            _ = try await JasperConnectClient.shared.dataRequest(
                path: "/v1/\(resource)", query: query, method: "DELETE",
                payload: nil, overrideToken: token, idempotencyKey: idempotencyKey)
        } catch JasperConnectError.revoked {
            try check(context, epoch: epoch)
            drop(uid)
            throw JasperConnectError.revoked
        }
    }

    // MARK: Raw client-token calls (Aug 17 2026 — grocery sync, diet generation)

    /// POST an arbitrary /v1 path as this client — same revocation handling
    /// and read-only-grant honesty as `write`, but returns raw bytes (these
    /// routes answer custom envelopes, not write receipts). The
    /// Idempotency-Key only travels to routes that honor it (grocery changes
    /// do; marketplace and the paused generator don't).
    func rawPost(forClient rawClientUID: String, path: String,
                 payload: [String: Any], timeout: TimeInterval? = nil,
                 idempotencyKey: String = UUID().uuidString) async throws -> Data {
        if path.split(separator: "?").first == "/v1/diet_plans/generate" {
            throw JasperConnectError.server(JasperConnectClient.nativeReviewMessage)
        }
        let context = try await JasperAccountSession.current()
        let epoch = accessEpoch
        let uid = Self.normalize(rawClientUID)
        func send(_ token: String) async throws -> Data {
            try await JasperConnectClient.shared.dataRequest(
                path: path, method: "POST", payload: payload,
                overrideToken: token, timeout: timeout, idempotencyKey: idempotencyKey)
        }
        let (_, token) = try await credentials(forClient: uid)
        try check(context, epoch: epoch)
        do {
            let result = try await send(token)
            try check(context, epoch: epoch)
            return result
        } catch JasperConnectError.revoked {
            try check(context, epoch: epoch)
            drop(uid)
            throw JasperConnectError.revoked
        } catch JasperConnectError.server(let message) where Self.isReadOnlyGrantMessage(message) {
            try check(context, epoch: epoch)
            markReadOnly(uid)
            throw JasperConnectError.server("This coaching grant is read-only — ask the client to switch coach access to read & write in Jasper, then try again.")
        }
    }

    /// GET /v1/grocery_list through the coach-held token — the SAME shared
    /// checklist state the client's Jasper app reads and writes.
    func sharedGroceryList(forClient uid: String) async throws -> JasperSharedGrocery? {
        let data = try await read(forClient: uid, "grocery_list")
        return JasperSharedGrocery.parse(data)
    }

    /// Check items off the client's list (write grant required) — the check
    /// lands in their Jasper instantly; `grocery.updated` shows up on the
    /// change feed at the next reconcile.
    func setGroceryChecks(forClient uid: String, planID: String?,
                          changes: [(id: String, checked: Bool)]) async throws {
        guard !changes.isEmpty else { return }
        var body: [String: Any] = [
            "items": changes.map { ["id": $0.id, "checked": $0.checked] as [String: Any] },
        ]
        if let planID { body["plan_id"] = planID }
        _ = try await rawPost(forClient: uid, path: "/v1/grocery_list", payload: body)
    }

    /// POST /v1/diet_plans/generate — Jasper's OWN generator on the client's
    /// token (scope + coach gate verified server-side BEFORE the model runs).
    /// Takes 15-60s — generous timeout, never on a UI-blocking path.
    func generateDietPlan(forClient uid: String,
                          request: JasperDietGenRequest) async throws -> JasperDietGenResult {
        throw JasperConnectError.server(JasperConnectClient.nativeReviewMessage)
    }

    /// Server said the grant is read-only now — remember it so coach tools
    /// hide without waiting for a re-mint.
    private func markReadOnly(_ uid: String) {
        guard var access = accessByClient[uid] else { return }
        access.canWrite = false
        accessByClient[uid] = access
        persist()
    }

    private func credentials(forClient uid: String) async throws -> (JasperCoachAccess, String) {
        let context = try await JasperAccountSession.current()
        let epoch = accessEpoch
        let access = try await access(forClient: uid)
        try check(context, epoch: epoch)
        guard access.coachUID == context.ownerID,
              accessByClient[uid]?.tokenID == access.tokenID else { throw CancellationError() }
        if let token = JasperCoachKeychain.load(clientUID: uid), owns(token: token) { return (access, token) }
        drop(uid)
        throw JasperConnectError.notConnected
    }

    // MARK: One-call dashboard (GET /v1/dashboard — Aug 2026)

    /// The ENTIRE coach dashboard in one request — the same payload Jasper's
    /// own in-app coach view renders (pixel parity by contract): profile,
    /// streaks, 14d readiness + sleep, vitals, workouts + PRs, meals + water,
    /// body + weight, bio age, blood panels, goals, active plans, photo
    /// metadata, plus a precomputed `summary`. Sections are scope-gated
    /// INDEPENDENTLY — anything the token can't read arrives as
    /// `{ locked, required_scope }` instead of failing the call (blood stays
    /// locked on coach tokens unless granted explicitly). Cached 60s per
    /// client, honoring the doc's ≤1/min polling cap; nil only when the call
    /// itself failed (older worker deploy, mint failure, offline).
    /// `period: "week"` flips to the weekly digest mode (Aug 17 2026):
    /// same payload over 7-day windows plus a `digest` block — this-week vs
    /// last-week deltas and ready-to-paste `highlights`. Cached separately
    /// from the daily payload, same 60s politeness window.
    func dashboard(forClient rawClientUID: String, period: String? = nil,
                   force: Bool = false) async -> JasperClientDashboard? {
        guard let context = try? await JasperAccountSession.current() else { return nil }
        let epoch = accessEpoch
        let uid = Self.normalize(rawClientUID)
        let key = period.map { "\(uid)#\($0)" } ?? uid
        if !force, let cached = dashboards[key],
           Date().timeIntervalSince(cached.fetchedAt) < 60 {
            return cached
        }
        if let running = dashboardInFlight[key] {
            let result = await running.value
            guard (try? check(context, epoch: epoch)) != nil else { return nil }
            return result
        }
        let task = Task<JasperClientDashboard?, Never> {
            await self.fetchDashboard(uid: uid, cacheKey: key, period: period)
        }
        dashboardInFlight[key] = task
        let result = await task.value
        guard (try? context.check()) != nil, epoch == accessEpoch else { return nil }
        dashboardInFlight[key] = nil
        return result
    }

    private func fetchDashboard(uid: String, cacheKey: String, period: String?) async -> JasperClientDashboard? {
        let generation = AccountStorage.generation
        let epoch = accessEpoch
        do {
            // Guide §06: the change feed rides the same once-a-minute rail as
            // the dashboard — and runs FIRST, so a pulse it raises joins this
            // in-flight read instead of triggering a second one.
            await reconcileChangeFeed(forClient: uid)
            guard generation == AccountStorage.generation, epoch == accessEpoch, !Task.isCancelled else { return nil }
            let extra = period.map { [URLQueryItem(name: "period", value: $0)] } ?? []
            let data = try await read(forClient: uid, "dashboard", extraQuery: extra)
            guard generation == AccountStorage.generation, epoch == accessEpoch, !Task.isCancelled else { return nil }
            guard let dash = JasperClientDashboard.parse(data) else {
                lastErrors[uid] = "Jasper's dashboard reply couldn't be read."
                return nil
            }
            // The dashboard bundles every native look — keep the store fresh.
            JasperLookStore.shared.ingest(looksBundle: data)
            dashboards[cacheKey] = dash

            return dash
        } catch {
            guard generation == AccountStorage.generation, epoch == accessEpoch, !Task.isCancelled else { return nil }
            lastErrors[uid] = Self.friendlyMintMessage(error)
            return nil
        }
    }

    // MARK: Live snapshot per client

    /// Counts + freshest timestamps for the headline resources, read through
    /// THIS CLIENT's token. Cached 5 minutes per client, in-flight deduped.
    func snapshot(forClient rawClientUID: String, days: Int = 30,
                  force: Bool = false) async -> JasperLiveSnapshot? {
        guard let context = try? await JasperAccountSession.current() else { return nil }
        let epoch = accessEpoch
        let uid = Self.normalize(rawClientUID)
        if !force, let cached = snapshots[uid],
           Date().timeIntervalSince(cached.fetchedAt) < 300 {
            return cached
        }
        if let running = inFlight[uid] {
            let result = await running.value
            guard (try? check(context, epoch: epoch)) != nil else { return nil }
            return result
        }
        let task = Task<JasperLiveSnapshot?, Never> { await self.fetchSnapshot(uid: uid, days: days) }
        inFlight[uid] = task
        let result = await task.value
        guard (try? check(context, epoch: epoch)) != nil else { return nil }
        inFlight[uid] = nil
        return result
    }

    /// Sequential probes (politeness contract: sustained ≤1 req/s). One
    /// failing resource is skipped and reported; nil only when the mint
    /// itself fails or every probe errors.
    private func fetchSnapshot(uid: String, days: Int) async -> JasperLiveSnapshot? {
        let generation = AccountStorage.generation
        let epoch = accessEpoch
        do {
            _ = try await credentials(forClient: uid)   // one crisp mint error, not six
        } catch {
            guard generation == AccountStorage.generation, epoch == accessEpoch, !Task.isCancelled else { return nil }
            lastErrors[uid] = Self.friendlyMintMessage(error)
            return nil
        }
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        var out: [JasperResourceSnapshot] = []
        var failures: [String] = []
        var lastError: String?
        for probe in JasperLiveSnapshot.probes {
            guard generation == AccountStorage.generation, epoch == accessEpoch, !Task.isCancelled else { return nil }
            do {
                let data = try await read(forClient: uid, probe.resource, since: since, limit: 200)
                let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let rows = (body?["data"] as? [[String: Any]]) ?? []
                let latest = rows.compactMap { jasperConnectDate($0[probe.timeField]) }.max()
                out.append(JasperResourceSnapshot(resource: probe.resource, title: probe.title,
                                                  symbol: probe.symbol, count: rows.count,
                                                  latest: latest))
            } catch {
                let message = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
                failures.append(probe.title)
                lastError = message

            }
        }
        guard generation == AccountStorage.generation, epoch == accessEpoch, !Task.isCancelled else { return nil }
        guard !out.isEmpty else {
            lastErrors[uid] = lastError ?? "Couldn't reach Jasper."
            return nil
        }
        let snap = JasperLiveSnapshot(fetchedAt: Date(), windowDays: days,
                                      resources: out, failedResources: failures)
        snapshots[uid] = snap
        lastErrors[uid] = failures.isEmpty ? nil : lastError
        return snap
    }

    // MARK: Change feed (GET /v1/events/page — September 15 2026)

    /// One journal pass for this client through the coach-held token, when
    /// the grant shares `read:events`. Jasper has paused webhook push
    /// (`webhook_egress_unavailable`), so this is how coach dashboards learn
    /// that something changed: throttled, deduped, first pass positions the
    /// cursor only. A 401 here is the same revocation as anywhere else —
    /// the token is dropped and never re-minted on its own.
    func reconcileChangeFeed(forClient rawClientUID: String) async {
        guard let context = try? await JasperAccountSession.current() else { return }
        let epoch = accessEpoch
        let uid = Self.normalize(rawClientUID)
        guard let (access, token) = try? await credentials(forClient: uid),
              (try? check(context, epoch: epoch)) != nil,
              access.scopes.contains("read:events") || access.scopes.contains("all") else { return }
        let outcome = await JasperEventPush.shared.reconcile(uid: uid, via: .coach(token: token))
        guard (try? check(context, epoch: epoch)) != nil else { return }
        if outcome == .revoked, accessByClient[uid]?.coachUID == context.ownerID { drop(uid) }
    }

    // MARK: Marketplace import (Aug 17 2026)

    /// POST /v1/marketplace/import { template_id } on THIS client's token —
    /// copies a published template into their Jasper with coach attribution.
    /// Imports upsert by template id, so importing twice never duplicates;
    /// the server rewrites payload.id/createdAt. Needs the matching write
    /// scope — read-only grants get the honest coach-actionable message.
    func importMarketplaceTemplate(_ templateID: String, forClient rawClientUID: String) async throws {
        let context = try await JasperAccountSession.current()
        let epoch = accessEpoch
        let uid = Self.normalize(rawClientUID)
        let payload = ["template_id": templateID]
        func send(_ token: String) async throws {
            _ = try await JasperConnectClient.shared.dataRequest(
                path: "/v1/marketplace/import", method: "POST",
                payload: payload, overrideToken: token)
        }
        let (_, token) = try await credentials(forClient: uid)
        try check(context, epoch: epoch)
        do {
            try await send(token)
        } catch JasperConnectError.revoked {
            try check(context, epoch: epoch)
            drop(uid)
            throw JasperConnectError.revoked
        } catch JasperConnectError.server(let message) where Self.isReadOnlyGrantMessage(message) {
            try check(context, epoch: epoch)
            markReadOnly(uid)
            throw JasperConnectError.server("This coaching grant is read-only — ask the client to switch coach access to read & write in Jasper, then try again.")
        }
        try check(context, epoch: epoch)
        // Their graph just changed — the next dashboard read must be fresh.
        dashboards.removeValue(forKey: uid)
        dashboards.removeValue(forKey: "\(uid)#week")
    }

    // MARK: Revoke / lifecycle

    /// Blocks local access immediately; retains an owner-bound token ID until
    /// the server confirms revocation. A failed attempt remains retryable.
    @discardableResult
    func revokeAccess(forClient rawClientUID: String) async -> Bool {
        let uid = Self.normalize(rawClientUID)
        let generation = AccountStorage.generation
        guard !revokingClients.contains(uid) else { return false }
        let pendingKey = pendingRevokeKey
        var pending = UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: String] ?? [:]
        let access = accessByClient[uid]
        guard access == nil || access?.coachUID == AccountStorage.currentUserID.lowercased() else { return false }
        let tokenID = pending[uid] ?? access?.tokenID.uuidString
        if let tokenID { pending[uid] = tokenID }
        UserDefaults.standard.set(pending, forKey: pendingKey)
        drop(uid)
        revokingClients.insert(uid)
        defer { if generation == AccountStorage.generation { revokingClients.remove(uid) } }
        guard let tokenID else { return true }
        do {
            let context = try await JasperAccountSession.current()
            guard context.generation == generation else { throw CancellationError() }
            // Guide §02: the holder's own session JWT manages connections.
            let confirmed = try await JasperConnectClient.shared.revokeToken(id: tokenID, context: context)
            try context.check()
            guard confirmed else {
                throw JasperConnectError.server("Jasper didn't confirm revocation.")
            }
            var current = UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: String] ?? [:]
            if current[uid] == tokenID { current.removeValue(forKey: uid) }
            UserDefaults.standard.set(current, forKey: pendingKey)
            lastErrors[uid] = nil
            return true
        } catch {
            guard generation == AccountStorage.generation, !Task.isCancelled else { return false }
            lastErrors[uid] = "Local access is blocked, but token revocation wasn't confirmed. Retry or remove this connection in Jasper."
            return false
        }
    }

    /// Clears every client token (sign-out safety).
    func wipeAll() {
        invalidateFlights()
        revokingClients.removeAll()
        for uid in accessByClient.keys {
            JasperEventPush.shared.forget(uid: uid)
        }
        accessByClient.removeAll()
        snapshots.removeAll()
        dashboards.removeAll()
        lastErrors.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        dashboardInFlight.values.forEach { $0.cancel() }
        dashboardInFlight.removeAll()
        restore()
    }

    private func drop(_ uid: String) {
        invalidateFlights()
        var revoked = Set(UserDefaults.standard.stringArray(forKey: revokedKey) ?? [])
        revoked.insert(uid)
        UserDefaults.standard.set(Array(revoked), forKey: revokedKey)
        mintTasks.values.forEach { $0.cancel() }
        mintTasks.removeAll()
        JasperCoachKeychain.clear(clientUID: uid)
        JasperEventPush.shared.forget(uid: uid)
        accessByClient.removeValue(forKey: uid)
        snapshots.removeValue(forKey: uid)
        dashboards.removeValue(forKey: uid)
        dashboards.removeValue(forKey: "\(uid)#week")
        inFlight[uid]?.cancel()
        inFlight.removeValue(forKey: uid)
        dashboardInFlight[uid]?.cancel()
        dashboardInFlight.removeValue(forKey: uid)
        persist()
    }

    // MARK: Plumbing

    /// Maps raw mint failures to something a coach can act on.
    nonisolated static func friendlyMintMessage(_ error: Error) -> String {
        let raw = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("missing_scope") || lower.contains("missing scope") {
            // Aug 2026: consent can be trimmed — a not-shared resource is the
            // client's choice, not a failure. Degrade, never retry-loop.
            return "The client chose not to share this data — scope choices live on their Jasper consent screen."
        }
        if lower.contains("grant") || lower.contains("coach") || lower.contains("permission")
            || lower.contains("not allowed") || lower.contains("forbidden") {
            return "Jasper reports no active coach grant for this client — ask them to re-grant coach access, then try again."
        }
        if lower.contains("sign in") { return raw }
        return raw
    }

    private func currentCoachUID() async -> String? {
        let client = SupabaseService.shared.client
        guard let session = try? await client.auth.session else { return nil }
        return session.user.id.uuidString.lowercased()
    }

    nonisolated private static func normalize(_ uid: String) -> String {
        uid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(try? encoder.encode(accessByClient), forKey: metaKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: metaKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let saved = (try? decoder.decode([String: JasperCoachAccess].self, from: data)) ?? [:]
        accessByClient = saved.filter { $0.value.coachUID == AccountStorage.currentUserID.lowercased() }
    }
}
