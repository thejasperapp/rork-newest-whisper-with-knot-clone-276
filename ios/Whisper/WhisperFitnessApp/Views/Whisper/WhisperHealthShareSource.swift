import Foundation
import HealthKit
import Supabase

/// Builds a `WhisperHealthShareEmbed.Payload` from the sender's REAL data
/// in Supabase — the exact rows that drive Whisper's charts. We read the
/// most recent `jasper_*` row for the signed-in user and ship that.
/// HealthKit is only used as a last-resort fallback when Supabase has no
/// row for the requested metric yet.
@MainActor
enum WhisperHealthShareSource {

    static func build(
        kind: WhisperHealthShareEmbed.Kind,
        senderUsername: String
    ) async -> WhisperHealthShareEmbed.Payload {
        let dayKey = startOfLocalDayUTC()

        // Biological age comes straight from the partner Jasper app's synced
        // snapshot — never from HealthKit.
        if kind == .bioAge {
            return await buildBioAge(username: senderUsername, dayKey: dayKey)
        }

        let uid = await currentUID()

        // 1) Try Supabase first — this is the source of truth Whisper's
        //    charts render from. If a row exists, we ship it verbatim.
        if let uid, let payload = await buildFromSupabase(
            kind: kind, username: senderUsername, dayKey: dayKey, uid: uid
        ) {
            return payload
        }

        // 2) Fallback: pull HealthKit on-device so the share still has
        //    something meaningful before the user's first sync.
        let hk: HealthKitService = HealthKitService()
        if hk.isAvailable {
            await hk.requestAuthorization()
            await hk.fetchAllData()
        }
        switch kind {
        case .sleep:
            return buildSleep(username: senderUsername, dayKey: dayKey, hk: hk)
        case .readiness:
            return buildReadiness(username: senderUsername, dayKey: dayKey, hk: hk)
        case .steps:
            return buildSteps(username: senderUsername, dayKey: dayKey, hk: hk)
        case .heartRate:
            return buildHeartRate(username: senderUsername, dayKey: dayKey, hk: hk)
        case .activeEnergy:
            return buildActiveEnergy(username: senderUsername, dayKey: dayKey, hk: hk)
        case .bioAge:
            return await buildBioAge(username: senderUsername, dayKey: dayKey)
        }
    }

    /// Latest partner-Jasper biological-age snapshot as a share payload.
    private static func buildBioAge(username: String, dayKey: String) async -> WhisperHealthShareEmbed.Payload {
        if let row = await WhisperBioAgeService.shared.fetchMine(force: true) {
            return WhisperBioAgeService.sharePayload(row, senderUsername: username, recordedOn: dayKey)
        }
        return WhisperHealthShareEmbed.Payload(
            kind: WhisperHealthShareEmbed.Kind.bioAge.rawValue,
            senderUsername: username,
            recordedOn: dayKey,
            summary: "No Jasper biological age synced yet — open the Jasper app to sync one.",
            startedAt: nil, endedAt: nil, durationSeconds: nil,
            deepSeconds: nil, remSeconds: nil, lightSeconds: nil,
            awakeSeconds: nil, qualityScore: nil,
            readinessScore: nil, sleepScore: nil, recoveryScore: nil, strainScore: nil,
            restingHR: nil, averageHR: nil, maxHR: nil, minHR: nil,
            hrvMs: nil, spo2Pct: nil,
            steps: nil, distanceM: nil,
            activeEnergyKcal: nil, basalEnergyKcal: nil,
            exerciseMinutes: nil, standHours: nil, moveGoalKcal: nil
        )
    }

    // MARK: - Supabase source (real chart data)

    private static func currentUID() async -> String? {
        let client = SupabaseService.shared.client
        if let session = try? await client.auth.session {
            let live = session.user.id.uuidString.lowercased()
            if WhisperIdentityService.isValidSupabaseUID(live) { return live }
        }
        let cached = AccountStorage.currentUserID
        return WhisperIdentityService.isValidSupabaseUID(cached) ? cached.lowercased() : nil
    }

