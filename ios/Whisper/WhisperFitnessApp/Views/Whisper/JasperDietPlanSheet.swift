import SwiftUI

// MARK: - Canonical model (diet_plans rows — §8 catalog)

/// One Jasper diet plan, decoded leniently from a `diet_plans` row: the
/// catalog's top-level fields (name, goal, dietary_preference, target_*,
/// meals_per_day, is_active) plus the `payload` — `days[].meals[]` and the
/// canonical `groceryList` (modelled by `JasperGroceryList`, rendered
/// verbatim, never re-derived).
nonisolated struct JasperDietPlan {
    nonisolated struct Meal: Identifiable {
        let name: String
        let mealType: String?
        let calories: Int?
        let proteinG: Double?
        let carbsG: Double?
        let fatG: Double?
        var id: String { (mealType ?? "") + "::" + name }

        var macroLine: String? {
            var parts: [String] = []
            if let calories { parts.append("\(calories) kcal") }
            if let proteinG { parts.append("P \(Int(proteinG))g") }
            if let carbsG { parts.append("C \(Int(carbsG))g") }
            if let fatG { parts.append("F \(Int(fatG))g") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    nonisolated struct Day: Identifiable {
        let name: String
        let meals: [Meal]
        var id: String { name }
    }

    let name: String
    let goal: String?
    let dietaryPreference: String?
    let targetCalories: Int?
    let targetProteinG: Int?
    let targetCarbsG: Int?
    let targetFatG: Int?
    let mealsPerDay: Int?
    let isActive: Bool
    let days: [Day]
    let groceries: JasperGroceryList?

    var hasTargets: Bool {
        targetCalories != nil || targetProteinG != nil || targetCarbsG != nil || targetFatG != nil
    }

    // MARK: Decode

    static func parse(row: [String: Any]) -> JasperDietPlan {
        let payload = row["payload"] as? [String: Any]
        let name = (row["name"] as? String)
            ?? ((payload?["groceryList"] as? [String: Any])?["planName"] as? String)
            ?? "Diet plan"
        return JasperDietPlan(
            name: name,
            goal: row["goal"] as? String,
            dietaryPreference: row["dietary_preference"] as? String,
            targetCalories: flexInt(row["target_calories"]),
            targetProteinG: flexInt(row["target_protein"] ?? row["target_protein_g"]),
            targetCarbsG: flexInt(row["target_carbs"] ?? row["target_carbs_g"]),
            targetFatG: flexInt(row["target_fat"] ?? row["target_fat_g"]),
            mealsPerDay: flexInt(row["meals_per_day"]),
            isActive: (row["is_active"] as? Bool) ?? false,
            days: parseDays(payload?["days"] as? [[String: Any]]),
            groceries: JasperGroceryList.parse(payload: payload, fallbackName: name)
                ?? JasperGroceryList.derive(payload: payload, fallbackName: name)
        )
    }

    /// Best row first: active plans beat inactive, then newest `recorded_on`.
    static func fromRows(_ rows: [[String: Any]]) -> JasperDietPlan? {
        let sorted = rows.sorted { a, b in
            let activeA = (a["is_active"] as? Bool) ?? false
            let activeB = (b["is_active"] as? Bool) ?? false
            if activeA != activeB { return activeA }
            let dateA = jasperConnectDate(a["recorded_on"]) ?? .distantPast
            let dateB = jasperConnectDate(b["recorded_on"]) ?? .distantPast
            return dateA > dateB
        }
        guard let best = sorted.first else { return nil }
        return parse(row: best)
    }

    private static func parseDays(_ raw: [[String: Any]]?) -> [Day] {
        guard let raw else { return [] }
        return raw.enumerated().map { index, day in
            let label: String
            if let s = day["name"] as? String, !s.isEmpty {
                label = s
            } else if let s = day["label"] as? String, !s.isEmpty {
                label = s
            } else if let n = flexInt(day["day"]) {
                label = "Day \(n)"
            } else {
                label = "Day \(index + 1)"
            }
            let meals: [Meal] = ((day["meals"] as? [[String: Any]]) ?? []).compactMap { meal in
                let mealName = (meal["name"] as? String)
                    ?? (meal["title"] as? String)
                    ?? (meal["meal"] as? String)
                guard let mealName, !mealName.isEmpty else { return nil }
                return Meal(
                    name: mealName,
                    mealType: (meal["meal_type"] as? String) ?? (meal["type"] as? String),
                    calories: flexInt(meal["calories"] ?? meal["calories_kcal"] ?? meal["kcal"]),
                    proteinG: flexDouble(meal["protein_g"] ?? meal["protein"]),
                    carbsG: flexDouble(meal["carbs_g"] ?? meal["carbs"]),
                    fatG: flexDouble(meal["fat_g"] ?? meal["fat"])
                )
            }
            return Day(name: label, meals: meals)
        }
    }

    nonisolated private static func flexInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) ?? Double(s).map(Int.init) }
        return nil
    }

    nonisolated private static func flexDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}

