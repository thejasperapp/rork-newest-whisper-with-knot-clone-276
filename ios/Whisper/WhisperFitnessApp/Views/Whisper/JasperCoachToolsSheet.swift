import SwiftUI
import UIKit

/// Phase 2 coach tools — real writes into the CLIENT's Jasper through the
/// coach-held Connect token, available only when the coaching grant is
/// read & write. Three tools: assign a training program, log a correction
/// (meal or water), and drop a note card into the client's Shared inbox.
/// Every successful write shows a receipt with one-tap Undo (DELETE by row
/// id — Jasper emits a deletion event so the client's apps stay truthful).
struct JasperCoachToolsSheet: View {
    let clientUID: String
    let clientUsername: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var coachConnect = JasperCoachConnect.shared

    private enum Tool: String, CaseIterable, Identifiable {
        case program = "Program"
        case diet = "Diet plan"
        case log = "Log"
        case card = "Inbox card"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .program: return "figure.strengthtraining.traditional"
            case .diet: return "leaf.fill"
            case .log: return "fork.knife"
            case .card: return "tray.and.arrow.down.fill"
            }
        }
    }

    private enum LogKind: String, CaseIterable {
        case meal = "Meal"
        case water = "Water"
    }

    @State private var tool: Tool = .program

    // Program — authored to Jasper's `plan_shapes` contract (GET /v1/catalog):
    // fixed goal vocabulary, per-day exercise drafts, byte-exact payload.
    @State private var programName = ""
    @State private var programGoal = "General Fitness"
    @State private var programWeeks = 4
    @State private var programDays = 3
    @State private var programNotes = ""
    @State private var dayDrafts: [DayDraft] = [DayDraft(), DayDraft(), DayDraft()]
    /// Aug 17 2026: one send can also publish the SAME plan_shapes payload
    /// to Jasper's public marketplace (coach session JWT; re-publishing the
    /// same title updates in place).
    @State private var publishToMarketplace = false

    /// Jasper's fixed program-goal vocabulary (plan_shapes — anything else
    /// is outside the contract).
    private static let programGoals = [
        "General Fitness", "Build Muscle", "Lose Fat", "Get Stronger",
        "Improve Endurance", "Athletic Performance", "Tone & Define",
        "Increase Flexibility",
    ]

    private struct ExerciseDraft: Identifiable {
        let id = UUID()
        var name = ""
        var sets = 3
        var reps = "8-12"      // reps is ALWAYS a string in plan_shapes
        var restSeconds = 90
    }

    private struct DayDraft: Identifiable {
        let id = UUID()
        var focus = ""
        var exercises: [ExerciseDraft] = [ExerciseDraft()]
    }

    // Diet plan — Jasper's OWN generator over the API (Aug 17 2026):
    // POST /v1/diet_plans/generate — targets or a Mifflin-St Jeor profile,
    // preference + allergies, complete plan_shapes payload back, grocery
    // list derived. save:true writes it to the client in the same call.
    @State private var dietGoal = "Fat Loss"
    @State private var dietPreference = "No Preference"
    @State private var dietAllergies = ""
    @State private var dietMealsPerDay = 4
    @State private var dietUseProfile = false
    @State private var dietKcal = ""
    @State private var dietProtein = ""
    @State private var dietCarbs = ""
    @State private var dietFat = ""
    @State private var profileAge = ""
    @State private var profileGender = "male"
    @State private var profileWeightLbs = ""
    @State private var profileHeightIn = ""
    @State private var profileActivity = "Moderately Active"
    @State private var dietSaveDirect = true
    @State private var genResult: JasperDietGenResult?
    @State private var sendingPreview = false

    // Log
    @State private var logKind: LogKind = .meal
    @State private var mealName = ""
    @State private var mealType = "lunch"
    @State private var mealKcal = ""
    @State private var mealProtein = ""
    @State private var mealCarbs = ""
    @State private var mealFat = ""
    @State private var waterML = 250

    // Card
    @State private var cardTitle = ""
    @State private var cardNote = ""

    @State private var sending = false
    @State private var errorMessage: String?
    @State private var receipt: Receipt?

    private struct Receipt {
        let summary: String
        let resource: String
        let id: UUID?
        var undone = false
    }

    var body: some View {
        ZStack {
            JasperBrand.stage(colorScheme).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                toolPicker
                ScrollView {
                    VStack(spacing: 12) {
                        switch tool {
                        case .program: programForm
                        case .diet: JasperNativeNutritionNotice()
                        case .log: logForm
                        case .card: cardForm
                        }
                        if let errorMessage { errorCard(errorMessage) }
                        if let receipt { receiptCard(receipt) }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .whisperPadContent(640)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                sendButton
            }
        }
        .presentationBackground(JasperBrand.stage(colorScheme))
        .presentationDragIndicator(.visible)
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 10) {
            JasperMarkTile(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Coach tools")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(JasperBrand.text(colorScheme))
                Text("Writes into @\(clientUsername)'s Jasper · undo anytime")
                    .font(.system(size: 10.5))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.65))
                    .frame(width: 32, height: 32)
                    .background(JasperBrand.chip(colorScheme), in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close coach tools")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var toolPicker: some View {
        HStack(spacing: 8) {
            ForEach(Tool.allCases) { item in
                chip(item.rawValue, icon: item.icon, selected: tool == item) {
                    tool = item
                    errorMessage = nil
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    // MARK: Forms

    private var programForm: some View {
        VStack(spacing: 12) {
            JasperGlowBox(cornerRadius: 18, glow: 0.5) {
                VStack(alignment: .leading, spacing: 12) {
                    glowField("Program name", text: $programName, placeholder: "8-week strength block")
                    VStack(alignment: .leading, spacing: 5) {
                        fieldLabel("Goal — Jasper's own vocabulary")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 6)],
                                  alignment: .leading, spacing: 6) {
                            ForEach(Self.programGoals, id: \.self) { goal in
                                chip(goal, small: true, selected: programGoal == goal) { programGoal = goal }
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        stepperField("Weeks", value: $programWeeks, range: 1...16)
                        stepperField("Days / week", value: $programDays, range: 1...7)
                    }
                    glowField("Overview", text: $programNotes, placeholder: "1-2 sentences — focus, progressions…")
                    marketplaceToggle
                    Text("Lands in @\(clientUsername)'s Jasper as a coach-assigned program under your handle — byte-exact to Jasper's published plan shape.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
                }
                .padding(14)
            }
            dayBuilder
        }
        .onChange(of: programDays) { _, newCount in syncDayDrafts(count: newCount) }
    }

    /// "Also publish to the marketplace" — the exact payload being assigned
    /// goes up as a public template too (plan_shapes-validated server-side).
    private var marketplaceToggle: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(duration: 0.25)) { publishToMarketplace.toggle() }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: publishToMarketplace ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(publishToMarketplace ? JasperBrand.ember : JasperBrand.text(colorScheme).opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Also publish to the marketplace")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(JasperBrand.text(colorScheme))
                    Text("Public template under your handle — same title updates in place, unpublish anytime")
                        .font(.system(size: 9.5))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "storefront")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(publishToMarketplace ? JasperBrand.ember : JasperBrand.text(colorScheme).opacity(0.3))
            }
            .padding(10)
            .background(publishToMarketplace
                        ? JasperBrand.ember.opacity(colorScheme == .dark ? 0.12 : 0.08)
                        : JasperBrand.chip(colorScheme).opacity(0.6),
                        in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: Day builder — plan_shapes `workoutDays`

    private var dayBuilder: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($dayDrafts) { $day in
                dayEditor($day)
            }
            Text("Days with at least one named exercise ship in Jasper's byte-exact plan shape — @\(clientUsername) gets day strips and the workout player with your coach badge on the card. Empty days are skipped.")
                .font(.system(size: 10.5))
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dayEditor(_ day: Binding<DayDraft>) -> some View {
        let index = dayDrafts.firstIndex(where: { $0.id == day.wrappedValue.id }) ?? 0
        return JasperGlowBox(cornerRadius: 18, glow: 0.4) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("DAY \(index + 1)")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(JasperBrand.ember)
                    TextField("", text: day.focus,
                              prompt: Text("Focus — Push · Pull · Legs…")
                                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.3)))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(JasperBrand.text(colorScheme))
                        .tint(JasperBrand.ember)
                }
                ForEach(day.exercises) { $exercise in
                    exerciseEditor($exercise, in: day)
                }
                Button {
                    Haptics.tap()
                    withAnimation(.spring(duration: 0.3)) {
                        day.wrappedValue.exercises.append(ExerciseDraft())
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("Add exercise")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(JasperBrand.ember)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(JasperBrand.ember.opacity(0.12), in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
        }
    }

    private func exerciseEditor(_ exercise: Binding<ExerciseDraft>, in day: Binding<DayDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("", text: exercise.name,
                          prompt: Text("Exercise — Bench Press…")
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.3)))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(JasperBrand.text(colorScheme))
                    .tint(JasperBrand.ember)
                Button {
                    Haptics.tap()
                    withAnimation(.spring(duration: 0.25)) {
                        day.wrappedValue.exercises.removeAll { $0.id == exercise.wrappedValue.id }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.45))
                        .frame(width: 24, height: 24)
                        .background(JasperBrand.chip(colorScheme), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove exercise")
            }
            HStack(alignment: .top, spacing: 12) {
                miniCounter("Sets", value: exercise.sets, range: 1...12)
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Reps")
                    TextField("", text: exercise.reps,
                              prompt: Text("8-10").foregroundStyle(JasperBrand.text(colorScheme).opacity(0.3)))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(JasperBrand.text(colorScheme))
                        .tint(JasperBrand.ember)
                        .padding(.horizontal, 10)
                        .frame(width: 76, height: 30)
                        .background(JasperBrand.chip(colorScheme), in: .rect(cornerRadius: 8))
                }
                miniCounter("Rest s", value: exercise.restSeconds, range: 0...600, step: 15)
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(JasperBrand.stage(colorScheme).opacity(colorScheme == .dark ? 0.5 : 0.6),
                    in: .rect(cornerRadius: 12))
    }

    private func miniCounter(_ title: String, value: Binding<Int>,
                             range: ClosedRange<Int>, step: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(title)
            HStack(spacing: 6) {
                stepButton("minus") { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) }
                Text("\(value.wrappedValue)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(JasperBrand.text(colorScheme))
                    .frame(minWidth: 26)
                    .contentTransition(.numericText())
                stepButton("plus") { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) }
            }
        }
    }

    private func syncDayDrafts(count: Int) {
        withAnimation(.spring(duration: 0.3)) {
            while dayDrafts.count < count { dayDrafts.append(DayDraft()) }
            while dayDrafts.count > count { dayDrafts.removeLast() }
        }
    }

    private var logForm: some View {
        VStack(spacing: 12) {
            JasperGlowBox(cornerRadius: 18, glow: 0.5) {
                HStack(spacing: 8) {
                    ForEach(LogKind.allCases, id: \.rawValue) { kind in
                        chip(kind.rawValue, selected: logKind == kind) { logKind = kind }
                    }
                    Spacer()
                }
                .padding(12)
            }
            if logKind == .meal { mealFields } else { waterFields }
        }
    }

    private var mealFields: some View {
        JasperGlowBox(cornerRadius: 18, glow: 0.5) {
            VStack(alignment: .leading, spacing: 12) {
                glowField("Meal name", text: $mealName, placeholder: "Post-workout bowl")
                VStack(alignment: .leading, spacing: 5) {
                    fieldLabel("Meal type")
                    HStack(spacing: 6) {
                        ForEach(["breakfast", "lunch", "dinner", "snack"], id: \.self) { type in
                            chip(type.capitalized, small: true, selected: mealType == type) { mealType = type }
                        }
                    }
                }
                HStack(spacing: 10) {
                    glowField("Calories", text: $mealKcal, placeholder: "650", keyboard: .numberPad)
                    glowField("Protein g", text: $mealProtein, placeholder: "45", keyboard: .decimalPad)
                }
                HStack(spacing: 10) {
                    glowField("Carbs g", text: $mealCarbs, placeholder: "60", keyboard: .decimalPad)
                    glowField("Fat g", text: $mealFat, placeholder: "18", keyboard: .decimalPad)
                }
            }
            .padding(14)
        }
    }

    private var waterFields: some View {
        JasperGlowBox(cornerRadius: 18, glow: 0.5) {
            VStack(alignment: .leading, spacing: 12) {
                fieldLabel("Amount")
                HStack(spacing: 6) {
                    ForEach([250, 500, 750, 1000], id: \.self) { ml in
                        chip("\(ml) ml", small: true, selected: waterML == ml) { waterML = ml }
                    }
                }
                HStack(spacing: 10) {
                    stepButton("minus") { if waterML > 50 { waterML -= 50 } }
                    Text("\(waterML) ml")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(JasperBrand.text(colorScheme))
                        .contentTransition(.numericText())
                        .frame(minWidth: 90)
                    stepButton("plus") { waterML += 50 }
                    Spacer()
                }
            }
            .padding(14)
        }
    }

    private var cardForm: some View {
        JasperGlowBox(cornerRadius: 18, glow: 0.5) {
            VStack(alignment: .leading, spacing: 12) {
                glowField("Card title", text: $cardTitle, placeholder: "Great week — keep the streak")
                glowField("Note", text: $cardNote, placeholder: "A few words your client sees in Jasper…")
                Text("Lands in @\(clientUsername)'s Jasper \"Shared with you\" inbox as a Whisper card.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
            }
            .padding(14)
        }
    }

    // MARK: Diet form — Jasper's generator, exposed

    private var dietForm: some View {
        VStack(spacing: 12) {
            if sending {
                // WHISPER_PLANS.md §4 — mandatory generate state: the glow box
                // breathes ember while Jasper cooks (15-60s), never a bare spinner.
                JasperGeneratingPlanCard(
                    status: "Jasper is composing @\(clientUsername)'s week — 15-60s…")
            }
            JasperGlowBox(cornerRadius: 18, glow: 0.5) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        fieldLabel("Goal — Jasper's diet vocabulary")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 6)],
                                  alignment: .leading, spacing: 6) {
                            ForEach(JasperDietGenRequest.goals, id: \.self) { goal in
                                chip(goal, small: true, selected: dietGoal == goal) { dietGoal = goal }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        fieldLabel("Dietary preference")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)],
                                  alignment: .leading, spacing: 6) {
                            ForEach(JasperDietGenRequest.preferences, id: \.self) { pref in
                                chip(pref, small: true, selected: dietPreference == pref) { dietPreference = pref }
                            }
                        }
                    }
                    glowField("Allergies — comma separated", text: $dietAllergies, placeholder: "peanuts, shellfish")
                    stepperField("Meals / day", value: $dietMealsPerDay, range: 2...6)
                }
                .padding(14)
            }
            JasperGlowBox(cornerRadius: 18, glow: 0.5) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        chip("Macro targets", small: true, selected: !dietUseProfile) { dietUseProfile = false }
                        chip("From a profile", small: true, selected: dietUseProfile) { dietUseProfile = true }
                        Spacer()
                    }
                    if dietUseProfile {
                        HStack(spacing: 10) {
                            glowField("Age", text: $profileAge, placeholder: "28", keyboard: .numberPad)
                            glowField("Weight lbs", text: $profileWeightLbs, placeholder: "185", keyboard: .decimalPad)
                            glowField("Height in", text: $profileHeightIn, placeholder: "71", keyboard: .decimalPad)
                        }
                        HStack(spacing: 6) {
                            ForEach(["male", "female"], id: \.self) { gender in
                                chip(gender.capitalized, small: true, selected: profileGender == gender) { profileGender = gender }
                            }
                            Spacer()
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Activity level")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 6)],
                                      alignment: .leading, spacing: 6) {
                                ForEach(JasperDietGenRequest.activityLevels, id: \.self) { level in
                                    chip(level, small: true, selected: profileActivity == level) { profileActivity = level }
                                }
                            }
                        }
                        Text("Mifflin-St Jeor computes the targets exactly like the app — the goal adjusts calories, protein lands at 1.8-2.2 g/kg.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: 10) {
                            glowField("Calories", text: $dietKcal, placeholder: "2400", keyboard: .numberPad)
                            glowField("Protein g", text: $dietProtein, placeholder: "180", keyboard: .numberPad)
                        }
                        HStack(spacing: 10) {
                            glowField("Carbs g", text: $dietCarbs, placeholder: "250", keyboard: .numberPad)
                            glowField("Fat g", text: $dietFat, placeholder: "70", keyboard: .numberPad)
                        }
                    }
                    dietSaveToggle
                    Text("Jasper's OWN generator (POST /v1/diet_plans/generate) writes a complete week — named days, meals with macros, the grocery checklist derived — that renders natively in @\(clientUsername)'s Jasper. Takes 15-60 seconds; the coach gate is verified before the model runs.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            }
            if let genResult { genPreviewCard(genResult) }
        }
    }

    /// save:true — one call writes the plan straight into the client's
    /// Jasper. Off = preview-first: show the generated week, then send.
    private var dietSaveToggle: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(duration: 0.25)) { dietSaveDirect.toggle() }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: dietSaveDirect ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(dietSaveDirect ? JasperBrand.ember : JasperBrand.text(colorScheme).opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Save straight to their Jasper")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(JasperBrand.text(colorScheme))
                    Text("One call — lands active with the grocery list live (fires diet_plan.updated). Off = preview here first.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(dietSaveDirect ? JasperBrand.ember : JasperBrand.text(colorScheme).opacity(0.3))
            }
            .padding(10)
            .background(dietSaveDirect
                        ? JasperBrand.ember.opacity(colorScheme == .dark ? 0.12 : 0.08)
                        : JasperBrand.chip(colorScheme).opacity(0.6),
                        in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// The generated week — NOT sent yet. Sending POSTs the byte-exact
    /// payload Jasper returned (plan_shapes verbatim).
    private func genPreviewCard(_ result: JasperDietGenResult) -> some View {
        JasperGlowBox(cornerRadius: 18, glow: 0.55) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(JasperBrand.ember)
                    Text("GENERATED — NOT SENT YET")
                        .font(.system(size: 9.5, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(JasperBrand.ember)
                    Spacer()
                }
                Text(result.planName)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(JasperBrand.text(colorScheme))
                HStack(spacing: 6) {
                    if let kcal = result.targetCalories { dietMiniChip("\(kcal) kcal") }
                    if let protein = result.targetProtein { dietMiniChip("P \(protein)g") }
                    if let carbs = result.targetCarbs { dietMiniChip("C \(carbs)g") }
                    if let fat = result.targetFat { dietMiniChip("F \(fat)g") }
                    if result.groceryItemCount > 0 { dietMiniChip("\(result.groceryItemCount) groceries") }
                }
                VStack(spacing: 0) {
                    ForEach(result.days) { day in
                        HStack(spacing: 8) {
                            Text(day.dayName)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(JasperBrand.text(colorScheme))
                            Spacer()
                            Text("\(day.meals.count) meals · \(day.kcal) kcal")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                        }
                        .padding(.vertical, 6)
                        if day.id != result.days.last?.id {
                            Rectangle()
                                .fill(JasperBrand.divider(colorScheme))
                                .frame(height: 0.7)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        Haptics.tap()
                        Task { await sendGeneratedPlan() }
                    } label: {
                        HStack(spacing: 6) {
                            if sendingPreview {
                                ProgressView().tint(JasperBrand.ink).controlSize(.mini)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(sendingPreview ? "Sending…" : "Send to @\(clientUsername)'s Jasper")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(JasperBrand.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(JasperBrand.emberGradient, in: .capsule)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(sendingPreview)
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(duration: 0.25)) { genResult = nil }
                    } label: {
                        Text("Discard")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(JasperBrand.chip(colorScheme), in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(14)
        }
    }

    private func dietMiniChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(JasperBrand.chip(colorScheme), in: .capsule)
    }

    /// POST /v1/diet_plans/generate through the coach-held client token.
    private func generateDiet() async {
        sending = true
        errorMessage = nil
        withAnimation(.spring(duration: 0.25)) { genResult = nil }
        defer { sending = false }
        let allergies = dietAllergies.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var request = JasperDietGenRequest(
            goal: dietGoal, dietaryPreference: dietPreference, allergies: allergies,
            mealsPerDay: dietMealsPerDay, targetCalories: nil, targetProtein: nil,
            targetCarbs: nil, targetFat: nil, profile: nil, save: dietSaveDirect)
        if dietUseProfile {
            request.profile = JasperDietGenRequest.Profile(
                age: Int(profileAge) ?? 28,
                gender: profileGender,
                weightLbs: Double(profileWeightLbs) ?? 170,
                heightInches: Double(profileHeightIn) ?? 70,
                activityLevel: profileActivity)
        } else {
            request.targetCalories = Int(dietKcal)
            request.targetProtein = Int(dietProtein)
            request.targetCarbs = Int(dietCarbs)
            request.targetFat = Int(dietFat)
        }
        do {
            let result = try await coachConnect.generateDietPlan(forClient: clientUID, request: request)
            Haptics.success()
            if result.saved {
                withAnimation(.spring(duration: 0.35)) {
                    receipt = Receipt(
                        summary: "\(result.planName) generated & saved to @\(clientUsername)'s Jasper — grocery list live, renders natively",
                        resource: "diet_plans",
                        id: result.clientID.flatMap(UUID.init(uuidString:)))
                }
            } else {
                withAnimation(.spring(duration: 0.35)) { genResult = result }
            }
        } catch {
            Haptics.warning()
            errorMessage = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Preview → send: POST /v1/diet_plans with the returned payload verbatim.
    private func sendGeneratedPlan() async {
        guard let result = genResult, !sendingPreview else { return }
        sendingPreview = true
        errorMessage = nil
        defer { sendingPreview = false }
        do {
            let response = try await coachConnect.write(forClient: clientUID,
                                                        resource: "diet_plans",
                                                        payload: result.postBody)
            Haptics.success()
            withAnimation(.spring(duration: 0.35)) {
                receipt = Receipt(
                    summary: "\(result.planName) → @\(clientUsername)'s Jasper — renders natively with the grocery list live",
                    resource: "diet_plans",
                    id: response.id ?? result.clientID.flatMap(UUID.init(uuidString:)))
                genResult = nil
            }
        } catch {
            Haptics.warning()
            errorMessage = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Result cards

    private func errorCard(_ message: String) -> some View {
        JasperGlowBox(cornerRadius: 16, glow: 0.4) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(JasperBrand.ember)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }

    private func receiptCard(_ receipt: Receipt) -> some View {
        JasperGlowBox(cornerRadius: 16, glow: 0.4) {
            HStack(spacing: 10) {
                Image(systemName: receipt.undone ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(receipt.undone
                                     ? JasperBrand.text(colorScheme).opacity(0.6)
                                     : Color(red: 0.36, green: 0.86, blue: 0.72))
                VStack(alignment: .leading, spacing: 2) {
                    Text(receipt.undone ? "Undone" : "Sent to Jasper")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(JasperBrand.text(colorScheme))
                    Text(receipt.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                        .lineLimit(2)
                }
                Spacer()
                if !receipt.undone, receipt.id != nil {
                    Button {
                        Haptics.tap()
                        Task { await undo() }
                    } label: {
                        Text("Undo")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(JasperBrand.ember)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(JasperBrand.ember.opacity(0.14), in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    // MARK: Send

    private var canSend: Bool {
        switch tool {
        case .program:
            return !programName.trimmingCharacters(in: .whitespaces).isEmpty
        case .diet:
            return false
        case .log:
            return logKind == .water
                ? waterML > 0
                : !mealName.trimmingCharacters(in: .whitespaces).isEmpty
        case .card:
            return !cardTitle.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var sendLabel: String {
        switch tool {
        case .program: return "Assign to @\(clientUsername)"
        case .diet: return "Native nutrition review required"
        case .log: return logKind == .meal ? "Log meal for @\(clientUsername)" : "Log water for @\(clientUsername)"
        case .card: return "Send to their Jasper inbox"
        }
    }

    private var sendButton: some View {
        Button {
            Haptics.tap()
            Task { await send() }
        } label: {
            HStack(spacing: 8) {
                if sending {
                    ProgressView().tint(JasperBrand.ink).controlSize(.small)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .bold))
                }
                Text(sending ? (tool == .diet ? "Jasper is generating (15-60s)…" : "Sending…") : sendLabel)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(JasperBrand.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(JasperBrand.emberGradient, in: .capsule)
            .opacity(canSend && !sending ? 1 : 0.45)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!canSend || sending)
        .shadow(color: JasperBrand.ember.opacity(canSend ? 0.3 : 0), radius: 16, y: 5)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func send() async {
        guard canSend, !sending else { return }
        if tool == .diet {
            await generateDiet()
            return
        }
        sending = true
        errorMessage = nil
        defer { sending = false }
        do {
            let (resource, payload, summary) = buildWrite()
            let response = try await coachConnect.write(forClient: clientUID,
                                                        resource: resource,
                                                        payload: payload)
            var summaryLine = summary
            if tool == .program, publishToMarketplace {
                // Publish the EXACT plan_shapes payload that was just
                // assigned — the marketplace validates it server-side.
                if let plan = payload["payload"] as? [String: Any] {
                    do {
                        _ = try await JasperMarketplace.shared.publish(
                            kind: "program",
                            title: (payload["name"] as? String) ?? programName,
                            summary: (payload["description"] as? String) ?? "Coach program authored in Whisper.",
                            goal: programGoal,
                            topLevel: ["goal": programGoal, "weeks": programWeeks, "days_per_week": programDays],
                            payload: plan)
                        summaryLine += " · published to the marketplace"
                    } catch {
                        errorMessage = "Assigned to @\(clientUsername), but the marketplace publish failed: \((error as? JasperConnectError)?.errorDescription ?? error.localizedDescription)"
                    }
                } else {
                    errorMessage = "Assigned — but publishing needs at least one day with a named exercise, so the marketplace copy was skipped."
                }
            }
            Haptics.success()
            withAnimation(.spring(duration: 0.35)) {
                receipt = Receipt(summary: summaryLine, resource: resource, id: response.id)
            }
            clearForm()
        } catch {
            Haptics.warning()
            errorMessage = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func buildWrite() -> (String, [String: Any], String) {
        let iso = ISO8601DateFormatter().string(from: Date())
        switch tool {
        case .program:
            // plan_shapes (GET /v1/catalog — authoritative): uuid string ids
            // (payload.id mirrors client_id so re-posts upsert), createdAt in
            // APPLE-epoch seconds as a number, reps ALWAYS a string, notes
            // present even when empty, goal from the fixed vocabulary,
            // source "coach" for the coach badge. Jasper's importer is
            // decode-or-skip — conforming payloads render natively (day
            // strips + workout player); malformed ones vanish silently.
            let trimmedName = programName.trimmingCharacters(in: .whitespaces)
            let overview = programNotes.trimmingCharacters(in: .whitespaces)
            let coachHandle = JasperConnectClient.shared.connection?.username
            let planID = UUID().uuidString.lowercased()
            let workoutDays: [[String: Any]] = dayDrafts.enumerated().compactMap { index, day in
                let exercises: [[String: Any]] = day.exercises.compactMap { draft in
                    let exerciseName = draft.name.trimmingCharacters(in: .whitespaces)
                    guard !exerciseName.isEmpty else { return nil }
                    let reps = draft.reps.trimmingCharacters(in: .whitespaces)
                    return [
                        "id": UUID().uuidString.lowercased(),
                        "name": exerciseName,
                        "sets": max(1, draft.sets),
                        "reps": reps.isEmpty ? "10" : reps,
                        "restSeconds": max(0, draft.restSeconds),
                        "notes": "",
                    ]
                }
                guard !exercises.isEmpty else { return nil }
                let focus = day.focus.trimmingCharacters(in: .whitespaces)
                return [
                    "id": UUID().uuidString.lowercased(),
                    "dayName": "Day \(index + 1)",
                    "focus": focus.isEmpty ? "Full body" : focus,
                    "exercises": exercises,
                ]
            }
            var payload: [String: Any] = [
                "client_id": planID,
                "name": trimmedName,
                "goal": programGoal,
                "weeks": programWeeks,
                "days_per_week": programDays,
                "source": "coach",
            ]
            if !overview.isEmpty { payload["description"] = overview }
            if let coachHandle { payload["coach_username"] = coachHandle }
            if !workoutDays.isEmpty {
                var plan: [String: Any] = [
                    "id": planID,
                    "title": trimmedName,
                    "overview": overview.isEmpty ? "Coach program assigned from Whisper." : overview,
                    "goal": programGoal,
                    "weeks": programWeeks,
                    "daysPerWeek": programDays,
                    "createdAt": Int(Date().timeIntervalSinceReferenceDate),
                    "source": "coach",
                    "workoutDays": workoutDays,
                ]
                if let coachHandle { plan["coachUsername"] = coachHandle }
                payload["payload"] = plan
            }
            let renderNote = workoutDays.isEmpty
                ? ""
                : " · renders natively in their workout player"
            return ("programs", payload, "\(trimmedName) → @\(clientUsername)'s programs\(renderNote)")
        case .diet:
            // Unreachable — send() routes .diet to generateDiet() before
            // buildWrite. Kept for switch exhaustiveness.
            return ("diet_plans", [:], "")
        case .log:
            if logKind == .water {
                return ("water",
                        ["amount_ml": waterML, "logged_at": iso],
                        "\(waterML) ml water logged for @\(clientUsername)")
            }
            var payload: [String: Any] = [
                "name": mealName.trimmingCharacters(in: .whitespaces),
                "meal_type": mealType,
                "logged_at": iso,
            ]
            if let kcal = Int(mealKcal) { payload["calories_kcal"] = kcal }
            if let protein = Double(mealProtein) { payload["protein_g"] = protein }
            if let carbs = Double(mealCarbs) { payload["carbs_g"] = carbs }
            if let fat = Double(mealFat) { payload["fat_g"] = fat }
            return ("meals", payload, "\(mealName) logged for @\(clientUsername)")
        case .card:
            var payload: [String: Any] = [
                "title": cardTitle.trimmingCharacters(in: .whitespaces),
                "kind": "card",
            ]
            if !cardNote.isEmpty { payload["note"] = cardNote }
            return ("charts", payload, "Card sent to @\(clientUsername)'s Jasper inbox")
        }
    }

    private func undo() async {
        guard let current = receipt, let id = current.id, !current.undone else { return }
        do {
            try await coachConnect.delete(forClient: clientUID,
                                          resource: current.resource,
                                          id: id.uuidString)
            Haptics.success()
            withAnimation(.spring(duration: 0.3)) { receipt?.undone = true }
        } catch {
            Haptics.warning()
            errorMessage = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func clearForm() {
        switch tool {
        case .diet:
            genResult = nil
        case .program:
            programName = ""
            programGoal = "General Fitness"
            programNotes = ""
            publishToMarketplace = false
            dayDrafts = (0..<max(1, programDays)).map { _ in DayDraft() }
        case .log:
            mealName = ""
            mealKcal = ""
            mealProtein = ""
            mealCarbs = ""
            mealFat = ""
        case .card:
            cardTitle = ""
            cardNote = ""
        }
    }

    // MARK: Field kit

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .heavy))
            .tracking(1.4)
            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
    }

    private func glowField(_ title: String, text: Binding<String>, placeholder: String,
                           keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel(title)
            TextField("", text: text,
                      prompt: Text(placeholder).foregroundStyle(JasperBrand.text(colorScheme).opacity(0.3)))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(JasperBrand.text(colorScheme))
                .tint(JasperBrand.ember)
                .keyboardType(keyboard)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(JasperBrand.chip(colorScheme), in: .rect(cornerRadius: 12))
        }
    }

    private func stepperField(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel(title)
            HStack(spacing: 10) {
                stepButton("minus") { if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1 } }
                Text("\(value.wrappedValue)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(JasperBrand.text(colorScheme))
                    .frame(minWidth: 28)
                    .contentTransition(.numericText())
                stepButton("plus") { if value.wrappedValue < range.upperBound { value.wrappedValue += 1 } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(duration: 0.25)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(JasperBrand.ember)
                .frame(width: 30, height: 30)
                .background(JasperBrand.chip(colorScheme), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }

    private func chip(_ label: String, icon: String? = nil, small: Bool = false,
                      selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(duration: 0.3)) { action() }
        } label: {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: small ? 9 : 10.5, weight: .bold))
                }
                Text(label)
                    .font(.system(size: small ? 11.5 : 12.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? JasperBrand.ink : JasperBrand.text(colorScheme).opacity(0.7))
            .padding(.horizontal, small ? 10 : 13)
            .padding(.vertical, small ? 6 : 7)
            .background {
                if selected {
                    Capsule().fill(JasperBrand.emberGradient)
                } else {
                    Capsule().fill(JasperBrand.chip(colorScheme))
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}
