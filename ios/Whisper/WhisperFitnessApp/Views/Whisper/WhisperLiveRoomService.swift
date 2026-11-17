import Foundation
import Supabase

/// Supabase operations for Whisper Live audio/video rooms.
/// Mirrors the web tables: `whisper_live_rooms`, `whisper_live_room_speakers`,
/// `whisper_live_room_listeners`, `whisper_live_speaker_requests`, and
/// `whisper_live_invites` (group live co-host invitations).
///
/// Lifecycle rules:
/// - Rooms live in the DB only while `is_live = true` OR they're scheduled
///   for the future. Ending a live deletes it (client-side + SQL trigger).
/// - Broadcasters are hard-capped at `maxBroadcasters` (4), Instagram-style.
@MainActor
final class WhisperLiveRoomService: @unchecked Sendable {
    static let shared = WhisperLiveRoomService()

    /// Instagram-style cap — a live can hold at most 4 people on camera.
    static let maxBroadcasters = 4

    private let client = SupabaseService.shared.client
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []
    private var listChannel: RealtimeChannelV2?
    private var listTasks: [Task<Void, Never>] = []

    private init() {}

    /// Currently signed-in Supabase user id, if any.
    private var currentUserID: String? {
        SupabaseService.shared.client.auth.currentUser?.id.uuidString
    }

    // MARK: - Rooms

    /// Live rooms + upcoming scheduled rooms. Falls back to the legacy
    /// live-only query when the `scheduled_at` column hasn't been migrated yet.
    func fetchRooms() async throws -> [WhisperLiveRoom] {
        let nowISO = ISO8601DateFormatter().string(from: Date())
        do {
            let data = try await client
                .from("whisper_live_rooms")
                .select("*")
                .or("is_live.eq.true,scheduled_at.gt.\(nowISO)")
                .order("created_at", ascending: false)
                .execute()
                .data
            let rooms = try JSONDecoder().decode([WhisperLiveRoom].self, from: data)
            // Live rooms first (by viewers), then upcoming by soonest.
            return rooms.sorted { a, b in
                if a.is_live != b.is_live { return a.is_live }
                if a.is_live { return a.listener_count > b.listener_count }
                return (a.scheduledDate ?? .distantFuture) < (b.scheduledDate ?? .distantFuture)
            }
        } catch {
            // scheduled_at column may not exist yet — legacy live-only query.
            let data = try await client
                .from("whisper_live_rooms")
                .select("*")
                .eq("is_live", value: true)
                .order("listener_count", ascending: false)
                .execute()
                .data
            return try JSONDecoder().decode([WhisperLiveRoom].self, from: data)
        }
    }

    func fetchRoom(id: String) async throws -> WhisperLiveRoom? {
        let data = try await client
            .from("whisper_live_rooms")
            .select("*")
            .eq("id", value: id)
            .single()
            .execute()
            .data
        return try JSONDecoder().decode(WhisperLiveRoom?.self, from: data)
    }

    /// Create a live room. When `scheduledAt` is set the room is created in
    /// the "upcoming" state (`is_live = false`) and flips live via `goLive`.
    func createRoom(
        name: String,
        description: String,
        topic: String,
        scheduledAt: Date? = nil
    ) async throws -> WhisperLiveRoom {
        guard let userID = currentUserID else {
            throw WhisperLiveRoomError.notSignedIn
        }
        var payload: [String: AnyJSON] = [
            "name": .string(name),
            "description": .string(description),
            "topic": .string(topic),
            "host_id": .string(userID),
            "is_live": .bool(scheduledAt == nil),
            "is_video_enabled": .bool(true),
            "listener_count": .integer(0)
        ]
        if let scheduledAt {
            payload["scheduled_at"] = .string(ISO8601DateFormatter().string(from: scheduledAt))
        }
        let data = try await client
            .from("whisper_live_rooms")
            .insert(payload)
            .select("*")
            .single()
            .execute()
            .data
        let room = try JSONDecoder().decode(WhisperLiveRoom.self, from: data)
        // Insert host as a speaker
        try await addSpeaker(roomID: room.id, userID: userID, isHost: true)
        if room.is_live {
            fanOutGoLiveAlert(room: room)
        }
        return room
    }

