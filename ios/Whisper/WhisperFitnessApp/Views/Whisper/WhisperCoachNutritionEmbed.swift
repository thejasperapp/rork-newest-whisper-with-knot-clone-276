import SwiftUI

// MARK: - Coach Macros embed
//
// Wire format Whisper (the client) receives on `whisper_messages.embed`:
//   { "kind": "coach_macros",
//     "payload": { "calories": Int?, "protein_g": Number?,
//                  "carbs_g": Number?, "fat_g": Number?,
//                  "water_cups": Int? } }
//
// All payload fields are optional — the coach sends only what's changing.
// `water_cups` is 8 oz cups; honor it only when explicitly set by the sender.
// Field names match the Whisper integration contract (program-style embed,
// no `coach_proposal` wrapper, no proposal row).
//
// On the wire we bridge the embed into a prefixed `body` string so the
// existing DM thread renderer can render it inline. The actual JSON shape
// of `WhisperCoachMacrosEmbed.Payload` matches the contract 1:1.

enum WhisperCoachMacrosEmbed {
    static let prefix = "::whisper-coach-macros-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable {
        let id: String
        let coachUsername: String
        let calories: Int?
        let protein_g: Double?
        let carbs_g: Double?
        let fat_g: Double?
        let water_cups: Int?
    }

    static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    static func decode(_ body: String) -> Payload? {
        guard body.hasPrefix(prefix) else { return nil }
        let json = String(body.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// "2400 kcal · 200P / 240C / 70F"
    static func summary(_ p: Payload) -> String {
        var parts: [String] = []
        if let cal = p.calories { parts.append("\(cal) kcal") }
        var macros: [String] = []
        if let v = p.protein_g { macros.append("\(fmt(v))P") }
        if let v = p.carbs_g   { macros.append("\(fmt(v))C") }
        if let v = p.fat_g     { macros.append("\(fmt(v))F") }
        if !macros.isEmpty { parts.append(macros.joined(separator: " / ")) }
        if let w = p.water_cups { parts.append("\(w) cups water") }
        return parts.joined(separator: " · ")
    }

    private static func fmt(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(v))" }
        return String(format: "%.1f", v)
    }
}

/// Applies a coach-macros embed to the local Whisper nutrition goals blob
/// (`jasper_nutrition_goals`). Only fields the coach sent are overwritten;
/// missing fields keep their current value. `water` is never touched (the
/// contract is macros-only). Posts a `jasperNutritionGoalsUpdated`
/// notification so the live Nutrition tab refreshes immediately.
enum WhisperCoachMacrosImport {
    @MainActor
    static func apply(_ payload: WhisperCoachMacrosEmbed.Payload) {
        var goals: NutritionGoals = .default
        if let data = AccountStorage.data(forKey: "jasper_nutrition_goals"),
           let decoded = try? JSONDecoder().decode(NutritionGoals.self, from: data) {
            goals = decoded
        }
        if let cal = payload.calories { goals.calories = cal }
        if let v = payload.protein_g  { goals.protein = v }
        if let v = payload.carbs_g    { goals.carbs = v }
        if let v = payload.fat_g      { goals.fat = v }

        if let encoded = try? JSONEncoder().encode(goals) {
            AccountStorage.set(encoded, forKey: "jasper_nutrition_goals")
        }

        // Keep the shared widget defaults in sync so the nutrition widget
        // doesn't lag behind the coach update.
        if let shared = UserDefaults(suiteName: "group.com.mydailywhisper.whisper") {
            shared.set(goals.calories, forKey: "widget_nutritionGoalCalories")
            shared.set(goals.protein,  forKey: "widget_nutritionGoalProtein")
            shared.set(goals.carbs,    forKey: "widget_nutritionGoalCarbs")
            shared.set(goals.fat,      forKey: "widget_nutritionGoalFat")
        }

        NotificationCenter.default.post(
            name: Notification.Name("jasperNutritionGoalsUpdated"),
            object: nil
        )
        Haptics.success()
    }
}

// MARK: - Coach Diet Plan embed
//
// Wire format on `whisper_messages.embed`:
//   { "kind": "coach_diet_plan",
//     "payload": { "plan_id": String?,
//                  "name": String?,
//                  "calories": Int, "protein_g": Number,
//                  "carbs_g": Number, "fat_g": Number,
//                  "dietary_preference": String?, "goal": String?,
//                  "days_count": Int?, "meals_per_day": Int? } }
//
// `name` defaults to "Coach plan" if omitted; all macros are required per
// the contract. `plan_id` is the row id in `jasper_diet_plans` when the
// sender is a real Supabase user — use it to deep-link the chat card into
// the full plan + days + meals. `dietary_preference` falls back to
// "No Preference" for unknown values; `goal` falls back to "Maintain".
// `days_count` is 0 for targets-only plans (no weekly schedule).

