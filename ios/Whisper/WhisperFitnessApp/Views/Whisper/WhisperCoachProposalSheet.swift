import SwiftUI
import Supabase

/// Sheet a coach uses to propose macro changes (or any other patch) to a
/// client's active diet plan. On submit we insert a row in
/// `whisper_coach_proposals` and open a `jasper://coach-proposal/<id>` deep
/// link so the client can review/accept inside Whisper.
struct WhisperCoachProposalSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let client: WhisperCoachRequestRow
    let kind: ProposalKind
    /// Existing diet plan (when editing macros / diet_plan) — used to
    /// prefill fields. Optional for other kinds.
    let activePlan: WhisperDietPlanRow?
    /// Lets the parent stash the freshly created proposal so its badge
    /// updates without another network round-trip.
    var onSubmitted: ((WhisperCoachProposalRow) -> Void)? = nil

    @State private var service = WhisperCoachProposalService()

    // Macros / diet plan fields. Calories are derived from P/C/F
    // (4·protein + 4·carbs + 9·fat) so coaches only enter macros.
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    /// Water target (8 oz cups). Only sent when the coach explicitly types
    /// a value — the Whisper contract treats `water_cups` as optional.
    @State private var waterCups: String = ""
    @State private var note: String = ""

    // Note fields (Nov-2026 program-style embed)
    @State private var noteTitle: String = ""
    @State private var noteText: String = ""

    @State private var submitting: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        switch kind {
                        case .macros, .dietPlan:
                            macrosForm
                        case .note:
                            noteForm
                        }
                        if let err = service.lastError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        submitButton
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: kind.icon)
                .font(.title2)
                .foregroundStyle(WhisperTheme.coachAccent)
                .frame(width: 44, height: 44)
                .background(WhisperTheme.coachAccent.opacity(0.15), in: Circle())
            Text("Suggest to @\(client.client_username)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("They'll see a diff in Whisper and can accept, modify or decline.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 32)
        }
        .padding(.top, 4)
    }

    // MARK: - Forms

    private var macrosForm: some View {
        VStack(spacing: 12) {
            macroField("Protein", value: $protein, suffix: "g", keyboard: .decimalPad)
            macroField("Carbs", value: $carbs, suffix: "g", keyboard: .decimalPad)
            macroField("Fat", value: $fat, suffix: "g", keyboard: .decimalPad)
            if kind == .macros {
                macroField("Water", value: $waterCups, suffix: "cups", keyboard: .numberPad)
            }
            caloriesPreview
            noteField
        }
        .padding(.horizontal, 16)
    }

    private var derivedCalories: Int? {
        let p = Double(protein) ?? 0
        let c = Double(carbs) ?? 0
        let f = Double(fat) ?? 0
        let total = p * 4 + c * 4 + f * 9
        guard total > 0 else { return nil }
        return Int(total.rounded())
    }

    private var caloriesPreview: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calories")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Auto from 4·P + 4·C + 9·F")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Text(derivedCalories.map { "\($0)" } ?? "—")
                .font(.title3.weight(.heavy))
                .foregroundStyle(WhisperTheme.coachAccent)
            Text("kcal")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(12)
        .background(WhisperTheme.coachAccent.opacity(0.08), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(WhisperTheme.coachAccent.opacity(0.25), lineWidth: 1)
        }
    }

    private var noteForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeledField("Title (optional)", placeholder: "e.g. Form check", text: $noteTitle)
            VStack(alignment: .leading, spacing: 6) {
                Text("Message")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                TextEditor(text: $noteText)
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
            }
        }
        .padding(.horizontal, 16)
    }

    private func labeledField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField(placeholder, text: text)
                .padding(12)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
        }
    }

    private func macroField(_ label: String, value: Binding<String>, suffix: String, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .frame(width: 80, alignment: .leading)
            TextField("0", text: value)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.weight(.bold))
            Text(suffix)
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .frame(width: 36, alignment: .leading)
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Note for your client (optional)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("e.g. bumping protein for your cut phase", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .padding(10)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
        }
        .padding(.top, 4)
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if submitting { ProgressView().tint(.white) }
                Text(submitting ? "Sending…" : "Send suggestion")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canSubmit ? WhisperTheme.coachAccent : WhisperTheme.muted(colorScheme), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || submitting)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var canSubmit: Bool {
        switch kind {
        case .macros, .dietPlan:
            return [protein, carbs, fat].contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        case .note:
            return !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func prefill() {
        guard let plan = activePlan else { return }
        if let p = plan.target_protein_g  { protein  = formatGrams(p) }
        if let c = plan.target_carbs_g    { carbs    = formatGrams(c) }
        if let f = plan.target_fat_g      { fat      = formatGrams(f) }
    }

    private func formatGrams(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(value))" }
        return String(format: "%.1f", value)
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }

        var patch: [String: JSONValue] = [:]
        switch kind {
        case .macros, .dietPlan:
            // Whisper contract: `calories`, `protein_g`, `carbs_g`, `fat_g`.
            // Calories are derived from the macros (P·4 + C·4 + F·9) so the
            // coach only enters what they decide.
            let p = Double(protein) ?? 0
            let c = Double(carbs)   ?? 0
            let f = Double(fat)     ?? 0
            if p > 0 { patch["protein_g"] = .number(p) }
            if c > 0 { patch["carbs_g"]   = .number(c) }
            if f > 0 { patch["fat_g"]     = .number(f) }
            let kcal = (p * 4) + (c * 4) + (f * 9)
            if kcal > 0 { patch["calories"] = .number(kcal.rounded()) }
        case .note:
            let title = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
            patch["text"] = .string(text)
            if !title.isEmpty { patch["title"] = .string(title) }
        }

        // V2 flow per Whisper integration contract: macros / diet_plan /
        // exercise_swap / note skip the `whisper_coach_proposals` table
        // entirely and ship the full payload inside the chat embed. Whisper
        // applies accept/decline purely client-side.
        //
        // Workout proposals still use the legacy v1 table flow until that
        // kind is migrated too — Whisper still reads v1 for back-compat.
        // Program-style flow (Whisper integration contract, Nov 2026):
        // macros + diet_plan ship the FULL Whisper-native object inside the
        // chat embed under `kind: "macros"` / `kind: "diet_plan"`. No patch
        // wrapper, no proposal_id, no whisper_coach_proposals row. Whisper
        // accepts/declines purely client-side from the embed.
        let summary = Self.summary(for: kind.rawValue, patch: patch, freeText: "")
        await sendProgramStyleEmbed(kind: kind, patch: patch, summary: summary)
        Haptics.success()
        dismiss()
    }

    /// Program-style embed for macros / diet_plan. Mirrors how `kind:
    /// "program"` already works: full Whisper-native object inside
    /// `embed.payload`, no patch wrapper, no proposal_id, no
    /// `whisper_coach_proposals` row. Field names match Whisper's
    /// `NutritionGoals` / `WeeklyDietPlan` Codables exactly.
    private func sendProgramStyleEmbed(
        kind: ProposalKind,
        patch: [String: JSONValue],
        summary: String
    ) async {
        let p = patch["protein_g"]?.doubleValue ?? 0
        let c = patch["carbs_g"]?.doubleValue ?? 0
        let f = patch["fat_g"]?.doubleValue ?? 0
        let kcalDouble = patch["calories"]?.doubleValue ?? (p * 4 + c * 4 + f * 9)
        let kcal = Int(kcalDouble.rounded())

        // Whisper integration contract (Nov-2026): top-level kinds are
        // `coach_macros` / `coach_diet_plan` with `_g` suffixes on macros.
        // Macros: every field optional (coach sends only what's changing).
        // Diet plan: macros required, `name` defaults to "Coach plan".
        let embedKind: String
        let payload: [String: AnyJSON]
        switch kind {
        case .macros:
            var macros: [String: AnyJSON] = [:]
            if kcal > 0 { macros["calories"] = .integer(kcal) }
            if p > 0 { macros["protein_g"] = Self.numberJSON(p) }
            if c > 0 { macros["carbs_g"]   = Self.numberJSON(c) }
            if f > 0 { macros["fat_g"]     = Self.numberJSON(f) }
            // `water_cups` is optional — only include when the coach
            // explicitly typed a target (per Whisper contract, omit otherwise).
            let waterStr = waterCups.trimmingCharacters(in: .whitespacesAndNewlines)
            if !waterStr.isEmpty, let cups = Int(waterStr), cups > 0 {
                macros["water_cups"] = .integer(cups)
            }
            embedKind = "coach_macros"
            payload = macros
        case .dietPlan:
            // Whisper contract (Nov-2026 update): `days[]` MUST be embedded
            // inline with every meal — RLS prevents the recipient from
            // joining back to the coach's rows, so the embed is the only
            // source of truth on delivery. If we ship macros-only, Whisper
            // saves an empty plan shell. So: pull the coach's most-recent
            // saved WeeklyDietPlan from AccountStorage and inline its full
            // weekly schedule. Fall back to a targets-only payload only
            // when the coach has no saved plan locally.
            let coachPlan = Self.loadCoachActivePlan()
            let coachPlanName: String? = {
                guard let n = coachPlan?.name, !n.isEmpty else { return nil }
                return n
            }()
            let planName = coachPlanName ?? activePlan?.name ?? "Coach plan"
            embedKind = "coach_diet_plan"
            var plan: [String: AnyJSON] = [
                "name": .string(planName),
                "calories": .integer(kcal),
                "protein_g": Self.numberJSON(p),
                "carbs_g": Self.numberJSON(c),
                "fat_g": Self.numberJSON(f),
            ]
            // `plan_id` is the coach's local WeeklyDietPlan.id when
            // available (matches what Whisper mirrors into
            // `jasper_diet_plans` for the coach themself); otherwise we
            // omit it per the contract.
            if let pid = coachPlan?.id { plan["plan_id"] = .string(pid) }
            // Dietary preference / goal — prefer the coach's local plan
            // (authoritative for what they're sending) over the client's
            // active row used for prefill.
            let prefRaw = coachPlan?.dietaryPreference.rawValue ?? activePlan?.dietary_preference
            if let raw = prefRaw, !raw.isEmpty {
                plan["dietary_preference"] = .string(Self.normalizedDietaryPreference(raw))
            }
            let goalRaw = coachPlan?.goal.rawValue ?? activePlan?.goal
            if let raw = goalRaw, !raw.isEmpty {
                plan["goal"] = .string(Self.normalizedGoal(raw))
            }
            // Inline days + meals when we have them.
            if let coachPlan, !coachPlan.days.isEmpty {
                let daysArr: [AnyJSON] = coachPlan.days.map { day in
                    let mealsArr: [AnyJSON] = day.meals.map { meal in
                        var m: [String: AnyJSON] = [
                            "meal_type": .string(Self.normalizedMealType(meal.mealType)),
                            "name": .string(meal.name),
                            "description": .string(meal.description),
                            "ingredients": .array(meal.ingredients.map { .string($0) }),
                            "calories": .integer(meal.calories),
                            "protein_g": Self.numberJSON(meal.protein),
                            "carbs_g": Self.numberJSON(meal.carbs),
                            "fat_g": Self.numberJSON(meal.fat),
                        ]
                        if !meal.prepTime.isEmpty { m["prep_time"] = .string(meal.prepTime) }
                        return .object(m)
                    }
                    return .object([
                        "day_name": .string(day.dayName),
                        "meals": .array(mealsArr),
                    ])
                }
                plan["days"] = .array(daysArr)
                plan["days_count"] = .integer(coachPlan.days.count)
                // Average meals per day across the schedule, rounded; the
                // contract treats this as a hint, not the source of truth.
                let totalMeals = coachPlan.days.reduce(0) { $0 + $1.meals.count }
                let mpd = coachPlan.days.isEmpty ? 0
                    : Int((Double(totalMeals) / Double(coachPlan.days.count)).rounded())
                if mpd > 0 { plan["meals_per_day"] = .integer(mpd) }
            } else {
                // Targets-only fallback.
                plan["days_count"] = .integer(0)
                if let mpd = activePlan?.meals_per_day, mpd > 0 {
                    plan["meals_per_day"] = .integer(mpd)
                }
            }
            payload = plan
        case .note:
            let text = patch["text"]?.stringValue ?? ""
            let title = patch["title"]?.stringValue
            var noteObj: [String: AnyJSON] = [
                "text": .string(text),
            ]
            if let title, !title.isEmpty { noteObj["title"] = .string(title) }
            embedKind = "coach_note"
            payload = noteObj
        }

        // Coach-side DM still renders the inline summary card from the v1
        // prefixed body. Whisper reads the embed.
        let coachUsername = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "your coach"
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteOrNil = trimmedNote.isEmpty ? nil : trimmedNote
        let localPayload = WhisperCoachProposalEmbed.Payload(
            id: UUID().uuidString,
            kind: kind.rawValue,
            coachUsername: coachUsername,
            summary: summary,
            note: noteOrNil
        )
        let body = WhisperCoachProposalEmbed.encode(localPayload)

        let embed: [String: AnyJSON] = [
            "kind": .string(embedKind),
            "payload": .object(payload),
        ]

        _ = await WhisperBackendService.shared.sendMessage(
            toUserID: client.client_user_id,
            toUsername: client.client_username,
            body: body,
            embed: embed
        )
    }

    private static func numberJSON(_ v: Double) -> AnyJSON {
        if v.truncatingRemainder(dividingBy: 1) == 0,
           v >= Double(Int.min), v <= Double(Int.max) {
            return .integer(Int(v))
        }
        return .double(v)
    }

    /// Whisper Nov-2026 contract uses camelCase enum keys on the wire
    /// (`noPreference|vegan|vegetarian|pescatarian|keto|paleo|`
    /// `mediterranean|glutenFree|dairyFree`). Accepts both the legacy
    /// display string ("No Preference") and the new key.
    private static func normalizedDietaryPreference(_ raw: String) -> String {
        switch raw {
        case "vegan", "Vegan":                            return "vegan"
        case "vegetarian", "Vegetarian":                  return "vegetarian"
        case "pescatarian", "Pescatarian":                return "pescatarian"
        case "keto", "Keto":                              return "keto"
        case "paleo", "Paleo":                            return "paleo"
        case "mediterranean", "Mediterranean":            return "mediterranean"
        case "glutenFree", "Gluten Free":                 return "glutenFree"
        case "dairyFree", "Dairy Free":                   return "dairyFree"
        default:                                          return "noPreference"
        }
    }

    /// Whisper Nov-2026 contract: `lose|gain|recomp|maintain` (lowercase).
    /// Maps both the Swift enum raw values ("Aggressive Fat Loss", etc.)
    /// and the new wire keys.
    private static func normalizedGoal(_ raw: String) -> String {
        switch raw {
        case "lose", "Fat Loss", "Aggressive Fat Loss", "Lose":
            return "lose"
        case "gain", "Muscle Gain", "Lean Bulk", "Gain":
            return "gain"
        case "recomp":
            return "recomp"
        default:
            return "maintain"
        }
    }

    /// Normalizes Whisper meal-type strings ("Breakfast", "PM Snack",
    /// "Pre-workout Shake", …) to the contract enum
    /// `breakfast|lunch|dinner|snack|drink`.
    private static func normalizedMealType(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("breakfast") { return "breakfast" }
        if lower.contains("lunch")     { return "lunch" }
        if lower.contains("dinner")    { return "dinner" }
        if lower.contains("shake") || lower.contains("smoothie") || lower.contains("drink") {
            return "drink"
        }
        return "snack"
    }

    /// Loads the coach's most-recently-saved WeeklyDietPlan from the
    /// shared `jasper_diet_plans` AccountStorage key (same blob
    /// `DietPlanService` reads). Used to inline the full weekly schedule
    /// into the coach_diet_plan embed.
    private static func loadCoachActivePlan() -> WeeklyDietPlan? {
        guard let data = AccountStorage.data(forKey: "jasper_diet_plans"),
              let plans = try? JSONDecoder().decode([WeeklyDietPlan].self, from: data)
        else { return nil }
        return plans.first
    }

    static func summary(for kind: String, patch: [String: JSONValue], freeText: String) -> String {
        switch kind {
        case "macros", "diet_plan":
            let cal = patch["calories"]?.doubleValue.map { Int($0) }
            let p = patch["protein_g"]?.doubleValue
            let c = patch["carbs_g"]?.doubleValue
            let f = patch["fat_g"]?.doubleValue
            var parts: [String] = []
            if let cal { parts.append("\(cal) kcal") }
            var macros: [String] = []
            if let p { macros.append("\(formatG(p))P") }
            if let c { macros.append("\(formatG(c))C") }
            if let f { macros.append("\(formatG(f))F") }
            if !macros.isEmpty { parts.append(macros.joined(separator: " / ")) }
            return parts.joined(separator: " · ")
        case "note":
            if let title = patch["title"]?.stringValue, !title.isEmpty { return title }
            return patch["text"]?.stringValue ?? freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func formatG(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(v))" }
        return String(format: "%.1f", v)
    }
}