// MARK: - Sheet (Jasper glow language, adaptive light/dark)

/// The full diet plan read straight off the Connect API: targets up top,
/// the week's meals in glow boxes, and the canonical grocery checklist one
/// tap away. Own account loads through the user's own token; a coach view
/// loads through that client's coach token (view-only, honestly labelled).
struct JasperDietPlanSheet: View {
    enum Source {
        /// Self-loading through the user's OWN Connect token.
        case ownConnect
        /// A coach reading an accepted client through the coach-held token.
        case coachClient(uid: String, username: String)
        /// Already-loaded plan (coach dashboard preloads through the client token).
        case preloaded(JasperDietPlan, note: String?)
    }

    let source: Source
    /// Overlay presentations (Jasper action modals) pass a custom close;
    /// sheet presentations fall back to `dismiss`.
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: Phase = .loading
    @State private var showGroceries = false
    @State private var selectedDay = 0

    private enum Phase {
        case loading
        case plan(JasperDietPlan)
        case empty(String)
        case failed(String)
    }

    private var isOwn: Bool {
        if case .ownConnect = source { return true }
        return false
    }

    private var note: String? {
        switch source {
        case .ownConnect:
            return "Read live from your connected Jasper account — the same plan Jasper renders in-app."
        case .coachClient(_, let username):
            return "Read live through @\(username)'s coach token — their current plan, view-only here."
        case .preloaded(_, let note):
            return note
        }
    }

