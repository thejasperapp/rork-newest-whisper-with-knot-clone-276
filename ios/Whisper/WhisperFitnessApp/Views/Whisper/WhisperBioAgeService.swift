import Foundation
import SwiftUI
import Supabase

// MARK: - Row model (partner Jasper app's `jasper_biological_age` table)

/// One factor driving the biological-age estimate ("HRV −1.2y").
nonisolated struct WhisperBioAgeFactor: Codable, Sendable, Hashable {
    var title: String?
    var delta: Double?
    var detail: String?

    init(title: String? = nil, delta: Double? = nil, detail: String? = nil) {
        self.title = title
        self.delta = delta
        self.detail = detail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try? c.decodeIfPresent(String.self, forKey: .title)
        self.detail = try? c.decodeIfPresent(String.self, forKey: .detail)
        if let d = try? c.decodeIfPresent(Double.self, forKey: .delta) {
            self.delta = d
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .delta) {
            self.delta = Double(s)
        } else {
            self.delta = nil
        }
    }

    enum CodingKeys: String, CodingKey { case title, delta, detail }
}

/// A biological-age snapshot synced by the partner Jasper app. Tolerant
/// decoding: number columns may arrive as strings, and alternate column
/// names are tried so a schema tweak never blanks the feature.
nonisolated struct WhisperBioAgeRow: Codable, Sendable, Hashable {
    var user_id: String?
    var username: String?
    var biologicalAge: Double?
    var chronologicalAge: Double?
    var factors: [WhisperBioAgeFactor]?
    var confidence: Double?
    var usedBloodBiomarkers: Bool?
    var freshness: String?
    var createdAt: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexKey.self)
        func flexDouble(_ names: [String]) -> Double? {
            for name in names {
                let key = FlexKey(stringValue: name)
                if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
                if let s = try? c.decodeIfPresent(String.self, forKey: key), let d = Double(s) { return d }
                if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i) }
            }
            return nil
        }
        func flexString(_ names: [String]) -> String? {
            for name in names {
                if let s = try? c.decodeIfPresent(String.self, forKey: FlexKey(stringValue: name)) { return s }
            }
            return nil
        }
        self.user_id = flexString(["user_id", "uid"])
        self.username = flexString(["username"])
        self.biologicalAge = flexDouble(["biological_age", "bio_age", "biologicalAge"])
        self.chronologicalAge = flexDouble(["chronological_age", "chrono_age", "chronologicalAge", "real_age"])
        self.confidence = flexDouble(["confidence", "confidence_score"])
        self.freshness = flexString(["freshness", "blood_freshness"])
        self.createdAt = flexString(["created_at", "recorded_on", "updated_at"])
        if let b = try? c.decodeIfPresent(Bool.self, forKey: FlexKey(stringValue: "used_blood_biomarkers")) {
            self.usedBloodBiomarkers = b
        } else {
            self.usedBloodBiomarkers = nil
        }
        self.factors = (try? c.decodeIfPresent([WhisperBioAgeFactor].self, forKey: FlexKey(stringValue: "factors"))) ?? nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: FlexKey.self)
        try c.encodeIfPresent(user_id, forKey: FlexKey(stringValue: "user_id"))
        try c.encodeIfPresent(username, forKey: FlexKey(stringValue: "username"))
        try c.encodeIfPresent(biologicalAge, forKey: FlexKey(stringValue: "biological_age"))
        try c.encodeIfPresent(chronologicalAge, forKey: FlexKey(stringValue: "chronological_age"))
        try c.encodeIfPresent(factors, forKey: FlexKey(stringValue: "factors"))
        try c.encodeIfPresent(confidence, forKey: FlexKey(stringValue: "confidence"))
        try c.encodeIfPresent(usedBloodBiomarkers, forKey: FlexKey(stringValue: "used_blood_biomarkers"))
        try c.encodeIfPresent(freshness, forKey: FlexKey(stringValue: "freshness"))
        try c.encodeIfPresent(createdAt, forKey: FlexKey(stringValue: "created_at"))
    }

    nonisolated struct FlexKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

// MARK: - Derived presentation values (Jasper's exact vitality spec)

