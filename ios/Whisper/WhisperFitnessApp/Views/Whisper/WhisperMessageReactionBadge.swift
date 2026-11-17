import SwiftUI

/// Sits just below the bubble's outer edge, with row space reserved by its host.
struct WhisperMessageReactionBadge: View {
    let emoji: String
    var count: Int = 1
    var mine: Bool = false
    /// Ephemeral confirmed-arrival signal; never populated from saved history.
    var landingID: UUID? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            Text(emoji)
            if count > 1 { Text(count.formatted()).font(.system(size: 10, weight: .semibold)) }
        }
            .font(.system(size: 15))
            .padding(.horizontal, 5)
            .frame(minWidth: 26, minHeight: 22)
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black.opacity(0.75))
            .background(colorScheme == .dark ? Color(white: 0.14).opacity(0.94) : Color(white: 0.92).opacity(0.94), in: Capsule())
            .overlay { Capsule().strokeBorder(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.85), lineWidth: 1) }
            .keyframeAnimator(initialValue: ReactionLandingValues(), trigger: landingID) { badge, pose in
                badge
                    .scaleEffect(reduceMotion ? 1 : pose.scale, anchor: .top)
                    .offset(y: reduceMotion ? 0 : pose.lift)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.045, duration: 0.10)
                    SpringKeyframe(1, duration: 0.24, spring: .smooth)
                }
                KeyframeTrack(\.lift) {
                    CubicKeyframe(-2, duration: 0.10)
                    SpringKeyframe(0, duration: 0.24, spring: .smooth)
                }
            }
            .accessibilityLabel("\(emoji), \(count) reaction\(count == 1 ? "" : "s")\(mine ? ", including yours" : "")")
    }
}

private struct ReactionLandingValues {
    var scale: CGFloat = 1
    var lift: CGFloat = 0
}

/// A tiny drop into place, not a message-row or scroll-layout animation.
enum WhisperMessageReactionMotion {
    static let landing = Animation.spring(response: 0.34, dampingFraction: 0.78)
    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .asymmetric(
            insertion: .scale(scale: 0.86, anchor: .top)
                .combined(with: .offset(y: -5))
                .combined(with: .opacity),
            removal: .opacity
        )
    }
}

struct WhisperMessageReactionsBar: View {
    let reactions: [WhisperSharedReaction]
    var landingIDs: [String: UUID] = [:]
    let onTap: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 3) {
            ForEach(reactions) { reaction in
                Button { onTap(reaction.emoji) } label: {
                    WhisperMessageReactionBadge(emoji: reaction.emoji, count: reaction.reaction_count, mine: reaction.mine, landingID: landingIDs[reaction.emoji])
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(WhisperMessageReactionMotion.transition(reduceMotion: reduceMotion))
                .accessibilityHint(reaction.mine ? "Remove your reaction" : "React with this emoji")
            }
        }
        // First reads and remounted history have no changed arrival signal.
        .animation(reduceMotion ? nil : WhisperMessageReactionMotion.landing, value: landingIDs)
    }
}
