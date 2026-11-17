import SwiftUI
import Charts

/// Parses + renders the fenced output blocks the shared Jasper brain appends
/// to a reply. The grammar is server-owned and guaranteed identical to
/// Whisper's (same prompt), so Whisper just decodes and renders native cards:
///   - ```chart    → an interactive chart
///   - ```goalplan → a dated, trackable goal card
///   - ```schedule → the user's schedule (rules + conditions)
///
/// `parse(_:)` splits a raw reply into the visible prose (block stripped out)
/// plus the decoded block, so the chat bubble shows clean text with the card
/// rendered beneath it.
nonisolated enum WhisperEmberBlocks {

    // MARK: - Parsed result

    nonisolated enum Block: Sendable, Hashable {
        case chart(Chart)
        case goalplan(GoalPlan)
        case schedule(Schedule)
        case postdraft(PostDraft)
        case profilecard(ProfileCard)
        case jasper(JasperLook)
    }

    nonisolated struct Parsed: Sendable {
        /// Reply prose with the fenced block removed (trimmed).
        let text: String
        /// The decoded trailing block, if the reply ended in one.
        let block: Block?
    }

    /// Strips a trailing ```chart/```goalplan/```schedule fence out of a reply
    /// and decodes it. Tolerant of the fence appearing anywhere; the prose is
    /// whatever's left after removing the matched block.
    static func parse(_ reply: String) -> Parsed {
        for kind in ["jasper", "chart", "goalplan", "schedule", "postdraft", "profilecard"] {
            guard let (range, json) = fencedBody(in: reply, kind: kind) else { continue }
            let stripped = reply.replacingCharacters(in: range, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = json.data(using: .utf8) else { continue }
            switch kind {
            case "jasper":
                if let j = try? JSONDecoder().decode(JasperLook.self, from: data) {
                    return Parsed(text: stripped, block: .jasper(j))
                }
            case "chart":
                if let c = try? JSONDecoder().decode(Chart.self, from: data) {
                    return Parsed(text: stripped, block: .chart(c))
                }
            case "goalplan":
                if let g = try? JSONDecoder().decode(GoalPlan.self, from: data) {
                    return Parsed(text: stripped, block: .goalplan(g))
                }
            case "schedule":
                if let s = try? JSONDecoder().decode(Schedule.self, from: data) {
                    return Parsed(text: stripped, block: .schedule(s))
                }
            case "postdraft":
                if let d = try? JSONDecoder().decode(PostDraft.self, from: data) {
                    return Parsed(text: stripped, block: .postdraft(d))
                }
            case "profilecard":
                if let c = try? JSONDecoder().decode(ProfileCard.self, from: data) {
                    return Parsed(text: stripped, block: .profilecard(c))
                }
            default:
                break
            }
        }
        return Parsed(text: reply.trimmingCharacters(in: .whitespacesAndNewlines), block: nil)
    }

    /// Finds a ```<kind> … ``` fence and returns the full range (so it can be
    /// removed) plus the inner JSON string.
    private static func fencedBody(in text: String, kind: String) -> (Range<String.Index>, String)? {
        let open = "```\(kind)"
        guard let openRange = text.range(of: open, options: .caseInsensitive) else { return nil }
        guard let closeRange = text.range(of: "```", range: openRange.upperBound..<text.endIndex) else { return nil }
        let inner = String(text[openRange.upperBound..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (openRange.lowerBound..<closeRange.upperBound, inner)
    }

    // MARK: - jasper (native live data card)

    /// The ```jasper fence — asks the client to render a LIVE native Jasper
    /// data card (vitality blob, recovery ring, hypnogram, water cup, blood
    /// panel) pulled from the Connect API at render time. `client` names an
    /// accepted coaching client; omitted → the user's own data.
    nonisolated struct JasperLook: Codable, Sendable, Hashable {
        let kind: String
        let client: String?

        var normalizedKind: String {
            kind.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - chart

    nonisolated struct Chart: Codable, Sendable, Hashable {
        let type: String          // line | bar | area | point
        let title: String?
        let unit: String?
        let goal: Double?
        let data: [Point]?        // single-metric
        let series: [Series]?     // multi-metric

        nonisolated struct Point: Codable, Sendable, Hashable {
            let x: String
            let y: Double

            init(x: String, y: Double) {
                self.x = x
                self.y = y
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                // x may arrive as a string or a number — coerce to a label.
                if let s = (try? c.decodeIfPresent(String.self, forKey: .x)) ?? nil {
                    self.x = s
                } else if let d = (try? c.decodeIfPresent(Double.self, forKey: .x)) ?? nil {
                    self.x = d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(d)
                } else {
                    self.x = ""
                }
                if let d = (try? c.decodeIfPresent(Double.self, forKey: .y)) ?? nil {
                    self.y = d
                } else if let s = (try? c.decodeIfPresent(String.self, forKey: .y)) ?? nil, let d = Double(s) {
                    self.y = d
                } else {
                    self.y = 0
                }
            }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(x, forKey: .x)
                try c.encode(y, forKey: .y)
            }
            enum CodingKeys: String, CodingKey { case x, y }
        }

        nonisolated struct Series: Codable, Sendable, Hashable {
            let name: String?
            let data: [Point]

            init(name: String?, data: [Point]) {
                self.name = name
                self.data = data
            }
        }

        init(
            type: String,
            title: String?,
            unit: String?,
            goal: Double?,
            data: [Point]?,
            series: [Series]?
        ) {
            self.type = type
            self.title = title
            self.unit = unit
            self.goal = goal
            self.data = data
            self.series = series
        }

        /// Flattened list of (seriesName?, points) for rendering.
        var renderSeries: [(name: String?, points: [Point])] {
            if let series, !series.isEmpty {
                return series.map { ($0.name, $0.data) }
            }
            return [(nil, data ?? [])]
        }
    }

    // MARK: - goalplan

    nonisolated struct GoalPlan: Codable, Sendable, Hashable, Identifiable {
        var id: String { (title ?? "") + (targetDate ?? "") }
        let title: String?
        let goal: String?
        let category: String?
        let summary: String?
        let targetDate: String?
        let metricLabel: String?
        let startValue: Double?
        let targetValue: Double?
        let weeklyFocus: [String]?
        let milestones: [Milestone]?

        nonisolated struct Milestone: Codable, Sendable, Hashable {
            let label: String?
            let date: String?
            let value: Double?

            init(from decoder: Decoder) throws {
                // Milestones come back as either an object or a bare string.
                if let single = try? decoder.singleValueContainer(),
                   let str = try? single.decode(String.self) {
                    self.label = str; self.date = nil; self.value = nil
                    return
                }
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.label = try? c.decodeIfPresent(String.self, forKey: .label)
                self.date = try? c.decodeIfPresent(String.self, forKey: .date)
                self.value = try? c.decodeIfPresent(Double.self, forKey: .value)
            }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeIfPresent(label, forKey: .label)
                try c.encodeIfPresent(date, forKey: .date)
                try c.encodeIfPresent(value, forKey: .value)
            }
            enum CodingKeys: String, CodingKey { case label, date, value }
        }
    }

    // MARK: - schedule

    nonisolated struct Schedule: Codable, Sendable, Hashable {
        let rules: [FlexString]?
        let conditions: [FlexString]?
    }

    // MARK: - postdraft

    nonisolated struct PostDraft: Codable, Sendable, Hashable {
        let caption: String?
        let hashtags: [String]?
        let community: String?
        let bestTime: String?
        let mediaIdea: String?
    }

    // MARK: - profilecard

    nonisolated struct ProfileCard: Codable, Sendable, Hashable {
        let title: String?
        let bio: String?
        let pinnedIdea: String?
        let tips: [String]?
    }

    /// Decodes a schedule entry that may be a plain string or a `{label/text}`
    /// object, so we render whichever shape Jasper emits.
    nonisolated struct FlexString: Codable, Sendable, Hashable, Identifiable {
        let value: String
        var id: String { value }

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(),
               let str = try? single.decode(String.self) {
                self.value = str
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.value = (try? c.decodeIfPresent(String.self, forKey: .label))
                ?? (try? c.decodeIfPresent(String.self, forKey: .text))
                ?? (try? c.decodeIfPresent(String.self, forKey: .rule))
                ?? ""
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(value)
        }
        enum CodingKeys: String, CodingKey { case label, text, rule }
    }

}

// MARK: - Block card (router)

struct WhisperEmberBlockCard: View {
    let block: WhisperEmberBlocks.Block

    var body: some View {
        switch block {
        case .chart(let chart):         WhisperEmberChartCard(chart: chart)
        case .goalplan(let plan):       WhisperEmberGoalPlanCard(plan: plan)
        case .schedule(let sched):      WhisperEmberScheduleCard(schedule: sched)
        case .postdraft(let draft):     WhisperEmberPostDraftCard(draft: draft)
        case .profilecard(let card):    WhisperEmberProfileCardView(card: card)
        case .jasper(let look):         WhisperEmberJasperLookCard(request: look)
        }
    }
}

// MARK: - Chart card

struct WhisperEmberChartCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let chart: WhisperEmberBlocks.Chart

    /// X label the user is scrubbing to (drag-to-read). Whisper plots in pure
    /// ink; multiple series step down through ink opacities instead of hues.
    @State private var selectedX: String?

    /// Jasper-inbox preview + post state — shown only while Connect is live.
    @State private var showJasperPreview: Bool = false
    @State private var jasperPostState: JasperPostState = .idle
    @State private var jasperPostError: String?

    private enum JasperPostState: Equatable { case idle, posting, sent, failed }

    private func tint(_ idx: Int) -> Color {
        let opacities: [Double] = [1.0, 0.55, 0.32, 0.78, 0.42]
        return WhisperTheme.ink(colorScheme).opacity(opacities[idx % opacities.count])
    }

    /// The value(s) at the scrubbed x position, for the readout pill.
    private var selectedReadout: String? {
        guard let selectedX else { return nil }
        let parts: [String] = chart.renderSeries.compactMap { entry in
            guard let p = entry.points.first(where: { $0.x == selectedX }) else { return nil }
            let name = entry.name.map { "\($0): " } ?? ""
            return "\(name)\(formatted(p.y))"
        }
        guard !parts.isEmpty else { return nil }
        return "\(selectedX) · " + parts.joined(separator: "  ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(width: 28, height: 28)
                    .background(WhisperTheme.ink(colorScheme), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text((chart.title ?? "Chart").uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .opacity(0.7)
                    if let unit = chart.unit, !unit.isEmpty {
                        Text(unit)
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
                Spacer(minLength: 0)
                if let readout = selectedReadout {
                    Text(readout)
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(WhisperTheme.surface(colorScheme), in: Capsule())
                        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Chart {
                ForEach(Array(chart.renderSeries.enumerated()), id: \.offset) { idx, entry in
                    let seriesTint = tint(idx)
                    ForEach(Array(entry.points.enumerated()), id: \.offset) { _, p in
                        mark(p, tint: seriesTint)
                    }
                }
                if let selectedX {
                    RuleMark(x: .value("x", selectedX))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.35))
                }
                if let goal = chart.goal {
                    RuleMark(y: .value("Goal", goal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("goal \(formatted(goal))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel().font(.caption2)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.caption2)
                }
            }
            .chartXSelection(value: $selectedX)
            .frame(height: 150)
            .animation(.spring(response: 0.25), value: selectedX)

            if chart.renderSeries.count > 1 {
                HStack(spacing: 12) {
                    ForEach(Array(chart.renderSeries.enumerated()), id: \.offset) { idx, entry in
                        if let name = entry.name {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(tint(idx))
                                    .frame(width: 8, height: 8)
                                Text(name)
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                    }
                }
            }

            if JasperConnectClient.shared.connection != nil, !previewValues.isEmpty {
                jasperInboxSection
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    @ChartContentBuilder
    private func mark(_ p: WhisperEmberBlocks.Chart.Point, tint: Color) -> some ChartContent {
        switch chart.type.lowercased() {
        case "bar":
            BarMark(x: .value("x", p.x), y: .value("y", p.y))
                .foregroundStyle(tint.gradient)
                .cornerRadius(4)
        case "area":
            AreaMark(x: .value("x", p.x), y: .value("y", p.y))
                .foregroundStyle(tint.opacity(0.25).gradient)
            LineMark(x: .value("x", p.x), y: .value("y", p.y))
                .foregroundStyle(tint)
        case "point":
            PointMark(x: .value("x", p.x), y: .value("y", p.y))
                .foregroundStyle(tint)
        default: // line
            LineMark(x: .value("x", p.x), y: .value("y", p.y))
                .foregroundStyle(tint)
                .interpolationMethod(.catmullRom)
            PointMark(x: .value("x", p.x), y: .value("y", p.y))
                .foregroundStyle(tint)
                .symbolSize(22)
        }
    }

    private func formatted(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.1fk", v / 1000) }
        if v.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(v))" }
        return String(format: "%.1f", v)
    }

    // MARK: Jasper Shared-inbox preview + post

    private var previewValues: [Double] {
        Array((chart.renderSeries.first?.points.map(\.y) ?? []).suffix(24))
    }

    private var previewLabels: [String]? {
        guard let points = chart.renderSeries.first?.points, !points.isEmpty else { return nil }
        return Array(points.map(\.x).suffix(24))
    }

    /// Flip the chart into EXACTLY how it will land in Jasper's Shared inbox
    /// (the `charts` look: ember gradient on cream), then post it for real.
    @ViewBuilder
    private var jasperInboxSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    showJasperPreview.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(showJasperPreview ? "Hide Jasper preview" : "Preview in Jasper")
                        .font(.caption.weight(.bold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(showJasperPreview ? 180 : 0))
                }
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .buttonStyle(.plain)

            if showJasperPreview {
                JasperInboxCardPreview(
                    title: chart.title ?? "Chart",
                    values: previewValues,
                    labels: previewLabels,
                    type: chart.type,
                    unit: chart.unit,
                    note: nil,
                    kind: "chart"
                )
                .transition(.scale(scale: 0.96).combined(with: .opacity))

                Text("Exactly how this lands in Jasper's Shared inbox.")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))

                Button {
                    guard jasperPostState == .idle || jasperPostState == .failed else { return }
                    Haptics.tap()
                    postToJasper()
                } label: {
                    HStack(spacing: 6) {
                        switch jasperPostState {
                        case .posting:
                            ProgressView()
                                .controlSize(.mini)
                                .tint(WhisperTheme.surface(colorScheme))
                        case .sent:
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                        case .failed:
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.bold))
                        case .idle:
                            Image(systemName: "paperplane.fill")
                                .font(.caption.weight(.bold))
                        }
                        Text(jasperPostLabel)
                            .font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                }
                .buttonStyle(.plain)
                .disabled(jasperPostState == .posting || jasperPostState == .sent)

                if let jasperPostError {
                    Text(jasperPostError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.top, 2)
    }

    private var jasperPostLabel: String {
        switch jasperPostState {
        case .idle: return "Send to Jasper inbox"
        case .posting: return "Sending…"
        case .sent: return "In your Jasper inbox"
        case .failed: return "Try again"
        }
    }

    private func postToJasper() {
        jasperPostState = .posting
        jasperPostError = nil
        let values = previewValues
        let labels = previewLabels
        let title = chart.title ?? "Chart"
        let type = chart.type
        let unit = chart.unit
        Task {
            do {
                _ = try await JasperConnectClient.shared.postChart(
                    title: title,
                    chart: JasperConnectClient.chartObject(type: type, unit: unit,
                                                           values: values, labels: labels)
                )
                withAnimation(.spring(response: 0.3)) { jasperPostState = .sent }
                Haptics.success()
            } catch {
                withAnimation(.spring(response: 0.3)) { jasperPostState = .failed }
                jasperPostError = (error as? JasperConnectError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}

// MARK: - Goal plan card

struct WhisperEmberGoalPlanCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let plan: WhisperEmberBlocks.GoalPlan

    @State private var saved: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.green, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("GOAL PLAN")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .opacity(0.7)
                    if let cat = plan.category, !cat.isEmpty {
                        Text(cat)
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
                Spacer(minLength: 0)
                if let date = plan.targetDate, !date.isEmpty {
                    Text(date)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(WhisperTheme.surface(colorScheme), in: Capsule())
                }
            }

            if let title = plan.title, !title.isEmpty {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            if let summary = plan.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let start = plan.startValue, let target = plan.targetValue {
                progress(start: start, target: target)
            }

            if let focus = plan.weeklyFocus, !focus.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly focus")
                        .font(.caption.weight(.heavy))
                        .opacity(0.7)
                    ForEach(focus.prefix(6), id: \.self) { f in
                        Label(f, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                }
            }

            if let milestones = plan.milestones, !milestones.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Milestones")
                        .font(.caption.weight(.heavy))
                        .opacity(0.7)
                    ForEach(Array(milestones.enumerated()), id: \.offset) { _, m in
                        HStack(spacing: 6) {
                            Image(systemName: "flag.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.green)
                            Text(milestoneLabel(m))
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                        }
                    }
                }
            }

            Button {
                Haptics.success()
                WhisperEmberGoalStore.shared.save(plan)
                withAnimation(.spring(response: 0.3)) { saved = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: saved ? "checkmark" : "plus")
                        .font(.caption.weight(.bold))
                    Text(saved ? "Saved to your goals" : "Track this goal")
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(saved ? Color.green.opacity(0.18) : Color.green, in: Capsule())
                .foregroundStyle(saved ? Color.green : .white)
            }
            .buttonStyle(.plain)
            .disabled(saved)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func milestoneLabel(_ m: WhisperEmberBlocks.GoalPlan.Milestone) -> String {
        var parts: [String] = []
        if let l = m.label, !l.isEmpty { parts.append(l) }
        if let v = m.value { parts.append(formatted(v)) }
        if let d = m.date, !d.isEmpty { parts.append("· \(d)") }
        return parts.isEmpty ? "Milestone" : parts.joined(separator: " ")
    }

    private func progress(start: Double, target: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(formatted(start)) \(plan.metricLabel ?? "")")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(formatted(target)) \(plan.metricLabel ?? "")")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            Capsule()
                .fill(WhisperTheme.surface(colorScheme))
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.green)
                        .frame(width: 16, height: 8)
                }
        }
    }

    private func formatted(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(v))" }
        return String(format: "%.1f", v)
    }
}

// MARK: - Schedule card

struct WhisperEmberScheduleCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let schedule: WhisperEmberBlocks.Schedule

    @State private var saved: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.indigo, in: Circle())
                Text("SCHEDULE")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .opacity(0.7)
                Spacer(minLength: 0)
            }
            if let rules = schedule.rules, !rules.isEmpty {
                section("Rules", icon: "repeat", items: rules.map { $0.value })
            }
            if let conditions = schedule.conditions, !conditions.isEmpty {
                section("Conditions", icon: "slider.horizontal.3", items: conditions.map { $0.value })
            }
            Button {
                Haptics.success()
                WhisperEmberGoalStore.shared.saveSchedule(schedule)
                withAnimation(.spring(response: 0.3)) { saved = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: saved ? "checkmark" : "tray.and.arrow.down")
                        .font(.caption.weight(.bold))
                    Text(saved ? "Schedule saved" : "Save schedule")
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(saved ? Color.indigo.opacity(0.18) : Color.indigo, in: Capsule())
                .foregroundStyle(saved ? Color.indigo : .white)
            }
            .buttonStyle(.plain)
            .disabled(saved)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func section(_ title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.heavy))
                .opacity(0.7)
            ForEach(items.filter { !$0.isEmpty }, id: \.self) { item in
                Label(item, systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
        }
    }
}

// MARK: - Post draft card

struct WhisperEmberPostDraftCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let draft: WhisperEmberBlocks.PostDraft
    @State private var copied: Bool = false

    private var username: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    private var fullCaption: String {
        let tags = (draft.hashtags ?? [])
            .map { "#\($0)" }
            .filter { !(draft.caption ?? "").lowercased().contains($0.lowercased()) }
        return [draft.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                tags.joined(separator: " ")]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(width: 24, height: 24)
                    .background(WhisperTheme.ink(colorScheme), in: Circle())
                Text("POST DRAFT \u{00B7} PREVIEW")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .opacity(0.7)
                Spacer(minLength: 0)
                if let best = draft.bestTime, !best.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(best)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(WhisperTheme.surface(colorScheme), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                WhisperTheme.hairline(colorScheme).frame(height: 0.75)
            }

            // Real thread-card preview
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    WhisperAvatar(username: username, size: 36)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(WhisperTheme.ink(colorScheme).opacity(0.1))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(username)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        if let community = draft.community, !community.isEmpty {
                            Text("\u{2039}")
                                .font(.system(size: 13))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                            Text("#\(community.replacingOccurrences(of: "#", with: ""))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .lineLimit(1)
                        }
                        Text("now")
                            .font(.system(size: 12))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    Text(fullCaption.isEmpty ? "\u{2026}" : fullCaption)
                        .font(.system(size: 14.5))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if let media = draft.mediaIdea, !media.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 12))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                            Text(media)
                                .font(.system(size: 12))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(WhisperTheme.surface(colorScheme).opacity(0.4), in: .rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(WhisperTheme.hairline(colorScheme).opacity(0.5),
                                              style: .init(lineWidth: 1, dash: [4, 3]))
                        }
                    }
                    // Action row
                    HStack(spacing: 20) {
                        Image(systemName: "heart")
                            .font(.system(size: 16))
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.6))
                        Image(systemName: "message")
                            .font(.system(size: 16))
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.6))
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 16))
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.6))
                        Image(systemName: "paperplane")
                            .font(.system(size: 14))
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.6))
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(14)

            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    WhisperEmberActionRouter.shared.openComposer(draft: fullCaption)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 12, weight: .bold))
                        Text("Open in composer")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.tap()
                    UIPasteboard.general.string = fullCaption
                    withAnimation(.spring(response: 0.3)) { copied = true }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(width: 40, height: 40)
                        .background(WhisperTheme.card(colorScheme), in: Circle())
                        .overlay { Circle().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }
}

