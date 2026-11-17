import SwiftUI

/// Single source of truth for "what kind of profile is this".
///
/// Resolves the highest-ranked role a user has across:
/// - `UserBadge` (verified / moderator / admin / owner)
/// - `WhisperCoachService.isCoach`
///
/// Used in the DM thread header and on the user's own profile in place of
/// the old "Synced with Whisper" subtitle, so coaches / verified / admin /
/// moderators / owners get a visible label next to their name.
nonisolated struct WhisperRoleDescriptor: Sendable, Equatable {
    let text: String
    let systemImage: String
    let tint: Color

    static let coach    = WhisperRoleDescriptor(text: "Coach",     systemImage: "figure.run.circle.fill", tint: Color(red: 0.97, green: 0.45, blue: 0.30))
    static let director = WhisperRoleDescriptor(text: "Director",  systemImage: "movieclapper.fill",      tint: Color(red: 0.10, green: 0.10, blue: 0.10))
    static let verified = WhisperRoleDescriptor(text: "Verified",  systemImage: "checkmark.seal.fill",    tint: Color(red: 0.13, green: 0.55, blue: 0.96))
    static let moderator = WhisperRoleDescriptor(text: "Moderator", systemImage: "shield.lefthalf.filled", tint: Color(red: 0.55, green: 0.58, blue: 0.62))
    static let admin    = WhisperRoleDescriptor(text: "Admin",     systemImage: "checkmark.seal.fill",    tint: Color(red: 0.85, green: 0.62, blue: 0.10))
    static let owner    = WhisperRoleDescriptor(text: "Founder",   systemImage: "crown.fill",             tint: Color(red: 0.85, green: 0.25, blue: 0.55))
}

@MainActor
enum WhisperRoleResolver {
    /// Returns a label descriptor for the most prestigious role this user
    /// holds, or `nil` if they have no special role.
    static func descriptor(userID: String?, username: String) -> WhisperRoleDescriptor? {
        let badge = UserVerificationService.shared.badge(forUsername: username)
        let isCoach: Bool = {
            if let uid = userID, WhisperCoachService.shared.isCoach(userID: uid) { return true }
            return WhisperCoachService.shared.isCoach(username: username)
        }()
        // Owner > admin > moderator > director > verified > coach. (The
        // retired Athlete badge is a Creator niche now — see the profile's
        // professional-category line.)
        let isDirector = {
            if let uid = userID, WhisperDirectorService.shared.isDirector(userID: uid) { return true }
            return false
        }()
        switch badge {
        case .owner:     return .owner
        case .admin:     return .admin
        case .moderator: return .moderator
        case .verified:
            if isDirector { return .director }
            return .verified
        case .none:
            if isDirector { return .director }
            if isCoach { return .coach }
            return nil
        }
    }

    /// Convenience for the current user.
    static func descriptorForMe() -> WhisperRoleDescriptor? {
        let me = (LeaderboardService.shared.savedUsername
                  ?? AuthenticationService.shared.currentUser.username
                  ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !me.isEmpty else { return nil }
        let badge = UserVerificationService.shared.badge(forUsername: me)
        switch badge {
        case .owner:     return .owner
        case .admin:     return .admin
        case .moderator: return .moderator
        case .verified:  return .verified
        case .none:
            if WhisperDirectorService.shared.isMeDirector { return .director }
            if WhisperCoachService.shared.isMeCoach { return .coach }
            return nil
        }
    }
}

/// Inline pill that renders a `WhisperRoleDescriptor`. Mirrors the small
/// "⊗ Lead · Business chat" tag in the reference screenshot. Draws a real
/// tinted capsule (matching `WhisperBadgeTextPill`) so role chips stay
/// legible on dark and pitch-black surfaces.
struct WhisperRolePill: View {
    @Environment(\.colorScheme) private var colorScheme
    let descriptor: WhisperRoleDescriptor
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Text(descriptor.text)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
            if let trailing {
                Text("· \(trailing)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