    private static func buildFromSupabase(
        kind: WhisperHealthShareEmbed.Kind,
        username: String,
        dayKey: String,
        uid: String
    ) async -> WhisperHealthShareEmbed.Payload? {
        let client = SupabaseService.shared.client
        switch kind {
        case .bioAge:
            // Handled by the early return in `build` — bio age never reads
            // the jasper_* chart tables here.
            return nil
        case .sleep:
            struct Row: Decodable, Sendable {
                let started_at: String?; let ended_at: String?
                let duration_seconds: Int?; let deep_seconds: Int?; let rem_seconds: Int?
                let light_seconds: Int?; let awake_seconds: Int?
                let resting_hr_bpm: Int?; let hrv_ms: Double?; let spo2_pct: Double?
                let quality_score: Int?
            }
            let rows: [Row]? = try? await client.from("jasper_sleep_sessions")
                .select().eq("user_id", value: uid)
                .order("started_at", ascending: false, nullsFirst: false)
                .limit(1).execute().value
            guard let r = rows?.first else { return nil }
            let total = r.duration_seconds ?? 0
            let h = total / 3600, m = (total % 3600) / 60
            let q = r.quality_score ?? 0
            let summary = total > 0 ? "Slept \(h)h \(m)m · quality \(q)/100"
                                    : "Latest sleep row from your Whisper chart."
            return WhisperHealthShareEmbed.Payload(
                kind: WhisperHealthShareEmbed.Kind.sleep.rawValue,
                senderUsername: username, recordedOn: dayKey, summary: summary,
                startedAt: r.started_at, endedAt: r.ended_at,
                durationSeconds: total,
                deepSeconds: r.deep_seconds ?? 0, remSeconds: r.rem_seconds ?? 0,
                lightSeconds: r.light_seconds ?? 0, awakeSeconds: r.awake_seconds ?? 0,
                qualityScore: q,
                readinessScore: nil, sleepScore: nil, recoveryScore: nil, strainScore: nil,
                restingHR: r.resting_hr_bpm, averageHR: nil, maxHR: nil, minHR: nil,
                hrvMs: r.hrv_ms, spo2Pct: r.spo2_pct,
                steps: nil, distanceM: nil,
                activeEnergyKcal: nil, basalEnergyKcal: nil,
                exerciseMinutes: nil, standHours: nil, moveGoalKcal: nil
            )

        case .readiness:
            struct Row: Decodable, Sendable {
                let recorded_on: String?
                let score: Int?; let sleep_score: Int?
                let recovery_score: Int?; let strain_score: Int?
                let hrv_ms: Double?; let resting_hr_bpm: Int?
            }
            let rows: [Row]? = try? await client.from("jasper_readiness_scores")
                .select().eq("user_id", value: uid)
                .order("recorded_on", ascending: false, nullsFirst: false)
                .limit(1).execute().value
            guard let r = rows?.first else { return nil }
            let s = r.score ?? 0
            let summary = "Readiness \(s)/100 · sleep \(r.sleep_score ?? 0), recovery \(r.recovery_score ?? 0), strain \(r.strain_score ?? 0)"
            return WhisperHealthShareEmbed.Payload(
                kind: WhisperHealthShareEmbed.Kind.readiness.rawValue,
                senderUsername: username, recordedOn: r.recorded_on ?? dayKey, summary: summary,
                startedAt: nil, endedAt: nil,
                durationSeconds: nil, deepSeconds: nil, remSeconds: nil, lightSeconds: nil, awakeSeconds: nil,
                qualityScore: nil,
                readinessScore: s, sleepScore: r.sleep_score, recoveryScore: r.recovery_score, strainScore: r.strain_score,
                restingHR: r.resting_hr_bpm, averageHR: nil, maxHR: nil, minHR: nil,
                hrvMs: r.hrv_ms, spo2Pct: nil,
                steps: nil, distanceM: nil,
                activeEnergyKcal: nil, basalEnergyKcal: nil,
                exerciseMinutes: nil, standHours: nil, moveGoalKcal: nil
            )

        case .steps:
            struct Row: Decodable, Sendable {
                let recorded_on: String?; let steps: Int?; let distance_m: Double?
            }
            let rows: [Row]? = try? await client.from("jasper_steps_daily")
                .select().eq("user_id", value: uid)
                .order("recorded_on", ascending: false, nullsFirst: false)
                .limit(1).execute().value
            guard let r = rows?.first else { return nil }
            let s = r.steps ?? 0
            let summary = s > 0 ? "\(formattedThousands(Double(s))) steps today" : "Latest steps row from Whisper."
            return WhisperHealthShareEmbed.Payload(
                kind: WhisperHealthShareEmbed.Kind.steps.rawValue,
                senderUsername: username, recordedOn: r.recorded_on ?? dayKey, summary: summary,
                startedAt: nil, endedAt: nil,
                durationSeconds: nil, deepSeconds: nil, remSeconds: nil, lightSeconds: nil, awakeSeconds: nil,
                qualityScore: nil,
                readinessScore: nil, sleepScore: nil, recoveryScore: nil, strainScore: nil,
                restingHR: nil, averageHR: nil, maxHR: nil, minHR: nil,
                hrvMs: nil, spo2Pct: nil,
                steps: s, distanceM: r.distance_m,
                activeEnergyKcal: nil, basalEnergyKcal: nil,
                exerciseMinutes: nil, standHours: nil, moveGoalKcal: nil
            )

        case .heartRate:
            struct Row: Decodable, Sendable {
                let recorded_on: String?
                let resting_bpm: Int?; let average_bpm: Int?
                let max_bpm: Int?; let min_bpm: Int?; let hrv_ms: Double?
            }
            let rows: [Row]? = try? await client.from("jasper_heart_rate_daily")
                .select().eq("user_id", value: uid)
                .order("recorded_on", ascending: false, nullsFirst: false)
                .limit(1).execute().value
            guard let r = rows?.first else { return nil }
            let summary: String = {
                if let rest = r.resting_bpm { return "Resting \(rest) bpm · HRV \(Int((r.hrv_ms ?? 0).rounded())) ms" }
                if let avg = r.average_bpm { return "Avg \(avg) bpm today" }
                return "Latest heart-rate row from Whisper."
            }()
            return WhisperHealthShareEmbed.Payload(
                kind: WhisperHealthShareEmbed.Kind.heartRate.rawValue,
                senderUsername: username, recordedOn: r.recorded_on ?? dayKey, summary: summary,
                startedAt: nil, endedAt: nil,
                durationSeconds: nil, deepSeconds: nil, remSeconds: nil, lightSeconds: nil, awakeSeconds: nil,
                qualityScore: nil,
                readinessScore: nil, sleepScore: nil, recoveryScore: nil, strainScore: nil,
                restingHR: r.resting_bpm, averageHR: r.average_bpm, maxHR: r.max_bpm, minHR: r.min_bpm,
                hrvMs: r.hrv_ms, spo2Pct: nil,
                steps: nil, distanceM: nil,
                activeEnergyKcal: nil, basalEnergyKcal: nil,
                exerciseMinutes: nil, standHours: nil, moveGoalKcal: nil
            )

        case .activeEnergy:
            struct Row: Decodable, Sendable {
                let recorded_on: String?
                let active_energy_kcal: Double?; let basal_energy_kcal: Double?
                let exercise_minutes: Int?; let stand_hours: Int?; let move_goal_kcal: Int?
            }
            let rows: [Row]? = try? await client.from("jasper_active_energy_daily")
                .select().eq("user_id", value: uid)
                .order("recorded_on", ascending: false, nullsFirst: false)
                .limit(1).execute().value
            guard let r = rows?.first else { return nil }
            let active = r.active_energy_kcal ?? 0
            let mins = r.exercise_minutes ?? 0
            let summary = active > 0 ? "\(Int(active.rounded())) active kcal · \(mins) min exercise"
                                     : "Latest energy row from Whisper."
            return WhisperHealthShareEmbed.Payload(
                kind: WhisperHealthShareEmbed.Kind.activeEnergy.rawValue,
                senderUsername: username, recordedOn: r.recorded_on ?? dayKey, summary: summary,
                startedAt: nil, endedAt: nil,
                durationSeconds: nil, deepSeconds: nil, remSeconds: nil, lightSeconds: nil, awakeSeconds: nil,
                qualityScore: nil,
                readinessScore: nil, sleepScore: nil, recoveryScore: nil, strainScore: nil,
                restingHR: nil, averageHR: nil, maxHR: nil, minHR: nil,
                hrvMs: nil, spo2Pct: nil,
                steps: nil, distanceM: nil,
                activeEnergyKcal: active, basalEnergyKcal: r.basal_energy_kcal,
                exerciseMinutes: mins, standHours: r.stand_hours, moveGoalKcal: r.move_goal_kcal
            )
        }
    }