// MARK: - Profile card view

struct WhisperEmberProfileCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let card: WhisperEmberBlocks.ProfileCard
    @State private var copied: Bool = false

    private var username: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(width: 24, height: 24)
                    .background(WhisperTheme.ink(colorScheme), in: Circle())
                Text((card.title ?? "Profile upgrade").uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .opacity(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                WhisperTheme.hairline(colorScheme).frame(height: 0.75)
            }

            if let bio = card.bio, !bio.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    WhisperAvatar(username: username, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(username)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text("@\(username)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        Text(bio)
                            .font(.system(size: 13.5))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)

                Button {
                    Haptics.tap()
                    UIPasteboard.general.string = bio
                    withAnimation(.spring(response: 0.3)) { copied = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .bold))
                        Text(copied ? "Bio copied" : "Copy new bio")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            if let pinned = card.pinnedIdea, !pinned.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pin this: ")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        + Text(pinned)
                            .font(.system(size: 12.5))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(WhisperTheme.surface(colorScheme).opacity(0.5), in: .rect(cornerRadius: 12))
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            if let tips = card.tips, !tips.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tips")
                        .font(.system(size: 11, weight: .heavy))
                        .opacity(0.7)
                    ForEach(tips.prefix(6), id: \.self) { tip in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                            Text(tip)
                                .font(.system(size: 12))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
            }
        }
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }
}
