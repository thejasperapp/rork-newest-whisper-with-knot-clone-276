import SwiftUI
import EventKit

/// Interactive workout proposal sent via `/workout`. Recipient taps
/// "I'll do it with you" to RSVP — the embed records both names locally
/// and (if calendar permission is granted) drops a calendar event on
/// both sides. After both have accepted the card shows a pact state.
nonisolated enum WhisperWorkoutProposalEmbed {
    static let prefix = "::whisper-workoutproposal-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let proposerUsername: String
        let title: String
        let focus: String
        let durationMinutes: Int
        /// Bullet list of moves / blocks (4-6 short lines).
        let blocks: [String]
        /// ISO timestamp the proposer suggested. nil = "today, you pick".
        let when: String?
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
}

/// Per-device "I'll do it" acceptance store. Keyed by proposal id so the
/// state survives backgrounding and the same card can't be double-tapped.
@MainActor
final class WhisperWorkoutProposalStore {
    static let shared = WhisperWorkoutProposalStore()
    private let key = "whisper_workout_proposal_accepted_v1"
    private var ids: Set<String>

    private init() {
        let raw = UserDefaults.standard.stringArray(forKey: key) ?? []
        ids = Set(raw)
    }

    func isAccepted(_ id: String) -> Bool { ids.contains(id) }

    func accept(_ id: String) {
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}

struct WhisperWorkoutProposalInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperWorkoutProposalEmbed.Payload
    let mine: Bool
    /// Tapped when the recipient says "I'll do it with you". The DM thread
    /// records the acceptance, schedules a calendar event, and sends a
    /// confirmation message back.
    var onAccept: (() -> Void)?

    @State private var accepted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "figure.run")
                    .font(.subheadline.weight(.bold))
                Text("Workout pact")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if let w = payload.when {
                    Text(w)
                        .font(.caption2.weight(.semibold))
                        .opacity(0.7)
                } else {
                    Text("Today")
                        .font(.caption2.weight(.semibold))
                        .opacity(0.7)
                }
            }

            Text(payload.title)
                .font(.headline.weight(.heavy))
                .lineLimit(2)

            HStack(spacing: 6) {
                chip(icon: "clock", text: "\(payload.durationMinutes) min")
                if !payload.focus.isEmpty {
                    chip(icon: "target", text: payload.focus)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(payload.blocks.prefix(6).enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .opacity(0.6)
                        Text(line)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                    }
                }
            }

            if !mine {
                Button {
                    Haptics.success()
                    withAnimation(.spring(response: 0.3)) { accepted = true }
                    WhisperWorkoutProposalStore.shared.accept(payload.id)
                    onAccept?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: accepted ? "checkmark.circle.fill" : "hand.raised.fill")
                        Text(accepted ? "You're in" : "I'll do it with you")
                            .font(.caption.weight(.heavy))
                    }
                    .foregroundStyle(accepted ? Color.green : WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        accepted
                        ? Color.green.opacity(0.15)
                        : WhisperTheme.ink(colorScheme),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(accepted)
            }

            Text("@\(payload.proposerUsername)")
                .font(.caption2.weight(.heavy))
                .opacity(0.65)
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
        .onAppear {
            accepted = WhisperWorkoutProposalStore.shared.isAccepted(payload.id)
        }
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((mine ? Color.white : Color.black).opacity(0.08), in: Capsule())
    }
}

/// Schedules a calendar event for an accepted workout. Silently no-ops if
/// permission is denied or EventKit fails.
nonisolated enum WhisperWorkoutCalendar {
    static func schedule(_ payload: WhisperWorkoutProposalEmbed.Payload) async {
        let store = EKEventStore()
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        } else {
            granted = await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) }
            }
        }
        guard granted else { return }
        let event = EKEvent(eventStore: store)
        event.title = "Whisper workout · \(payload.title)"
        event.notes = payload.blocks.joined(separator: "\n")
        let start: Date = {
            let iso = ISO8601DateFormatter()
            if let w = payload.when, let d = iso.date(from: w) { return d }
            // Default: top of the next hour today.
            let cal = Calendar.current
            let now = Date()
            var comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
            comps.hour = (comps.hour ?? 12) + 1
            return cal.date(from: comps) ?? now.addingTimeInterval(3600)
        }()
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(payload.durationMinutes * 60))
        event.calendar = store.defaultCalendarForNewEvents
        try? store.save(event, span: .thisEvent)
    }
}