    // MARK: - Sleep

    private static func buildSleep(
        username: String,
        dayKey: String,
        hk: HealthKitService
    ) -> WhisperHealthShareEmbed.Payload {
        let analysis = hk.sleepAnalysisData
        let total = Int(analysis.totalSleepDuration)
        let rem = Int(analysis.remDuration)
        let deep = Int(analysis.deepDuration)
        let light = Int(analysis.coreDuration)
        let awake = Int(analysis.awakeDuration)
        let quality = analysis.sleepScore
        let isoFractional = Self.isoFractional
        let started = analysis.bedTime.map { isoFractional.string(from: $0) } ?? dayKey
        let ended = analysis.wakeTime.map { isoFractional.string(from: $0) } ?? dayKey
        let resting = hk.summary.restingHeartRate > 0 ? Int(hk.summary.restingHeartRate.rounded()) : nil
        let hrv = hk.summary.heartRateVariability > 0 ? hk.summary.heartRateVariability : nil
        let spo2 = hk.summary.bloodOxygen > 0 ? hk.summary.bloodOxygen * 100 : nil

        let h = total / 3600
        let m = (total % 3600) / 60
        let summary = total > 0
            ? "Slept \(h)h \(m)m · quality \(quality)/100"
            : "No sleep recorded yet today — sharing the placeholder summary."

        return WhisperHealthShareEmbed.Payload(
            kind: WhisperHealthShareEmbed.Kind.sleep.rawValue,
            senderUsername: username,
            recordedOn: dayKey,
            summary: summary,
            startedAt: started,
            endedAt: ended,
            durationSeconds: total,
            deepSeconds: deep,
            remSeconds: rem,
            lightSeconds: light,
            awakeSeconds: awake,
            qualityScore: quality,
            readinessScore: nil, sleepScore: nil, recoveryScore: nil, strainScore: nil,
            restingHR: resting, averageHR: nil, maxHR: nil, minHR: nil,
            hrvMs: hrv, spo2Pct: spo2,
            steps: nil, distanceM: nil,
            activeEnergyKcal: nil, basalEnergyKcal: nil,
            exerciseMinutes: nil, standHours: nil, moveGoalKcal: nil
        )
    }