    /// Best-effort go-live alert fanout to followers — never blocks the host.
    private func fanOutGoLiveAlert(room: WhisperLiveRoom) {
        let hostUsername = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? ""
        Task.detached {
            await WhisperLiveModerationService.shared.notifyFollowersLive(
                hostID: room.host_id,
                hostUsername: hostUsername,
                roomID: room.id,
                roomName: room.name
            )
        }
    }

    /// Flip a scheduled room live (host taps "Go live" when the countdown ends).
    func goLive(id: String) async throws -> WhisperLiveRoom? {
        _ = try await client
            .from("whisper_live_rooms")
            .update(["is_live": AnyJSON.bool(true)])
            .eq("id", value: id)
            .execute()
        // Re-add host as speaker in case a cleanup removed the row.
        if let me = currentUserID {
            try? await addSpeaker(roomID: id, userID: me, isHost: true)
        }
        let room = try await fetchRoom(id: id)
        if let room {
            fanOutGoLiveAlert(room: room)
        }
        return room
    }

    /// End a live. Marks it not-live, then deletes it — ended lives never
    /// linger (mirrors the SQL auto-delete trigger for safety when the
    /// trigger isn't installed yet). Future-scheduled rooms are kept.
    func endRoom(id: String, scheduledDate: Date? = nil) async throws {
        _ = try await client
            .from("whisper_live_rooms")
            .update(["is_live": AnyJSON.bool(false)])
            .eq("id", value: id)
            .execute()
        let isFutureScheduled = (scheduledDate ?? .distantPast) > Date()
        if !isFutureScheduled {
            try? await deleteRoom(id: id)
        }
    }

