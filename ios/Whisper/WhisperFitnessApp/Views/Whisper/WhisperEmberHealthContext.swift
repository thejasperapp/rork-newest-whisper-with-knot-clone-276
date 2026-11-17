import Foundation

/// Composes the `healthContext` block Whisper hands to the shared Jasper
/// brain (`/ember/chat`). The server owns the reasoning; the CALLER owns the
/// context. Whisper has no HealthKit, but every value Jasper needs is already
/// mirrored into the shared `jasper_*` bridge tables — we resolve the real
/// Whisper id via `jasper_uid_for()` and read them, then format into the SAME
/// labelled blocks Whisper uses. The exact labels matter: the brain's
/// reasoning/format layers key off them.
///
/// A block is OMITTED when we genuinely have no data for it — we never
/// fabricate values to fill a section.
nonisolated struct WhisperEmberHealthContext: Sendable {

    /// A windowed numeric series Whisper can also hand to `/interpret` for
    /// real stats. Kept alongside the formatted text so the chat layer can
    /// optionally run the analysis path without re-reading the tables.
    nonisolated struct Series: Sendable {
        var days: [String] = []
        var steps: [Double] = []
        var hrv: [Double] = []
        var sleepHours: [Double] = []
        var activeEnergy: [Double] = []
        var bodyWeight: [Double] = []

        /// Maps to the `/interpret` `dataset.series` shape. The engine's
        /// fallback correlation/trend scan keys off camelCase metric names,
        /// so we use those (not snake_case). Series must be most-recent-first
        /// and the same length — the caller hands them in reversed to that
        /// order. Only non-empty metrics are included so the analysis engine
        /// doesn't choke on gaps, and all-zero series are dropped (the server
        /// ignores them anyway).
        var interpretSeries: [String: [Double]] {
            var out: [String: [Double]] = [:]
            func put(_ name: String, _ values: [Double]) {
                guard !values.isEmpty, values.contains(where: { $0 != 0 }) else { return }
                out[name] = Array(values.reversed())
            }
            put("steps", steps)
            put("hrv", hrv)
            put("sleepHours", sleepHours)
            put("activeEnergy", activeEnergy)
            put("bodyMass", bodyWeight)
            return out
        }

        /// Day labels most-recent-first, aligned to `interpretSeries`.
        var interpretDays: [String] { Array(days.reversed()) }

        var isEmpty: Bool { interpretSeries.isEmpty }
    }

    /// The formatted, labelled `healthContext` string for `/ember/chat`.
    let text: String
    /// The parallel numeric series (oldest → newest) for `/interpret`.
    let series: Series
    /// True when the user has a usable Whisper data picture. When false the
    /// chat still works (Jasper answers generically) — the context just omits
    /// the data blocks rather than inventing numbers.
    let hasWhisperData: Bool

    // MARK: - Build

    /// Builds the context for the signed-in Whisper user. Resolves the linked
    /// Whisper id (or the caller's own uid if unlinked) and reads the bridge
    /// tables through it. Safe to call when unlinked — returns a minimal
    /// context (device time + whatever profile we have).
    @MainActor
    static func build(memory: [String] = []) async -> WhisperEmberHealthContext {
        var blocks: [String] = []
        blocks.append(deviceTimeBlock())

        // Resolve the real Whisper id. Never assume auth.uid() IS the Whisper
        // user — read-through identity goes through jasper_uid_for().
        let jasperUID = await WhisperWhisperLinkService.shared.resolvedWhisperUID()
        var seriesOut = Series()
        var hasData = false

        if let jasperUID, !jasperUID.isEmpty {
            let data = await WhisperWhisperDataService.shared.fetchAll(forClient: jasperUID)
            hasData = !data.isCompletelyEmpty

            if let vitals = liveVitalsBlock(data) { blocks.append(vitals) }
            let (dailyBlock, series) = dailySeriesBlock(data)
            seriesOut = series
            if let dailyBlock { blocks.append(dailyBlock) }
            let myName = WhisperUserService.shared.me.flatMap {
                ($0.display_name?.isEmpty == false ? $0.display_name : $0.username)
            }
            if let profile = profileBlock(data, name: myName) { blocks.append(profile) }
        }

        // Account-style tailoring — mirrors the web's role-aware Jasper brain.
        // Tells the brain what kind of account this is so replies match the
        // user's toolkit (coach practice help, athlete recruiting, creator
        // growth, recruiter scouting, and so on).
        if let account = accountRoleBlock() { blocks.append(account) }

        if let mem = memoryBlock(memory) { blocks.append(mem) }

        // Full app awareness: the live account state, the complete Whisper
        // feature map (with linkable route ids), and the action grammar that
        // lets Jasper open screens, place calls, draft messages, schedule
        // meetings, and build client plans through real app services.
        blocks.append(WhisperEmberAtlas.awarenessBlock())

        return WhisperEmberHealthContext(
            text: blocks.joined(separator: "\n\n"),
            series: seriesOut,
            hasWhisperData: hasData
        )
    }

    /// Describes the signed-in user's Whisper roles so Jasper tailors its
    /// coaching, tools, and suggestions to the account type — same behavior
    /// as the web client's role-aware brain.
    @MainActor
    private static func accountRoleBlock() -> String? {
        var roles: [String] = []
        if WhisperCoachService.shared.isMeCoach {
            roles.append("VERIFIED COACH — act as their practice co-pilot: client acquisition through content, program announcements, check-in cadence with clients, testimonials, and pricing confidence.")
        }
        if WhisperAthleteService.shared.isMeAthlete {
            roles.append("VERIFIED ATHLETE — help with training consistency, recruiting visibility, stat-sheet storytelling, and highlight-worthy posts.")
        }
        if WhisperRecruiterService.shared.isMeRecruiter {
            roles.append("RECRUITER — help with scouting workflows, evaluating athlete profiles, outreach messages, and meeting scheduling.")
        }
        if WhisperDirectorService.shared.isMeDirector {
            roles.append("WHISPER STUDIO DIRECTOR — help with film projects, article drafts, premieres, and media-team coordination.")
        }
        guard !roles.isEmpty else { return nil }
        return "ACCOUNT TYPE\nThis user's Whisper roles (tailor every reply to these):\n" +
            roles.map { "- \($0)" }.joined(separator: "\n")
    }

    // MARK: - Blocks

    /// Ground truth for "today/tonight" — device now, weekday, timezone.
    private static func deviceTimeBlock() -> String {
        let now = Date()
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "EEEE, MMM d, yyyy 'at' h:mm a"
        let tz = TimeZone.current
        let tzName = tz.localizedName(for: .standard, locale: .current) ?? tz.identifier
        return """
        CURRENT DEVICE TIME
        \(df.string(from: now)) (\(tz.abbreviation() ?? tz.identifier) · \(tzName))
        """
    }

    /// Latest readiness, resting HR, HRV, sleep, steps.
    private static func liveVitalsBlock(_ data: WhisperWhisperClientData) -> String? {
        var lines: [String] = []
        if let r = data.latestReadiness?.score {
            lines.append("Readiness: \(Int(r.rounded()))/100")
        }
        if let hr = data.heartRateDaily.first {
            if let resting = hr.resting_bpm {
                lines.append("Resting HR: \(Int(resting.rounded())) bpm")
            }
            if let hrv = hr.hrv_ms {
                lines.append("HRV: \(Int(hrv.rounded())) ms")
            }
        }
        if let sleep = data.sleep.first, let secs = sleep.duration_seconds, secs > 0 {
            let hours = Double(secs) / 3600.0
            lines.append(String(format: "Last sleep: %.1f hr", hours))
        }
        if let steps = data.stepsDaily.first?.steps {
            lines.append("Steps today: \(steps)")
        }
        guard !lines.isEmpty else { return nil }
        return "LIVE VITALS\n" + lines.joined(separator: "\n")
    }

    /// Windowed day-by-day arrays for trend reasoning. Returns both the
    /// formatted text block and the numeric `Series` (oldest → newest).
    private static func dailySeriesBlock(_ data: WhisperWhisperClientData) -> (String?, Series) {
        var series = Series()

        // jasper_*_daily rows come back newest-first; reverse to oldest→newest
        // so trends read left-to-right like a timeline.
        let steps = Array(data.stepsDaily.prefix(14)).reversed()
        let hr = Array(data.heartRateDaily.prefix(14)).reversed()
        let sleep = Array(data.sleep.prefix(14)).reversed()
        let energy = Array(data.activeEnergyDaily.prefix(14)).reversed()
        let body = Array(data.bodyMetrics.prefix(14)).reversed()

        series.steps = steps.compactMap { $0.steps.map(Double.init) }
        series.hrv = hr.compactMap { $0.hrv_ms }
        series.sleepHours = sleep.compactMap { row in
            row.duration_seconds.map { Double($0) / 3600.0 }
        }
        series.activeEnergy = energy.compactMap { $0.active_energy_kcal }
        series.bodyWeight = body.compactMap { $0.weight_kg }

        // Day labels from steps (most complete daily table); fall back to HR.
        series.days = steps.map { Self.shortDay($0.recorded_on) }
        if series.days.isEmpty { series.days = hr.map { Self.shortDay($0.recorded_on) } }

        var lines: [String] = []
        func line(_ label: String, _ values: [Double], _ fmt: (Double) -> String) {
            guard !values.isEmpty else { return }
            lines.append("\(label): [\(values.map(fmt).joined(separator: ", "))]")
        }
        if !series.days.isEmpty {
            lines.append("days: [\(series.days.joined(separator: ", "))]")
        }
        line("steps", series.steps) { String(Int($0.rounded())) }
        line("hrv_ms", series.hrv) { String(Int($0.rounded())) }
        line("sleep_hrs", series.sleepHours) { String(format: "%.1f", $0) }
        line("active_energy_kcal", series.activeEnergy) { String(Int($0.rounded())) }
        line("body_weight_kg", series.bodyWeight) { String(format: "%.1f", $0) }

        guard !lines.isEmpty else { return (nil, series) }
        return ("DAILY SERIES\n" + lines.joined(separator: "\n"), series)
    }

    /// Goal + units + macro target context from preferences / goals.
    private static func profileBlock(_ data: WhisperWhisperClientData, name: String?) -> String? {
        var lines: [String] = []
        if let name, !name.isEmpty {
            lines.append("Name: \(name)")
        }
        let survey = data.preferences?.payload_json?.macro_survey
        if let goal = survey?.goal, !goal.isEmpty {
            lines.append("Goal: \(goal)")
        } else if let goalRow = data.goals.first?.kind, !goalRow.isEmpty {
            lines.append("Goal: \(goalRow)")
        }
        if let unit = data.preferences?.weight_unit, !unit.isEmpty {
            lines.append("Units: \(unit)")
        }
        let goals = data.preferences?.payload_json?.nutrition_goals
            ?? data.userDataNutritionGoals
        if let cal = goals?.calories, cal > 0 {
            var macro = "Nutrition target: \(Int(cal)) cal"
            if let p = goals?.protein_g, p > 0 { macro += ", P \(Int(p))g" }
            if let c = goals?.carbs_g, c > 0 { macro += ", C \(Int(c))g" }
            if let f = goals?.fat_g, f > 0 { macro += ", F \(Int(f))g" }
            lines.append(macro)
        }
        if let weightLb = survey?.weightLb, weightLb > 0 {
            lines.append(String(format: "Body weight: %.0f lb", weightLb))
        }
        guard !lines.isEmpty else { return nil }
        return "PROFILE\n" + lines.joined(separator: "\n")
    }

    /// Whisper's own lightweight memory store (facts the user wants Jasper to
    /// remember). Omitted when empty.
    private static func memoryBlock(_ memory: [String]) -> String? {
        let facts = memory.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !facts.isEmpty else { return nil }
        return "JASPER'S MEMORY\n" + facts.prefix(20).map { "- \($0)" }.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// "2026-06-10" (or ISO datetime) → "6/10". Falls back to the raw string.
    private static func shortDay(_ raw: String) -> String {
        let datePart = String(raw.prefix(10))
        let comps = datePart.split(separator: "-")
        guard comps.count == 3,
              let m = Int(comps[1]), let d = Int(comps[2]) else { return datePart }
        return "\(m)/\(d)"
    }
}
