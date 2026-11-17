import SwiftUI

// MARK: - Parsed plan_shapes program (render-only)

/// A `plan_shapes.programs` payload parsed for RENDERING only — the verbatim
/// payload dictionary always rides untouched next to this (WHISPER_PLANS.md §3:
/// "reps is a STRING — render it verbatim, never parse it").
struct JasperPlanShape {
    struct Exercise: Identifiable {
        let id = UUID()
        let name: String
        let sets: Int
        let reps: String
        let restSeconds: Int
    }

    struct Day: Identifiable {
        let id = UUID()
        let dayName: String
        let focus: String
        let exercises: [Exercise]
    }

    let title: String
    let overview: String
    let goal: String
    let days: [Day]

    var exerciseCount: Int { days.reduce(0) { $0 + $1.exercises.count } }
    var setCount: Int { days.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets } } }

    /// "{days} sessions · {exercises} exercises · {sets} sets" — §3 meta line.
    var metaLine: String {
        "\(days.count) session\(days.count == 1 ? "" : "s") · \(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s") · \(setCount) sets"
    }

    static func parse(_ payload: [String: Any], fallbackTitle: String = "", fallbackGoal: String = "") -> JasperPlanShape {
        let rawDays = (payload["workoutDays"] as? [[String: Any]])
            ?? (payload["days"] as? [[String: Any]])
            ?? []
        let days: [Day] = rawDays.map { day in
            let exercises = ((day["exercises"] as? [[String: Any]]) ?? []).map { ex -> Exercise in
                let reps: String
                if let s = ex["reps"] as? String { reps = s } else if let n = ex["reps"] as? NSNumber { reps = n.stringValue } else { reps = "—" }
                return Exercise(name: (ex["name"] as? String) ?? "Exercise",
                                sets: (ex["sets"] as? NSNumber)?.intValue ?? 3,
                                reps: reps,
                                restSeconds: (ex["restSeconds"] as? NSNumber)?.intValue
                                    ?? (ex["rest_seconds"] as? NSNumber)?.intValue ?? 0)
            }
            let name = (day["dayName"] as? String) ?? (day["name"] as? String) ?? "Day"
            let week = (day["weekNumber"] as? Int).flatMap { $0 > 0 ? "Week \($0)" : nil }
            return Day(dayName: [week, name].compactMap { $0 }.joined(separator: " · "),
                       focus: (day["focus"] as? String) ?? "",
                       exercises: exercises)
        }
        return JasperPlanShape(
            title: (payload["title"] as? String) ?? (payload["name"] as? String) ?? fallbackTitle,
            overview: (payload["overview"] as? String) ?? (payload["summary"] as? String) ?? "",
            goal: (payload["goal"] as? String) ?? fallbackGoal,
            days: days)
    }
}

// MARK: - Shared atoms

/// 25pt numbered circle filled with the ember gradient — §3 day rows.
struct JasperEmberDayDot: View {
    let index: Int
    var size: CGFloat = 25

    var body: some View {
        Text("\(index)")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(JasperBrand.emberGradient, in: .circle)
    }
}

/// Context chip — §3.3: icon + caption.bold on ember @ 0.10 light / 0.16 dark,
/// hairline ember @ 0.24 at 0.7pt.
struct JasperContextChip: View {
    var icon: String? = nil
    let label: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(label)
                .font(.caption.bold())
                .lineLimit(1)
        }
        .foregroundStyle(colorScheme == .dark ? JasperBrand.ember : JasperBrand.emberDeep)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(JasperBrand.ember.opacity(colorScheme == .dark ? 0.16 : 0.10), in: .capsule)
        .overlay { Capsule().strokeBorder(JasperBrand.ember.opacity(0.24), lineWidth: 0.7) }
    }
}

/// Teal "Saved"/state chip — §3.1: checkmark.seal.fill + caption.bold on
/// teal @ 0.13.
struct JasperSavedChip: View {
    var label: String = "Saved"
    var icon: String = "checkmark.seal.fill"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.caption.bold())
        }
        .foregroundStyle(JasperBrand.teal)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(JasperBrand.teal.opacity(0.13), in: .capsule)
    }
}