    var body: some View {
        ZStack {
            JasperGlowStage()
            VStack(spacing: 0) {
                header
                switch phase {
                case .loading:
                    ScrollView { loadingBody }
                        .scrollIndicators(.hidden)
                case .failed(let message):
                    statusBody(icon: "wifi.exclamationmark", title: "Couldn't load the plan",
                               message: message, retry: true)
                case .empty(let message):
                    ScrollView { WhisperEmptyState(icon: "fork.knife", title: "No diet plan yet", message: message, isCard: false) }
                case .plan(let plan):
                    planBody(plan)
                }
            }
        }
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            EmberGlowIcon(systemName: "fork.knife")
            VStack(alignment: .leading, spacing: 3) {
                JasperKicker(text: "Diet plan")
                if case .plan(let plan) = phase {
                    HStack(spacing: 7) {
                        Text(plan.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(JasperBrand.text(colorScheme))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        if plan.isActive {
                            Text("ACTIVE")
                                .font(.system(size: 8.5, weight: .heavy))
                                .tracking(1.0)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(JasperBrand.emberGradient, in: .capsule)
                        }
                    }
                    Text(metaLine(plan))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.58))
                }
            }
            Spacer()
            Button {
                Haptics.tap()
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.65))
                    .frame(width: 32, height: 32)
                    .background(JasperBrand.chip(colorScheme), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close diet plan")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    // MARK: Plan body

    /// §4 meta: "{days} days · {meals_per_day} meals/day · {goal}".
    private func metaLine(_ plan: JasperDietPlan) -> String {
        var parts: [String] = []
        if !plan.days.isEmpty { parts.append("\(plan.days.count) day\(plan.days.count == 1 ? "" : "s")") }
        if let meals = plan.mealsPerDay { parts.append("\(meals) meals/day") }
        if let goal = plan.goal, !goal.isEmpty { parts.append(goal.capitalized) }
        return parts.joined(separator: " · ")
    }

    private func planBody(_ plan: JasperDietPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                contextChips(plan)
                if plan.hasTargets {
                    JasperMacroTileRow(kcal: plan.targetCalories,
                                       protein: plan.targetProteinG,
                                       carbs: plan.targetCarbsG,
                                       fat: plan.targetFatG)
                }
                if plan.groceries != nil { groceriesRow(plan) }
                if !plan.days.isEmpty {
                    dayStrip(plan)
                    selectedDayBox(plan)
                }
                if plan.days.isEmpty {
                    Text("This plan doesn't carry day-by-day meals — targets\(plan.groceries != nil ? " and the grocery checklist" : "") still read live.")
                        .font(.caption2)
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.45))
                }
                Text("Straight from the Jasper Connect API — the plan exactly as Jasper stores it.")
                    .font(.caption2)
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                    .padding(.top, 2)
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private func contextChips(_ plan: JasperDietPlan) -> some View {
        HStack(spacing: 8) {
            if let goal = plan.goal, !goal.isEmpty {
                chip(icon: "target", text: goal.capitalized)
            }
            if let pref = plan.dietaryPreference, !pref.isEmpty {
                chip(icon: "leaf.fill", text: pref.capitalized)
            }
            if let meals = plan.mealsPerDay {
                chip(icon: "fork.knife", text: "\(meals) meals/day")
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(icon: String, text: String) -> some View {
        JasperContextChip(icon: icon, label: text)
    }

    /// §4.3 — 7-day chip strip: selected = ember-gradient capsule, white
    /// caption.bold; unselected = quiet inset. Selection springs.
    private func dayStrip(_ plan: JasperDietPlan) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(plan.days.enumerated()), id: \.element.id) { index, day in
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            selectedDay = index
                        }
                    } label: {
                        Text(day.name)
                            .font(.caption.bold())
                            .foregroundStyle(selectedDay == index
                                             ? .white
                                             : JasperBrand.text(colorScheme).opacity(0.65))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background {
                                if selectedDay == index {
                                    Capsule().fill(JasperBrand.emberGradient)
                                } else {
                                    Capsule().fill(colorScheme == .dark
                                                   ? Color.white.opacity(0.08)
                                                   : JasperBrand.ink.opacity(0.05))
                                }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// §4.4–5 — the selected day's meal cards + the day-totals row.
    @ViewBuilder
    private func selectedDayBox(_ plan: JasperDietPlan) -> some View {
        let index = min(selectedDay, plan.days.count - 1)
        let day = plan.days[max(0, index)]
        VStack(alignment: .leading, spacing: 10) {
            ForEach(day.meals) { meal in
                mealCard(meal)
            }
            if day.meals.isEmpty {
                Text("No meals recorded for \(day.name).")
                    .font(.caption)
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
            }
            dayTotals(day)
        }
    }

    private func mealCard(_ meal: JasperDietPlan.Meal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let type = meal.mealType, !type.isEmpty {
                Text(type.uppercased())
                    .font(.caption2.bold())
                    .tracking(0.6)
                    .foregroundStyle(JasperBrand.kicker(colorScheme))
            }
            Text(meal.name)
                .font(.subheadline.bold())
                .foregroundStyle(JasperBrand.text(colorScheme))
                .lineLimit(2)
            if let macros = meal.macroLine {
                Text(macros)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.58))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JasperBrand.inset(colorScheme), in: .rect(cornerRadius: 15))
    }

    private func dayTotals(_ day: JasperDietPlan.Day) -> some View {
        let kcal = day.meals.compactMap(\.calories).reduce(0, +)
        let p = Int(day.meals.compactMap(\.proteinG).reduce(0, +))
        let c = Int(day.meals.compactMap(\.carbsG).reduce(0, +))
        let f = Int(day.meals.compactMap(\.fatG).reduce(0, +))
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(JasperBrand.text(colorScheme).opacity(0.08))
                .frame(height: 0.7)
            Text("Day total · \(kcal.formatted()) kcal · \(p)P · \(c)C · \(f)F")
                .font(.caption.weight(.semibold))
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.60))
                .padding(.top, 8)
        }
    }

    /// §4.6 — the grocery box: a second glow box (glow 0.5) headed by a 32pt
    /// EmberGlowIcon cart + GROCERY LIST kicker + trailing item counter.
    private func groceriesRow(_ plan: JasperDietPlan) -> some View {
        Button {
            Haptics.tap()
            showGroceries = true
        } label: {
            JasperGlowBox(cornerRadius: 22, glow: 0.5) {
                HStack(spacing: 12) {
                    EmberGlowIcon(systemName: "cart.fill", size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        JasperKicker(text: "Grocery list", secondary: true)
                        if let groceries = plan.groceries {
                            Text("\(groceries.itemCount) items · \(groceries.categories.count) aisles — shared with Jasper, checks sync both ways")
                                .font(.system(size: 11))
                                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.6))
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 6)
                    if let groceries = plan.groceries {
                        Text("\(groceries.itemCount)")
                            .font(.system(.subheadline, design: .rounded).bold())
                            .foregroundStyle(JasperBrand.kicker(colorScheme))
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                }
                .padding(12)
            }
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showGroceries) {
            if isOwn {
                JasperGroceryListSheet(source: .ownConnect)
            } else if let groceries = plan.groceries {
                JasperGroceryListSheet(source: .preloaded(groceries, note: note))
            }
        }
    }

    // MARK: Loading / status

    private var loadingBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(JasperBrand.text(colorScheme).opacity(0.14))
                        .frame(width: 84, height: 24)
                }
            }
            ForEach(0..<2, id: \.self) { _ in
                JasperGlowBox(cornerRadius: 18, glow: 0.3) {
                    VStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in
                            HStack(spacing: 12) {
                                Capsule()
                                    .fill(JasperBrand.text(colorScheme).opacity(0.16))
                                    .frame(width: 150, height: 11)
                                Spacer()
                                Capsule()
                                    .fill(JasperBrand.text(colorScheme).opacity(0.10))
                                    .frame(width: 54, height: 10)
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
        .padding(.horizontal, 20)
        .phaseAnimator([0.9, 0.45]) { view, phaseValue in
            view.opacity(phaseValue)
        } animation: { _ in .easeInOut(duration: 0.7) }
    }

    private func statusBody(icon: String, title: String, message: String, retry: Bool) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(JasperBrand.kicker(colorScheme))
            Text(title)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(JasperBrand.text(colorScheme))
            Text(message)
                .font(.footnote)
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if retry {
                Button {
                    Haptics.tap()
                    phase = .loading
                    Task { await load() }
                } label: {
                    Text("Try again")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(JasperBrand.ink)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(JasperBrand.emberGradient, in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Load

    private func load() async {
        switch source {
        case .preloaded(let plan, _):
            phase = .plan(plan)
        case .ownConnect:
            guard case .loading = phase else { return }
            do {
                let data = try await JasperConnectClient.shared.read("diet_plans", limit: 20)
                apply(data: data,
                      emptyMessage: "No diet plan in Jasper yet — create one there and it appears here: meals, targets, groceries and all.")
            } catch {
                applyError(error)
            }
        case .coachClient(let uid, let username):
            guard case .loading = phase else { return }
            do {
                let data = try await JasperCoachConnect.shared.read(forClient: uid, "diet_plans", limit: 20)
                apply(data: data,
                      emptyMessage: "@\(username) has no diet plan in Jasper yet.")
            } catch {
                applyError(error)
            }
        }
    }

    private func apply(data: Data, emptyMessage: String) {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let rows = (body?["data"] as? [[String: Any]]) ?? []
        if let plan = JasperDietPlan.fromRows(rows) {
            withAnimation(.spring(duration: 0.35)) { phase = .plan(plan) }
        } else {
            phase = .empty(emptyMessage)
        }
    }

    private func applyError(_ error: Error) {
        if case JasperConnectError.revoked = error {
            phase = .failed("This connection was revoked — reconnect Jasper and try again.")
            return
        }
        let message = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
        if message.lowercased().contains("missing_scope") || message.lowercased().contains("missing scope") {
            phase = .empty("Nutrition isn't shared on this token — that's a consent choice made on the Jasper side, not an error.")
        } else {
            phase = .failed(message)
        }
    }
}
