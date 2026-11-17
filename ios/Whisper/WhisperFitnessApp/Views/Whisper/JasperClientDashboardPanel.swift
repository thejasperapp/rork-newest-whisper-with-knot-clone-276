import SwiftUI
import UIKit

// MARK: - Model (WHISPER_CONNECT.md Aug 16 2026 — the one-call dashboard)

/// `GET /v1/dashboard` parsed: the ENTIRE coach dashboard Jasper's own coach
/// view renders, in one envelope — a precomputed `summary`, per-resource
/// sections that lock INDIVIDUALLY (`{ locked, required_scope }` instead of
/// failing the whole call), and the bundled native `looks`. Row shapes inside
/// `data` are identical to the single-resource reads, so the existing
/// decoders (diet plan, groceries, hypnogram) drop straight in.
nonisolated struct JasperClientDashboard {
    nonisolated enum Section {
        case locked(requiredScope: String)
        case rows([[String: Any]])
    }

    nonisolated struct Summary {
        let readinessScore: Int?
        let sleepQualityScore: Int?
        let sleepDurationSeconds: Int?
        let biologicalAge: Double?
        let bioageDeltaYears: Double?
        let weightKg: Double?
        let workoutsLast7d: Int?
        let mealsToday: Int?
        let kcalToday: Int?
        let bloodLocked: Bool
    }

    /// `?period=week` (Aug 17 2026): this-week vs last-week deltas plus
    /// ready-to-paste `highlights` — server-computed; render, don't recompute.
    nonisolated struct Digest {
        let windowDays: Int?
        let readinessAvg: Double?
        let readinessDelta: Double?
        let sleepQuality: Double?
        let sleepQualityDelta: Double?
        let sleepDurationSeconds: Int?
        let sleepPrevDurationSeconds: Int?
        let workouts: Int?
        let workoutsDelta: Int?
        let volumeKg: Double?
        let volumeDeltaKg: Double?
        let prsThisWeek: Int?
        let kcalPerDay: Int?
        let kcalDelta: Int?
        let mealsLogged: Int?
        let weightKgLatest: Double?
        let weightDeltaKg: Double?
        let highlights: [String]

        nonisolated static func parse(_ any: Any?) -> Digest? {
            guard let d = any as? [String: Any] else { return nil }
            let readiness = (d["readiness"] as? [String: Any]) ?? [:]
            let sleep = (d["sleep"] as? [String: Any]) ?? [:]
            let training = (d["training"] as? [String: Any]) ?? [:]
            let nutrition = (d["nutrition"] as? [String: Any]) ?? [:]
            let body = (d["body"] as? [String: Any]) ?? [:]
            return Digest(
                windowDays: JasperClientDashboard.intAny(d["window_days"]),
                readinessAvg: JasperClientDashboard.doubleAny(readiness["avg"]),
                readinessDelta: JasperClientDashboard.doubleAny(readiness["delta"]),
                sleepQuality: JasperClientDashboard.doubleAny(sleep["avg_quality"]),
                sleepQualityDelta: JasperClientDashboard.doubleAny(sleep["quality_delta"]),
                sleepDurationSeconds: JasperClientDashboard.intAny(sleep["avg_duration_seconds"]),
                sleepPrevDurationSeconds: JasperClientDashboard.intAny(sleep["prev_avg_duration_seconds"]),
                workouts: JasperClientDashboard.intAny(training["workouts"]),
                workoutsDelta: JasperClientDashboard.intAny(training["workouts_delta"]),
                volumeKg: JasperClientDashboard.doubleAny(training["volume_kg"]),
                volumeDeltaKg: JasperClientDashboard.doubleAny(training["volume_delta_kg"]),
                prsThisWeek: JasperClientDashboard.intAny(training["prs_this_week"]),
                kcalPerDay: JasperClientDashboard.intAny(nutrition["kcal_per_day"]),
                kcalDelta: JasperClientDashboard.intAny(nutrition["kcal_delta"]),
                mealsLogged: JasperClientDashboard.intAny(nutrition["meals_logged"]),
                weightKgLatest: JasperClientDashboard.doubleAny(body["weight_kg_latest"]),
                weightDeltaKg: JasperClientDashboard.doubleAny(body["weight_delta_kg"]),
                highlights: (d["highlights"] as? [String]) ?? [])
        }
    }

    let fetchedAt: Date
    let generatedAt: Date?
    let summary: Summary
    let sections: [String: Section]
    /// Present only on `?period=week` reads.
    let digest: Digest?

    // MARK: Decode

    static func parse(_ data: Data, fetchedAt: Date = Date()) -> JasperClientDashboard? {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              body["ok"] as? Bool == true,
              let rawSections = body["sections"] as? [String: Any] else { return nil }
        var sections: [String: Section] = [:]
        for (name, value) in rawSections {
            guard let dict = value as? [String: Any] else { continue }
            if dict["locked"] as? Bool == true {
                sections[name] = .locked(requiredScope: (dict["required_scope"] as? String) ?? "")
            } else {
                sections[name] = .rows((dict["data"] as? [[String: Any]]) ?? [])
            }
        }
        let bloodLockedFallback: Bool
        if case .some(.locked) = sections["blood_panels"] { bloodLockedFallback = true } else { bloodLockedFallback = false }
        let s = (body["summary"] as? [String: Any]) ?? [:]
        let summary = Summary(
            readinessScore: intAny(s["readiness_score"]),
            sleepQualityScore: intAny(s["sleep_quality_score"]),
            sleepDurationSeconds: intAny(s["sleep_duration_seconds"]),
            biologicalAge: doubleAny(s["biological_age"]),
            bioageDeltaYears: doubleAny(s["bioage_delta_years"]),
            weightKg: doubleAny(s["weight_kg"]),
            workoutsLast7d: intAny(s["workouts_last_7d"]),
            mealsToday: intAny(s["meals_today"]),
            kcalToday: intAny(s["kcal_today"]),
            bloodLocked: (s["blood_locked"] as? Bool) ?? bloodLockedFallback)
        return JasperClientDashboard(
            fetchedAt: fetchedAt,
            generatedAt: jasperConnectDate(body["generated_at"]),
            summary: summary,
            sections: sections,
            digest: Digest.parse(body["digest"]))
    }

    // MARK: Accessors

    func rows(_ name: String) -> [[String: Any]] {
        if case .rows(let rows)? = sections[name] { return rows }
        return []
    }

    /// Rows sorted newest-first by a §8 time field.
    func rows(_ name: String, sortedBy timeField: String) -> [[String: Any]] {
        rows(name).sorted {
            (jasperConnectDate($0[timeField]) ?? .distantPast)
                > (jasperConnectDate($1[timeField]) ?? .distantPast)
        }
    }

    func lockedScope(_ name: String) -> String? {
        if case .locked(let scope)? = sections[name] {
            return scope.isEmpty ? "read scope" : scope
        }
        return nil
    }

    var lockedSectionNames: [String] {
        sections.compactMap { key, value in
            if case .locked = value { return key }
            return nil
        }.sorted()
    }

    /// The walkthrough + phase plumbing still speak `JasperLiveSnapshot` —
    /// synthesize one from the sections. `windowDays: 0` marks "one call"
    /// mode (each section carries its own window server-side).
    func legacySnapshot() -> JasperLiveSnapshot {
        let resources: [JasperResourceSnapshot] = JasperLiveSnapshot.probes.map { probe in
            let sectionRows = rows(probe.resource)
            let latest = sectionRows.compactMap { jasperConnectDate($0[probe.timeField]) }.max()
            return JasperResourceSnapshot(resource: probe.resource, title: probe.title,
                                          symbol: probe.symbol, count: sectionRows.count,
                                          latest: latest)
        }
        return JasperLiveSnapshot(fetchedAt: fetchedAt, windowDays: 0,
                                  resources: resources, failedResources: [])
    }

    // MARK: Lenient number parsing (§8 rows mix Int/Double/NSNumber)

    nonisolated static func intAny(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    nonisolated static func doubleAny(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }
}

// MARK: - Panel

/// The coach client dashboard, rendered from ONE `GET /v1/dashboard` call —
/// the exact payload Jasper's own in-app coach view consumes, so external
/// pixel parity is the contract, not an aspiration. Sections the token can't
/// read render as honest locked rows naming the scope to ask the client for;
/// blood gets the full locked card. Whisper's monochrome chrome outside,
/// Jasper's native looks (recovery ring, hypnogram) inside.
struct JasperClientDashboardPanel: View {
    let dashboard: JasperClientDashboard
    let clientUsername: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedNightID: String?

    private let jasperOrange = Color(red: 0.953, green: 0.565, blue: 0.341)
    private static let readyMint = Color(red: 0.361, green: 0.859, blue: 0.722)   // #5CDBB8
    private static let readyBlue = Color(red: 0.200, green: 0.580, blue: 0.878)   // #3394E0
    private static let readyRed  = Color(red: 0.949, green: 0.400, blue: 0.349)   // #F26659

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            profileLine
            summaryGrid
            digestBlock
            readinessBlock
            sleepBlock
            bloodBlock
            detailRows
            lockedFootnote
        }
    }

    // MARK: Profile / streak topline

    @ViewBuilder
    private var profileLine: some View {
        if let profile = dashboard.rows("profile").first {
            let streak = JasperClientDashboard.intAny(profile["current_streak"]) ?? 0
            let total = JasperClientDashboard.intAny(profile["total_workouts"]) ?? 0
            if streak > 0 || total > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(jasperOrange)
                    Text(profileSummary(streak: streak, total: total))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    Spacer()
                }
            }
        }
    }

    private func profileSummary(streak: Int, total: Int) -> String {
        var parts: [String] = []
        if streak > 0 { parts.append("\(streak)-day streak") }
        if total > 0 { parts.append("\(total) lifetime workouts") }
        return parts.joined(separator: " · ")
    }

    // MARK: Summary — the precomputed headline numbers

    @Environment(\.dynamicTypeSize) private var summaryTextSize

    private var summaryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: summaryTextSize.isAccessibilitySize ? 1 : 3), spacing: 8) {
            summaryTile("READINESS",
                        value: dashboard.summary.readinessScore.map(String.init) ?? "—",
                        tint: readinessColor(dashboard.summary.readinessScore))
            summaryTile("SLEEP",
                        value: dashboard.summary.sleepQualityScore.map(String.init) ?? "—",
                        sub: dashboard.summary.sleepDurationSeconds.map(hm))
            summaryTile("BIO AGE",
                        value: dashboard.summary.bioageDeltaYears.map { String(format: "%+.1fy", $0) } ?? "—",
                        tint: dashboard.summary.bioageDeltaYears.map { JasperVitalityPalette.accent(deltaYears: $0) },
                        sub: dashboard.summary.biologicalAge.map { String(format: "%.1f bio", $0) })
            summaryTile("WEIGHT",
                        value: dashboard.summary.weightKg.map { String(format: "%.1f", $0) } ?? "—",
                        sub: dashboard.summary.weightKg != nil ? "kg" : nil)
            summaryTile("WORKOUTS 7D",
                        value: dashboard.summary.workoutsLast7d.map(String.init) ?? "—")
            summaryTile("TODAY",
                        value: dashboard.summary.kcalToday.map { "\($0)" } ?? "—",
                        sub: summaryTodaySub)
        }
    }

    private var summaryTodaySub: String? {
        var parts: [String] = []
        if dashboard.summary.kcalToday != nil { parts.append("kcal") }
        if let meals = dashboard.summary.mealsToday { parts.append("\(meals) meals") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func summaryTile(_ title: String, value: String,
                             tint: Color? = nil, sub: String? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.callout.weight(.bold))
                .foregroundStyle(tint ?? WhisperTheme.ink(colorScheme))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(0.3)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let sub {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
    }

    // MARK: Weekly digest (?period=week — this week vs last, server-computed)

    @ViewBuilder
    private var digestBlock: some View {
        if let digest = dashboard.digest {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("THIS WEEK VS LAST")
                VStack(spacing: 4) {
                    digestRow("Readiness",
                              value: digest.readinessAvg.map { String(format: "%.0f avg", $0) },
                              delta: digest.readinessDelta.map { String(format: "%+.1f", $0) })
                    digestRow("Sleep",
                              value: sleepDigestValue(digest),
                              delta: digest.sleepQualityDelta.map { String(format: "%+.1f", $0) })
                    digestRow("Training",
                              value: trainingDigestValue(digest),
                              delta: digest.workoutsDelta.map { String(format: "%+d", $0) })
                    digestRow("Nutrition",
                              value: nutritionDigestValue(digest),
                              delta: digest.kcalDelta.map { String(format: "%+d kcal", $0) })
                    digestRow("Weight",
                              value: digest.weightKgLatest.map { String(format: "%.1f kg", $0) },
                              delta: digest.weightDeltaKg.map { String(format: "%+.1f kg", $0) })
                }
                if !digest.highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(digest.highlights.prefix(4).enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 6) {
                                Circle().fill(jasperOrange)
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 5)
                                Text(line)
                                    .font(.caption2)
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                Button {
                                    UIPasteboard.general.string = line
                                    Haptics.tap()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                        .frame(width: 22, height: 22)
                                        .background(WhisperTheme.card(colorScheme), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Copy highlight")
                            }
                        }
                        Text("Written to paste into a weekly check-in — Jasper computed these server-side.")
                            .font(.system(size: 8.5))
                            .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.8))
                    }
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
        }
    }

    private func sleepDigestValue(_ digest: JasperClientDashboard.Digest) -> String? {
        var parts: [String] = []
        if let q = digest.sleepQuality { parts.append(String(format: "%.0f quality", q)) }
        if let secs = digest.sleepDurationSeconds { parts.append(hm(secs)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func trainingDigestValue(_ digest: JasperClientDashboard.Digest) -> String? {
        var parts: [String] = []
        if let w = digest.workouts { parts.append("\(w) workouts") }
        if let vol = digest.volumeKg { parts.append("\(grouped(Int(vol))) kg") }
        if let prs = digest.prsThisWeek, prs > 0 { parts.append("\(prs) PR\(prs == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func nutritionDigestValue(_ digest: JasperClientDashboard.Digest) -> String? {
        var parts: [String] = []
        if let kcal = digest.kcalPerDay { parts.append("\(grouped(kcal)) kcal/day") }
        if let meals = digest.mealsLogged { parts.append("\(meals) meals") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func digestRow(_ title: String, value: String?, delta: String?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Spacer()
            Text(value ?? "—")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let delta {
                Text(delta)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(jasperOrange)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(jasperOrange.opacity(0.13), in: Capsule())
            }
        }
    }

    private func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: Readiness — ring + 14-day trend

    private struct TrendPoint: Identifiable {
        let id: String
        let score: Int
    }

    @ViewBuilder
    private var readinessBlock: some View {
        if let scope = dashboard.lockedScope("readiness") {
            lockedRow("Readiness", scope: scope)
        } else {
            let rows = dashboard.rows("readiness", sortedBy: "recorded_on")
            if let latest = rows.first,
               let score = JasperClientDashboard.intAny(latest["score"] ?? latest["readiness_score"]) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("READINESS · 14 DAYS")
                    HStack(spacing: 14) {
                        JasperRecoveryRing(score: score, size: 64)
                        trendBars(points: trendPoints(rows))
                    }
                }
                .padding(10)
                .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
            }
        }
    }

    private func trendPoints(_ rows: [[String: Any]]) -> [TrendPoint] {
        rows.prefix(14).reversed().enumerated().compactMap { index, row in
            guard let score = JasperClientDashboard.intAny(row["score"] ?? row["readiness_score"]) else { return nil }
            let id = (row["recorded_on"] as? String) ?? "day-\(index)"
            return TrendPoint(id: id, score: score)
        }
    }

    private func trendBars(points: [TrendPoint]) -> some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(points) { point in
                Capsule(style: .continuous)
                    .fill(readinessColor(point.score) ?? Self.readyBlue)
                    .frame(height: max(5, CGFloat(point.score) / 100 * 44))
                    .frame(maxWidth: .infinity)
                    .opacity(point.id == points.last?.id ? 1 : 0.55)
            }
        }
        .frame(height: 44, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Fourteen day readiness trend")
    }

    /// Score colors per Jasper's published readiness spec:
    /// ≥75 mint, ≥50 blue, else red.
    private func readinessColor(_ score: Int?) -> Color? {
        guard let score else { return nil }
        if score >= 75 { return Self.readyMint }
        if score >= 50 { return Self.readyBlue }
        return Self.readyRed
    }

    // MARK: Sleep — 14 tappable nights + hypnogram

    private struct Night: Identifiable {
        let id: String
        let date: Date?
        let trackable: Bool
        let row: [String: Any]
    }

    private var nights: [Night] {
        dashboard.rows("sleep", sortedBy: "started_at").prefix(14).enumerated().map { index, row in
            let started = jasperConnectDate(row["started_at"])
            let trackable = JasperClientDashboard.intAny(row["awake_seconds"]) != nil
                || JasperClientDashboard.intAny(row["rem_seconds"]) != nil
                || JasperClientDashboard.intAny(row["light_seconds"]) != nil
                || JasperClientDashboard.intAny(row["deep_seconds"]) != nil
                || JasperClientDashboard.intAny(row["quality_score"]) != nil
            let id = (row["started_at"] as? String) ?? "night-\(index)"
            return Night(id: id, date: started, trackable: trackable, row: row)
        }
    }

    private var selectedNight: Night? {
        let all = nights
        if let id = selectedNightID, let match = all.first(where: { $0.id == id }) { return match }
        return all.first   // newest
    }

    @ViewBuilder
    private var sleepBlock: some View {
        if let scope = dashboard.lockedScope("sleep") {
            lockedRow("Sleep", scope: scope)
        } else {
            let all = nights
            if !all.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel(all.count > 1 ? "SLEEP · TAP A NIGHT" : "SLEEP · LAST NIGHT")
                    if all.count > 1 { nightStrip(all) }
                    if let night = selectedNight {
                        // Picking another night genuinely switches nights —
                        // same fix Jasper shipped in its own sleep picker.
                        JasperHypnogram(
                            startedAt: jasperConnectDate(night.row["started_at"]),
                            endedAt: jasperConnectDate(night.row["ended_at"]),
                            awakeSeconds: JasperClientDashboard.intAny(night.row["awake_seconds"]),
                            remSeconds: JasperClientDashboard.intAny(night.row["rem_seconds"]),
                            coreSeconds: JasperClientDashboard.intAny(night.row["light_seconds"]),
                            deepSeconds: JasperClientDashboard.intAny(night.row["deep_seconds"]),
                            qualityScore: JasperClientDashboard.intAny(night.row["quality_score"]),
                            compact: true)
                            .id(night.id)
                    }
                }
                .padding(10)
                .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
            }
        }
    }

    private func nightStrip(_ all: [Night]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(all.reversed())) { night in   // oldest → newest
                    nightChip(night, selected: night.id == selectedNight?.id)
                }
            }
        }
        .defaultScrollAnchor(.trailing)
        // Locked in place — the strip only moves when there are genuinely
        // more nights than fit; no loose rubber-banding.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func nightChip(_ night: Night, selected: Bool) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(duration: 0.3)) { selectedNightID = night.id }
        } label: {
            VStack(spacing: 3) {
                Text(weekdayLetter(night.date))
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(selected ? WhisperTheme.surface(colorScheme) : WhisperTheme.muted(colorScheme))
                Text(dayNumber(night.date))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                Circle()
                    .fill(night.trackable
                          ? (selected ? WhisperTheme.surface(colorScheme) : jasperOrange)
                          : .clear)
                    .frame(width: 3, height: 3)
            }
            .frame(width: 30)
            .padding(.vertical, 6)
            .background(selected ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme),
                        in: .rect(cornerRadius: 9))
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sleep night \(dayNumber(night.date))")
    }

    private func weekdayLetter(_ date: Date?) -> String {
        guard let date else { return "·" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    private func dayNumber(_ date: Date?) -> String {
        guard let date else { return "—" }
        return String(Calendar.current.component(.day, from: date))
    }

    // MARK: Blood — PhenoAge + all nine markers, or the honest locked card

    private static let bloodMarkers: [(label: String, key: String, unit: String)] = [
        ("Albumin", "albumin_g_dl", "g/dL"),
        ("Creatinine", "creatinine_mg_dl", "mg/dL"),
        ("Glucose", "glucose_mg_dl", "mg/dL"),
        ("CRP", "crp_mg_l", "mg/L"),
        ("Lymph", "lymphocyte_pct", "%"),
        ("MCV", "mcv_fl", "fL"),
        ("RDW", "rdw_pct", "%"),
        ("ALP", "alp_u_l", "U/L"),
        ("WBC", "wbc_1000_ul", "10³/µL"),
    ]

    @ViewBuilder
    private var bloodBlock: some View {
        if dashboard.summary.bloodLocked || dashboard.lockedScope("blood_panels") != nil {
            bloodLockedCard
        } else {
            let panels = dashboard.rows("blood_panels", sortedBy: "drawn_on")
            if let latest = panels.first {
                bloodPanelCard(latest)
            }
        }
    }

    /// Blood never rides a coach token by default — this card tells the
    /// coach EXACTLY what to ask the client to grant.
    private var bloodLockedCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(jasperOrange)
                Text("Blood work · locked")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                Text(dashboard.lockedScope("blood_panels") ?? "read:blood")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(jasperOrange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(jasperOrange.opacity(colorScheme == .dark ? 0.16 : 0.1), in: .capsule)
            }
            Text("Blood never rides a coach token by default. Ask @\(clientUsername) to grant blood work explicitly on their Jasper consent screen — until then this section stays locked, and everything else keeps working.")
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(jasperOrange.opacity(0.25), lineWidth: 1)
        }
    }

    private func bloodPanelCard(_ panel: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("BLOOD PANEL" + (jasperConnectDate(panel["drawn_on"]).map { " · DRAWN \(relativeShort($0).uppercased())" } ?? ""))
            if let pheno = JasperClientDashboard.doubleAny(panel["pheno_age"]) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", pheno))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("PhenoAge")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    Spacer()
                    if let count = JasperClientDashboard.intAny(panel["marker_count"]) {
                        Text("\(count) markers")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Self.bloodMarkers, id: \.key) { marker in
                    if let value = JasperClientDashboard.doubleAny(panel[marker.key]) {
                        markerTile(marker.label, value: value, unit: marker.unit)
                    }
                }
            }
        }
        .padding(10)
        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
    }

    private func markerTile(_ label: String, value: Double, unit: String) -> some View {
        VStack(spacing: 1) {
            Text(trimmedNumber(value))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(label) · \(unit)")
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 8))
    }

    private func trimmedNumber(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: Detail rows — training, nutrition, goals, check-ins, programs

    private var detailRows: some View {
        VStack(spacing: 6) {
            trainingRow
            nutritionRow
            goalsRow
            photosRow
            programsRow
        }
    }

    @ViewBuilder
    private var trainingRow: some View {
        if let scope = dashboard.lockedScope("workouts") {
            lockedRow("Training", scope: scope)
        } else {
            let workouts = dashboard.rows("workouts", sortedBy: "performed_at")
            let prs = dashboard.rows("personal_records", sortedBy: "achieved_at")
            if !workouts.isEmpty || !prs.isEmpty {
                dashRow(icon: "figure.strengthtraining.traditional",
                        title: "TRAINING",
                        value: trainingValue(workouts),
                        sub: latestPR(prs))
            }
        }
    }

    private func trainingValue(_ workouts: [[String: Any]]) -> String {
        var parts = ["\(workouts.count) workouts"]
        if let latest = workouts.first, let date = jasperConnectDate(latest["performed_at"]) {
            parts.append("last \(relativeShort(date))")
        }
        return parts.joined(separator: " · ")
    }

    private func latestPR(_ prs: [[String: Any]]) -> String? {
        guard let pr = prs.first, let name = pr["exercise_name"] as? String else { return nil }
        var line = "PR: \(name)"
        if let kg = JasperClientDashboard.doubleAny(pr["weight_kg"]) {
            line += " \(trimmedNumber(kg)) kg"
        } else if let value = JasperClientDashboard.doubleAny(pr["value"]) {
            line += " \(trimmedNumber(value))"
        }
        if let date = jasperConnectDate(pr["achieved_at"]) { line += " · \(relativeShort(date))" }
        return line
    }

    @ViewBuilder
    private var nutritionRow: some View {
        if let scope = dashboard.lockedScope("meals") {
            lockedRow("Nutrition", scope: scope)
        } else {
            let meals = dashboard.rows("meals")
            let waterToday = todayWaterML
            if !meals.isEmpty || waterToday > 0 || (dashboard.summary.mealsToday ?? 0) > 0 {
                dashRow(icon: "fork.knife",
                        title: "NUTRITION",
                        value: nutritionValue(waterML: waterToday))
            }
        }
    }

    private var todayWaterML: Int {
        dashboard.rows("water").reduce(0) { total, row in
            guard let date = jasperConnectDate(row["logged_at"]),
                  Calendar.current.isDateInToday(date),
                  let ml = JasperClientDashboard.intAny(row["amount_ml"]) else { return total }
            return total + ml
        }
    }

    private func nutritionValue(waterML: Int) -> String {
        var parts: [String] = []
        if let meals = dashboard.summary.mealsToday { parts.append("\(meals) meals today") }
        if let kcal = dashboard.summary.kcalToday { parts.append("\(kcal) kcal") }
        if waterML > 0 { parts.append("\(waterML) ml water") }
        return parts.isEmpty ? "Nothing logged today" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var goalsRow: some View {
        if let scope = dashboard.lockedScope("goal_entries") {
            lockedRow("Goals", scope: scope)
        } else {
            let open = dashboard.rows("goal_entries").filter { !(($0["is_complete"] as? Bool) ?? false) }
            if !open.isEmpty {
                dashRow(icon: "target",
                        title: "GOALS",
                        value: "\(open.count) open",
                        sub: goalProgress(open.first))
            }
        }
    }

    private func goalProgress(_ goal: [String: Any]?) -> String? {
        guard let goal, let title = goal["title"] as? String else { return nil }
        var line = title
        if let current = JasperClientDashboard.doubleAny(goal["current_value"]),
           let target = JasperClientDashboard.doubleAny(goal["target_value"]), target > 0 {
            line += " · \(trimmedNumber(current))/\(trimmedNumber(target))"
            if let unit = goal["target_unit"] as? String, !unit.isEmpty { line += " \(unit)" }
        }
        return line
    }

    @ViewBuilder
    private var photosRow: some View {
        if let scope = dashboard.lockedScope("progress_photos") {
            lockedRow("Photo check-ins", scope: scope)
        } else {
            let photos = dashboard.rows("progress_photos", sortedBy: "recorded_on")
            if !photos.isEmpty {
                dashRow(icon: "camera.fill",
                        title: "PHOTO CHECK-INS",
                        value: photosValue(photos),
                        sub: "Metadata only — photo bytes stay in Jasper's private storage")
            }
        }
    }

    private func photosValue(_ photos: [[String: Any]]) -> String {
        var parts = ["\(photos.count) check-ins"]
        if let latest = photos.first, let date = jasperConnectDate(latest["recorded_on"]) {
            parts.append("latest \(relativeShort(date))")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var programsRow: some View {
        if let scope = dashboard.lockedScope("programs") {
            lockedRow("Programs", scope: scope)
        } else {
            let programs = dashboard.rows("programs")
            if !programs.isEmpty {
                dashRow(icon: "list.clipboard.fill",
                        title: "ACTIVE PROGRAMS",
                        value: programsValue(programs))
            }
        }
    }

    private func programsValue(_ programs: [[String: Any]]) -> String {
        var parts = ["\(programs.count)"]
        if let name = programs.first?["name"] as? String, !name.isEmpty { parts.append(name) }
        return parts.joined(separator: " · ")
    }

    // MARK: Shared row kit

    private func dashRow(icon: String, title: String, value: String, sub: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(jasperOrange)
                .frame(width: 26, height: 26)
                .background(jasperOrange.opacity(colorScheme == .dark ? 0.16 : 0.1), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let sub {
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
    }

    /// A section the client chose not to share — the scope name is the exact
    /// thing to ask for. Never an error state.
    private func lockedRow(_ title: String, scope: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .frame(width: 26, height: 26)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased() + " · NOT SHARED")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Text("Client's choice — ask @\(clientUsername) to grant \(scope)")
                    .font(.system(size: 10))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(WhisperTheme.surface(colorScheme).opacity(0.6), in: .rect(cornerRadius: 10))
    }

    /// Locked sections that don't have a dedicated block above (vitals,
    /// body, bioage…) — one honest footnote instead of silent absence.
    @ViewBuilder
    private var lockedFootnote: some View {
        let handled: Set<String> = ["blood_panels", "readiness", "sleep", "workouts",
                                    "meals", "goal_entries", "progress_photos", "programs"]
        let leftover = dashboard.lockedSectionNames.filter { !handled.contains($0) }
        if !leftover.isEmpty {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                Text("Also not shared (client's choice): " + leftover.map { name in
                    if let scope = dashboard.lockedScope(name) { return "\(name.replacingOccurrences(of: "_", with: " ")) (\(scope))" }
                    return name
                }.joined(separator: ", "))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 9))
            .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.85))
        }
    }

    // MARK: Formatting

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(WhisperTheme.muted(colorScheme))
    }

    private func hm(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func relativeShort(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Compact pulse card (Jasper Intelligence chat modal)

/// The live client dashboard Jasper Intelligence attaches in chat when a
/// coach asks about a client — the SAME one-call payload the coach dashboard
/// renders, presented as a scrollable card. Rides the 60s-cached coach rail,
/// so opening it never breaks the ≤1/min polling cap.
struct JasperClientPulseModalCard: View {
    let username: String?

    @Environment(\.colorScheme) private var colorScheme
    @State private var dashboard: JasperClientDashboard?
    @State private var failureReason: String?
    @State private var resolvedName: String = ""

    private let jasperOrange = Color(red: 0.953, green: 0.565, blue: 0.341)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let dash = dashboard {
                ScrollView(showsIndicators: false) {
                    JasperClientDashboardPanel(dashboard: dash, clientUsername: resolvedName)
                        .padding(.bottom, 4)
                }
            } else if let failureReason {
                Text(failureReason)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("One call — pulling the live dashboard…")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            }
            Button {
                Haptics.tap()
                WhisperEmberActionRouter.shared.dismissModal()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme))
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(dashboard != nil ? Color.green : jasperOrange)
                .frame(width: 6, height: 6)
            Text(resolvedName.isEmpty ? "Client dashboard" : "@\(resolvedName) — live")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(1)
            Spacer()
            Text("ONE CALL · /v1/dashboard")
                .font(.system(size: 7.5, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(jasperOrange)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(jasperOrange.opacity(0.12), in: Capsule())
        }
    }

    private func load() async {
        guard let client = WhisperEmberActionRouter.jasperClient(for: username) else {
            failureReason = "That's not an accepted coaching client — live dashboards open through an active coach grant. Check the name and try again."
            return
        }
        resolvedName = client.username
        if let dash = await JasperCoachConnect.shared.dashboard(forClient: client.uid) {
            dashboard = dash
        } else {
            let uid = client.uid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            failureReason = JasperCoachConnect.shared.lastErrors[uid]
                ?? "Couldn't reach Jasper right now — try again in a moment."
        }
    }
}