enum WhisperCoachDietPlanEmbed {
    static let prefix = "::whisper-coach-diet-plan-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable {
        let id: String
        let coachUsername: String
        let name: String
        let calories: Int
        let protein_g: Double
        let carbs_g: Double
        let fat_g: Double
        let plan_id: String?
        let dietary_preference: String?
        let goal: String?
        let days_count: Int?
        let meals_per_day: Int?
    }

    static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    static func decode(_ body: String) -> Payload? {
        guard body.hasPrefix(prefix) else { return nil }
        let json = String(body.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func summary(_ p: Payload) -> String {
        let macros = [
            "\(fmt(p.protein_g))P",
            "\(fmt(p.carbs_g))C",
            "\(fmt(p.fat_g))F",
        ].joined(separator: " / ")
        return "\(p.calories) kcal · \(macros)"
    }

    private static func fmt(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(v))" }
        return String(format: "%.1f", v)
    }
}

/// Materializes a coach diet-plan embed into Whisper's saved `WeeklyDietPlan`
/// list. We don't have days/meals in the embed, so the resulting plan is
/// macro-targets only; the user can still generate a meal plan against it
/// from the Nutrition tab.
enum WhisperCoachDietPlanImport {
    @MainActor
    static func apply(_ payload: WhisperCoachDietPlanEmbed.Payload) {
        let plan = WeeklyDietPlan(
            name: payload.name.isEmpty ? "Coach plan" : payload.name,
            targetCalories: payload.calories,
            targetProtein: payload.protein_g,
            targetCarbs: payload.carbs_g,
            targetFat: payload.fat_g,
            dietaryPreference: .noPreference,
            goal: .maintain,
            days: []
        )
        // plan_id / dietary_preference / goal / days_count / meals_per_day
        // are informational on the coach side — they're used to render the
        // rich card and (future) deep-link to the full plan via
        // `jasper_diet_plans` + `jasper_diet_plan_days` + `jasper_diet_plan_meals`.
        // No need to apply them to the local WeeklyDietPlan blob here.

        var saved: [WeeklyDietPlan] = []
        if let data = AccountStorage.data(forKey: "jasper_diet_plans"),
           let decoded = try? JSONDecoder().decode([WeeklyDietPlan].self, from: data) {
            saved = decoded
        }
        // Dedupe by coach embed id (encoded in name suffix would be hacky)
        // — instead, dedupe by exact name + macro tuple to avoid stacking
        // duplicates from re-tapping the banner.
        saved.removeAll { existing in
            existing.name == plan.name &&
            existing.targetCalories == plan.targetCalories &&
            existing.targetProtein == plan.targetProtein &&
            existing.targetCarbs == plan.targetCarbs &&
            existing.targetFat == plan.targetFat
        }
        saved.insert(plan, at: 0)

        if let encoded = try? JSONEncoder().encode(saved) {
            AccountStorage.set(encoded, forKey: "jasper_diet_plans")
        }

        // Also bump nutrition goals to match — saving a diet plan in the
        // app already syncs the targets to the Nutrition tab, mirror that.
        var goals: NutritionGoals = .default
        if let data = AccountStorage.data(forKey: "jasper_nutrition_goals"),
           let decoded = try? JSONDecoder().decode(NutritionGoals.self, from: data) {
            goals = decoded
        }
        goals.calories = payload.calories
        goals.protein  = payload.protein_g
        goals.carbs    = payload.carbs_g
        goals.fat      = payload.fat_g
        if let encoded = try? JSONEncoder().encode(goals) {
            AccountStorage.set(encoded, forKey: "jasper_nutrition_goals")
        }

        NotificationCenter.default.post(
            name: Notification.Name("jasperDietPlansUpdated"),
            object: nil
        )
        NotificationCenter.default.post(
            name: Notification.Name("jasperNutritionGoalsUpdated"),
            object: nil
        )
        Haptics.success()
    }
}

// MARK: - Inline cards (DM bubbles)

