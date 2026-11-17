import Foundation
import SwiftUI
import Supabase
import Auth

// MARK: - Rows

nonisolated struct WhisperMeetingRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let host_id: String
    let host_username: String
    let title: String
    let status: String
    let scheduled_at: String?
    let started_at: String?
    let ended_at: String?
    let summary: String?
    let created_at: String?

    var groupCall: WhisperGroupCallDescriptor? {
        guard let descriptor = WhisperGroupCallDescriptor.decode(summary), descriptor.roomID.lowercased() == id.lowercased() else { return nil }
        return descriptor
    }
    var isGroupCall: Bool { groupCall != nil || summary?.hasPrefix(WhisperGroupCallDescriptor.prefix) == true || title.hasPrefix("Group call · ") }
    var isLive: Bool { status == "live" }
    var isEnded: Bool { status == "ended" }
}

nonisolated struct WhisperMeetingTranscriptRow: Codable, Sendable {
    let username: String
    let text: String
}

nonisolated struct WhisperMeetingParticipantRow: Codable, Sendable {
    let user_id: String
    let username: String
}

/// Per-user Notebook preference for one meeting — favorite + custom title.
/// Shared with the web Notebook via whisper_notebook_prefs (the shared
/// meeting row itself is never touched by renames).
nonisolated struct WhisperNotebookPrefRow: Codable, Sendable {
    let meeting_id: String
    let custom_title: String?
    let is_favorite: Bool
}

/// Whisper Meetings — private video meetings that reuse the live-room WebRTC
/// engine on the shared `meeting:{id}` signaling channel, so iOS and web join
/// the exact same rooms. After the call, transcripts become AI notes.
@MainActor
@Observable
final class WhisperMeetingService {
    static let shared = WhisperMeetingService()
    private let client = SupabaseService.shared.client
    private init() {}

    var myMeetings: [WhisperMeetingRow] = []
    var meetingsError: String?
    private var meetingsRequest = UUID()
    private var meetingsOwner: String?

    func resetMeetingList() {
        meetingsRequest = UUID(); meetingsOwner = nil; myMeetings = []; meetingsError = nil
    }
    /// A serial tail keeps local speech segments in their capture order and
    /// lets the host wait for every write before producing AI notes.
    var transcriptSaveError: String? { WhisperTranscriptOutbox.shared.errorText }

    /// Public ordinary invitation: preserve the supplied UUID/code exactly.
    nonisolated static func link(for id: String) -> String {
        "https://meet.mydailywhisper.com/meet/\(id)"
    }

    nonisolated static func socialCallLink(for id: String) -> String {
        "https://www.mydailywhisper.com/meet/\(id)?groupCall=1"
    }

    // MARK: - Notebook prefs (favorites + renames — synced with the web Notebook)

    /// The signed-in user's notebook prefs keyed by meeting id. Favorites pin
    /// to the top of the Meetings list; custom titles rename rows per-user.
    /// Returns [:] until supabase/notebook.sql has been applied.
    func fetchNotebookPrefs() async -> [String: WhisperNotebookPrefRow] {
        guard let uid = client.auth.currentUser?.id.uuidString.lowercased() else { return [:] }
        let rows: [WhisperNotebookPrefRow]? = try? await client
            .from("whisper_notebook_prefs")
            .select("meeting_id,custom_title,is_favorite")
            .eq("user_id", value: uid)
            .execute()
            .value
        var out: [String: WhisperNotebookPrefRow] = [:]
        for row in rows ?? [] { out[row.meeting_id] = row }
        return out
    }