/// The 4 macro stat tiles — §4.2, canonical colors: kcal ember · protein teal ·
/// carbs amber · fat blue. Tile: macro @ 0.10 light / 0.16 dark, radius 14,
/// hairline macro @ 0.22.
struct JasperMacroTileRow: View {
    let kcal: Int?
    let protein: Int?
    let carbs: Int?
    let fat: Int?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            tile(kcal.map { "\($0)" } ?? "—", "kcal", JasperBrand.macroKcal)
            tile(protein.map { "\($0)" } ?? "—", "Protein", JasperBrand.macroProtein)
            tile(carbs.map { "\($0)" } ?? "—", "Carbs", JasperBrand.macroCarbs)
            tile(fat.map { "\($0)" } ?? "—", "Fat", JasperBrand.macroFat)
        }
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(colorScheme == .dark ? 0.16 : 0.10), in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.22), lineWidth: 1) }
    }
}

/// Primary plan action — full-width ember-gradient capsule, §3.5.
struct JasperEmberCapsuleButton: View {
    let label: String
    var icon: String? = nil
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 7) {
                if busy {
                    ProgressView().controlSize(.small).tint(.white)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.footnote.weight(.bold))
                }
                Text(label)
                    .font(.subheadline.bold())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(JasperBrand.emberGradient, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

/// 44pt quiet circle button beside the primary capsule — §3.5.
struct JasperPlanCircleButton: View {
    let icon: String
    var busy: Bool = false
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Group {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(JasperBrand.text(colorScheme))
            .frame(width: 44, height: 44)
            .background(colorScheme == .dark ? Color.white.opacity(0.10) : JasperBrand.ink.opacity(0.06), in: .circle)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

// MARK: - Workout program glow card (§3)

/// The workout plan API, rendered — WHISPER_PLANS.md §3 card anatomy, top to
/// bottom: glow icon + WORKOUT PLAN kicker header, overview inset, context
/// chips, WEEKLY STRUCTURE day rows (≤4, ember day dots), action row.
struct JasperWorkoutPlanGlowCard: View {
    let plan: JasperPlanShape
    var glow: Double = 1
    var live: Bool = false
    var saved: Bool = false
    var chips: [String] = []
    var primaryLabel: String = "View program"
    var onPrimary: (() -> Void)? = nil
    var publishState: JasperPlanPublishState = .hidden
    var onPublish: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var textColor: Color { JasperBrand.text(colorScheme) }

    var body: some View {
        JasperGlowBox(cornerRadius: 22, glow: glow) {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !plan.overview.isEmpty { overviewInset }
                if !chips.isEmpty { chipsRow }
                weeklyStructure
                actions
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            EmberGlowIcon(systemName: "figure.strengthtraining.traditional")
            VStack(alignment: .leading, spacing: 3) {
                JasperKicker(text: "Workout plan")
                Text(plan.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(textColor)
                    .lineLimit(2)
                Text(plan.metaLine)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(textColor.opacity(0.58))
            }
            Spacer(minLength: 0)
            if saved {
                JasperSavedChip()
            } else if live {
                JasperSavedChip(label: "Live", icon: "bolt.fill")
            }
        }
    }

    private var overviewInset: some View {
        Text(plan.overview)
            .font(.subheadline)
            .foregroundStyle(textColor.opacity(0.74))
            .fixedSize(horizontal: false, vertical: true)
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JasperBrand.inset(colorScheme), in: .rect(cornerRadius: 16))
    }

    private var chipsRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    JasperContextChip(label: chip)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    @ViewBuilder
    private var weeklyStructure: some View {
        if !plan.days.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                JasperKicker(text: "Weekly structure", secondary: true)
                ForEach(Array(plan.days.prefix(4).enumerated()), id: \.element.id) { index, day in
                    dayRow(index: index + 1, day: day)
                }
                if plan.days.count > 4 {
                    Text("+ \(plan.days.count - 4) more session\(plan.days.count - 4 == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JasperBrand.kicker(colorScheme))
                }
            }
        }
    }

    private func dayRow(index: Int, day: JasperPlanShape.Day) -> some View {
        HStack(alignment: .top, spacing: 10) {
            JasperEmberDayDot(index: index)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.dayName)
                    .font(.subheadline.bold())
                    .foregroundStyle(textColor)
                if !day.focus.isEmpty {
                    Text(day.focus)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(textColor.opacity(0.55))
                }
                if !day.exercises.isEmpty {
                    Text(day.exercises.prefix(3).map(\.name).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(textColor.opacity(0.58))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JasperBrand.insetRow(colorScheme), in: .rect(cornerRadius: 15))
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let onPrimary {
                    JasperEmberCapsuleButton(label: primaryLabel, action: onPrimary)
                }
                if case .publishable(let busy) = publishState, let onPublish {
                    JasperPlanCircleButton(icon: "storefront.fill", busy: busy, action: onPublish)
                }
                if let onEdit {
                    JasperPlanCircleButton(icon: "slider.horizontal.3", action: onEdit)
                }
            }
            if case .published = publishState {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                    Text("On the marketplace — re-publishing updates in place")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(JasperBrand.teal)
            }
        }
    }
}

/// Marketplace-publish affordance state for plan glow cards.
enum JasperPlanPublishState: Equatable {
    case hidden
    case publishable(busy: Bool)
    case published
}

// MARK: - Diet plan glow card (§4, studio row form)

/// Diet plan rendered as the §4 glow card: fork.knife glow icon, DIET PLAN
/// kicker, macro target tiles in the canonical colors, actions.
struct JasperDietPlanGlowCard: View {
    let name: String
    let metaLine: String
    var attribution: String? = nil
    var kcal: Int? = nil
    var protein: Int? = nil
    var carbs: Int? = nil
    var fat: Int? = nil
    var glow: Double = 1
    var live: Bool = false
    var groceryCount: Int = 0
    var primaryLabel: String = "View plan"
    var onPrimary: (() -> Void)? = nil
    var publishState: JasperPlanPublishState = .hidden
    var onPublish: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var textColor: Color { JasperBrand.text(colorScheme) }

    var body: some View {
        JasperGlowBox(cornerRadius: 22, glow: glow) {
            VStack(alignment: .leading, spacing: 16) {
                header
                if kcal != nil || protein != nil || carbs != nil || fat != nil {
                    JasperMacroTileRow(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
                }
                actions
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            EmberGlowIcon(systemName: "fork.knife")
            VStack(alignment: .leading, spacing: 3) {
                JasperKicker(text: "Diet plan")
                Text(name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(textColor)
                    .lineLimit(2)
                Text(metaLine)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(textColor.opacity(0.58))
                if let attribution {
                    Text(attribution)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JasperBrand.bronze)
                }
            }
            Spacer(minLength: 0)
            if live { JasperSavedChip(label: "Live", icon: "bolt.fill") }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let onPrimary {
                    JasperEmberCapsuleButton(label: primaryLabel, action: onPrimary)
                }
                if case .publishable(let busy) = publishState, let onPublish {
                    JasperPlanCircleButton(icon: "storefront.fill", busy: busy, action: onPublish)
                }
            }
            if groceryCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(groceryCount) grocery items ride this plan — shared with Jasper")
                        .font(.caption)
                }
                .foregroundStyle(textColor.opacity(0.55))
            }
            if case .published = publishState {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                    Text("On the marketplace — re-publishing updates in place")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(JasperBrand.teal)
            }
        }
    }
}

