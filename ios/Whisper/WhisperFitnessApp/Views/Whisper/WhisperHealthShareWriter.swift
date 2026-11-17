import Foundation
import Supabase

/// Recipient-side writer: takes a `WhisperHealthShareEmbed.Payload` that
/// landed in a DM and upserts it into the recipient's own `jasper_*`
/// tables. RLS enforces `auth.uid() = user_id`, so we always write under
/// the logged-in user — never the sender. Idempotent via deterministic
/// UUID per (user, scope, day).
@MainActor
enum WhisperHealthShareWriter {

    /// UUID v5 namespace shared with Whisper for stable health-row ids.
    /// Any fixed UUID is fine — both sides just need to derive the same
    /// key from `(userID, scope, dayKey)`.
    private static let namespace = UUID(uuidString: "6A8B7B6E-1F1C-4D0F-8D8C-9B0E6E2A77F1")!

    /// Performs the upsert. Returns `true` on success.
    @discardableResult
    static func apply(_ payload: WhisperHealthShareEmbed.Payload) async -> Bool {
        guard let uid = await resolvedUID() else { return false }
        let scope = payload.kindEnum.scope
        let dayKey = payload.recordedOn
        let stableID = deterministicID(userID: uid, scope: scope, dayKey: dayKey)
        let client = SupabaseService.shared.client

        switch payload.kindEnum {
        case .bioAge:
            // A biological-age card is the SENDER's score — it is never
            // imported into the recipient's own charts (the card hides the
            // save button for this kind).
            return false
        case .sleep:
            let row = SleepInsert(
                id: stableID,
                user_id: uid,
                client_id: stableID,
                started_at: payload.startedAt ?? dayKey,
                ended_at: payload.endedAt ?? dayKey,
                duration_seconds: payload.durationSeconds ?? 0,
                deep_seconds: payload.deepSeconds ?? 0,
                rem_seconds: payload.remSeconds ?? 0,
                light_seconds: payload.lightSeconds ?? 0,
                awake_seconds: payload.awakeSeconds ?? 0,
                resting_hr_bpm: payload.restingHR,
                hrv_ms: payload.hrvMs,
                spo2_pct: payload.spo2Pct,
                quality_score: payload.qualityScore ?? 0,
                source: "whisper",
                visibility: "private"
            )
            return await upsert(table: "jasper_sleep_sessions", row: row, onConflict: "user_id,client_id")

        case .readiness:
            let row = ReadinessInsert(
                id: stableID,
                user_id: uid,
                client_id: stableID,
                recorded_on: dayKey,
                score: payload.readinessScore ?? 0,
                sleep_score: payload.sleepScore ?? 0,
                recovery_score: payload.recoveryScore ?? 0,
                strain_score: payload.strainScore ?? 0,
                hrv_ms: payload.hrvMs,
                resting_hr_bpm: payload.restingHR,
                notes: nil,
                visibility: "private"
            )
            return await upsert(table: "jasper_readiness_scores", row: row, onConflict: "user_id,client_id")

        case .steps:
            let row = StepsInsert(
                id: stableID,
                user_id: uid,
                client_id: stableID,
                recorded_on: dayKey,
                steps: payload.steps ?? 0,
                distance_m: payload.distanceM ?? 0,
                source: "whisper",
                visibility: "private"
            )
            return await upsert(table: "jasper_steps_daily", row: row, onConflict: "user_id,recorded_on")

        case .heartRate:
            let row = HeartRateInsert(
                id: stableID,
                user_id: uid,
                client_id: stableID,
                recorded_on: dayKey,
                resting_bpm: payload.restingHR,
                average_bpm: payload.averageHR,
                max_bpm: payload.maxHR,
                min_bpm: payload.minHR,
                hrv_ms: payload.hrvMs,
                source: "whisper",
                visibility: "private"
            )
            return await upsert(table: "jasper_heart_rate_daily", row: row, onConflict: "user_id,recorded_on")

        case .activeEnergy:
            let row = ActiveEnergyInsert(
                id: stableID,
                user_id: uid,
                client_id: stableID,
                recorded_on: dayKey,
                active_energy_kcal: payload.activeEnergyKcal ?? 0,
                basal_energy_kcal: payload.basalEnergyKcal ?? 0,
                exercise_minutes: payload.exerciseMinutes ?? 0,
                stand_hours: payload.standHours ?? 0,
                move_goal_kcal: payload.moveGoalKcal,
                source: "whisper",
                visibility: "private"
            )
            return await upsert(table: "jasper_active_energy_daily", row: row, onConflict: "user_id,recorded_on")
        }
    }

    // MARK: - Upsert

