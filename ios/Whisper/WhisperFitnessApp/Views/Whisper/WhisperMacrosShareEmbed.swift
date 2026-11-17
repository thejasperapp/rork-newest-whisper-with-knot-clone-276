import SwiftUI

/// "Today's macros" + accountability share card. Encoded into a DM body
/// when a user types `/macros` or `/accountability`. The receiver sees a
/// side-by-side snapshot of the sender's progress and can tap "Match me"
/// to push a paired accountability card back.
nonisolated enum WhisperMacrosShareEmbed {
    static let prefix = "::whisper-macros-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let username: String
        let dateLabel: String
        let calories: Int
        let calorieGoal: Int
        let protein: Double
        let proteinGoal: Double
        let carbs: Double
        let carbGoal: Double
        let fat: Double
        let fatGoal: Double
        /// `true` if the sender is challenging the receiver to match.
        let isAccountability: Bool
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
              let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return p
    }

    /// Build a snapshot of the current user's macros for sharing.
    @MainActor
    static func currentSnapshot(username: String, isAccountability: Bool = false) -> Payload {
        let s = NutritionStore.shared
        let f = DateFormatter()
        f.dateStyle = .medium
        return Payload(
            id: UUID().uuidString,
            username: username,
            dateLabel: f.string(from: Date()),
            calories: s.totalCalories,
            calorieGoal: s.goals.calories,
            protein: s.totalProtein,
            proteinGoal: s.goals.protein,
            carbs: s.totalCarbs,
            carbGoal: s.goals.carbs,
            fat: s.totalFat,
            fatGoal: s.goals.fat,
            isAccountability: isAccountability
        )
    }
}

struct WhisperMacrosShareInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperMacrosShareEmbed.Payload
    let mine: Bool
    /// Tapped when the viewer wants to send back their own matching snapshot.
    var onMatch: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: payload.isAccountability ? "figure.2.arms.open" : "chart.pie.fill")
                    .font(.subheadline.weight(.bold))
                Text(payload.isAccountability ? "Accountability check" : "Today's macros")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(payload.dateLabel)
                    .font(.caption2.weight(.semibold))
                    .opacity(0.7)
            }

            VStack(spacing: 8) {
                bar(label: "Calories", value: Double(payload.calories), goal: Double(payload.calorieGoal), unit: "kcal", color: .orange)
                bar(label: "Protein",  value: payload.protein, goal: payload.proteinGoal, unit: "g", color: .red)
                bar(label: "Carbs",    value: payload.carbs,   goal: payload.carbGoal,    unit: "g", color: .yellow)
                bar(label: "Fat",      value: payload.fat,     goal: payload.fatGoal,     unit: "g", color: .blue)
            }

            HStack(spacing: 6) {
                Text("@\(payload.username)")
                    .font(.caption2.weight(.heavy))
                Spacer()
                if let onMatch, !mine {
                    Button {
                        Haptics.tap()
                        onMatch()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left.arrow.right")
                            Text("Match me")
                        }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
        .foregroundStyle(mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
        .background(
            mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme),
            in: .rect(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(mine ? Color.clear : WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func bar(label: String, value: Double, goal: Double, unit: String, color: Color) -> some View {
        let pct = goal > 0 ? min(value / goal, 1.0) : 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption2.weight(.bold))
                Spacer()
                Text("\(Int(value))/\(Int(goal)) \(unit)")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.8)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill((mine ? Color.white : Color.black).opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * pct))
                }
            }
            .frame(height: 6)
        }
    }
}
