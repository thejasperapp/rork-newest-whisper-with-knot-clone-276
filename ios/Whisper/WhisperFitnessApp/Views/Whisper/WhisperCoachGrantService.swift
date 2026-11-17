import Foundation
import SwiftUI
import UIKit
import Supabase

/// Whisper's side of the **coach access** layer (`coach_grants`).
///
/// This is a *different* primitive from `account_links` (the "Connect Whisper"
/// identity alias). `account_links` answers *"who am I?"* — a 1:1 read-through
/// alias resolved with `jasper_uid_for()`. `coach_grants` answers *"who can act
/// on my data, and how much?"* — a 1:many, scoped (`read` / `read_write`),
/// revocable permission. The two never mix: identity is resolved through
/// `account_links`, never through a grant.
///
/// Whisper owns the schema + RPCs (`generate_coach_grant_code`,
/// `redeem_coach_grant_code`, `revoke_coach_grant`, `revoke_all_coach_grants`,
/// `my_coaches`, `my_clients`) and the `coach_grants` / `coach_grant_codes`
/// tables. We only call them; every RPC stamps `auth.uid()` server-side so the
/// mapping can't be forged.
///
/// Granting is **one tap, no codes**: `authorize(coachUID:scope:)` calls the
/// Whisper backend, which verifies the accepted coaching relationship
/// (`whisper_coach_requests.status = accepted`) against the caller's session
/// and writes the `coach_grants` row directly — same row the old code-redeem
/// path produced, so every downstream rail (lists, revokes, Jasper Connect
/// coach-token minting) is unchanged. The code RPCs remain only for the
/// legacy cross-app invite deep link.
@MainActor
@Observable
final class WhisperCoachGrantService {
    static let shared = WhisperCoachGrantService()

    /// Coaches the signed-in user (as a client) has granted access to.
    private(set) var coaches: [CoachGrantParty] = []
    /// Clients who have granted the signed-in user (as a coach) access.
    private(set) var clients: [CoachGrantParty] = []

    /// In-flight flag so UI can show progress + disable buttons.
    var isBusy: Bool = false
    /// Last user-facing status/error message surfaced by the access UI.
    var statusMessage: String?

    private let client = SupabaseService.shared.client
    /// Persisted so a verifiable `state` survives Whisper being backgrounded
    /// while the client taps Allow in Whisper.
    private let pendingStateKey = "whisper.coachGrant.pendingState"

    private init() {}

    // MARK: - Models

    /// Access scope a coach holds over a client's data.
    enum GrantScope: String, CaseIterable, Sendable {
        case read
        case readWrite = "read_write"

        var label: String {
            switch self {
            case .read: return "Can view"
            case .readWrite: return "Can view & edit"
            }
        }
    }

    /// One side of a grant — either a coach (from `my_coaches`) or a client
    /// (from `my_clients`). The `uid` is the *other* party's `auth.uid()`.
    struct CoachGrantParty: Identifiable, Equatable {
        let uid: String
        let scope: GrantScope
        let grantedAt: Date?
        /// Resolved Whisper @handle, when known.
        var username: String?

        var id: String { uid }
    }

    // MARK: - Decodable RPC rows (nonisolated: decoded off the main actor)

    private nonisolated struct MyCoachRow: Decodable {
        let coach_uid: String
        let scope: String
        let granted_at: String?
    }

    private nonisolated struct MyClientRow: Decodable {
        let client_uid: String
        let scope: String
        let granted_at: String?
    }

    private nonisolated struct ProfileRow: Decodable {
        let user_id: String
        let username: String?
    }

    // MARK: - Listing

    /// Refreshes both `coaches` (`my_coaches`) and `clients` (`my_clients`).
    /// Never throws — failures resolve to empty lists so the UI stays calm.
    func refresh() async {
        async let coachRows = fetchMyCoaches()
        async let clientRows = fetchMyClients()
        let (c, cl) = await (coachRows, clientRows)
        coaches = c
        clients = cl
        await hydrateUsernames()
    }

    private func fetchMyCoaches() async -> [CoachGrantParty] {
        do {
            let rows: [MyCoachRow] = try await client.rpc("my_coaches").execute().value
            return rows.map {
                CoachGrantParty(
                    uid: $0.coach_uid,
                    scope: GrantScope(rawValue: $0.scope) ?? .read,
                    grantedAt: Self.parseISO($0.granted_at)
                )
            }
        } catch {
            return []
        }
    }

    private func fetchMyClients() async -> [CoachGrantParty] {
        do {
            let rows: [MyClientRow] = try await client.rpc("my_clients").execute().value
            return rows.map {
                CoachGrantParty(
                    uid: $0.client_uid,
                    scope: GrantScope(rawValue: $0.scope) ?? .read,
                    grantedAt: Self.parseISO($0.granted_at)
                )
            }
        } catch {
            return []
        }
    }