    /// Hard-delete a room (host only, enforced by RLS).
    func deleteRoom(id: String) async throws {
        _ = try await client
            .from("whisper_live_rooms")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Speakers

    func fetchSpeakers(roomID: String) async throws -> [WhisperLiveSpeaker] {
        let data = try await client
            .from("whisper_live_room_speakers")
            .select("room_id, user_id, is_host, is_cohost, can_video")
            .eq("room_id", value: roomID)
            .execute()
            .data
        return try JSONDecoder().decode([WhisperLiveSpeaker].self, from: data)
    }

    /// Bulk speaker fetch for the story-row live bubbles — one query for all
    /// visible rooms, returned as a `[roomID: speakers]` map.
    func fetchSpeakersForRooms(roomIDs: [String]) async -> [String: [WhisperLiveSpeaker]] {
        guard !roomIDs.isEmpty else { return [:] }
        do {
            let data = try await client
                .from("whisper_live_room_speakers")
                .select("room_id, user_id, is_host, is_cohost, can_video")
                .in("room_id", values: roomIDs)
                .execute()
                .data
            let rows = try JSONDecoder().decode([WhisperLiveSpeaker].self, from: data)
            var map: [String: [WhisperLiveSpeaker]] = [:]
            for row in rows {
                map[row.room_id ?? "", default: []].append(row)
            }
            // Host first so the cluster leads with the host's face.
            for (key, list) in map {
                map[key] = list.sorted { a, b in
                    if a.is_host != b.is_host { return a.is_host }
                    return a.user_id < b.user_id
                }
            }
            return map
        } catch {
            return [:]
        }
    }

    func addSpeaker(roomID: String, userID: String, isHost: Bool = false, isCohost: Bool = false, canVideo: Bool = true) async throws {
        // Instagram-style cap: max 4 people on camera.
        let existing = (try? await fetchSpeakers(roomID: roomID)) ?? []
        if existing.contains(where: { $0.user_id == userID }) { return }
        guard existing.count < Self.maxBroadcasters else {
            throw WhisperLiveRoomError.roomFull
        }
        _ = try await client
            .from("whisper_live_room_speakers")
            .insert([
                "room_id": AnyJSON.string(roomID),
                "user_id": .string(userID),
                "is_host": .bool(isHost),
                "is_cohost": .bool(isCohost),
                "can_video": .bool(canVideo)
            ])
            .execute()
    }

    func removeSpeaker(roomID: String, userID: String) async throws {
        _ = try await client
            .from("whisper_live_room_speakers")
            .delete()
            .eq("room_id", value: roomID)
            .eq("user_id", value: userID)
            .execute()
    }

    // MARK: - Group live invites

    /// Invite friends to join a live as co-broadcasters. Best-effort — the
    /// invites table may not be migrated yet, so failures are swallowed.
    func invite(roomID: String, inviteeIDs: [String]) async {
        guard let me = currentUserID, !inviteeIDs.isEmpty else { return }
        for invitee in inviteeIDs {
            let payload: [String: AnyJSON] = [
                "room_id": .string(roomID),
                "inviter_id": .string(me),
                "invitee_id": .string(invitee),
                "status": .string("pending")
            ]
            _ = try? await client
                .from("whisper_live_invites")
                .insert(payload)
                .execute()
        }
    }

    /// True when the current user has a pending co-host invite for `roomID`.
    /// Invited users auto-join the broadcast grid when they open the live.
    func hasInvite(roomID: String) async -> Bool {
        guard let me = currentUserID else { return false }
        do {
            struct Row: Codable { let id: String }
            let rows: [Row] = try await client
                .from("whisper_live_invites")
                .select("id")
                .eq("room_id", value: roomID)
                .eq("invitee_id", value: me)
                .eq("status", value: "pending")
                .limit(1)
                .execute()
                .value
            return !rows.isEmpty
        } catch {
            return false
        }
    }

    /// Mark my invite accepted once I've joined the broadcast.
    func acceptInvite(roomID: String) async {
        guard let me = currentUserID else { return }
        _ = try? await client
            .from("whisper_live_invites")
            .update(["status": AnyJSON.string("accepted")])
            .eq("room_id", value: roomID)
            .eq("invitee_id", value: me)
            .execute()
    }

    /// Room IDs the current user is invited to (pending) — used to badge
    /// live bubbles with "Invited".
    func myInvitedRoomIDs() async -> Set<String> {
        guard let me = currentUserID else { return [] }
        do {
            struct Row: Codable { let room_id: String }
            let rows: [Row] = try await client
                .from("whisper_live_invites")
                .select("room_id")
                .eq("invitee_id", value: me)
                .eq("status", value: "pending")
                .execute()
                .value
            return Set(rows.map { $0.room_id })
        } catch {
            return []
        }
    }

    // MARK: - Listener presence

    func joinListener(roomID: String, userID: String) async throws {
        _ = try await client
            .from("whisper_live_room_listeners")
            .upsert(["room_id": AnyJSON.string(roomID), "user_id": .string(userID)])
            .execute()
    }

    func leaveListener(roomID: String, userID: String) async throws {
        _ = try await client
            .from("whisper_live_room_listeners")
            .delete()
            .eq("room_id", value: roomID)
            .eq("user_id", value: userID)
            .execute()
    }

    // MARK: - Speaker requests

    func createSpeakerRequest(roomID: String, desiredRole: String, answers: [String: String]) async throws {
        guard let userID = currentUserID else {
            throw WhisperLiveRoomError.notSignedIn
        }
        let answersJSON = AnyJSON.object(answers.mapValues { AnyJSON.string($0) })
        _ = try await client
            .from("whisper_live_speaker_requests")
            .insert([
                "room_id": AnyJSON.string(roomID),
                "user_id": .string(userID),
                "desired_role": .string(desiredRole),
                "answers": answersJSON
            ])
            .execute()
    }

    func fetchSpeakerRequests(roomID: String) async throws -> [WhisperLiveSpeakerRequest] {
        let data = try await client
            .from("whisper_live_speaker_requests")
            .select("id, room_id, user_id, desired_role, answers, status, requested_at, reviewed_by, reviewed_at")
            .eq("room_id", value: roomID)
            .order("requested_at", ascending: false)
            .execute()
            .data
        return try JSONDecoder().decode([WhisperLiveSpeakerRequest].self, from: data)
    }

    func decideSpeakerRequest(request: WhisperLiveSpeakerRequest, accept: Bool) async throws {
        guard let reviewerID = currentUserID else {
            throw WhisperLiveRoomError.notSignedIn
        }
        _ = try await client
            .from("whisper_live_speaker_requests")
            .update([
                "status": AnyJSON.string(accept ? "accepted" : "rejected"),
                "reviewed_by": .string(reviewerID),
                "reviewed_at": .string(ISO8601DateFormatter().string(from: Date()))
            ])
            .eq("id", value: request.id)
            .execute()
        if accept {
            try await addSpeaker(
                roomID: request.room_id,
                userID: request.user_id,
                canVideo: true
            )
        }
    }

    // MARK: - Profile hydration

    /// Resolve usernames + avatars for a set of user IDs so live surfaces
    /// show real handles and faces instead of raw UUIDs.
    func hydrateProfiles(userIDs: [String]) async -> [String: WhisperBackendService.WhisperPublicProfile] {
        let unique = Array(Set(userIDs))
        guard !unique.isEmpty else { return [:] }
        return await WhisperBackendService.shared.fetchPublicProfiles(userIDs: unique)
    }

    // MARK: - Realtime (single room)

    func subscribeToRoom(roomID: String, onChange: @escaping @MainActor () -> Void) {
        unsubscribe()
        let channel = client.realtimeV2.channel("live-room:\(roomID)")
        realtimeChannel = channel

        let speakerChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "whisper_live_room_speakers",
            filter: "room_id=eq.\(roomID)"
        )
        let requestChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "whisper_live_speaker_requests",
            filter: "room_id=eq.\(roomID)"
        )
        let roomChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "whisper_live_rooms",
            filter: "id=eq.\(roomID)"
        )

        realtimeTasks = [
            Task { await channel.subscribe() },
            Task { for await _ in speakerChanges { await MainActor.run { onChange() } } },
            Task { for await _ in requestChanges { await MainActor.run { onChange() } } },
            Task { for await _ in roomChanges { await MainActor.run { onChange() } } },
            // Changes that happened while the socket was down never replay —
            // trigger a refetch on every re-subscribe so speaker lists and
            // room state can't go stale after a network blip.
            Task { [weak channel] in
                guard let channel else { return }
                var sawFirstSubscribe = false
                for await status in channel.statusChange {
                    if Task.isCancelled { return }
                    guard status == .subscribed else { continue }
                    if !sawFirstSubscribe {
                        sawFirstSubscribe = true
                        continue
                    }
                    await MainActor.run { onChange() }
                }
            }
        ]
    }

    func unsubscribe() {
        realtimeTasks.forEach { $0.cancel() }
        realtimeTasks = []
        if let channel = realtimeChannel {
            Task { await channel.unsubscribe() }
        }
        realtimeChannel = nil
    }

    // MARK: - Realtime (rooms list / story row)

    private var listCallbacks: [String: @MainActor () -> Void] = [:]

    /// Watch the whole rooms table so the story-row live bubbles and the Live
    /// hub appear/disappear in real time as friends go live or end their
    /// broadcasts. Multiple surfaces can subscribe with distinct keys; the
    /// underlying channel is shared and torn down when the last one leaves.
    func subscribeToRoomsList(key: String = "default", onChange: @escaping @MainActor () -> Void) {
        listCallbacks[key] = onChange
        guard listChannel == nil else { return }
        let channel = client.realtimeV2.channel("live-rooms-list")
        listChannel = channel
        let roomChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "whisper_live_rooms"
        )
        listTasks = [
            Task { await channel.subscribe() },
            Task { [weak self] in
                for await _ in roomChanges {
                    await MainActor.run {
                        guard let self else { return }
                        for callback in self.listCallbacks.values { callback() }
                    }
                }
            },
            // Re-notify every watcher after a reconnect so live bubbles and
            // the Live hub reflect rooms that started/ended while offline.
            Task { [weak self, weak channel] in
                guard let channel else { return }
                var sawFirstSubscribe = false
                for await status in channel.statusChange {
                    if Task.isCancelled { return }
                    guard status == .subscribed else { continue }
                    if !sawFirstSubscribe {
                        sawFirstSubscribe = true
                        continue
                    }
                    await MainActor.run {
                        guard let self else { return }
                        for callback in self.listCallbacks.values { callback() }
                    }
                }
            }
        ]
    }

    func unsubscribeFromRoomsList(key: String = "default") {
        listCallbacks.removeValue(forKey: key)
        guard listCallbacks.isEmpty else { return }
        listTasks.forEach { $0.cancel() }
        listTasks = []
        if let channel = listChannel {
            Task { await channel.unsubscribe() }
        }
        listChannel = nil
    }
}

