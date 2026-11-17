import Foundation
import Supabase
import Realtime

@Observable
class SupabaseService {
    static let shared = SupabaseService()

    private(set) var isConnected: Bool = false

    let client: SupabaseClient

    static let supabaseURL = "https://uryyyegnbtlmyhqlgndy.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVyeXl5ZWduYnRsbXlocWxnbmR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyMzM3MDcsImV4cCI6MjA5MDgwOTcwN30.fBo6K9yNHmk1nTArspc5ByMsWEiI2SahCFk6Mdp7qUQ"

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: Self.supabaseURL)!,
            supabaseKey: Self.supabaseAnonKey
        )
        isConnected = true
    }

    func createRace(_ race: Race) async throws {
        try await client.from("races").insert(race).execute()
    }

    func fetchRace(byJoinCode code: String) async throws -> Race? {
        let response: [Race] = try await client.from("races")
            .select()
            .eq("join_code", value: code.uppercased())
            .execute()
            .value
        return response.first
    }

    func fetchRace(byId id: String) async throws -> Race? {
        let response: [Race] = try await client.from("races")
            .select()
            .eq("id", value: id)
            .execute()
            .value
        return response.first
    }

    func updateRaceStatus(raceId: String, status: RaceStatus) async throws {
        var updates: [String: String] = ["status": status.rawValue]
        if status == .active {
            updates["race_started_at"] = ISO8601DateFormatter().string(from: Date())
        }
        try await client.from("races")
            .update(updates)
            .eq("id", value: raceId)
            .execute()
    }

    func addParticipant(_ participant: RaceParticipant) async throws {
        try await client.from("race_participants").insert(participant).execute()
    }

    func fetchParticipants(raceId: String) async throws -> [RaceParticipant] {
        let response: [RaceParticipant] = try await client.from("race_participants")
            .select()
            .eq("race_id", value: raceId)
            .execute()
            .value
        return response
    }

    func updateParticipantStatus(participantId: String, status: ParticipantStatus) async throws {
        try await client.from("race_participants")
            .update(["status": status.rawValue])
            .eq("id", value: participantId)
            .execute()
    }

    func finishParticipant(participantId: String, timeSeconds: Double, avgPace: Double?) async throws {
        var updates: [String: AnyJSON] = [
            "status": .string(ParticipantStatus.finished.rawValue),
            "finish_time_seconds": .double(timeSeconds)
        ]
        if let pace = avgPace {
            updates["average_pace"] = .double(pace)
        }
        try await client.from("race_participants")
            .update(updates)
            .eq("id", value: participantId)
            .execute()
    }

    func upsertRunnerPosition(raceId: String, position: RunnerPosition) async throws {
        try await client.from("runner_positions")
            .upsert([
                "participant_id": AnyJSON.string(position.participantId),
                "race_id": AnyJSON.string(raceId),
                "display_name": AnyJSON.string(position.displayName),
                "latitude": AnyJSON.double(position.latitude),
                "longitude": AnyJSON.double(position.longitude),
                "speed": AnyJSON.double(position.speed),
                "distance_covered": AnyJSON.double(position.distanceCovered),
                "timestamp": AnyJSON.double(position.timestamp)
            ], onConflict: "participant_id")
            .execute()
    }

    func fetchRunnerPositions(raceId: String) async throws -> [RunnerPosition] {
        let response: [RunnerPosition] = try await client.from("runner_positions")
            .select()
            .eq("race_id", value: raceId)
            .execute()
            .value
        return response
    }

    func deleteRunnerPositions(raceId: String) async throws {
        try await client.from("runner_positions")
            .delete()
            .eq("race_id", value: raceId)
            .execute()
    }

    func createRaceChannel(raceId: String) -> RealtimeChannelV2 {
        let channel = client.realtimeV2.channel("race:\(raceId)") {
            $0.broadcast.receiveOwnBroadcasts = true
        }
        return channel
    }
}