extension WhisperBioAgeRow {
    /// biological − chronological, negative = younger than real age.
    var deltaYears: Double? {
        guard let bio = biologicalAge, let chrono = chronologicalAge else { return nil }
        return bio - chrono
    }

    /// Maps the delta (clamped ±10y) onto 0…1 — 0 much younger, 1 much older.
    var vitalityT: Double {
        let d = min(10, max(-10, deltaYears ?? 0))
        return (d + 10) / 20
    }

    nonisolated enum Band: Sendable { case younger, aligned, older }

    var band: Band {
        if vitalityT < 0.50 { return .younger }
        if vitalityT < 0.62 { return .aligned }
        return .older
    }

    /// Accent color by vitality band — mint / teal / ember orange.
    var accent: Color {
        switch band {
        case .younger: return Color(red: 0.25, green: 0.85, blue: 0.55)
        case .aligned: return Color(red: 0.20, green: 0.78, blue: 0.82)
        case .older:   return Color(red: 1.00, green: 0.50, blue: 0.32)
        }
    }

    /// Confidence normalized to 0…1 (tolerates 0–100 storage).
    var confidence01: Double {
        guard let c = confidence else { return 0 }
        return c > 1.5 ? min(1, c / 100) : min(1, max(0, c))
    }

    var confidenceLevel: String {
        if confidence01 >= 0.67 { return "High" }
        if confidence01 >= 0.34 { return "Moderate" }
        return "Low"
    }

    var confidenceColor: Color {
        if confidence01 >= 0.67 { return Color(red: 0.16, green: 0.68, blue: 0.42) }
        if confidence01 >= 0.34 { return Color(red: 0.95, green: 0.65, blue: 0.20) }
        return Color(red: 0.92, green: 0.42, blue: 0.26)
    }

    /// "4.2 years younger" / "on par with your real age" / "3.1 years older".
    var deltaHeadline: String {
        guard let d = deltaYears else { return "estimate pending" }
        let mag = abs(d)
        if mag < 0.5 { return "on par with real age" }
        let years = mag < 9.95 ? String(format: "%.1f", mag) : "\(Int(mag.rounded()))"
        return d < 0 ? "\(years) years younger" : "\(years) years older"
    }

    /// Factors sorted most-younger first, matching the Jasper app layout.
    var sortedFactors: [WhisperBioAgeFactor] {
        (factors ?? []).sorted { ($0.delta ?? 0) < ($1.delta ?? 0) }
    }

    var topFactorLine: String? {
        guard let f = sortedFactors.first, let title = f.title, let d = f.delta else { return nil }
        return String(format: "%@ %@%.1fy", title, d < 0 ? "−" : "+", abs(d))
    }
}

// MARK: - Service

/// Fetches biological-age snapshots synced by the partner Jasper app.
/// Rows are RLS-scoped: users read their own; accepted coaches read their
/// clients' through explicit coach grants (mirrors client snapshots).
@MainActor
@Observable
final class WhisperBioAgeService {
    static let shared = WhisperBioAgeService()
    private init() {}

    private let client = SupabaseService.shared.client

    /// The signed-in user's latest snapshot (cached for the session).
    var mine: WhisperBioAgeRow?
    private var mineFetchedAt: Date?
    private var cache: [String: WhisperBioAgeRow] = [:]

    private var isRemote: Bool {
        let uid = AccountStorage.currentUserID
        return uid != "guest" && !uid.hasPrefix("local_")
    }

    @discardableResult
    func fetchMine(force: Bool = false) async -> WhisperBioAgeRow? {
        guard isRemote else { return nil }
        if !force, let mine, let at = mineFetchedAt, Date().timeIntervalSince(at) < 300 {
            return mine
        }
        let row = await fetch(forUser: AccountStorage.currentUserID, force: force)
        if let row { mine = row }
        mineFetchedAt = Date()
        return mine
    }

