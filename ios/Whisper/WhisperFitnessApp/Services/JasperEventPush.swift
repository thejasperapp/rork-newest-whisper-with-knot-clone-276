import Foundation
import Security
import CryptoKit

// MARK: - Event model

/// One change-feed event from Jasper's journal (`GET /v1/events/page`,
/// guide §06 — September 15, 2026). Hints only: something changed; they never
/// establish complete mutation coverage, so snapshots are still re-read.
nonisolated struct JasperPushEvent: Identifiable, Equatable {
    let id: String
    let event: String              // e.g. "workout.completed"
    let resource: String?
    let refID: String?
    let occurredAt: Date?

    /// "workout.completed" → "Workout completed".
    var title: String {
        let words = event
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        guard let first = words.first else { return event }
        return String(first).uppercased() + words.dropFirst()
    }
}

/// Which credential reads the journal: the user's own connection or a
/// coach-held client token (re-verified by `JasperCoachConnect.owns(token:)`
/// on every request).
nonisolated enum JasperEventVia: Equatable {
    case own
    case coach(token: String)

    var overrideToken: String? {
        if case .coach(let token) = self { return token }
        return nil
    }
}

/// How one reconcile pass ended. Callers act on `.revoked` (the credential
/// is dead — drop it and never retry under it); everything else is
/// informational and the polling rail keeps working.
nonisolated enum JasperEventReconcileOutcome: Equatable {
    case skipped
    case positioned
    case unchanged
    case fresh(Int)
    case unavailable
    case revoked
}

// MARK: - Journal position (per signed-in account, per Jasper uid)

/// `next_cursor` and `context` travel together — Jasper needs both to
/// continue a journal read. `settled` is false while the first walk to the
/// journal tail is still in progress (nothing seen then is ever shown as
/// live). Retention is 30 days, so an untouched position is re-established.
nonisolated private struct JasperEventCursor: Codable, Equatable {
    var cursor: String
    var context: String?
    var settled: Bool
    var updatedAt: Date
}

/// One decoded `GET /v1/events/page` answer.
nonisolated private struct JasperEventPage {
    let events: [JasperPushEvent]
    let nextCursor: String?
    let context: String?
    let hasMore: Bool
}

/// Signing secrets from earlier webhook registrations — cleared on forget so
/// no stale row outlives a revoked connection.
private enum JasperHookKeychain {
    private static let service = "jasper.connect.hooks"