enum WhisperLiveRoomError: Error {
    case notSignedIn
    /// The 4-person broadcaster cap was hit.
    case roomFull
}

nonisolated struct WhisperLiveRoom: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String?
    let topic: String?
    let host_id: String
    let is_live: Bool
    let is_video_enabled: Bool
    let listener_count: Int
    let created_at: String
    /// Future date when this live is scheduled to start; nil for instant lives.
    let scheduled_at: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, topic, host_id, is_live, is_video_enabled
        case listener_count, created_at, scheduled_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        topic = try? c.decodeIfPresent(String.self, forKey: .topic)
        host_id = (try? c.decode(String.self, forKey: .host_id)) ?? ""
        is_live = (try? c.decode(Bool.self, forKey: .is_live)) ?? false
        is_video_enabled = (try? c.decode(Bool.self, forKey: .is_video_enabled)) ?? true
        listener_count = (try? c.decode(Int.self, forKey: .listener_count)) ?? 0
        created_at = (try? c.decode(String.self, forKey: .created_at)) ?? ""
        scheduled_at = try? c.decodeIfPresent(String.self, forKey: .scheduled_at)
    }

    init(
        id: String,
        name: String,
        description: String?,
        topic: String?,
        host_id: String,
        is_live: Bool,
        is_video_enabled: Bool,
        listener_count: Int,
        created_at: String,
        scheduled_at: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.topic = topic
        self.host_id = host_id
        self.is_live = is_live
        self.is_video_enabled = is_video_enabled
        self.listener_count = listener_count
        self.created_at = created_at
        self.scheduled_at = scheduled_at
    }

    /// Parsed schedule date (tolerant ISO parsing).
    var scheduledDate: Date? {
        WhisperBackendService.parseISO(scheduled_at)
    }

    /// True for rooms scheduled in the future that haven't gone live yet.
    var isUpcoming: Bool {
        guard !is_live, let date = scheduledDate else { return false }
        return date > Date()
    }

    /// Canonical share URL on the public site.
    var shareURL: URL {
        URL(string: "https://mydailywhisper.com/live/\(id)") ?? URL(string: "https://mydailywhisper.com/live")!
    }
}

