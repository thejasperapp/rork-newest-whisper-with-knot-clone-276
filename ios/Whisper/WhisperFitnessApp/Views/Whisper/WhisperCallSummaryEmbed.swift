import SwiftUI

/// Encodes a completed call summary inside a DM body so both participants
/// see a widget-style "Call ended" row with mode (audio/video), duration,
/// and a tappable "Call back" pill — instead of a plain emoji + duration
/// string (which renders as raw codepoints in some contexts).
nonisolated enum WhisperCallSummaryEmbed {
    static let prefix = "::whisper-callsummary-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let id: String
        /// "audio" or "video".
        let mode: String
        /// Total elapsed seconds while the call was connected.
        let durationSeconds: Int
        /// True if the call connected; false if it was missed or declined.
        let connected: Bool

        var isVideo: Bool { mode.lowercased() == "video" }

        var durationLabel: String {
            let s = max(0, durationSeconds)
            let h = s / 3600
            let m = (s % 3600) / 60
            let sec = s % 60
            if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
            return String(format: "%d:%02d", m, sec)
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
              let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return p
    }
}

/// Inline widget rendered in chat for a completed/missed call.
struct WhisperCallSummaryInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperCallSummaryEmbed.Payload
    let mine: Bool
    /// Caller invokes this with the chat partner's user id + username +
    /// avatar so the card can place a return call.
    let onCallBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(payload.connected ? Color.green.opacity(0.18) : Color.red.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: payload.isVideo ? "video.fill" : "phone.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(payload.connected ? Color.green : Color.red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(payload.connected
                     ? (payload.isVideo ? "Video call" : "Audio call")
                     : (payload.isVideo ? "Missed video call" : "Missed audio call"))
                    .font(.subheadline.weight(.bold))
                Text(payload.connected ? payload.durationLabel : "No answer")
                    .font(.caption)
                    .opacity(0.75)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                onCallBack()
            } label: {
                Text("Call back")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 280, alignment: .leading)
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
}
