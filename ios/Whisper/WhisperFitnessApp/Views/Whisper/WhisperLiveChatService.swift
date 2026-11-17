import Foundation
import Supabase

/// Live chat message row from `whisper_live_chat_messages`.
nonisolated struct WhisperLiveChatMessage: Codable, Identifiable, Sendable {
    let id: String
    let room_id: String
    let user_id: String
    let username: String
    let body: String
    let is_host: Bool
    let is_pinned: Bool
    let created_at: String?

    enum CodingKeys: String, CodingKey {
        case id, room_id, user_id, username, body, is_host, is_pinned, created_at
    }
}

/// Instagram/Twitch-style live chat for live rooms.
/// Messages are stored in `whisper_live_chat_messages` and delivered via
/// Supabase Realtime postgres_changes.
final class WhisperLiveChatService: @unchecked Sendable {
    static let shared = WhisperLiveChatService()

    private var client: SupabaseClient {
        SupabaseService.shared.client
    }

    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []

    /// Fetch recent chat messages for a room (newest last).
    func fetchMessages(roomID: String, limit: Int = 100) async -> [WhisperLiveChatMessage] {
        do {
            let rows: [WhisperLiveChatMessage] = try await client
                .from("whisper_live_chat_messages")
                .select()
                .eq("room_id", value: roomID)
                .order("created_at", ascending: false)
                .order("id", ascending: false)
                .limit(min(max(limit, 1), 200))
                .execute()
                .value
            return Array(rows.reversed())
        } catch {
            print("[WhisperLiveChat] fetchMessages error: \(error)")
            return []
        }
    }

    /// Send a chat message.
    func sendMessage(
        roomID: String,
        userID: String,
        username: String,
        body: String,
        isHost: Bool
    ) async throws {
        let payload: [String: AnyJSON] = [
            "room_id": .string(roomID),
            "user_id": .string(userID),
            "username": .string(username),
            "body": .string(body),
            "is_host": .bool(isHost),
            "is_pinned": .bool(false),
        ]
        try await client.from("whisper_live_chat_messages").insert(payload).execute()
    }

    /// Delete a chat message — allowed for the sender, the room's host,
    /// and the host's channel mods (enforced by RLS after live-v3).
    func deleteMessage(messageID: String) async throws {
        try await client
            .from("whisper_live_chat_messages")
            .delete()
            .eq("id", value: messageID)
            .execute()
    }

    /// Pin or unpin a message (host only).
    func togglePin(messageID: String, pinned: Bool) async throws {
        try await client
            .from("whisper_live_chat_messages")
            .update(["is_pinned": AnyJSON.bool(pinned)])
            .eq("id", value: messageID)
            .execute()
    }

    /// Subscribe to realtime chat messages for a room.
    /// Calls `onInsert` for new messages and `onDelete` when messages are removed.
    func subscribe(
        roomID: String,
        onInsert: @escaping @MainActor (WhisperLiveChatMessage) -> Void,
        onDelete: @escaping @MainActor (String) -> Void,
        onResync: (@MainActor () -> Void)? = nil
    ) {
        unsubscribe()
        let channel = client.realtimeV2.channel("live-chat:\(roomID)")
        realtimeChannel = channel

        let insertStream = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "whisper_live_chat_messages",
            filter: "room_id=eq.\(roomID)"
        )
        // Deletes don't support row-level filters in Postgres Realtime,
        // so we subscribe table-wide and filter locally.
        let deleteStream = channel.postgresChange(
            DeleteAction.self,
            schema: "public",
            table: "whisper_live_chat_messages"
        )

        realtimeTasks = [
            Task { await channel.subscribe() },
            Task {
                for await change in insertStream {
                    if let msg = try? change.decodeRecord(as: WhisperLiveChatMessage.self, decoder: JSONDecoder()) {
                        await MainActor.run { onInsert(msg) }
                    }
                }
            },
            Task {
                for await change in deleteStream {
                    if let raw = change.oldRecord["id"] {
                        let id: String
                        switch raw {
                        case .string(let s): id = s
                        default: id = String(describing: raw)
                        }
                        await MainActor.run { onDelete(id) }
                    }
                }
            },
            // Supabase auto-rejoins after network blips, but messages sent
            // while offline never replay — resync the full list on every
            // re-subscribe so live chat can't silently miss messages (the
            // same recovery the meeting signaling channel uses).
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
                    await MainActor.run { onResync?() }
                }
            }
        ]
    }

    /// Unsubscribe from realtime.
    func unsubscribe() {
        realtimeTasks.forEach { $0.cancel() }
        realtimeTasks = []
        if let channel = realtimeChannel {
            Task { await channel.unsubscribe() }
            realtimeChannel = nil
        }
    }
}
