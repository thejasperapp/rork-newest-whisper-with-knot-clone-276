import SwiftUI

// MARK: - Own one-call dashboard (cached)

/// The user's OWN one-call dashboard (`GET /v1/dashboard` on their own
/// token), cached 60s — powers Jasper Intelligence's native data cards so
/// in-chat cards quote the exact payload every other surface renders.
enum WhisperEmberOwnDashboard {
    private static var cached: JasperClientDashboard?

    static func fetch(force: Bool = false) async -> JasperClientDashboard? {
        if !force, let cached, Date().timeIntervalSince(cached.fetchedAt) < 60 {
            return cached
        }
        guard JasperConnectClient.shared.connection != nil else { return nil }
        guard let data = try? await JasperConnectClient.shared.ownDashboard(),
              let dash = JasperClientDashboard.parse(data) else { return nil }
        cached = dash
        return dash
    }
}

/// Resolves a `client` username from a ```jasper fence to an accepted
/// coaching client (coach-side cards ride the coach token).
private func jasperLookClient(_ username: String?) -> (id: String, username: String)? {
    guard let username, !username.isEmpty else { return nil }
    let needle = username.lowercased()
        .trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
    guard let row = WhisperCoachRequestService.shared.myClients.first(where: {
        $0.client_username.lowercased() == needle
    }) else { return nil }
    return (row.client_user_id, row.client_username)
}

// MARK: - Router

/// Renders the ```jasper fenced block — Jasper Intelligence's NATIVE data
/// cards: live API-backed looks (bio age, readiness, sleep, water, blood)
/// drawn in Jasper's own render language inside the ember glow box.
struct WhisperEmberJasperLookCard: View {
    let request: WhisperEmberBlocks.JasperLook