    /// Resolves @handles for every party uid in one batched query so the lists
    /// show readable names instead of raw uuids. Best-effort — missing names
    /// just fall back to a shortened uid in the UI.
    private func hydrateUsernames() async {
        let ids = Set(coaches.map { $0.uid } + clients.map { $0.uid })
        guard !ids.isEmpty else { return }
        do {
            let rows: [ProfileRow] = try await client
                .from("whisper_profiles")
                .select("user_id, username")
                .in("user_id", values: Array(ids))
                .execute()
                .value
            var byID: [String: String] = [:]
            for row in rows where row.username != nil { byID[row.user_id] = row.username }
            coaches = coaches.map { var p = $0; p.username = byID[$0.uid]; return p }
            clients = clients.map { var p = $0; p.username = byID[$0.uid]; return p }
        } catch {
            // Names are cosmetic; leave the uids in place.
        }
    }

    // MARK: - Client side: one-tap authorize (no codes)

    /// Grants (or re-grants) `coachUID` access at `scope` in a single tap.
    /// The backend checks the accepted coaching relationship server-side and
    /// writes the grant with the service role — no code ever exists. Calling
    /// it again with a different scope switches the access level in place.
    @discardableResult
    func authorize(coachUID: String, scope: GrantScope) async -> Bool {
        isBusy = true
        defer { isBusy = false }

        guard let session = try? await client.auth.session else {
            statusMessage = "Sign in to Whisper first, then authorize your coach."
            Haptics.warning()
            return false
        }
        struct Body: Encodable { let coachId: String; let scope: String }
        let payload = try? JSONEncoder().encode(
            Body(coachId: coachUID.lowercased(), scope: scope.rawValue)
        )

        // Walk the backend candidates (configured env first, stable deploy
        // second) the same way voice tokens do — a stale configured host that
        // predates this route 404s and the next candidate picks it up.
        var lastStatus = 0
        var lastText = ""
        for host in WhisperBillingBackend.hosts {
            guard let url = URL(string: "\(host)/coach-access/grant") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = payload

            guard let (data, response) = try? await URLSession.shared.data(for: request) else { continue }
            lastStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastText = String(data: data, encoding: .utf8) ?? ""
            if lastStatus == 404 { continue }

            if lastStatus == 200 {
                await refresh()
                statusMessage = "Coach authorized — \(scope.label.lowercased())."
                Haptics.success()
                return true
            }
            break
        }

        if lastText.contains("not_your_coach") {
            statusMessage = "Only an accepted coach can be authorized. Send them a coaching request first."
        } else if lastStatus == 401 {
            statusMessage = "Sign in to Whisper first, then authorize your coach."
        } else {
            statusMessage = "Couldn't authorize right now. Please try again."
        }
        print("[Whisper] coach authorize failed (\(lastStatus)): \(lastText.prefix(200))")
        Haptics.warning()
        return false
    }

    // MARK: - Client side: redeem a coach's code (legacy deep-link path)

    enum RedeemOutcome: Equatable {
        case granted
        case invalidOrExpired
        case notAuthenticated
        case failed
    }

    /// Redeems a coach grant code as the signed-in client, writing an `active`
    /// grant `(client_uid = auth.uid()) → coach_uid`. The server trims/upper-
    /// cases, so raw user input is fine. Refreshes lists on success.
    @discardableResult
    func redeemCode(_ code: String) async -> RedeemOutcome {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Enter the code your coach gave you."
            return .invalidOrExpired
        }
        isBusy = true
        defer { isBusy = false }

