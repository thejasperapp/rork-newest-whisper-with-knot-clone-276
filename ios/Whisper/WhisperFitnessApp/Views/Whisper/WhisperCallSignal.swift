import Foundation

/// Encodes call-signaling control messages inside a DM body so we can
/// piggyback on the existing `whisper_messages` realtime channel without
/// adding a dedicated `calls` table. Bodies start with the v1 prefix and
/// are filtered out of the visible chat by `WhisperBackendService`.
///
/// Media rides the shared mesh WebRTC engine (`WhisperLiveRTCService`) on
/// the same `meeting:{id}` room the web client joins, so an iOS caller and
/// a web callee land in the exact same room. The signal layer only carries
/// call lifecycle — invite (ring), accept, decline, cancel, end.
///
/// The invite payload is a superset of BOTH clients' historical shapes:
/// - iOS fields: `id`, `kind`, `mode`
/// - web fields: `meetingId`, `fromUserId`, `fromUsername`, `toUserId`, `at`
/// so a single invite rings web AND iOS recipients.
nonisolated enum WhisperCallSignal {
    static let prefix = "::whisper-call-v1::"

    nonisolated enum Kind: String, Codable, Sendable {
        case invite   // caller → recipient: ring the recipient
        case accept   // recipient → caller: I answered (joining the room)
        case decline  // recipient → caller: I declined
        case cancel   // caller → recipient: I hung up before connect
        case end      // either side: hung up after connect
        case ice      // legacy — no longer produced
    }

    nonisolated enum Mode: String, Codable, Sendable {
        case audio, video
    }

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let id: String      // shared call id
        let kind: Kind
        let mode: Mode
        // Web-parity ring fields — carried on invites so the web client's
        // IncomingCallWatcher rings too, and so iOS knows which meeting
        // room carries the media.
        var meetingId: String? = nil
        var fromUserId: String? = nil
        var fromUsername: String? = nil
        var toUserId: String? = nil
        /// Epoch ms when the ring was placed — rings expire after ~45s so
        /// replayed signals never ghost-ring after reconnects.
        var at: Double? = nil
        // Group calls — set when this ring belongs to a group call.
        var groupId: String? = nil
        var groupName: String? = nil
        // Legacy WebRTC payloads — kept optional so older signals still decode.
        var sdp: String? = nil
        var sdpType: String? = nil
        var candidate: String? = nil
        var sdpMid: String? = nil
        var sdpMLineIndex: Int32? = nil

        /// The mesh room that carries this call's media.
        var roomID: String { meetingId ?? id }
    }

    nonisolated static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    nonisolated static func decode(_ body: String) -> Payload? {
        guard body.hasPrefix(prefix) else { return nil }
        let json = String(body.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return p
    }

    /// Decodes BOTH wire shapes: the iOS payload above, and the web
    /// client's `CallInvitePayload` (`{meetingId, fromUserId, fromUsername,
    /// toUserId, at}` — no `kind`/`mode`), which is synthesized into an
    /// `.invite` so web-originated calls ring on iOS.
    nonisolated static func decodeCompat(_ body: String) -> Payload? {
        if let standard = decode(body) { return standard }
        guard body.hasPrefix(prefix) else { return nil }
        let json = String(body.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8) else { return nil }

        struct WebInvite: Codable {
            let meetingId: String
            let fromUserId: String
            let fromUsername: String?
            let toUserId: String?
            let at: Double?
        }
        guard let web = try? JSONDecoder().decode(WebInvite.self, from: data) else { return nil }
        return Payload(
            id: web.meetingId,
            kind: .invite,
            mode: .video,
            meetingId: web.meetingId,
            fromUserId: web.fromUserId,
            fromUsername: web.fromUsername,
            toUserId: web.toUserId,
            at: web.at
        )
    }

    /// True when an invite is too old to still ring (or has no timestamp —
    /// legacy invites are treated as fresh to preserve old-client behavior).
    nonisolated static func isStaleInvite(_ p: Payload, windowSeconds: TimeInterval = 45) -> Bool {
        guard p.kind == .invite, let at = p.at, at > 0 else { return false }
        let ageMs = Date().timeIntervalSince1970 * 1000 - at
        return ageMs > windowSeconds * 1000
    }

    /// Preserve group identity through both CallKit and alert-notification entry points.
    static func pushInvite(_ info: [String: String]) -> Payload? {
        guard let id = info["call_id"], !id.isEmpty,
              let from = info["from_user_id"], !from.isEmpty else { return nil }
        var value = Payload(id: id, kind: .invite, mode: info["mode"] == "video" ? .video : .audio)
        value.meetingId = info["meeting_id"]
        value.fromUserId = from
        value.fromUsername = info["from_username"]
        value.toUserId = info["recipient_user_id"]
        value.at = info["at"].flatMap(Double.init)
        value.groupId = info["group_id"].flatMap { UUID(uuidString: $0) == nil ? nil : $0 }
        value.groupName = value.groupId == nil ? nil : info["group_name"]
        return value
    }

    nonisolated static func isSignal(_ body: String) -> Bool {
        body.hasPrefix(prefix)
    }
}
