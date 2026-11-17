import SwiftUI

/// Compact checkmark badge displayed next to a username when the user has been
/// granted a verification flag in Supabase.
///
/// - `.verified` renders the brand-blue sealed checkmark (handed out manually).
/// - `.moderator` renders a silver checkmark for community moderators.
/// - `.admin` renders a gold checkmark for app admins.
/// - `.owner` renders a multi-color gradient checkmark.
/// - `.none` collapses to an empty view.
///
/// Inline rendering is intentionally capped at **2 chips** (after the
/// verified seal) so usernames never get cluttered. Any remaining badges
/// surface in the full `WhisperBadgeShelf` on the profile page. Priority
/// order — only the highest-priority active chips fill the 2 slots:
///
/// 1. Safety Watch (mod-only)
/// 2. Restricted DMs
/// 3. Liar Liar
/// 4. Teen / 18+ (mutually exclusive)
/// 5. Trusted Member
/// 6. Community Guardian
/// 7. Established Member
/// 8. Founding Member
struct VerifiedBadge: View {
    let badge: UserBadge
    var size: CGFloat = 14
    /// Username this badge is being rendered for. When provided, we also
    /// stack the Liar Liar chip and safety chips inline so callers don't
    /// have to know which ones are active.
    var username: String? = nil
    /// Optional user id — required for the Safety Watch chip (mod-only)
    /// because watch flags are keyed by uuid, not username.
    var userID: String? = nil
    /// Hard cap for chips drawn inline next to the username. Remaining
    /// badges still appear in the profile-page shelf.
    var maxChips: Int = 2

    @State private var liar = WhisperLiarLiarService.shared
    @State private var safety = WhisperSafetyService.shared

    private var inlineSize: CGFloat {
        min(size, 12)
    }

    var body: some View {
        verifiedGlyph
            .accessibilityHint("Identity or staff role only. Not a guarantee of safety or accuracy.")
    }

    /// Active chip kinds for this user, in priority order. Computed each
    /// render so the inline strip reacts immediately when a safety flag
    /// is added or appealed away.
    private var activeChips: [WhisperBadgeKind] {
        WhisperBadgeKind.active(forUsername: username, userID: userID, liar: liar, safety: safety)
    }

    @ViewBuilder
    private var verifiedGlyph: some View {
        if badge == .none {
            EmptyView()
        } else if badge == .owner {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: inlineSize, weight: .bold))
                .foregroundStyle(badge.gradient)
                .shadow(color: Color(red: 0.97, green: 0.45, blue: 0.30).opacity(0.45), radius: 2.5, y: 0.5)
                .accessibilityLabel(Text(badge.accessibilityLabel))
        } else if badge == .moderator {
            // Brushed-silver moderator checkmark with subtle vertical sheen.
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: inlineSize, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.92, green: 0.93, blue: 0.96),
                            Color(red: 0.70, green: 0.72, blue: 0.78),
                            Color(red: 0.86, green: 0.88, blue: 0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.black.opacity(0.18), radius: 1.5, y: 0.5)
                .accessibilityLabel(Text(badge.accessibilityLabel))
        } else {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: inlineSize, weight: .bold))
                .foregroundStyle(badge.color)
                .shadow(color: badge.color.opacity(0.35), radius: 2, y: 0.5)
                .accessibilityLabel(Text(badge.accessibilityLabel))
        }
    }
}

extension View {
    /// Appends a verified / moderator badge inline next to a username label.
    @ViewBuilder
    func verifiedBadge(for username: String, size: CGFloat = 14, userID: String? = nil) -> some View {
        HStack(spacing: 4) {
            self
            VerifiedBadge(
                badge: UserVerificationService.shared.badge(forUsername: username),
                size: size,
                username: username,
                userID: userID
            )
        }
    }
}