    /// Upsert one notebook pref. Merges with the stored row so toggling the
    /// favorite never wipes a rename (and vice versa) — web parity.
    /// `customTitle`: outer nil = leave unchanged; `.some(nil)` = clear.
    @discardableResult
    func saveNotebookPref(
        meetingID: String,
        customTitle: String?? = nil,
        isFavorite: Bool? = nil
    ) async -> Bool {
        guard let uid = client.auth.currentUser?.id.uuidString.lowercased() else { return false }
        let existing: [WhisperNotebookPrefRow]? = try? await client
            .from("whisper_notebook_prefs")
            .select("meeting_id,custom_title,is_favorite")
            .eq("user_id", value: uid)
            .eq("meeting_id", value: meetingID)
            .limit(1)
            .execute()
            .value
        let current = existing?.first
        struct Upsert: Encodable {
            let user_id: String
            let meeting_id: String
            let custom_title: String?
            let is_favorite: Bool
            let updated_at: String
        }
        let row = Upsert(
            user_id: uid,
            meeting_id: meetingID,
            custom_title: customTitle ?? current?.custom_title,
            is_favorite: isFavorite ?? current?.is_favorite ?? false,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            _ = try await client
                .from("whisper_notebook_prefs")
                .upsert(row, onConflict: "user_id,meeting_id")
                .execute()
            return true
        } catch {
            return false
        }
    }

    /// Internal archive/calendar matching only. Invitation routing uses
    /// WhisperMeetingInvitation directly and never derives a database ID.
    nonisolated static func meetingID(fromText text: String?) -> String? {
        guard let identity = WhisperMeetingInvitation.fromText(text)?.idOrCode else { return nil }
        return resolveRoomID(identity)
    }