    static func clear(uid: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: uid,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Service

/// Jasper change feed, September 15 2026 contract:
///
/// Webhook push and new registrations are paused server-side
/// (`webhook_egress_unavailable`), so Whisper no longer registers hooks.
/// Instead every coach dashboard read and own live snapshot also pulls
/// `GET /v1/events/page` — commit-visible journal positions with a
/// decimal-string `next_cursor` and a `context` that must be sent back
/// together. The first pass only walks to the journal tail and positions the
/// cursor, so history is never replayed as live; later passes surface the
/// events that landed since, deduped by id, as `recent` + `pulses`.
///
/// Hints are not complete mutation coverage — callers still re-read their
/// snapshots. Every failure here is silent (a sanitized note in `lastNotes`);
/// the once-a-minute polling rail keeps working. The signed-webhook verifier
/// stays for when egress resumes.
@MainActor
@Observable
final class JasperEventPush {
    static let shared = JasperEventPush()

    /// Last pass that found fresh journal events per Jasper uid — dashboards
    /// refresh off this.
    private(set) var pulses: [String: Date] = [:]
    /// Most recent events per uid, newest first (capped at 8).
    private(set) var recent: [String: [JasperPushEvent]] = [:]
    /// Uids whose journal cursor is positioned at the tail — later passes
    /// report live changes.
    private(set) var armed: Set<String> = []
    /// One-line transport status for the coach dashboard strip.
    private(set) var dispatcherLine: String? = JasperEventPush.pausedLine
    /// Sanitized reason the last pass for a uid produced no hints (stable code
    /// + request id tail, never bodies or credentials).
    private(set) var lastNotes: [String: String] = [:]

    @ObservationIgnored private var seen: [String: Set<String>] = [:]
    @ObservationIgnored private var running: Set<String> = []
    @ObservationIgnored private var lastPass: [String: Date] = [:]

    nonisolated static let pausedLine = "webhook push paused by Jasper"
    nonisolated private static let pageLimit = 200
    /// Pages per pass — positioning walks toward the tail; live passes rarely
    /// need more than one. A longer journal simply continues next pass.
    nonisolated private static let maxPages = 6
    /// Politeness floor between passes for one uid (the dashboard rail is 60s).
    nonisolated private static let minimumInterval: TimeInterval = 20
    /// Journal retention per the guide; an older local position is discarded.
    nonisolated private static let retention: TimeInterval = 29 * 86_400

    private init() {}

    // MARK: Reconcile (guide §06)

    /// One journal pass for this uid on the given credential. Bounded, deduped
    /// and throttled; never throws. `.revoked` means the token is dead.
    func reconcile(uid rawUID: String, via: JasperEventVia) async -> JasperEventReconcileOutcome {
        let uid = Self.normalize(rawUID)
        guard !uid.isEmpty, !running.contains(uid) else { return .skipped }
        if let last = lastPass[uid], Date().timeIntervalSince(last) < Self.minimumInterval { return .skipped }
        guard let context = try? await JasperAccountSession.current() else { return .skipped }
        running.insert(uid)
        defer { running.remove(uid) }
        lastPass[uid] = Date()
        let generation = AccountStorage.generation
        let key = cursorKey(uid: uid)

        var stored = loadCursor(key)
        if let current = stored, Date().timeIntervalSince(current.updatedAt) > Self.retention {
            stored = nil   // retention expired the position — re-establish, never replay
        }
        let positioning = stored?.settled != true
        var position = stored ?? JasperEventCursor(cursor: "0", context: nil, settled: false, updatedAt: Date())
        var fresh: [JasperPushEvent] = []
        var reachedTail = false

        for _ in 0..<Self.maxPages {
            let data: Data
            do {
                data = try await JasperConnectClient.shared.eventsPage(
                    cursor: position.cursor, context: position.context,
                    limit: Self.pageLimit, overrideToken: via.overrideToken)
            } catch JasperConnectError.revoked {
                guard generation == AccountStorage.generation else { return .skipped }
                forget(uid: uid)
                return .revoked
            } catch {
                guard generation == AccountStorage.generation, (try? context.check()) != nil else { return .skipped }
                return note(error, uid: uid, key: key)
            }
            guard generation == AccountStorage.generation, (try? context.check()) != nil else { return .skipped }
            guard let page = Self.parsePage(data) else {
                lastNotes[uid] = "The change feed answered in a shape this build doesn't read — refresh still works."
                return .unavailable
            }
            if !positioning { fresh.append(contentsOf: page.events) }
            if let next = page.nextCursor {
                position.cursor = next
            } else if !page.events.isEmpty {
                // Events without a continuation would replay forever — refuse to arm.
                lastNotes[uid] = "The change feed returned events without a cursor — refresh still works."
                return .unavailable
            }
            if let ctx = page.context { position.context = ctx }
            if !page.hasMore {
                reachedTail = true
                break
            }
        }

        if positioning { position.settled = reachedTail }
        position.updatedAt = Date()
        saveCursor(position, key: key)
        if position.settled { armed.insert(uid) }
        lastNotes[uid] = nil
        if positioning { return .positioned }
        let added = record(fresh, uid: uid)
        return added > 0 ? .fresh(added) : .unchanged
    }

    /// Local cleanup when a credential dies or coaching ends — position,
    /// hints and any leftover signing secret go together.
    func forget(uid rawUID: String) {
        let uid = Self.normalize(rawUID)
        JasperHookKeychain.clear(uid: uid)
        UserDefaults.standard.removeObject(forKey: cursorKey(uid: uid))
        armed.remove(uid)
        recent[uid] = nil
        pulses[uid] = nil
        seen[uid] = nil
        lastNotes[uid] = nil
        lastPass[uid] = nil
    }

    /// Transport status for the strip. Push egress is paused by contract, so
    /// this is constant today; it stays async for the resumption path.
    func refreshDispatcherStatus() async {
        dispatcherLine = Self.pausedLine
    }

    // MARK: Plumbing

    /// At-least-once semantics → dedupe by id; newest first; pulse only when
    /// something genuinely new landed.
    private func record(_ events: [JasperPushEvent], uid: String) -> Int {
        var seenIDs = seen[uid] ?? []
        var fresh: [JasperPushEvent] = []
        for event in events where !seenIDs.contains(event.id) {
            seenIDs.insert(event.id)
            fresh.append(event)
        }
        if seenIDs.count > 600 { seenIDs = Set(fresh.map(\.id)) }
        seen[uid] = seenIDs
        guard !fresh.isEmpty else { return 0 }
        fresh.sort { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }
        recent[uid] = Array((fresh + (recent[uid] ?? [])).prefix(8))
        pulses[uid] = Date()
        return fresh.count
    }

    /// Sanitized failure handling: the stable code leads every message.
    /// `missing_scope` is the user's choice (degrade); an expired or unknown
    /// cursor drops the local position so the next pass re-establishes it.
    private func note(_ error: Error, uid: String, key: String) -> JasperEventReconcileOutcome {
        let message = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
        let code = message.split(separator: " ").first.map(String.init) ?? ""
        switch code {
        case "missing_scope":
            lastNotes[uid] = "Change hints need read:events — this connection doesn't share it."
        case "unknown_resource":
            lastNotes[uid] = "This Jasper host has no change-feed journal yet."
        default:
            if code.contains("cursor") || code.contains("expired") || code.contains("context") {
                UserDefaults.standard.removeObject(forKey: key)
                armed.remove(uid)
            }
            lastNotes[uid] = message
        }
        return .unavailable
    }

    nonisolated private static func parsePage(_ data: Data) -> JasperEventPage? {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              body["ok"] as? Bool != false else { return nil }
        let rows = (body["events"] as? [[String: Any]]) ?? (body["data"] as? [[String: Any]]) ?? []
        let events = rows.compactMap(parseEvent)
        // `next_cursor` is the continuation; a tail page that omits it can
        // still continue from the last row's own journal position.
        let next = decimalString(body["next_cursor"])
            ?? rows.last.flatMap { decimalString($0["position"] ?? $0["cursor"] ?? $0["id"]) }
        let hasMore = (body["has_more"] as? Bool) ?? (rows.count >= pageLimit)
        return JasperEventPage(events: events, nextCursor: next,
                               context: body["context"] as? String, hasMore: hasMore)
    }

    nonisolated private static func parseEvent(_ row: [String: Any]) -> JasperPushEvent? {
        let id = (row["id"] as? String)
            ?? (row["id"] as? Int).map(String.init)
            ?? decimalString(row["position"])
        guard let id, !id.isEmpty else { return nil }
        let name = (row["event"] as? String) ?? (row["type"] as? String) ?? (row["name"] as? String) ?? "event"
        return JasperPushEvent(
            id: id,
            event: name,
            resource: row["resource"] as? String,
            refID: (row["ref_id"] as? String)
                ?? (row["ref_id"] as? Int).map(String.init)
                ?? (row["resource_id"] as? String),
            occurredAt: jasperConnectDate(row["occurred_at"] ?? row["created_at"] ?? row["at"]))
    }

    /// Journal positions are decimal strings (`^[0-9]+$`); a numeric answer is
    /// tolerated, anything else is not a cursor.
    nonisolated private static func decimalString(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) ? trimmed : nil
        }
        if let number = value as? Int { return String(number) }
        return nil
    }

