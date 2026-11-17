import SwiftUI

/// Weekly check-in card sent via `/checkin`. Shows weight delta, streak,
/// top win, and hardest day so two friends can hold each other
/// accountable. Recipient can tap one of four sticker reactions which
/// echoes back as its own inline message.
nonisolated enum WhisperCheckinEmbed {
    static let prefix = "::whisper-checkin-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let username: String
        let weekLabel: String
        /// Weight change over the week in pounds (signed). `nil` if missing.
        let weightDelta: Double?
        /// Current streak of meals-or-workouts logged days.
        let streakDays: Int
        let workoutsLogged: Int
        let avgCalories: Int
        /// Top win line written by Jasper (or the user).
        let topWin: String
        /// Hardest day line.
        let hardestDay: String
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

    /// Builds a snapshot using the current user's NutritionStore + recent
    /// activity. Jasper adds the "top win" and "hardest day" lines.
    @MainActor
    static func currentSnapshot(username: String, topWin: String, hardestDay: String) -> Payload {
        let store = NutritionStore.shared
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(byAdding: .day, value: -6, to: now) ?? now
        // Streak: consecutive days from today backwards with any meal logged.
        var streak = 0
        for d in 0..<30 {
            guard let day = cal.date(byAdding: .day, value: -d, to: now) else { break }
            let logged = store.meals.contains { cal.isDate($0.timestamp, inSameDayAs: day) }
            if logged { streak += 1 } else { break }
        }
        // Average calories in the last 7 days.
        let weekMeals = store.meals.filter { $0.timestamp >= start }
        let days = max(1, Set(weekMeals.map { cal.startOfDay(for: $0.timestamp) }).count)
        let avg = weekMeals.reduce(0) { $0 + $1.totalCalories } / days
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let weekLabel = "\(f.string(from: start)) – \(f.string(from: now))"
        return Payload(
            id: UUID().uuidString,
            username: username,
            weekLabel: weekLabel,
            weightDelta: nil,
            streakDays: streak,
            workoutsLogged: 0,
            avgCalories: avg,
            topWin: topWin,
            hardestDay: hardestDay
        )
    }
}

struct WhisperCheckinInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperCheckinEmbed.Payload
    let mine: Bool
    /// Sticker emoji tapped by the recipient. Fires a follow-up message.
    var onReact: ((String) -> Void)?

    private let stickers = ["🔥", "💪", "🫶", "🥲"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.subheadline.weight(.bold))
                Text("Weekly check-in")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(payload.weekLabel)
                    .font(.caption2.weight(.semibold))
                    .opacity(0.7)
            }

            HStack(spacing: 10) {
                stat(icon: "flame.fill", label: "Streak", value: "\(payload.streakDays)d")
                stat(icon: "chart.line.uptrend.xyaxis", label: "Avg cal", value: "\(payload.avgCalories)")
                if let dw = payload.weightDelta {
                    let signed = dw >= 0 ? "+\(String(format: "%.1f", dw))" : String(format: "%.1f", dw)
                    stat(icon: "scalemass.fill", label: "Δ lbs", value: signed)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Top win")
                    .font(.caption2.weight(.heavy))
                    .opacity(0.7)
                Text(payload.topWin)
                    .font(.caption.weight(.semibold))
                    .lineLimit(3)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Hardest day")
                    .font(.caption2.weight(.heavy))
                    .opacity(0.7)
                Text(payload.hardestDay)
                    .font(.caption.weight(.semibold))
                    .lineLimit(3)
            }

            if !mine, let onReact {
                HStack(spacing: 8) {
                    ForEach(stickers, id: \.self) { s in
                        Button {
                            Haptics.success()
                            onReact(s)
                        } label: {
                            Text(s)
                                .font(.system(size: 22))
                                .padding(6)
                                .background((mine ? Color.white : Color.black).opacity(0.06), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            Text("@\(payload.username)")
                .font(.caption2.weight(.heavy))
                .opacity(0.7)
        }
        .padding(14)
        .frame(width: 270, alignment: .leading)
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

    private func stat(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
                Text(label)
                    .font(.caption2.weight(.bold))
                    .opacity(0.7)
            }
            Text(value)
                .font(.subheadline.weight(.heavy))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background((mine ? Color.white : Color.black).opacity(0.06), in: .rect(cornerRadius: 10))
    }
}
