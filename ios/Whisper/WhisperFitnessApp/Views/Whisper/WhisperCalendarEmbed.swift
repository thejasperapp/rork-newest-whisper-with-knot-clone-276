import SwiftUI

/// Encodes/decodes a calendar event invite inside a DM message body so
/// tagged users receive a tappable "team message" card in their inbox.
/// The card shows the event title, type, date/time, location, meeting
/// link, and who tagged them — tapping it opens the full calendar view.
///
/// This is the iOS counterpart to the web calendar's "team message" DM
/// notification: when a user creates a calendar event and tags people,
/// each tagged user gets one of these as a DM from the event creator.
nonisolated enum WhisperCalendarEmbed {
    static let prefix = "::whisper-calendar-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let eventID: String
        let title: String
        let eventType: String
        let startTime: String
        let location: String?
        let meetingLink: String?
        let createdByUsername: String
        /// Usernames of everyone tagged (for display in the card)
        let taggedUsernames: [String]
        /// "invite" (default), "update", or "cancelled" — optional so older
        /// payloads still decode.
        var kind: String?
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

    /// Human-readable label for the event type
    nonisolated static func typeLabel(_ raw: String) -> String {
        switch raw {
        case "meet": return "Meet up"
        case "content_collab": return "Content collab"
        case "training": return "Training"
        case "event": return "Event"
        case "deadline": return "Deadline"
        default: return "Other"
        }
    }

    /// Color for the event type dot/bar
    nonisolated static func typeColor(_ raw: String) -> Color {
        switch raw {
        case "meet": return Color(red: 0.23, green: 0.51, blue: 0.96)
        case "content_collab": return Color(red: 0.66, green: 0.33, blue: 0.91)
        case "training": return Color(red: 0.13, green: 0.77, blue: 0.37)
        case "event": return Color(red: 0.96, green: 0.62, blue: 0.04)
        case "deadline": return Color(red: 0.94, green: 0.27, blue: 0.27)
        default: return Color(red: 0.42, green: 0.45, blue: 0.50)
        }
    }

    /// Formats an ISO timestamp into "MMM d · h:mm a"
    nonisolated static func formattedDate(_ iso: String) -> String {
        guard let date = WhisperBackendService.parseISO(iso) else { return iso }
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f.string(from: date)
    }
}

// MARK: - Inline DM card

/// Calendar invite card rendered inline in a DM thread. Shows the event
/// details and a "View in calendar" button that opens the full calendar.
struct WhisperCalendarInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperCalendarEmbed.Payload
    let mine: Bool
    var onOpen: (() -> Void)? = nil

    private var isCancelled: Bool { payload.kind == "cancelled" }

    private var heading: String {
        switch payload.kind {
        case "cancelled": return "Event cancelled"
        case "update": return "Event updated"
        default: return "Team calendar invite"
        }
    }

    var body: some View {
        if payload.kind == "chat-meet" {
            WhisperChatMeetCard(eventID: payload.eventID)
        } else { legacyCard }
    }

    private var legacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: calendar icon + type label + date
            HStack(spacing: 8) {
                Image(systemName: isCancelled ? "calendar.badge.minus" : "calendar.badge.plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isCancelled ? Color(red: 0.94, green: 0.27, blue: 0.27) : WhisperCalendarEmbed.typeColor(payload.eventType))
                Text(heading)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                Spacer(minLength: 0)
            }

            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(WhisperCalendarEmbed.typeColor(payload.eventType))
                .frame(height: 3)

            // Title
            Text(payload.title)
                .font(.body.weight(.bold))
                .strikethrough(isCancelled)
                .foregroundStyle(mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                .opacity(isCancelled ? 0.7 : 1)
                .lineLimit(2)

            // Date / time
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption.weight(.bold))
                Text(WhisperCalendarEmbed.formattedDate(payload.startTime))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(mine ? WhisperTheme.surface(colorScheme).opacity(0.8) : WhisperTheme.muted(colorScheme))

            // Location
            if let loc = payload.location, !loc.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption.weight(.bold))
                    Text(loc)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(mine ? WhisperTheme.surface(colorScheme).opacity(0.8) : WhisperTheme.muted(colorScheme))
            }

            // Meeting link
            if let link = payload.meetingLink, !link.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "video")
                        .font(.caption.weight(.bold))
                    Text("Online meeting")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(mine ? WhisperTheme.surface(colorScheme).opacity(0.8) : WhisperTheme.muted(colorScheme))
            }

            // Tagged users
            if !payload.taggedUsernames.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "person.2")
                        .font(.caption.weight(.bold))
                    Text("With \(payload.taggedUsernames.prefix(3).map { "@\($0)" }.joined(separator: ", "))\(payload.taggedUsernames.count > 3 ? " +\(payload.taggedUsernames.count - 3)" : "")")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(mine ? WhisperTheme.surface(colorScheme).opacity(0.8) : WhisperTheme.muted(colorScheme))
            }

            // From
            Text("From @\(payload.createdByUsername)")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(mine ? WhisperTheme.surface(colorScheme).opacity(0.6) : WhisperTheme.muted(colorScheme))

            // Action button
            if let onOpen, !isCancelled {
                Button {
                    Haptics.tap()
                    onOpen()
                } label: {
                    Text("View in calendar")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme),
                            in: .rect(cornerRadius: 10)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .background(
            mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme),
            in: .rect(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(mine ? Color.clear : WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }
}