// MARK: - Program detail (§3 detail surface)

/// §3 detail surface: each day is its own glow box (glow 0.5) with the
/// numbered ember dot, exercise rows carrying "{sets} × {reps}" verbatim in
/// the kicker color plus a rest chip, and an optional pinned bottom CTA.
struct JasperProgramDetailSheet: View {
    let plan: JasperPlanShape
    var ctaLabel: String? = nil
    var ctaBusy: Bool = false
    var ctaDone: Bool = false
    var onCTA: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var textColor: Color { JasperBrand.text(colorScheme) }

    var body: some View {
        ZStack {
            JasperGlowStage()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    Text("Saved plan · cloud storage does not confirm native validation or an active schedule. Review in Jasper before using this plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !plan.overview.isEmpty {
                        Text(plan.overview)
                            .font(.subheadline)
                            .foregroundStyle(textColor.opacity(0.74))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(JasperBrand.inset(colorScheme), in: .rect(cornerRadius: 16))
                    }
                    ForEach(Array(plan.days.enumerated()), id: \.element.id) { index, day in
                        dayBox(index: index + 1, day: day)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 110)
                .whisperPadContent(640)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            if let ctaLabel, let onCTA {
                ctaBar(label: ctaLabel, action: onCTA)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(textColor.opacity(0.65))
                    .frame(width: 34, height: 34)
                    .background(JasperBrand.chip(colorScheme), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            .padding(.top, 14)
            .accessibilityLabel("Close program")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            EmberGlowIcon(systemName: "figure.strengthtraining.traditional", size: 44)
            VStack(alignment: .leading, spacing: 3) {
                JasperKicker(text: plan.goal.isEmpty ? "Workout plan" : plan.goal)
                Text(plan.title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                Text(plan.metaLine)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(textColor.opacity(0.58))
            }
            Spacer(minLength: 30)
        }
    }

    private func dayBox(index: Int, day: JasperPlanShape.Day) -> some View {
        JasperGlowBox(cornerRadius: 22, glow: 0.5) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    JasperEmberDayDot(index: index)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(day.dayName)
                            .font(.subheadline.bold())
                            .foregroundStyle(textColor)
                        if !day.focus.isEmpty {
                            Text(day.focus)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(textColor.opacity(0.55))
                        }
                    }
                    Spacer(minLength: 0)
                }
                ForEach(day.exercises) { ex in
                    exerciseRow(ex)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func exerciseRow(_ ex: JasperPlanShape.Exercise) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ex.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(textColor)
                .lineLimit(2)
            Spacer(minLength: 6)
            Text("\(ex.sets) × \(ex.reps)")
                .font(.subheadline.bold())
                .foregroundStyle(JasperBrand.kicker(colorScheme))
            if ex.restSeconds > 0 {
                Text("\(ex.restSeconds)s rest")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(textColor.opacity(0.6))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(JasperBrand.ink.opacity(colorScheme == .dark ? 0.3 : 0.05), in: .capsule)
            }
        }
    }

    private func ctaBar(label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if ctaBusy {
                    ProgressView().controlSize(.small).tint(.white)
                } else if ctaDone {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.headline)
                }
                Text(ctaDone ? "Saved to Jasper" : label)
                    .font(.headline.weight(.heavy))
            }
            .foregroundStyle(ctaDone ? JasperBrand.teal : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background {
                if ctaDone {
                    Capsule().fill(JasperBrand.teal.opacity(0.13))
                } else {
                    Capsule().fill(JasperBrand.emberGradient)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(ctaBusy || ctaDone)
        .shadow(color: JasperBrand.emberDeep.opacity(ctaDone ? 0 : 0.30), radius: 18, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .whisperPadContent(640)
    }
}

// MARK: - Generate loading state (§4, mandatory)

/// The mandatory `/v1/diet_plans/generate` loading state: the glow box renders
/// immediately as a skeleton and the aura BREATHES (glow 0.5 ↔ 1.0,
/// easeInOut 1.4s, forever) while Jasper cooks — never a bare spinner.
struct JasperGeneratingPlanCard: View {
    var status: String = "Jasper is composing your week…"
    var icon: String = "fork.knife"

    @Environment(\.colorScheme) private var colorScheme
    @State private var shimmer = false

    var body: some View {
        JasperGlowBox(cornerRadius: 22, glow: 0.5, breathing: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    EmberGlowIcon(systemName: icon)
                    VStack(alignment: .leading, spacing: 6) {
                        shimmerBar(widthFraction: 0.42, height: 10)
                        shimmerBar(widthFraction: 0.68, height: 14)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    shimmerBar(widthFraction: 0.70, height: 12)
                    shimmerBar(widthFraction: 0.55, height: 12)
                    shimmerBar(widthFraction: 0.63, height: 12)
                }
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }

    private func shimmerBar(widthFraction: CGFloat, height: CGFloat) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(JasperBrand.inset(colorScheme))
                .frame(width: proxy.size.width * widthFraction, height: height)
                .opacity(shimmer ? 0.45 : 1)
        }
        .frame(height: height)
    }
}