/// Premium coach-sent macros card. Warm-accent header strip, columnar
/// stat tiles with hairline dividers, and a real CTA chip footer.
struct WhisperCoachMacrosInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperCoachMacrosEmbed.Payload
    let mine: Bool
    let saved: Bool

    private var fg: Color {
        mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme)
    }
    private var bg: Color {
        mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme)
    }

    private struct Stat: Identifiable {
        let id = UUID()
        let value: String
        let unit: String
    }

    private var stats: [Stat] {
        var out: [Stat] = []
        if let cal = payload.calories { out.append(.init(value: "\(cal)", unit: "kcal")) }
        if let v = payload.protein_g  { out.append(.init(value: fmt(v), unit: "protein")) }
        if let v = payload.carbs_g    { out.append(.init(value: fmt(v), unit: "carbs")) }
        if let v = payload.fat_g      { out.append(.init(value: fmt(v), unit: "fat")) }
        if let w = payload.water_cups { out.append(.init(value: "\(w)", unit: "water")) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            statRow
            footer
        }
        .frame(width: 264, alignment: .leading)
        .foregroundStyle(fg)
        .background(bg, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    mine ? Color.white.opacity(0.08) : WhisperTheme.hairline(colorScheme),
                    lineWidth: 0.5
                )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            WhisperAvatar(username: payload.coachUsername, size: 32, ring: false)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("@\(payload.coachUsername)")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    WhisperCoachBadge(size: 10)
                }
                Text("Macro update")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "scalemass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WhisperTheme.coachAccent)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var statRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { idx, s in
                VStack(spacing: 1) {
                    Text(s.value)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    Text(s.unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                if idx < stats.count - 1 {
                    Rectangle()
                        .fill(fg.opacity(0.10))
                        .frame(width: 0.5, height: 22)
                }
            }
        }
        .padding(.vertical, 10)
        .background(
            fg.opacity(mine ? 0.08 : 0.05),
            in: .rect(cornerRadius: 12)
        )
        .padding(.horizontal, 12)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: saved ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.footnote)
            Text(saved ? "Applied to your goals" : "Tap to apply")
                .font(.footnote.weight(.medium))
            Spacer(minLength: 0)
            if !saved {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(saved ? Color.green : WhisperTheme.coachAccent)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func fmt(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(v))" }
        return String(format: "%.1f", v)
    }
}

struct WhisperCoachDietPlanInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperCoachDietPlanEmbed.Payload
    let mine: Bool
    let saved: Bool

    private var metaChips: [String] {
        var out: [String] = []
        if let pref = payload.dietary_preference, !pref.isEmpty, pref != "No Preference" {
            out.append(pref)
        }
        if let g = payload.goal, !g.isEmpty { out.append(g) }
        if let d = payload.days_count, d > 0 {
            out.append("\(d) day\(d == 1 ? "" : "s")")
        }
        if let m = payload.meals_per_day, m > 0 {
            out.append("\(m) meal\(m == 1 ? "" : "s")/day")
        }
        return out
    }

    private var fg: Color {
        mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme)
    }
    private var bg: Color {
        mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            planTitle
            statRow
            if !metaChips.isEmpty { chipsRow }
            footer
        }
        .frame(width: 264, alignment: .leading)
        .foregroundStyle(fg)
        .background(bg, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    mine ? Color.white.opacity(0.08) : WhisperTheme.hairline(colorScheme),
                    lineWidth: 0.5
                )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            WhisperAvatar(username: payload.coachUsername, size: 32, ring: false)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("@\(payload.coachUsername)")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    WhisperCoachBadge(size: 10)
                }
                Text("Diet plan")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "fork.knife")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WhisperTheme.coachAccent)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var planTitle: some View {
        Text(payload.name.isEmpty ? "Coach plan" : payload.name)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
    }

    private var statRow: some View {
        HStack(spacing: 0) {
            statTile("\(payload.calories)", "kcal", isLast: false)
            statTile(fmt(payload.protein_g), "protein", isLast: false)
            statTile(fmt(payload.carbs_g), "carbs", isLast: false)
            statTile(fmt(payload.fat_g), "fat", isLast: true)
        }
        .padding(.vertical, 10)
        .background(fg.opacity(mine ? 0.08 : 0.05), in: .rect(cornerRadius: 12))
        .padding(.horizontal, 12)
    }

    private func statTile(_ v: String, _ u: String, isLast: Bool) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 1) {
                Text(v)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text(u)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            if !isLast {
                Rectangle()
                    .fill(fg.opacity(0.10))
                    .frame(width: 0.5, height: 22)
            }
        }
    }

    private var chipsRow: some View {
        HStack(spacing: 5) {
            ForEach(metaChips, id: \.self) { chip in
                Text(chip)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(fg.opacity(0.08), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: saved ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.footnote)
            Text(saved ? "Saved to your plans" : "Tap to save")
                .font(.footnote.weight(.medium))
            Spacer(minLength: 0)
            if !saved {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(saved ? Color.green : WhisperTheme.coachAccent)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func fmt(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(v))" }
        return String(format: "%.1f", v)
    }
}