    // MARK: - Readiness (computed locally using Whisper's formula)

    private static func buildReadiness(
        username: String,
        dayKey: String,
        hk: HealthKitService
    ) -> WhisperHealthShareEmbed.Payload {
        let sleepHours = hk.summary.sleepHours
        let hrv = hk.summary.heartRateVariability
        let rhr = hk.summary.restingHeartRate
        let active = hk.summary.calories

        // Component scores 0–100
        let sleepComp = Int(max(0, min(100, (sleepHours / 8.0) * 100)).rounded())
        let hrvComp: Int = {
            guard hrv > 0 else { return 50 }
            // 30ms → 30, 80ms → 100
            return Int(max(0, min(100, ((hrv - 20) / 80) * 100)).rounded())
        }()
        let rhrComp: Int = {
            guard rhr > 0 else { return 50 }
            // RHR lower = better; 45→100, 75→40
            return Int(max(0, min(100, 100 - (rhr - 45) * 2)).rounded())
        }()
        let activityComp: Int = {
            guard active > 0 else { return 50 }
            return Int(max(0, min(100, (active / 800.0) * 100)).rounded())
        }()
        let score = Int(max(10, min(100,
            0.30 * Double(hrvComp) +
            0.20 * Double(rhrComp) +
            0.30 * Double(sleepComp) +
            0.20 * Double(activityComp)
        )).rounded())

        let summary = "Readiness \(score)/100 · sleep \(sleepComp), recovery \(hrvComp), strain \(activityComp)"

        return WhisperHealthShareEmbed.Payload(
            kind: WhisperHealthShareEmbed.Kind.readiness.rawValue,
            senderUsername: username,
            recordedOn: dayKey,
            summary: summary,
            startedAt: nil, endedAt: nil,
            durationSeconds: nil, deepSeconds: nil, remSeconds: nil, lightSeconds: nil, awakeSeconds: nil,
            qualityScore: nil,
            readinessScore: score,
            sleepScore: sleepComp,
            recoveryScore: hrvComp,
            strainScore: activityComp,
            restingHR: rhr > 0 ? Int(rhr.rounded()) : nil,
            averageHR: nil, maxHR: nil, minHR: nil,
            hrvMs: hrv > 0 ? hrv : nil,
            spo2Pct: nil,
            steps: nil, distanceM: nil,
            activeEnergyKcal: nil, basalEnergyKcal: nil,
            exerciseMinutes: nil, standHours: nil, moveGoalKcal: nil
        )
    }

    // MARK: - Steps