        struct Params: Encodable { let p_code: String }
        do {
            _ = try await client
                .rpc("redeem_coach_grant_code", params: Params(p_code: trimmed))
                .execute()
            await refresh()
            statusMessage = "Coach connected."
            Haptics.success()
            return .granted
        } catch {
            let outcome = Self.classifyRedeem(error)
            switch outcome {
            case .invalidOrExpired:
                statusMessage = "That code expired or isn't valid. Codes last 30 minutes — ask your coach for a new one."
            case .notAuthenticated:
                statusMessage = "Sign in to Whisper first, then connect your coach."
            default:
                statusMessage = "Couldn't connect right now. Please try again."
            }
            Haptics.warning()
            return outcome
        }
    }

    private static func classifyRedeem(_ error: Error) -> RedeemOutcome {
        let text = String(describing: error).lowercased()
        if text.contains("expired") || text.contains("invalid") || text.contains("not found") {
            return .invalidOrExpired
        }
        if text.contains("not authenticated") { return .notAuthenticated }
        return .failed
    }

    // MARK: - Coach side: mint an invite

    /// Mints a fresh one-time coach grant code (30-min expiry) for the given
    /// scope by calling `generate_coach_grant_code`. Returns the code, or nil
    /// on failure.
    func generateCode(scope: GrantScope) async -> String? {
        isBusy = true
        defer { isBusy = false }
        struct Params: Encodable { let p_scope: String }
        do {
            let code: String = try await client
                .rpc("generate_coach_grant_code", params: Params(p_scope: scope.rawValue))
                .execute()
                .value
            return code
        } catch {
            statusMessage = "Couldn't create an invite code. Please try again."
            Haptics.warning()
            return nil
        }
    }

    /// Whether Whisper appears installed (so the coach can run the one-tap Allow
    /// invite). When false, the coach should share the raw code instead.
    var isWhisperInstalled: Bool {
        guard let url = URL(string: "jasper://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// The signed-in user's live auth uid (what RLS checks). Needed to embed the
    /// coach uid into the invite deep link.
    private func resolvedUID() async -> String? {
        if let session = try? await client.auth.session {
            return session.user.id.uuidString.lowercased()
        }
        let cached = AccountStorage.currentUserID
        return cached == "guest" || cached.hasPrefix("local_") ? nil : cached.lowercased()
    }

    /// Builds + opens the coach invite deep link into Whisper:
    /// `jasper://coach-grant?coach=<uid>&name=<name>&scope=<scope>&code=<code>&state=<rnd>&redirect=whisper`.
    /// Mints a fresh code first. Whisper shows the client a consent sheet, redeems
    /// on Allow, and bounces back to `whisper://coach-linked?granted=1&state=…`.
    /// Returns false (without opening) when Whisper isn't installed.
    @discardableResult
    func inviteViaDeepLink(coachName: String, scope: GrantScope) async -> Bool {
        guard isWhisperInstalled else { return false }
        guard let coachUID = await resolvedUID() else {
            statusMessage = "Sign in to Whisper first."
            return false
        }
        guard let code = await generateCode(scope: scope) else { return false }

        let state = UUID().uuidString
        AccountStorage.set(state, forKey: pendingStateKey)

        var components = URLComponents()
        components.scheme = "jasper"
        components.host = "coach-grant"
        components.queryItems = [
            URLQueryItem(name: "coach", value: coachUID),
            URLQueryItem(name: "name", value: coachName),
            URLQueryItem(name: "scope", value: scope.rawValue),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect", value: "whisper"),
        ]
        guard let url = components.url else { return false }
        await UIApplication.shared.open(url)
        return true
    }

    // MARK: - Deep-link return

    /// Handles Whisper's return after a coach invite consent screen:
    /// `whisper://coach-linked?granted=1&state=…` (or `denied=1`). Verifies
    /// `state`, refreshes the lists on grant. Returns true when the URL was a
    /// `whisper://coach-linked` response so the router can stop forwarding it.
    @discardableResult
    func handleReturn(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "whisper",
              url.host?.lowercased() == "coach-linked" else { return false }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        let expectedState = AccountStorage.string(forKey: pendingStateKey)
        let returnedState = value("state")
        AccountStorage.set("", forKey: pendingStateKey)
        guard let expectedState, !expectedState.isEmpty,
              returnedState == expectedState else {
            return true
        }

        if value("denied") == "1" {
            statusMessage = "Invite cancelled."
            return true
        }

        if value("granted") == "1" {
            Task {
                await refresh()
                statusMessage = "Client connected."
                Haptics.success()
            }
        }
        return true
    }

    // MARK: - Revoke

    /// Revokes a single grant. As a client pass the coach's uid; as a coach pass
    /// the client's uid (the RPC is symmetric on `auth.uid()` + the other side).
    @discardableResult
    func revoke(otherUID: String) async -> Bool {
        guard let context = try? await JasperAccountSession.current(), !isBusy else { return false }
        isBusy = true
        defer { if context.generation == AccountStorage.generation { isBusy = false } }
        struct Params: Encodable { let p_other: String }
        do {
            try await client
                .rpc("revoke_coach_grant", params: Params(p_other: otherUID))
                .execute()
            try context.check()
            let tokenRevoked = await JasperCoachConnect.shared.revokeAccess(forClient: otherUID)
            try context.check()
            await refresh()
            try context.check()
            statusMessage = tokenRevoked ? "Access revoked." : "Coaching grant revoked. Token cleanup wasn't confirmed — remove the connection in Jasper or retry."
            Haptics.tap()
            return true
        } catch {
            guard (try? context.check()) != nil else { return false }
            statusMessage = "Couldn't revoke right now. Please try again."
            return false
        }
    }

    /// Client-only: revokes every coach the signed-in user has granted.
    @discardableResult
    func revokeAllCoaches() async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.rpc("revoke_all_coach_grants").execute()
            await refresh()
            statusMessage = "All coaches removed."
            Haptics.tap()
            return true
        } catch {
            statusMessage = "Couldn't revoke right now. Please try again."
            return false
        }
    }

    // MARK: - Helpers

    private nonisolated static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