    private static func upsert<Row: Encodable & Sendable>(
        table: String,
        row: Row,
        onConflict: String
    ) async -> Bool {
        let client = SupabaseService.shared.client
        do {
            _ = try await client.from(table).upsert(row, onConflict: onConflict).execute()
            return true
        } catch {
            print("[HealthShareWriter] upsert \(table) failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - UID resolution

    /// Pulls the live auth UID from the active Supabase session so writes
    /// always satisfy RLS (`auth.uid() = user_id`).
    private static func resolvedUID() async -> String? {
        let client = SupabaseService.shared.client
        if let session = try? await client.auth.session {
            let live = session.user.id.uuidString.lowercased()
            if WhisperIdentityService.isValidSupabaseUID(live) {
                return live
            }
        }
        let cached = AccountStorage.currentUserID
        return WhisperIdentityService.isValidSupabaseUID(cached) ? cached.lowercased() : nil
    }

    // MARK: - Deterministic id (UUID v5 over SHA-1)

    /// Produces the same UUID Whisper derives for `(user, scope, day)` so
    /// re-applies of the same share don't duplicate the row.
    nonisolated static func deterministicID(userID: String, scope: String, dayKey: String) -> String {
        let name = "\(userID)|\(scope)|\(dayKey)"
        return uuidV5(namespace: namespace, name: name).uuidString.lowercased()
    }

    private nonisolated static func uuidV5(namespace: UUID, name: String) -> UUID {
        var bytes = [UInt8]()
        bytes.reserveCapacity(16 + name.utf8.count)
        let ns = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        bytes.append(contentsOf: ns)
        bytes.append(contentsOf: Array(name.utf8))
        var hash = sha1(bytes)
        // Set version (5) and variant per RFC 4122
        hash[6] = (hash[6] & 0x0F) | 0x50
        hash[8] = (hash[8] & 0x3F) | 0x80
        let u = (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        )
        return UUID(uuid: u)
    }

    /// Minimal SHA-1 for UUID v5 only. ~30 lines, no CryptoKit dep needed
    /// (CryptoKit is available but using a tiny self-contained impl keeps
    /// this file zero-import beyond Supabase).
    private nonisolated static func sha1(_ message: [UInt8]) -> [UInt8] {
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        var msg = message
        let originalBitLen = UInt64(message.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0x00) }
        for i in (0..<8).reversed() {
            msg.append(UInt8((originalBitLen >> UInt64(i * 8)) & 0xFF))
        }

        for chunkStart in stride(from: 0, to: msg.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                let j = chunkStart + i * 4
                w[i] = (UInt32(msg[j]) << 24) | (UInt32(msg[j + 1]) << 16) | (UInt32(msg[j + 2]) << 8) | UInt32(msg[j + 3])
            }
            for i in 16..<80 {
                let v = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]
                w[i] = (v << 1) | (v >> 31)
            }
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch i {
                case 0...19:  f = (b & c) | ((~b) & d); k = 0x5A827999
                case 20...39: f = b ^ c ^ d;            k = 0x6ED9EBA1
                case 40...59: f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC
                default:      f = b ^ c ^ d;            k = 0xCA62C1D6
                }
                let temp = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = (b << 30) | (b >> 2)
                b = a
                a = temp
            }
            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
        }

        var out = [UInt8]()
        for v in [h0, h1, h2, h3, h4] {
            out.append(UInt8((v >> 24) & 0xFF))
            out.append(UInt8((v >> 16) & 0xFF))
            out.append(UInt8((v >> 8) & 0xFF))
            out.append(UInt8(v & 0xFF))
        }
        return out
    }

    // MARK: - Wire shapes (match Whisper's contract exactly)

    private nonisolated struct SleepInsert: Encodable, Sendable {
        let id: String
        let user_id: String
        let client_id: String
        let started_at: String
        let ended_at: String
        let duration_seconds: Int
        let deep_seconds: Int
        let rem_seconds: Int
        let light_seconds: Int
        let awake_seconds: Int
        let resting_hr_bpm: Int?
        let hrv_ms: Double?
        let spo2_pct: Double?
        let quality_score: Int
        let source: String
        let visibility: String
    }

    private nonisolated struct ReadinessInsert: Encodable, Sendable {
        let id: String
        let user_id: String
        let client_id: String
        let recorded_on: String
        let score: Int
        let sleep_score: Int
        let recovery_score: Int
        let strain_score: Int
        let hrv_ms: Double?
        let resting_hr_bpm: Int?
        let notes: String?
        let visibility: String
    }

    private nonisolated struct StepsInsert: Encodable, Sendable {
        let id: String
        let user_id: String
        let client_id: String
        let recorded_on: String
        let steps: Int
        let distance_m: Double
        let source: String
        let visibility: String
    }

    private nonisolated struct HeartRateInsert: Encodable, Sendable {
        let id: String
        let user_id: String
        let client_id: String
        let recorded_on: String
        let resting_bpm: Int?
        let average_bpm: Int?
        let max_bpm: Int?
        let min_bpm: Int?
        let hrv_ms: Double?
        let source: String
        let visibility: String
    }

    private nonisolated struct ActiveEnergyInsert: Encodable, Sendable {
        let id: String
        let user_id: String
        let client_id: String
        let recorded_on: String
        let active_energy_kcal: Double
        let basal_energy_kcal: Double
        let exercise_minutes: Int
        let stand_hours: Int
        let move_goal_kcal: Int?
        let source: String
        let visibility: String
    }
}