    /// True when the string is a real database uuid (vs a human meeting code).
    nonisolated static func isMeetingUUID(_ text: String) -> Bool {
        let pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: pattern, options: .regularExpression) != nil
    }

    /// Human meeting codes (wsp-5638-745f) map to a DETERMINISTIC uuid — the
    /// EXACT cyrb128 → RFC-4122 shaping the web client uses, so every platform
    /// opening the same code lands in the same room.
    nonisolated static func meetingID(fromCode code: String) -> String {
        let norm = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var h1: UInt32 = 1779033703
        var h2: UInt32 = 3144134277
        var h3: UInt32 = 1013904242
        var h4: UInt32 = 2773480762
        for unit in norm.utf16 {
            let k = UInt32(unit)
            h1 = h2 ^ ((h1 ^ k) &* 597399067)
            h2 = h3 ^ ((h2 ^ k) &* 2869860233)
            h3 = h4 ^ ((h3 ^ k) &* 951274213)
            h4 = h1 ^ ((h4 ^ k) &* 2716044179)
        }
        h1 = (h3 ^ (h1 >> 18)) &* 597399067
        h2 = (h4 ^ (h2 >> 22)) &* 2869860233
        h3 = (h1 ^ (h3 >> 17)) &* 951274213
        h4 = (h2 ^ (h4 >> 19)) &* 2716044179
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, word) in [h1, h2, h3, h4].enumerated() {
            bytes[index * 4] = UInt8((word >> 24) & 0xff)
            bytes[index * 4 + 1] = UInt8((word >> 16) & 0xff)
            bytes[index * 4 + 2] = UInt8((word >> 8) & 0xff)
            bytes[index * 4 + 3] = UInt8(word & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let p1 = hex.prefix(8)
        let p2 = hex.dropFirst(8).prefix(4)
        let p3 = hex.dropFirst(12).prefix(4)
        let p4 = hex.dropFirst(16).prefix(4)
        let p5 = hex.dropFirst(20)
        return "\(p1)-\(p2)-\(p3)-\(p4)-\(p5)"
    }

    /// Route input → database id: uuids pass through, codes derive.
    nonisolated static func resolveRoomID(_ idOrCode: String) -> String {
        let trimmed = idOrCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return isMeetingUUID(trimmed) ? trimmed.lowercased() : meetingID(fromCode: trimmed)
    }

    // MARK: - CRUD

    /// Start an instant meeting, or — when `scheduledAt` is set — create a
    /// scheduled meeting that stays un-started until the host begins it.
    /// Mirrors the web client's createMeeting, including the legacy-schema
    /// fallback where `started_at` is still NOT NULL.
    func create(title: String, scheduledAt: Date? = nil, id: String? = nil, callDescriptor: WhisperGroupCallDescriptor? = nil) async throws -> WhisperMeetingRow {
        let generation = AccountStorage.generation
        let uid = client.auth.currentUser?.id.uuidString.lowercased() ?? ""
        let username = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "host"
        struct Insert: Encodable {
            let id: String?
            let summary: String?
            let host_id: String
            let host_username: String
            let title: String
            let status: String
            let scheduled_at: String?
            let started_at: String?
        }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Meeting" : title
        let insert = Insert(
            id: id, summary: callDescriptor?.encoded,
            host_id: uid,
            host_username: username,
            title: cleanTitle,
            status: scheduledAt == nil ? "live" : "scheduled",
            scheduled_at: scheduledAt.map { ISO8601DateFormatter().string(from: $0) },
            started_at: scheduledAt == nil ? nowIso : nil
        )
        do {
            let rows: [WhisperMeetingRow] = try await client
                .from("whisper_meetings")
                .insert(insert)
                .select()
                .execute()
                .value
            guard let row = rows.first else {
                throw NSError(domain: "WhisperMeeting", code: 1, userInfo: [NSLocalizedDescriptionKey: "Meeting could not be created"])
            }
            return row
        } catch where scheduledAt != nil {
            guard !Task.isCancelled, generation == AccountStorage.generation,
                  uid == client.auth.currentUser?.id.uuidString.lowercased() else { throw CancellationError() }
            // Legacy database where started_at is NOT NULL — retry with a
            // placeholder creation timestamp so scheduling keeps working.
            let legacy = Insert(
                id: insert.id, summary: insert.summary,
                host_id: insert.host_id,
                host_username: insert.host_username,
                title: insert.title,
                status: insert.status,
                scheduled_at: insert.scheduled_at,
                started_at: nowIso
            )
            let rows: [WhisperMeetingRow] = try await client
                .from("whisper_meetings")
                .insert(legacy)
                .select()
                .execute()
                .value
            guard let row = rows.first else {
                throw NSError(domain: "WhisperMeeting", code: 1, userInfo: [NSLocalizedDescriptionKey: "Meeting could not be created"])
            }
            return row
        }
    }

    /// Create the meeting row for a CODE room if nobody has yet — the first
    /// signed-in arriver becomes the host. Idempotent and race-safe
    /// (ON CONFLICT DO NOTHING), mirroring the web's ensureMeetingRoom.
    func ensureRoom(id: String, title: String = "Meeting") async {
        let uid = client.auth.currentUser?.id.uuidString.lowercased() ?? ""
        guard !uid.isEmpty else { return }
        let username = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "host"
        struct Upsert: Encodable {
            let id: String
            let host_id: String
            let host_username: String
            let title: String
            let status: String
            let started_at: String
        }
        let row = Upsert(
            id: id,
            host_id: uid,
            host_username: username,
            title: title,
            status: "live",
            started_at: ISO8601DateFormatter().string(from: Date())
        )
        _ = try? await client
            .from("whisper_meetings")
            .upsert(row, onConflict: "id", ignoreDuplicates: true)
            .execute()
    }

    /// Host begins a scheduled meeting — flips it live and stamps the real
    /// start time. A no-op for meetings that are already live (RLS host-only).
    func start(meetingID: String) async {
        struct Patch: Encodable {
            let status: String
            let started_at: String
        }
        _ = try? await client
            .from("whisper_meetings")
            .update(Patch(status: "live", started_at: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: meetingID)
            .eq("status", value: "scheduled")
            .execute()
    }

    /// Reopen an ENDED meeting so its link works again — Meet's rule that a
    /// link is never dead. Any signed-in member holding the link may reopen
    /// through the guarded RPC (supabase/meetings-links.sql); until that
    /// migration lands the host can still reopen directly (their own row is
    /// updatable). Returns the refreshed row, or nil when nothing could flip.
    func reopen(meetingID: String) async -> WhisperMeetingRow? {
        let username = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "member"
        struct ReopenParams: Encodable {
            let p_meeting_id: String
            let p_username: String
        }
        do {
            _ = try await client
                .rpc("reopen_whisper_meeting", params: ReopenParams(p_meeting_id: meetingID, p_username: username))
                .execute()
        } catch {
            // Legacy database (no RPC yet): only the host's own row is updatable.
            struct Patch: Encodable {
                let status: String
                let started_at: String
                let ended_at: String?
            }
            _ = try? await client
                .from("whisper_meetings")
                .update(Patch(status: "live", started_at: ISO8601DateFormatter().string(from: Date()), ended_at: nil))
                .eq("id", value: meetingID)
                .eq("status", value: "ended")
                .execute()
        }
        let fresh = await fetch(id: meetingID)
        if let fresh, !fresh.isEnded {
            await recordJoin(meetingID: meetingID)
            return fresh
        }
        return nil
    }

    /// Send branded email invites for a scheduled meeting via the backend.
    /// Returns the number of invites sent, or nil when sending failed.
    func sendInvites(
        meetingID: String,
        title: String,
        scheduledAt: Date,
        emails: [String]
    ) async -> Int? {
        guard !emails.isEmpty,
              let token = try? await client.auth.session.accessToken,
              let url = URL(string: "\(WhisperBillingBackend.url)/meetings/invite") else { return nil }
        let username = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "host"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "meetingId": meetingID,
            "title": title,
            "scheduledAt": ISO8601DateFormatter().string(from: scheduledAt),
            "hostUsername": username,
            "emails": emails,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["ok"] as? Bool) == true else { return nil }
        return (json["sent"] as? Int) ?? emails.count
    }

    /// Outcome of emailing the AI notes through the backend.
    enum NotesEmailResult: Equatable {
        case sent(Int)
        /// Email isn't wired on this deployment — callers fall back to the
        /// system mail composer.
        case notConfigured
        case failed
    }

    /// Send the finished meeting's AI notes as a branded, formatted Whisper
    /// email (Resend) — the same backend path the web client uses, so iOS
    /// never depends on the device's Mail app being configured.
    func emailNotes(
        meetingID: String,
        title: String,
        notes: String,
        emails: [String]
    ) async -> NotesEmailResult {
        guard !emails.isEmpty,
              let token = try? await client.auth.session.accessToken,
              let url = URL(string: "\(WhisperBillingBackend.url)/meetings/notes-email") else {
            return .failed
        }
        let username = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "host"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "meetingId": meetingID,
            "title": title,
            "hostUsername": username,
            "notes": String(notes.prefix(16000)),
            "emails": Array(emails.prefix(20)),
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return .failed
        }
        if http.statusCode == 404 || http.statusCode == 503 { return .notConfigured }
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["ok"] as? Bool) == true else {
            return .failed
        }
        return .sent((json["sent"] as? Int) ?? emails.count)
    }

    func fetch(id: String) async -> WhisperMeetingRow? {
        // The guarded RPC turns possession of a private link into an explicit
        // participant record before strict RLS allows the meeting to be read.
        await recordJoin(meetingID: id)
        return await fetchArchived(id: id)
    }

    /// Archive browsing must never register a new meeting participant.
    func fetchArchived(id: String) async -> WhisperMeetingRow? {
        let rows: [WhisperMeetingRow]? = try? await client
            .from("whisper_meetings")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return rows?.first
    }

    func refreshMine() async {
        let uid = client.auth.currentUser?.id.uuidString.lowercased() ?? ""
        guard !uid.isEmpty else { resetMeetingList(); return }
        let generation = AccountStorage.generation, request = UUID()
        meetingsRequest = request
        if meetingsOwner != uid { myMeetings = []; meetingsOwner = uid }
        meetingsError = nil
        do {
        async let hostedTask: [WhisperMeetingRow] = client
            .from("whisper_meetings")
            .select()
            .eq("host_id", value: uid)
            .order("created_at", ascending: false)
            .limit(30)
            .execute()
            .value
        struct PartRow: Codable { let meeting_id: String }
        async let joinedTask: [PartRow] = client
            .from("whisper_meeting_participants")
            .select("meeting_id")
            .eq("user_id", value: uid)
            .order("joined_at", ascending: false)
            .limit(30)
            .execute()
            .value

        var rows = try await hostedTask
        let joinedIDs = (try await joinedTask)
            .map { $0.meeting_id }
            .filter { id in !rows.contains(where: { $0.id == id }) }
        guard !Task.isCancelled, generation == AccountStorage.generation, request == meetingsRequest,
              client.auth.currentUser?.id.uuidString.lowercased() == uid else { return }
        if !joinedIDs.isEmpty {
            let extra: [WhisperMeetingRow] = try await client
                .from("whisper_meetings")
                .select()
                .in("id", values: joinedIDs)
                .execute()
                .value
            rows.append(contentsOf: extra)
        }
        guard !Task.isCancelled, generation == AccountStorage.generation, request == meetingsRequest,
              client.auth.currentUser?.id.uuidString.lowercased() == uid else { return }
        myMeetings = rows.sorted { ($0.created_at ?? "") > ($1.created_at ?? "") }
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation, request == meetingsRequest,
                  client.auth.currentUser?.id.uuidString.lowercased() == uid else { return }
            meetingsError = "Meetings couldn’t refresh just now. Please try again."
        }
    }

    func recordJoin(meetingID: String) async {
        let uid = client.auth.currentUser?.id.uuidString.lowercased() ?? ""
        guard !uid.isEmpty else { return }
        let username = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "guest"
        struct JoinParams: Encodable {
            let p_meeting_id: String
            let p_username: String
        }
        do {
            _ = try await client
                .rpc("join_whisper_meeting", params: JoinParams(p_meeting_id: meetingID, p_username: username))
                .execute()
        } catch {
            // Older installs work until the hardening RPC is applied. Once the
            // SQL is live, RLS rejects this fallback and the guarded RPC wins.
            struct LegacyUpsert: Encodable {
                let meeting_id: String
                let user_id: String
                let username: String
            }
            _ = try? await client
                .from("whisper_meeting_participants")
                .upsert(LegacyUpsert(meeting_id: meetingID, user_id: uid, username: username), onConflict: "meeting_id,user_id")
                .execute()
        }
    }

    /// Shared title update with original-host authorization and a stale-title guard.
    func rename(_ meeting: WhisperMeetingRow, title: String) async throws -> WhisperMeetingRow {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = AccountStorage.currentUserID.lowercased()
        let generation = AccountStorage.generation
        guard !clean.isEmpty, clean.count <= 160, meeting.host_id.lowercased() == owner,
              client.auth.currentUser?.id.uuidString.lowercased() == owner else { throw WhisperNotebookError.accountChanged }
        let rows: [WhisperMeetingRow] = try await client.from("whisper_meetings")
            .update(["title": clean]).eq("id", value: meeting.id).eq("host_id", value: owner)
            .eq("title", value: meeting.title).select().execute().value
        guard AccountStorage.generation == generation, let saved = rows.first else { throw WhisperNotebookError.conflict }
        return saved
    }

    func end(meetingID: String) async {
        struct Patch: Encodable {
            let status: String
            let ended_at: String
        }
        _ = try? await client
            .from("whisper_meetings")
            .update(Patch(status: "ended", ended_at: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: meetingID)
            .execute()
    }

    // MARK: - Transcripts + notes

    @discardableResult
    func addTranscript(meetingID: String, text: String) async -> Bool {
        let id = WhisperTranscriptOutbox.shared.enqueue(meetingID: meetingID, text: text)
        await WhisperTranscriptOutbox.shared.flush()
        return id != nil && WhisperTranscriptOutbox.shared.errorText == nil
    }

    /// Queue an utterance without allowing network latency to reorder notes.
    func queueTranscript(meetingID: String, text: String, spokenAt: Date = Date()) {
        WhisperTranscriptOutbox.shared.enqueue(meetingID: meetingID, text: text, spokenAt: spokenAt)
    }

    /// Wait for all locally captured speech to reach the transcript table.
    func flushTranscriptQueue() async {
        await WhisperTranscriptOutbox.shared.flush()
    }

    /// The full meeting transcript as "username: text" lines — used by the
    /// recruiter's live prospect read and the post-meeting evaluation.
    func fetchTranscriptPlain(meetingID: String) async -> String {
        (try? await readTranscriptPlain(meetingID: meetingID)) ?? ""
    }

    func readTranscriptPlain(meetingID: String) async throws -> String {
        var lines: [String] = []
        let boundary = Date().ISO8601Format()
        for page in 0..<50 {
            let segments: [WhisperMeetingTranscriptRow] = try await client
                .from("whisper_meeting_transcripts").select("username,text")
                .eq("meeting_id", value: meetingID).lte("spoken_at", value: boundary)
                .order("spoken_at", ascending: true).order("id", ascending: true)
                .range(from: page * 200, to: page * 200 + 199).execute().value
            lines += segments.map { "\($0.username): \($0.text)" }
            if segments.count < 200 { return lines.joined(separator: "\n") }
        }
        throw WhisperNotebookError.tooLong
    }

    /// Everyone who joined this meeting — used to auto-DM the notes.
    func fetchParticipants(meetingID: String) async -> [WhisperMeetingParticipantRow] {
        let rows: [WhisperMeetingParticipantRow]? = try? await client
            .from("whisper_meeting_participants")
            .select("user_id,username")
            .eq("meeting_id", value: meetingID)
            .limit(60)
            .execute()
            .value
        return (rows ?? []).filter { !$0.user_id.isEmpty && !$0.username.isEmpty }
    }

    /// Generate AI meeting notes from the transcript, persist them on the
    /// meeting row, and return the markdown. Nil when there's no transcript.
    func generateNotes(meetingID: String) async -> String? {
        guard let room = await fetch(id: meetingID), !room.isGroupCall else { return nil }
        guard let fullTranscript = try? await readTranscriptPlain(meetingID: meetingID), !fullTranscript.isEmpty else { return nil }
        guard fullTranscript.utf16.count <= 24000 else { return nil }
        let transcript = fullTranscript

        let toolkitURL = Config.allValues["EXPO_PUBLIC_TOOLKIT_URL"] ?? "https://toolkit.rork.com"
        let secret = Config.allValues["EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY"] ?? ""
        guard !secret.isEmpty,
              let url = URL(string: "\(toolkitURL)/v2/vercel/v1/chat/completions") else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "openai/gpt-4o",
            "max_tokens": 900,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a meeting notes assistant (like Gemini notes for Google Meet). Given a raw speech transcript, produce clean structured notes with sections: **Summary** (2-3 sentences), **Key points** (bullets), **Decisions** (bullets, or 'None recorded'), **Action items** (bullets with owner names when identifiable, or 'None recorded'). Be concise and factual."
                ],
                ["role": "user", "content": String(transcript)]
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              choices.first?["finish_reason"] as? String == "stop",
              let message = choices.first?["message"] as? [String: Any],
              let generated = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !generated.isEmpty else { return nil }
        let summary = generated + "\n\n**Coverage**\nSaved speech snapshot. Pending or later-arriving speech is not included; refresh the transcript and review with Jasper for updates."

        struct Patch: Encodable {
            let summary: String
            let summary_generated_at: String
        }
        struct Acknowledgment: Decodable { let id: String }
        let acknowledged: [Acknowledgment]? = try? await client
            .from("whisper_meetings")
            .update(Patch(summary: summary, summary_generated_at: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: meetingID).select("id")
            .execute().value
        guard acknowledged?.first?.id.lowercased() == meetingID.lowercased() else { return nil }
        return summary
    }

    // MARK: - Coach heart-rate overlay

    /// Latest heart-rate readings for participants, from their Whisper client
    /// snapshots. Tolerant of varying payload shapes.
    func fetchHeartRates(userIDs: [String]) async -> [String: Int] {
        guard !userIDs.isEmpty else { return [:] }
        struct SnapRow: Codable {
            let user_id: String
            let payload: AnyJSON?
        }
        let rows: [SnapRow]? = try? await client
            .from("whisper_client_snapshots")
            .select("user_id,payload")
            .in("user_id", values: userIDs)
            .execute()
            .value
        var out: [String: Int] = [:]
        for row in rows ?? [] {
            if let payload = row.payload, let bpm = Self.extractHeartRate(payload, depth: 0) {
                out[row.user_id.lowercased()] = bpm
            }
        }
        return out
    }

    nonisolated private static func extractHeartRate(_ json: AnyJSON, depth: Int) -> Int? {
        guard depth <= 2, case .object(let obj) = json else { return nil }
        let keys = ["heartRate", "heart_rate", "currentHeartRate", "restingHeartRate", "resting_heart_rate", "latestHeartRate", "bpm"]
        for key in keys {
            if let value = obj[key] {
                if case .integer(let i) = value, i > 20, i < 250 { return i }
                if case .double(let d) = value, d > 20, d < 250 { return Int(d.rounded()) }
            }
        }
        for value in obj.values {
            if let nested = extractHeartRate(value, depth: depth + 1) { return nested }
        }
        return nil
    }
}
