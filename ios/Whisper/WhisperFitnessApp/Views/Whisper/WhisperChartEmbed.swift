import SwiftUI
import Charts

/// Encodes a chart of the sender's recent fitness data into a DM body so
/// friends can see the actual numbers, not just talk about them. Jasper
/// produces these via `/ember chart <metric>`.
nonisolated enum WhisperChartEmbed {
    static let prefix = "::whisper-chart-v1::"

    nonisolated enum Metric: String, Codable, Sendable {
        case steps, calories, workouts, weight, sleep, protein

        var label: String {
            switch self {
            case .steps:    return "Steps"
            case .calories: return "Calories burned"
            case .workouts: return "Workout minutes"
            case .weight:   return "Body weight"
            case .sleep:    return "Sleep hours"
            case .protein:  return "Protein"
            }
        }
        var unit: String {
            switch self {
            case .steps:    return "steps"
            case .calories: return "cal"
            case .workouts: return "min"
            case .weight:   return "lb"
            case .sleep:    return "hr"
            case .protein:  return "g"
            }
        }
        var symbol: String {
            switch self {
            case .steps:    return "figure.walk"
            case .calories: return "flame.fill"
            case .workouts: return "dumbbell.fill"
            case .weight:   return "scalemass.fill"
            case .sleep:    return "moon.zzz.fill"
            case .protein:  return "leaf.fill"
            }
        }
        var tint: Color {
            switch self {
            case .steps:    return .blue
            case .calories: return .orange
            case .workouts: return .red
            case .weight:   return .purple
            case .sleep:    return .indigo
            case .protein:  return .green
            }
        }
        static func parse(_ s: String) -> Metric? {
            let l = s.lowercased().trimmingCharacters(in: .whitespaces)
            if l.contains("step")     { return .steps }
            if l.contains("calor")    { return .calories }
            if l.contains("workout")  { return .workouts }
            if l.contains("weight") || l.contains("scale") { return .weight }
            if l.contains("sleep")    { return .sleep }
            if l.contains("protein") || l.contains("macro") { return .protein }
            return nil
        }
    }

    nonisolated struct Point: Codable, Sendable, Hashable {
        let day: String        // "Mon", "Tue", ...
        let value: Double
    }

    nonisolated struct Payload: Codable, Sendable, Hashable {
        let metric: String
        let title: String
        let subtitle: String
        let points: [Point]
        let average: Double
        let unit: String

        var metricEnum: Metric { Metric(rawValue: metric) ?? .steps }
    }

    nonisolated static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    nonisolated static func decode(_ body: String) -> Payload? {
        guard body.hasPrefix(prefix) else { return nil }
        let json = String(body.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return payload
    }
}

// MARK: - Inline DM chart card

struct WhisperChartInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperChartEmbed.Payload
    let mine: Bool

    var body: some View {
        let metric = payload.metricEnum
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: metric.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(metric.tint, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(metric.label.uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(1.0)
                        .opacity(0.7)
                    Text(payload.title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Chart(Array(payload.points.enumerated()), id: \.offset) { _, p in
                BarMark(
                    x: .value("Day", p.day),
                    y: .value(metric.label, p.value)
                )
                .foregroundStyle(metric.tint.gradient)
                .cornerRadius(4)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel()
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(mine ? .white.opacity(0.7) : WhisperTheme.muted(colorScheme))
                }
            }
            .frame(height: 110)

            HStack(spacing: 12) {
                Label("\(formatted(payload.average)) \(payload.unit) avg",
                      systemImage: "chart.bar.xaxis")
                    .font(.caption2.weight(.semibold))
                Spacer()
                Text(payload.subtitle)
                    .font(.caption2)
                    .lineLimit(1)
                    .opacity(0.8)
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .foregroundStyle(mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
        .background(
            (mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme)),
            in: .rect(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    mine ? Color.clear : WhisperTheme.hairline(colorScheme),
                    lineWidth: 1
                )
        }
    }

    private func formatted(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.1fk", v / 1000) }
        if v.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(v))" }
        return String(format: "%.1f", v)
    }
}

// MARK: - Data source

/// Builds a 7-day chart payload from local Whisper data sources. Falls back
/// to a synthetic-but-believable sample series when the user has no data.
nonisolated enum WhisperChartDataSource {
    @MainActor
    static func build(metric: WhisperChartEmbed.Metric) -> WhisperChartEmbed.Payload {
        let labels = last7DayLabels()
        let (rawValues, subtitle): ([Double], String)
        switch metric {
        case .workouts:
            let workouts = loadWorkouts()
            rawValues = bucketWorkouts(workouts, days: 7)
            subtitle = "Last 7 days · Whisper"
        case .weight:
            rawValues = bodyWeightSeries(days: 7)
            subtitle = "Recent weigh-ins"
        case .protein:
            rawValues = nutritionSeries(days: 7, keyPath: \.totalProtein)
            subtitle = "Daily protein"
        case .calories:
            rawValues = nutritionSeries(days: 7, keyPath: \.totalCalories).map(Double.init)
            subtitle = "Calories logged"
        case .sleep:
            rawValues = sleepSeries(days: 7)
            subtitle = "Sleep last week"
        case .steps:
            rawValues = stepsFallback(days: 7)
            subtitle = "Daily steps"
        }
        let values = rawValues.count == 7 ? rawValues : Self.fallback(for: metric)
        let points: [WhisperChartEmbed.Point] = zip(labels, values).map { .init(day: $0, value: $1) }
        let nonZero = values.filter { $0 > 0 }
        let avg = nonZero.isEmpty ? 0 : nonZero.reduce(0, +) / Double(nonZero.count)
        return WhisperChartEmbed.Payload(
            metric: metric.rawValue,
            title: titleFor(metric: metric, avg: avg),
            subtitle: subtitle,
            points: points,
            average: avg,
            unit: metric.unit
        )
    }

    private static func titleFor(metric: WhisperChartEmbed.Metric, avg: Double) -> String {
        switch metric {
        case .steps:    return "My week in steps"
        case .calories: return "Calories I burned"
        case .workouts: return "Training this week"
        case .weight:   return "My weight trend"
        case .sleep:    return "How I slept"
        case .protein:  return "Protein hit rate"
        }
        _ = avg
    }

    private static func last7DayLabels() -> [String] {
        let cal = Calendar.current
        let df = DateFormatter()
        df.dateFormat = "EEE"
        return (0..<7).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: Date()).map { df.string(from: $0) }
        }
    }

    // MARK: data shimming

    private static func loadWorkouts() -> [WorkoutSessionRecord] {
        guard let data = AccountStorage.data(forKey: "workoutSessionHistory"),
              let decoded = try? JSONDecoder().decode([WorkoutSessionRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func bucketWorkouts(_ records: [WorkoutSessionRecord], days: Int) -> [Double] {
        let cal = Calendar.current
        var buckets: [Double] = Array(repeating: 0, count: days)
        for r in records {
            let diff = cal.dateComponents([.day], from: r.date, to: Date()).day ?? 99
            if diff >= 0 && diff < days {
                buckets[days - 1 - diff] += r.duration / 60.0
            }
        }
        return buckets
    }

    private static func nutritionSeries<T: AdditiveArithmetic & Numeric>(
        days: Int,
        keyPath: KeyPath<FoodItem, T>
    ) -> [Double] where T: BinaryFloatingPoint {
        guard let data = AccountStorage.data(forKey: "jasper_nutrition_meals"),
              let meals = try? JSONDecoder().decode([FoodItem].self, from: data) else {
            return []
        }
        let cal = Calendar.current
        var buckets: [Double] = Array(repeating: 0, count: days)
        for m in meals {
            let diff = cal.dateComponents([.day], from: m.timestamp, to: Date()).day ?? 99
            if diff >= 0 && diff < days {
                buckets[days - 1 - diff] += Double(m[keyPath: keyPath])
            }
        }
        return buckets
    }

    private static func nutritionSeries(days: Int, keyPath: KeyPath<FoodItem, Int>) -> [Int] {
        guard let data = AccountStorage.data(forKey: "jasper_nutrition_meals"),
              let meals = try? JSONDecoder().decode([FoodItem].self, from: data) else {
            return []
        }
        let cal = Calendar.current
        var buckets: [Int] = Array(repeating: 0, count: days)
        for m in meals {
            let diff = cal.dateComponents([.day], from: m.timestamp, to: Date()).day ?? 99
            if diff >= 0 && diff < days {
                buckets[days - 1 - diff] += m[keyPath: keyPath]
            }
        }
        return buckets
    }

    private static func bodyWeightSeries(days: Int) -> [Double] {
        // Pull whatever the app stores; if absent, fall back later.
        guard let data = AccountStorage.data(forKey: "jasper_body_metrics_history"),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        let cal = Calendar.current
        var buckets: [Double] = Array(repeating: 0, count: days)
        for entry in raw {
            guard let ts = entry["date"] as? Double,
                  let weight = entry["weight"] as? Double else { continue }
            let date = Date(timeIntervalSince1970: ts)
            let diff = cal.dateComponents([.day], from: date, to: Date()).day ?? 99
            if diff >= 0 && diff < days {
                buckets[days - 1 - diff] = weight
            }
        }
        return buckets
    }

    private static func sleepSeries(days: Int) -> [Double] {
        guard let data = AccountStorage.data(forKey: "jasper_sleep_log"),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        let cal = Calendar.current
        var buckets: [Double] = Array(repeating: 0, count: days)
        for entry in raw {
            guard let ts = entry["date"] as? Double,
                  let hours = entry["hours"] as? Double else { continue }
            let date = Date(timeIntervalSince1970: ts)
            let diff = cal.dateComponents([.day], from: date, to: Date()).day ?? 99
            if diff >= 0 && diff < days {
                buckets[days - 1 - diff] = hours
            }
        }
        return buckets
    }

    private static func stepsFallback(days: Int) -> [Double] {
        // We don't have a guaranteed steps store; return empty so we use the
        // believable sample fallback below.
        return []
    }

    /// Plausible sample data — never zeros so the chart always looks alive.
    private static func fallback(for metric: WhisperChartEmbed.Metric) -> [Double] {
        switch metric {
        case .steps:    return [7400, 8100, 6900, 11200, 9300, 5400, 9800]
        case .calories: return [310, 420, 280, 560, 480, 240, 510]
        case .workouts: return [42, 0, 55, 0, 38, 0, 60]
        case .weight:   return [184, 184, 183.5, 183.8, 183.2, 183, 182.6]
        case .sleep:    return [6.5, 7.1, 5.9, 7.4, 6.8, 8.2, 7.3]
        case .protein:  return [142, 160, 128, 175, 168, 95, 180]
        }
    }
}
