import SwiftUI

/// DM-embed payload sent to the client every time a coach submits a
/// `whisper_coach_proposals` row. The bubble in the client's inbox lets
/// them open the review sheet (or directly accept/decline) without
/// hopping through the `jasper://coach-proposal/<id>` push.
nonisolated enum WhisperCoachProposalEmbed {
    static let prefix = "::whisper-coach-proposal-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let id: String              // proposal row id
        let kind: String            // ProposalKind.rawValue
        let coachUsername: String
        let summary: String         // pre-formatted one-liner (e.g. "2,400 kcal · 180P / 240C / 70F")
        let note: String?

        nonisolated enum CodingKeys: String, CodingKey {
            case id, kind, coachUsername, summary, note
        }

        nonisolated init(
            id: String,
            kind: String,
            coachUsername: String,
            summary: String,
            note: String?
        ) {
            self.id = id
            self.kind = kind
            self.coachUsername = coachUsername
            self.summary = summary
            self.note = note
        }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(String.self, forKey: .id)
            self.kind = try c.decode(String.self, forKey: .kind)
            self.coachUsername = (try? c.decode(String.self, forKey: .coachUsername)) ?? "your coach"
            self.summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
            self.note = try? c.decode(String.self, forKey: .note)
        }
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

    nonisolated static func title(for kind: String) -> String {
        switch kind {
        case "macros":        return "Macro update"
        case "diet_plan":     return "New diet plan"
        case "workout":       return "Workout tweak"
        case "exercise_swap": return "Exercise swap"
        case "note":          return "Coaching note"
        default:              return "Coach suggestion"
        }
    }

    nonisolated static func icon(for kind: String) -> String {
        switch kind {
        case "macros":        return "scalemass.fill"
        case "diet_plan":     return "leaf.fill"
        case "workout":       return "figure.strengthtraining.traditional"
        case "exercise_swap": return "arrow.left.arrow.right"
        case "note":          return "text.bubble.fill"
        default:              return "sparkles"
        }
    }
}

/// In-thread bubble that surfaces a coach proposal directly in the
/// client's DM with the coach. Tap → review sheet. Accept/Decline buttons
/// route through the same `WhisperCoachProposalReviewService` used by
/// the deep-link flow.
struct WhisperCoachProposalInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperCoachProposalEmbed.Payload
    let mine: Bool

    @State private var statusOverride: String?
    @State private var working: Bool = false

    private var service: WhisperCoachProposalReviewService { .shared }

    /// Per the Whisper ↔ Whisper integration contract, the client reviews and
    /// applies proposals inside Whisper (which owns the diet-plan / workout
    /// schema). The card deep-links to `jasper://coach-proposal/<id>`.
    private var jasperDeepLink: URL? {
        URL(string: "jasper://coach-proposal/\(payload.id)")
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
            content
            divider
            actionArea
        }
        .frame(width: 278, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
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
                Text(WhisperCoachProposalEmbed.title(for: payload.kind))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: WhisperCoachProposalEmbed.icon(for: payload.kind))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WhisperTheme.coachAccent)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !payload.summary.isEmpty {
                Text(payload.summary)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(fg.opacity(mine ? 0.08 : 0.05), in: .rect(cornerRadius: 12))
            }
            if let note = payload.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(fg.opacity(0.06))
            .frame(height: 0.5)
    }

    @ViewBuilder
    private var actionArea: some View {
        Group {
            if mine {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.caption2.weight(.heavy))
                    Text("Sent \u{00B7} awaiting client response")
                        .font(.caption.weight(.semibold))
                }
                .opacity(0.65)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            } else if let statusOverride {
                HStack { statusPill(statusOverride); Spacer(minLength: 0) }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else {
                actionButtons
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                Task { await quickDecline() }
            } label: {
                HStack(spacing: 5) {
                    if working {
                        ProgressView().controlSize(.mini).tint(.red)
                    }
                    Text(working ? "Declining\u{2026}" : "Decline")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.red.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(working)

            Button {
                Haptics.tap()
                if let url = jasperDeepLink {
                    UIApplication.shared.open(url) { opened in
                        if !opened {
                            Task { @MainActor in
                                service.presentedProposalID = payload.id
                            }
                        }
                    }
                } else {
                    service.presentedProposalID = payload.id
                }
            } label: {
                Text("Review")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(WhisperTheme.coachAccent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(working)
        }
    }

    private func statusPill(_ status: String) -> some View {
        let (label, color, icon): (String, Color, String) = {
            switch status {
            case "accepted": return ("Accepted", .green, "checkmark.seal.fill")
            case "declined": return ("Declined", .red, "xmark.seal.fill")
            case "expired":  return ("Expired",  .gray, "clock.badge.xmark")
            default:         return (status.capitalized, .gray, "circle")
            }
        }()
        return HStack(spacing: 6) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.caption.weight(.heavy))
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1))
    }

    private func quickDecline() async {
        working = true
        defer { working = false }
        if let row = await service.fetch(id: payload.id) {
            // v1 path — also writes the receipt via respond(...).
            let ok = await service.respond(to: row, status: "declined")
            if ok {
                Haptics.success()
                statusOverride = "declined"
            } else {
                Haptics.warning()
            }
            return
        }
        // v2 path — no row in whisper_coach_proposals. Just log the receipt.
        let ok = await WhisperProposalReceiptService.shared.record(
            proposalID: payload.id, status: "declined"
        )
        if ok { Haptics.success() } else { Haptics.warning() }
        statusOverride = "declined"
    }
}
