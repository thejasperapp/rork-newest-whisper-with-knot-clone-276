import SwiftUI

/// DM embed sent when a user replies to someone's "What's on your mind"
/// note. Renders as the original thought bubble + a thin thread line + the
/// reply text underneath — mirroring how IG / Threads quote-replies look.
nonisolated enum WhisperThoughtReplyEmbed {
    static let prefix = "::whisper-thought-reply-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        var id: String { UUID().uuidString }
        let text: String
        let accent: String
        let emoji: String
        let colorHex: String
        /// Raw value of `WhisperThoughtStyle` (`plain` / `location` / `music`).
        let style: String
        let posterUsername: String
        let reply: String
    }

    nonisolated static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return p.reply }
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

/// Inline DM bubble for a thought-reply: the original "What's on your mind"
/// bubble at the top, a vertical thread line connecting it to a small reply
/// bubble underneath.
struct WhisperThoughtReplyInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperThoughtReplyEmbed.Payload
    let mine: Bool

    private var style: WhisperThoughtStyle {
        WhisperThoughtStyle(rawValue: payload.style) ?? .plain
    }

    /// Horizontal inset (from the card's leading edge) where the vertical
    /// thread line is drawn. Chosen so the line lands near the center of
    /// the original thought bubble's tail dots, then continues straight
    /// down into the reply bubble below — making the connection visible.
    private let threadX: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1 — original thought bubble. Trailing Spacer keeps the
            // bubble at its intrinsic width so the card hugs its content.
            HStack(spacing: 0) {
                WhisperThoughtBubble(
                    text: payload.text,
                    scale: 0.72,
                    style: style,
                    accent: payload.accent,
                    emoji: payload.emoji,
                    colorHex: payload.colorHex
                )
                Spacer(minLength: 0)
            }

            // Row 2 — username caption sits to the right of the thread line.
            Text("@\(payload.posterUsername)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(captionColor)
                .padding(.leading, threadX + 12)

            // Row 3 — reply bubble, indented past the thread line so the
            // line visually connects into the bubble's left edge.
            HStack(spacing: 0) {
                replyBubble
                Spacer(minLength: 0)
            }
            .padding(.leading, threadX + 6)
        }
        .background(alignment: .topLeading) {
            // Continuous vertical thread line that spans from just under
            // the original bubble down to (and into) the reply bubble.
            // Drawn in the card's background so it sits behind both rows
            // and visually links them — the IG / Threads quote-reply look.
            Capsule()
                .fill(threadColor.opacity(0.55))
                .frame(width: 2)
                .padding(.top, 34)      // start just under the original bubble
                .padding(.bottom, 14)   // end just inside the reply bubble
                .offset(x: threadX)
        }
        .frame(maxWidth: 240, alignment: .leading)
        .padding(.vertical, 4)
    }

    /// The reply bubble itself — separated out so the thread-line overlay
    /// can be anchored to its exact height without intrinsic-sizing quirks.
    private var replyBubble: some View {
        Text(payload.reply.isEmpty ? " " : payload.reply)
            .font(.subheadline)
            .foregroundStyle(replyTextColor)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(replyBubbleFill, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(replyBorder, lineWidth: 0.75)
            }
    }

    private var captionColor: Color {
        mine
            ? WhisperTheme.surface(colorScheme).opacity(0.85)
            : WhisperTheme.muted(colorScheme)
    }

    private var threadColor: Color {
        mine
            ? WhisperTheme.surface(colorScheme)
            : WhisperTheme.muted(colorScheme)
    }

    private var replyBubbleFill: Color {
        mine
            ? WhisperTheme.surface(colorScheme).opacity(0.18)
            : WhisperTheme.card(colorScheme)
    }

    private var replyBorder: Color {
        mine
            ? WhisperTheme.surface(colorScheme).opacity(0.35)
            : WhisperTheme.hairline(colorScheme)
    }

    private var replyTextColor: Color {
        mine
            ? WhisperTheme.surface(colorScheme)
            : WhisperTheme.ink(colorScheme)
    }
}