    private static func buildSteps(
        username: String,
        dayKey: String,
        hk: HealthKitService
    ) -> WhisperHealthShareEmbed.Payload {
        let steps = hk.summary.steps
        // distance is stored in miles in DailyHealthSummary — convert to meters.
        let distanceMeters = hk.summary.distance * 1609.34
        let summary = steps > 0
            ? "\(formattedThousands(Double(steps))) steps today"
            : "No steps logged yet — sharing today's chart spot."

        return WhisperHealthShareEmbed.Payload(
            kind: WhisperHealthShareEmbed.Kind.steps.rawValue,
            senderUsername: username,
            recordedOn: dayKey,
            summary: summary,
            startedAt: nil, endedAt: nil,
            durationSeconds: nil, deepSeconds: nil, remSeconds: nil, lightSeconds: nil, awakeSeconds: nil,
            qualityScore: nil,
            readinessScore: nil, sleepScore: nil, recoveryScore: nil, strainScore: nil,
            restingHR: nil, averageHR: nil, maxHR: nil, minHR: nil,
            hrvMs: nil, spo2Pct: nil,
            steps: steps,
            distanceM: distanceMeters,
            activeEnergyKcal: nil, basalEnergyKcal: nil,
            exerciseMinutes: nil, standHours: nil, moveGoalKcal: nil
        )
    }

    // MARK: - Heart rate

    private static func buildHeartRate(
        username: String,
        dayKey: String,
        hk: HealthKitService
    ) -> WhisperHealthShareEmbed.Payload {
        let resting = hk.summary.restingHeartRate
        let avg = hk.summary.heartRate
        let hrv = hk.summary.heartRateVariability

        let summary: String = {
            if resting > 0 { return "Resting \(Int(resting.rounded())) bpm · HRV \(Int(hrv.rounded())) ms" }
            if avg > 0     { return "Avg \(Int(avg.rounded())) bpm today" }
            return "Sharing today's heart-rate slot."
        }()

        return WhisperHealthShareEmbed.Payload(
            kind: WhisperHealthShareEmbed.Kind.heartRate.rawValue,
            senderUsername: username,
            recordedOn: dayKey,
            summary: summary,
            startedAt: nil, endedAt: nil,
            durationSeconds: nil, deepSeconds: nil, remSeconds: nil, lightSeconds: nil, awakeSeconds: nil,
            qualityScore: nil,
            readinessScore: nil, sleepScore: nil, recoveryScore: nil, strainScore: nil,
            restingHR: resting > 0 ? Int(resting.rounded()) : nil,
            averageHR: avg > 0 ? Int(avg.rounded()) : nil,
            maxHR: nil, minHR: nil,
            hrvMs: hrv > 0 ? hrv : nil,
            spo2Pct: nil,
            steps: nil, distanceM: nil,
            activeEnergyKcal: nil, basalEnergyKcal: nil,
            exerciseMinutes: nil, standHours: nil, moveGoalKcal: nil
        )
    }

    // MARK: - Active energy

    private static func buildActiveEnergy(
        username: String,
        dayKey: String,
        hk: HealthKitService
    ) -> WhisperHealthShareEmbed.Payload {
        let active = hk.summary.calories
        let basal = hk.summary.basalEnergyBurned
        let exerciseMin = hk.summary.activeMinutes
        let standHrs = hk.summary.standHours
        let summary = active > 0
            ? "\(Int(active.rounded())) active kcal · \(exerciseMin) min exercise"
            : "Sharing today's energy ring slot."

        return WhisperHealthShareEmbed.Payload(
            kind: WhisperHealthShareEmbed.Kind.activeEnergy.rawValue,
            senderUsername: username,
            recordedOn: dayKey,
            summary: summary,
            startedAt: nil, endedAt: nil,
            durationSeconds: nil, deepSeconds: nil, remSeconds: nil, lightSeconds: nil, awakeSeconds: nil,
            qualityScore: nil,
            readinessScore: nil, sleepScore: nil, recoveryScore: nil, strainScore: nil,
            restingHR: nil, averageHR: nil, maxHR: nil, minHR: nil,
            hrvMs: nil, spo2Pct: nil,
            steps: nil, distanceM: nil,
            activeEnergyKcal: active,
            basalEnergyKcal: basal,
            exerciseMinutes: exerciseMin,
            standHours: standHrs,
            moveGoalKcal: nil
        )
    }

    // MARK: - Helpers

    /// Start of the sender's LOCAL day, expressed in UTC ISO8601 — matches
    /// Whisper's `recorded_on` convention. (e.g. midnight PT → 07:00 UTC.)
    private static func startOfLocalDayUTC() -> String {
        let cal = Calendar.current
        let startLocal = cal.startOfDay(for: Date())
        return isoFractional.string(from: startLocal)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func formattedThousands(_ v: Double) -> String {
        if v >= 10_000 { return String(format: "%.1fk", v / 1000) }
        if v >= 1_000  { return String(format: "%.2fk", v / 1000) }
        return "\(Int(v))"
    }
}