    var body: some View {
        switch request.normalizedKind {
        case "bioage", "bio_age", "vitality", "biological_age":
            WhisperEmberBioAgeLookCard(client: request.client)
        case "readiness", "recovery", "stress", "strain":
            WhisperEmberReadinessLookCard(client: request.client)
        case "sleep":
            WhisperEmberSleepLookCard(client: request.client)
        case "water", "hydration":
            WhisperEmberWaterLookCard()
        case "blood", "bloodwork", "blood_panels", "labs":
            WhisperEmberBloodLookCard(client: request.client)
        default:
            WhisperEmberLookShell(icon: "sparkles", kicker: "JASPER DATA", clientName: nil, loading: false) {
                Text("No native card for \"\(request.kind)\" yet — ask me for the numbers instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared shell (ember glow box + kicker header)

/// WHISPER_PLANS §2 glow box with a glow-icon header — the shell every
/// native data card wears. The aura breathes while the live read is
/// in flight (never a bare spinner).
struct WhisperEmberLookShell<Content: View>: View {
    let icon: String
    let kicker: String
    let clientName: String?
    let loading: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        JasperGlowBox(cornerRadius: 20, glow: 0.5, breathing: loading) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    EmberGlowIcon(systemName: icon, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kicker)
                            .font(.caption.bold())
                            .tracking(0.7)
                            .foregroundStyle(colorScheme == .dark ? JasperBrand.ember : JasperBrand.emberDeep)
                        Text(clientName.map { "@\($0) · live from their Jasper" } ?? "Live from your Jasper")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                content()
            }
            .padding(14)
        }
        .padding(.vertical, 2)
    }
}

/// Honest single-line states (not connected / not shared / nothing synced).
private func lookNote(_ text: String) -> some View {
    Text(text)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
}

private let lookConnectHint = "Jasper isn't connected — Settings → Sync with Jasper (one tap) turns this card live."

// MARK: - Readiness (recovery ring + 14-day trend)

struct WhisperEmberReadinessLookCard: View {
    let client: String?

    @State private var dash: JasperClientDashboard?
    @State private var loading = true

    private var resolvedClient: (id: String, username: String)? { jasperLookClient(client) }

    var body: some View {
        WhisperEmberLookShell(icon: "gauge.with.needle", kicker: "READINESS",
                              clientName: resolvedClient?.username, loading: loading) {
            if loading {
                lookNote("Reading readiness live…")
            } else if let dash {
                readinessBody(dash)
            } else {
                lookNote(resolvedClient == nil ? lookConnectHint : "Couldn't reach this client's Jasper right now.")
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func readinessBody(_ dash: JasperClientDashboard) -> some View {
        if let scope = dash.lockedScope("readiness") {
            lookNote("Readiness isn't shared on this token (needs \(scope)) — their choice, never guessed.")
        } else {
            let rows = dash.rows("readiness", sortedBy: "recorded_on")
            if let latest = rows.first,
               let score = JasperClientDashboard.intAny(latest["score"] ?? latest["readiness_score"]) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        JasperRecoveryRing(score: score, size: 84)
                        VStack(alignment: .leading, spacing: 8) {
                            trendBars(rows)
                            Text("14-day trend · newest right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    JasperReadinessBars(
                        sleep: JasperClientDashboard.intAny(latest["sleep_score"]),
                        recovery: JasperClientDashboard.intAny(latest["recovery_score"]),
                        strain: JasperClientDashboard.intAny(latest["strain_score"]))
                }
            } else {
                lookNote("No readiness synced yet — it lands here the moment Jasper scores a day.")
            }
        }
    }

    private func trendBars(_ rows: [[String: Any]]) -> some View {
        let points: [(String, Int)] = rows.prefix(14).reversed().enumerated().compactMap { index, row in
            guard let score = JasperClientDashboard.intAny(row["score"] ?? row["readiness_score"]) else { return nil }
            return ((row["recorded_on"] as? String) ?? "d\(index)", score)
        }
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                Capsule(style: .continuous)
                    .fill(JasperRecoveryRing.scoreColor(point.1))
                    .frame(height: max(5, CGFloat(point.1) / 100 * 42))
                    .frame(maxWidth: .infinity)
                    .opacity(index == points.count - 1 ? 1 : 0.55)
            }
        }
        .frame(height: 42, alignment: .bottom)
    }

    private func load() async {
        if let resolved = resolvedClient {
            dash = await JasperCoachConnect.shared.dashboard(forClient: resolved.id)
        } else {
            dash = await WhisperEmberOwnDashboard.fetch()
        }
        withAnimation(.spring(duration: 0.35)) { loading = false }
    }
}

// MARK: - Sleep (stage hypnogram)

struct WhisperEmberSleepLookCard: View {
    let client: String?

    @State private var dash: JasperClientDashboard?
    @State private var loading = true

    private var resolvedClient: (id: String, username: String)? { jasperLookClient(client) }

    var body: some View {
        WhisperEmberLookShell(icon: "moon.zzz.fill", kicker: "SLEEP",
                              clientName: resolvedClient?.username, loading: loading) {
            if loading {
                lookNote("Reading last night live…")
            } else if let dash {
                sleepBody(dash)
            } else {
                lookNote(resolvedClient == nil ? lookConnectHint : "Couldn't reach this client's Jasper right now.")
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func sleepBody(_ dash: JasperClientDashboard) -> some View {
        if let scope = dash.lockedScope("sleep") {
            lookNote("Sleep isn't shared on this token (needs \(scope)).")
        } else if let night = dash.rows("sleep", sortedBy: "started_at").first {
            JasperHypnogram(
                startedAt: jasperConnectDate(night["started_at"]),
                endedAt: jasperConnectDate(night["ended_at"]),
                awakeSeconds: JasperClientDashboard.intAny(night["awake_seconds"]),
                remSeconds: JasperClientDashboard.intAny(night["rem_seconds"]),
                coreSeconds: JasperClientDashboard.intAny(night["light_seconds"]),
                deepSeconds: JasperClientDashboard.intAny(night["deep_seconds"]),
                qualityScore: JasperClientDashboard.intAny(night["quality_score"]))
        } else {
            lookNote("No sleep sessions synced yet.")
        }
    }

    private func load() async {
        if let resolved = resolvedClient {
            dash = await JasperCoachConnect.shared.dashboard(forClient: resolved.id)
        } else {
            dash = await WhisperEmberOwnDashboard.fetch()
        }
        withAnimation(.spring(duration: 0.35)) { loading = false }
    }
}

// MARK: - Bio age (vitality card)

struct WhisperEmberBioAgeLookCard: View {
    let client: String?

    @State private var row: WhisperBioAgeRow?
    @State private var loading = true

    private var resolvedClient: (id: String, username: String)? { jasperLookClient(client) }

    var body: some View {
        WhisperEmberLookShell(icon: "hourglass", kicker: "BIOLOGICAL AGE",
                              clientName: resolvedClient?.username, loading: loading) {
            if loading {
                lookNote("Reading the vitality score live…")
            } else if let row {
                WhisperBioAgeCardView(row: row, compact: true)
            } else {
                lookNote(resolvedClient == nil
                         ? "No biological age synced yet — it appears once the partner Jasper app computes one."
                         : "No biological age synced for this client yet.")
            }
        }
        .task { await load() }
    }

    private func load() async {
        if let resolved = resolvedClient {
            row = await WhisperBioAgeService.shared.fetch(forUser: resolved.id)
        } else if let cached = WhisperBioAgeService.shared.mine {
            row = cached
        } else {
            row = await WhisperBioAgeService.shared.fetchMine()
        }
        withAnimation(.spring(duration: 0.35)) { loading = false }
    }
}

// MARK: - Water (live tap-to-log cup)

struct WhisperEmberWaterLookCard: View {
    private struct CupRow: Identifiable {
        let id: String
        let ml: Int
        let deletable: Bool
    }

    @State private var rows: [CupRow] = []
    @State private var loading = true
    @State private var connected = true
    @State private var busy = false

    private let cupML = 250
    private let goal = 8

    var body: some View {
        WhisperEmberLookShell(icon: "drop.fill", kicker: "WATER", clientName: nil, loading: loading) {
            if loading {
                lookNote("Reading today's cups live…")
            } else if !connected {
                lookNote(lookConnectHint)
            } else {
                JasperWaterCard(
                    cups: rows.count,
                    goal: goal,
                    totalML: rows.reduce(0) { $0 + $1.ml },
                    caption: "Tap the glass to log a 250 ml cup — it lands in Jasper instantly.",
                    onAdd: { Task { await add() } },
                    onRemove: { Task { await remove() } },
                    glassWidth: 74,
                    glassHeight: 102)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard JasperConnectClient.shared.connection != nil else {
            connected = false
            withAnimation(.spring(duration: 0.35)) { loading = false }
            return
        }
        let since = Calendar.current.startOfDay(for: Date())
        if let data = try? await JasperConnectClient.shared.read("water", since: since, limit: 200) {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let raw = (body?["data"] as? [[String: Any]]) ?? []
            rows = raw.compactMap { row in
                let ml = JasperClientDashboard.intAny(row["amount_ml"]) ?? 0
                guard ml > 0 else { return nil }
                let id = (row["id"] as? String) ?? (row["id"] as? NSNumber).map { "\($0)" }
                return CupRow(id: id ?? UUID().uuidString, ml: ml, deletable: id != nil)
            }
        }
        withAnimation(.spring(duration: 0.35)) { loading = false }
    }

    private func add() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if let receipt = try? await JasperConnectClient.shared.post("water", [
            "amount_ml": cupML,
            "logged_at": ISO8601DateFormatter().string(from: Date()),
        ]) {
            let id = receipt.id?.uuidString ?? receipt.clientID ?? UUID().uuidString
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                rows.append(CupRow(id: id, ml: cupML, deletable: receipt.id != nil || receipt.clientID != nil))
            }
            Haptics.success()
        } else {
            Haptics.warning()
        }
    }

    private func remove() async {
        guard !busy, let last = rows.last(where: \.deletable) else { return }
        busy = true
        defer { busy = false }
        if (try? await JasperConnectClient.shared.deleteRow(resource: "water", id: last.id)) != nil {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                rows.removeAll { $0.id == last.id }
            }
            Haptics.tap()
        } else {
            Haptics.warning()
        }
    }
}

// MARK: - Blood (PhenoAge + nine markers)

struct WhisperEmberBloodLookCard: View {
    let client: String?

    @State private var dash: JasperClientDashboard?
    @State private var loading = true

    private var resolvedClient: (id: String, username: String)? { jasperLookClient(client) }

    private static let markers: [(label: String, key: String, unit: String)] = [
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

    var body: some View {
        WhisperEmberLookShell(icon: "testtube.2", kicker: "BLOOD WORK",
                              clientName: resolvedClient?.username, loading: loading) {
            if loading {
                lookNote("Reading the latest panel live…")
            } else if let dash {
                bloodBody(dash)
            } else {
                lookNote(resolvedClient == nil ? lookConnectHint : "Couldn't reach this client's Jasper right now.")
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func bloodBody(_ dash: JasperClientDashboard) -> some View {
        if resolvedClient != nil && (dash.summary.bloodLocked || dash.lockedScope("blood_panels") != nil) {
            lookNote("Blood never rides a coach token unless the client grants read:blood explicitly — ask them to share it from Jasper's Coach access.")
        } else if dash.lockedScope("blood_panels") != nil {
            lookNote("Blood panels aren't shared on this token — grant read:blood from Jasper to see them here.")
        } else if let latest = dash.rows("blood_panels", sortedBy: "drawn_on").first {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let pheno = JasperClientDashboard.doubleAny(latest["pheno_age_years"]) {
                        Text(String(format: "PhenoAge %.1f", pheno))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    Spacer(minLength: 0)
                    if let drawn = jasperConnectDate(latest["drawn_on"]) {
                        Text("Drawn \(drawn.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                let present = Self.markers.filter { JasperClientDashboard.doubleAny(latest[$0.key]) != nil }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                    ForEach(present, id: \.key) { marker in
                        VStack(spacing: 2) {
                            Text(marker.label.uppercased())
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(0.5)
                                .foregroundStyle(.secondary)
                            Text(markerValue(latest[marker.key]) + " " + marker.unit)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 9))
                    }
                }
                if present.isEmpty {
                    lookNote("Panel synced, but no marker values decoded.")
                }
            }
        } else {
            lookNote("No blood panels synced yet — they appear the moment one lands in Jasper.")
        }
    }

    private func markerValue(_ any: Any?) -> String {
        guard let value = JasperClientDashboard.doubleAny(any) else { return "—" }
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }

    private func load() async {
        if let resolved = resolvedClient {
            dash = await JasperCoachConnect.shared.dashboard(forClient: resolved.id)
        } else {
            dash = await WhisperEmberOwnDashboard.fetch()
        }
        withAnimation(.spring(duration: 0.35)) { loading = false }
    }
}