nonisolated struct WhisperLiveSpeaker: Codable, Equatable {
    /// Present when fetched via the bulk rooms query; nil in legacy contexts.
    let room_id: String?
    let user_id: String
    let is_host: Bool
    let is_cohost: Bool
    let can_video: Bool

    enum CodingKeys: String, CodingKey {
        case room_id, user_id, is_host, is_cohost, can_video
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        room_id = try? c.decodeIfPresent(String.self, forKey: .room_id)
        user_id = try c.decode(String.self, forKey: .user_id)
        is_host = (try? c.decode(Bool.self, forKey: .is_host)) ?? false
        is_cohost = (try? c.decode(Bool.self, forKey: .is_cohost)) ?? false
        can_video = (try? c.decode(Bool.self, forKey: .can_video)) ?? true
    }

    init(room_id: String? = nil, user_id: String, is_host: Bool, is_cohost: Bool = false, can_video: Bool = true) {
        self.room_id = room_id
        self.user_id = user_id
        self.is_host = is_host
        self.is_cohost = is_cohost
        self.can_video = can_video
    }
}

nonisolated struct WhisperLiveSpeakerRequest: Identifiable, Codable {
    let id: String
    let room_id: String
    let user_id: String
    let desired_role: String
    let answers: [String: String]
    let status: String
    let requested_at: String
    let reviewed_by: String?
    let reviewed_at: String?
}