    /// Latest snapshot for any user id (self or an accepted client).
    func fetch(forUser userID: String, force: Bool = false) async -> WhisperBioAgeRow? {
        guard isRemote else { return nil }
        let key = userID.lowercased()
        if !force, let hit = cache[key] { return hit }
        do {
            let rows: [WhisperBioAgeRow] = try await client
                .from("jasper_biological_age")
                .select()
                .eq("user_id", value: userID)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            if let row = rows.first {
                cache[key] = row
                return row
            }
            return nil
        } catch {
            // Column-name drift on the order key — retry unordered.
            do {
                let rows: [WhisperBioAgeRow] = try await client
                    .from("jasper_biological_age")
                    .select()
                    .eq("user_id", value: userID)
                    .limit(1)
                    .execute()
                    .value
                if let row = rows.first {
                    cache[key] = row
                    return row
                }
            } catch {
                print("[WhisperBioAge] fetch error: \(error)")
            }
            return nil
        }
    }

    /// Resolve a handle → user id → latest snapshot.
    func fetch(forUsername username: String) async -> WhisperBioAgeRow? {
        let clean = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
        guard !clean.isEmpty else { return nil }
        let myName = (LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "").lowercased()
        if clean == myName {
            return await fetchMine()
        }
        if let client = WhisperCoachRequestService.shared.myClients.first(where: {
            $0.client_username.lowercased() == clean
        }) {
            return await fetch(forUser: client.client_user_id)
        }
        guard let user = await WhisperUserService.shared.fetchByUsername(clean) else { return nil }
        return await fetch(forUser: user.user_id)
    }

    // MARK: - Text builders (prompts, posts, shares)

    /// One-line truthful summary for Jasper's context blocks.
    nonisolated static func promptLine(_ row: WhisperBioAgeRow) -> String {
        guard let bio = row.biologicalAge else { return "synced, but no score yet" }
        var parts: [String] = [String(format: "biological age %.1f", bio)]
        if let chrono = row.chronologicalAge {
            parts.append(String(format: "real age %.0f", chrono))
        }
        parts.append(row.deltaHeadline)
        parts.append("confidence \(row.confidenceLevel)")
        if row.usedBloodBiomarkers == true { parts.append("includes blood biomarkers") }
        if let top = row.topFactorLine { parts.append("top driver: \(top)") }
        return parts.joined(separator: " · ")
    }

    /// Ready-to-publish feed post text.
    nonisolated static func feedPostText(_ row: WhisperBioAgeRow) -> String {
        guard let bio = row.biologicalAge else {
            return "Tracking my biological age with Jasper on Whisper."
        }
        var lines = [String(format: "My biological age: %.1f — %@.", bio, row.deltaHeadline)]
        if let top = row.topFactorLine {
            lines.append("Top driver: \(top).")
        }
        lines.append("Confidence: \(row.confidenceLevel) · synced from the Jasper app.")
        return lines.joined(separator: "\n")
    }

    /// DM-embeddable share payload (renders as a card in chat).
    nonisolated static func sharePayload(
        _ row: WhisperBioAgeRow,
        senderUsername: String,
        recordedOn: String
    ) -> WhisperHealthShareEmbed.Payload {
        WhisperHealthShareEmbed.Payload(
            kind: WhisperHealthShareEmbed.Kind.bioAge.rawValue,
            senderUsername: senderUsername,
            recordedOn: recordedOn,
            summary: "\(row.deltaHeadline) · confidence \(row.confidenceLevel) · via Jasper",
            startedAt: nil, endedAt: nil, durationSeconds: nil,
            deepSeconds: nil, remSeconds: nil, lightSeconds: nil,
            awakeSeconds: nil, qualityScore: nil,
            readinessScore: nil, sleepScore: nil, recoveryScore: nil, strainScore: nil,
            restingHR: nil, averageHR: nil, maxHR: nil, minHR: nil,
            hrvMs: nil, spo2Pct: nil,
            steps: nil, distanceM: nil,
            activeEnergyKcal: nil, basalEnergyKcal: nil,
            exerciseMinutes: nil, standHours: nil, moveGoalKcal: nil,
            bioAge: row.biologicalAge,
            chronoAge: row.chronologicalAge,
            deltaYears: row.deltaYears,
            confidenceLevel: row.confidenceLevel,
            topFactor: row.topFactorLine
        )
    }
}