    private func cursorKey(uid: String) -> String {
        "jasper_events_cursor_v1_" + AccountStorage.currentUserID.lowercased() + ":" + uid
    }

    private func loadCursor(_ key: String) -> JasperEventCursor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(JasperEventCursor.self, from: data)
    }

    private func saveCursor(_ cursor: JasperEventCursor, key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(try? encoder.encode(cursor), forKey: key)
    }

    nonisolated private static func normalize(_ uid: String) -> String {
        uid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: Signature verification (retained for webhook egress resumption)

    /// `X-Jasper-Signature: t=<unix>,v1=hex(hmac_sha256(secret, t + "." + rawBody))`
    /// over the RAW body bytes, rejected when |now − t| > 300s.
    nonisolated static func verifySignature(rawBody: Data, signatureHeader: String, secret: String) -> Bool {
        var t: String?
        var v1: String?
        for part in signatureHeader.split(separator: ",") {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            if kv[0] == "t" { t = String(kv[1]) }
            if kv[0] == "v1" { v1 = String(kv[1]) }
        }
        guard let t, let v1, let ts = TimeInterval(t),
              abs(Date().timeIntervalSince1970 - ts) < 300 else { return false }
        var signed = Data("\(t).".utf8)
        signed.append(rawBody)
        let mac = HMAC<SHA256>.authenticationCode(
            for: signed, using: SymmetricKey(data: Data(secret.utf8)))
        return mac.map { String(format: "%02x", $0) }.joined() == v1.lowercased()
    }
}
