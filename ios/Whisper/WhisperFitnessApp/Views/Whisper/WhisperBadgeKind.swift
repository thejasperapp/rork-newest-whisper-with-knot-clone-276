import SwiftUI

/// Single source of truth for every Whisper trust & identity chip. Both the
/// inline `VerifiedBadge` strip (capped at 2) and the full `WhisperBadgeShelf`
/// on profile pages enumerate `WhisperBadgeKind.active(...)` so they stay in
/// lockstep — adding a new badge means adding a case here and nothing else.
///
/// Order of cases is the rendering & priority order: higher cases win the
/// limited inline slots.
enum WhisperBadgeKind: Hashable, Identifiable {
    var id: String { storageKey }

    case safetyWatch
    case restricted
    case liar(muted: Bool)
    case one
    case coach
    case director
    case blogger
    case teen
    case adult
    case trusted
    case guardianRole
    case established
    case founding

    /// Public-facing name shown in the explainer sheet and shelf label.
    var title: String {
        switch self {
        case .safetyWatch:   return "Safety Watch"
        case .restricted:    return "Restricted DMs"
        case .liar:          return "Liar Liar"
        case .one:           return "Whisper One"
        case .coach:         return "Verified Coach"
        case .director:       return "Whisper Director"
        case .blogger:       return "Whisper Blogger"
        case .teen:          return "Teen Account"
        case .adult:         return "18+ Verified"
        case .trusted:       return "Trusted Member"
        case .guardianRole:  return "Community Guardian"
        case .established:  return "Established Member"
        case .founding:     return "Founding Member"
        }
    }

    /// Stable string identifier used as a persistence key for the
    /// award/seen tracking. Associated values are stripped so all `.liar`
    /// variants share a single "seen" record.
    var storageKey: String {
        switch self {
        case .safetyWatch:   return "safetyWatch"
        case .restricted:    return "restricted"
        case .liar:          return "liar"
        case .one:           return "one"
        case .coach:         return "coach"
        case .director:       return "director"
        case .blogger:       return "blogger"
        case .teen:          return "teen"
        case .adult:         return "adult"
        case .trusted:       return "trusted"
        case .guardianRole:  return "guardian"
        case .established:   return "established"
        case .founding:      return "founding"
        }
    }

    /// Short tagline used on the award celebration sheet / share card.
    /// Intentionally celebratory rather than explanatory.
    var tagline: String {
        switch self {
        case .safetyWatch:   return "Under moderator review"
        case .restricted:    return "DMs are throttled until reviewed"
        case .liar:          return "3 misleading posts in 30 days"
        case .one:           return "Whisper One member"
        case .coach:         return "Approved to coach on Whisper"
        case .director:       return "Whisper media team — directs Featured Film Friday"
        case .blogger:       return "Writes articles & film reviews on Whisper"
        case .teen:          return "Verified teen account"
        case .adult:         return "Verified 18+"
        case .trusted:       return "Trusted by the community"
        case .guardianRole:  return "3 helpful reports confirmed"
        case .established:   return "30 days clean and counting"
        case .founding:      return "Here from day one"
        }
    }

    /// Accent color used on the celebration sheet & share card.
    var accent: Color {
        switch self {
        case .safetyWatch:   return Color(red: 0.98, green: 0.55, blue: 0.10) // orange
        case .restricted:    return Color(red: 0.90, green: 0.20, blue: 0.20) // red
        case .liar:          return Color(red: 0.92, green: 0.18, blue: 0.18) // red (predominant)
        case .one:           return Color(red: 0.10, green: 0.10, blue: 0.12) // black seal
        case .coach:         return Color(red: 0.98, green: 0.45, blue: 0.15) // orange (predominant)
        case .director:       return Color(red: 0.10, green: 0.10, blue: 0.12) // ink black — Whisper media team
        case .blogger:       return Color(red: 0.05, green: 0.54, blue: 0.44) // deep teal-green — writer's ink
        case .teen:          return Color(red: 0.20, green: 0.65, blue: 0.98) // sky blue
        case .adult:         return Color(red: 0.55, green: 0.35, blue: 0.98) // purple
        case .trusted:       return Color(red: 0.10, green: 0.75, blue: 0.65) // teal
        case .guardianRole:  return Color(red: 0.25, green: 0.50, blue: 0.95) // royal blue
        case .established:   return Color(red: 0.95, green: 0.72, blue: 0.18) // amber/gold
        case .founding:      return Color(red: 0.92, green: 0.20, blue: 0.62) // magenta/pink
        }
    }

    /// Long-form celebratory copy shown on the award popup. Differs from
    /// `explainer` (which is neutral / educational).
    var celebrationCopy: String {
        switch self {
        case .safetyWatch:
            return "A moderator has flagged this account for review. You won't see this on others."
        case .restricted:
            return "Repeated safety strikes mean new DMs are throttled until a moderator reviews your activity."
        case .liar:
            return "This chip appears after 3 false or misleading public posts in 30 days. Keep posts honest and it'll fall off."
        case .one:
            return "You're a Whisper One member. The black + seal now shows next to your name everywhere on Whisper."
        case .coach:
            return "You're now an approved Whisper coach. Build programs, take clients, and share your expertise with the community."
        case .director:
            return "You're part of the Whisper media team. Directors produce Featured Film Friday shorts, organize creator collaborations, and run the studio workspace."
        case .blogger:
            return "You're a Whisper Blogger. Post articles and film reviews with featured-film tags and full byline credit."
        case .teen:
            return "You're verified as 13–17. Stricter DM defaults are on by default to keep things safe."
        case .adult:
            return "You've self-attested as 18+ — required to DM unfamiliar adults on Whisper."
        case .trusted:
            return "Long-standing account with a clean record. Granted manually after sustained good standing."
        case .guardianRole:
            return "Thanks for keeping the community safe. You filed 3 reports that moderators confirmed."
        case .established:
            return "You've been on Whisper at least 30 days with zero safety strikes. Others can trust you're not a throwaway."
        case .founding:
            return "You joined Whisper in the launch window. Thank you for being one of the first."
        }
    }

    /// User-facing badges that we should celebrate when newly earned.
    /// Moderation/punitive badges (`safetyWatch`, `restricted`, `liar`) are
    /// excluded — popping a "congrats" sheet for those would be tone-deaf.
    static var celebratable: Set<String> {
        ["one", "coach", "director", "blogger", "teen", "adult", "trusted", "guardian", "established", "founding"]
    }

    /// One-sentence description shown in the badge info sheet.
    var explainer: String {
        switch self {
        case .safetyWatch:
            return "Moderator-only flag. This account has crossed Jasper's safety threshold and is being reviewed. You won't see this chip on other users."
        case .restricted:
            return "Auto-applied after repeated safety strikes. New DMs from this account are throttled until a moderator reviews the activity."
        case .liar:
            return "Earned after 3 false or misleading public posts in 30 days. Only post text is evaluated — never DMs, workouts, or photos."
        case .one:
            return "Active Whisper One subscriber. The black + seal signals membership and unlocks One perks across the app."
        case .coach:
            return "Approved Whisper coach. Verified by the Whisper team to share programs, nutrition, and progress feedback with clients."
        case .director:
            return "Whisper media team member. Directors produce Featured Film Friday shorts, organize creator collaborations, and run the studio workspace."
        case .blogger:
            return "Dedicated writer on Whisper. Bloggers post articles and film reviews with featured-film tags and full byline credit."
        case .teen:
            return "Account belongs to a verified teen (13–17). Stricter DM defaults, no unsolicited messages from unverified adults."
        case .adult:
            return "User has self-attested they are 18 or older. Required to DM unfamiliar adults."
        case .trusted:
            return "Long-standing account with a clean record and positive community signal. Granted manually after sustained good standing."
        case .guardianRole:
            return "User has filed at least 3 helpful reports that moderators confirmed. Thank-you chip for keeping the community safe."
        case .established:
            return "Account is at least 30 days old with zero safety strikes. Helps you spot brand-new or throwaway accounts at a glance."
        case .founding:
            return "Joined Whisper in the launch window. A small thank-you to the first users on the platform."
        }
    }

    /// Returns the active chip kinds for a given user, in render/priority order.
    /// Identical logic powers the 2-chip inline cap and the full shelf.
    @MainActor
    static func active(
        forUsername username: String?,
        userID: String?,
        liar: WhisperLiarLiarService,
        safety: WhisperSafetyService
    ) -> [WhisperBadgeKind] {
        var chips: [WhisperBadgeKind] = []

        // Safety Watch — mod-only.
        let watchRow: WhisperSafetyFlagRow? = {
            if let userID, let row = safety.watchRow(forUserID: userID) { return row }
            if let username, let row = safety.watchRow(forUsername: username) { return row }
            return nil
        }()
        if watchRow != nil { chips.append(.safetyWatch) }

        // DM Restriction.
        if let userID, safety.isDMRestricted(userID: userID) {
            chips.append(.restricted)
        }

        // Liar Liar — keyed by username.
        if let username, let row = liar.badge(forUsername: username) {
            chips.append(.liar(muted: row.hasAppealedPending))
        }

        // Whisper One — black + seal for active subscribers (paid perk, so it
        // outranks the trust chips for the limited inline slots).
        let oneSvc = WhisperOneService.shared
        if oneSvc.isOne(userID: userID) || oneSvc.isOne(username: username) {
            chips.append(.one)
        }

        // Verified Coach — keyed by either userID or username.
        let coachSvc = WhisperCoachService.shared
        let isCoach: Bool = {
            if let uid = userID, coachSvc.isCoach(userID: uid) { return true }
            if let username, coachSvc.isCoach(username: username) { return true }
            // Fall back to the current user's own status so the chip shows
            // on the local profile before any directory lookup completes.
            return coachSvc.isMeCoach && (username?.caseInsensitiveCompare(
                LeaderboardService.shared.savedUsername ?? ""
            ) == .orderedSame)
        }()
        if isCoach { chips.append(.coach) }

        // Whisper Director — Whisper media team. Reads the `is_director` flag
        // from `whisper_profiles` (set manually by the founder/admin). Falls
        // back to the current user's own status so the chip shows on the
        // local profile before any lookup completes.
        let directorSvc = WhisperDirectorService.shared
        let isDirector: Bool = {
            if let uid = userID, directorSvc.isDirector(userID: uid) { return true }
            return directorSvc.isMeDirector && (username?.caseInsensitiveCompare(
                LeaderboardService.shared.savedUsername ?? ""
            ) == .orderedSame)
        }()
        if isDirector { chips.append(.director) }

        // Whisper Blogger — dedicated writer role, `is_blogger` on
        // whisper_profiles (granted from the admin console, never sold).
        let isBlogger: Bool = {
            if let uid = userID, directorSvc.isBlogger(userID: uid) { return true }
            return directorSvc.isMeBlogger && (username?.caseInsensitiveCompare(
                LeaderboardService.shared.savedUsername ?? ""
            ) == .orderedSame)
        }()
        if isBlogger { chips.append(.blogger) }

        // Age chips (mutually exclusive).
        if let userID {
            if safety.isTeen(userID: userID) {
                chips.append(.teen)
            } else if safety.isAdultAttested(userID: userID) {
                chips.append(.adult)
            }
        }

        // Reputation tiers — Trusted suppresses Established below it.
        if let userID {
            if safety.isTrustedMember(userID: userID) {
                chips.append(.trusted)
            } else if safety.isEstablishedMember(userID: userID) {
                // Established only shows when Restricted isn't already present.
                if !chips.contains(.restricted) { chips.append(.established) }
            }
            if safety.isCommunityGuardian(userID: userID), !chips.contains(.restricted) {
                chips.append(.guardianRole)
            }
            if safety.isFoundingMember(userID: userID) {
                chips.append(.founding)
            }
        }

        // Public age, reputation, membership and professional seals are retired.
        return []
    }

    /// Short label used in the inline text pill (kept punchy).
    var pillLabel: String {
        switch self {
        case .safetyWatch:   return "Safety Watch"
        case .restricted:    return "Restricted"
        case .liar:          return "Liar Liar"
        case .one:           return "One"
        case .coach:         return "Coach"
        case .director:       return "Director"
        case .blogger:       return "Blogger"
        case .teen:          return "Teen"
        case .adult:         return "18+"
        case .trusted:       return "Trusted"
        case .guardianRole:  return "Guardian"
        case .established:   return "Established"
        case .founding:      return "Founding"
        }
    }

    /// SF Symbol shown to the left of the pill label.
    var pillSymbol: String {
        switch self {
        case .safetyWatch:   return "eye.fill"
        case .restricted:    return "hand.raised.fill"
        case .liar:          return "exclamationmark.bubble.fill"
        case .one:           return "plus.circle.fill"
        case .coach:         return "figure.run.circle.fill"
        case .director:       return "film.circle.fill"
        case .blogger:       return "pencil.line"
        case .teen:          return "figure.child.circle.fill"
        case .adult:         return "checkmark.shield.fill"
        case .trusted:       return "hand.thumbsup.fill"
        case .guardianRole:  return "shield.lefthalf.filled"
        case .established:   return "calendar.badge.checkmark"
        case .founding:      return "sparkles"
        }
    }

    /// Tinted text pill (icon + label) used inline next to the username on
    /// profile pages. Always draws a real capsule behind the label so every
    /// badge stays legible on light, dark, and pitch-black surfaces.
    @ViewBuilder
    func pill() -> some View {
        WhisperBadgeTextPill(kind: self)
    }

    /// Renders the small chip glyph used both inline and inside shelf rows.
    @ViewBuilder
    func view(size: CGFloat, liar: WhisperLiarLiarService) -> some View {
        switch self {
        case .safetyWatch:        WhisperSafetyWatchBadge(size: size)
        case .restricted:         WhisperRestrictedBadge(size: size)
        case .liar(let muted):    WhisperLiarLiarBadge(size: size, muted: muted)
        case .one:                WhisperOneBadge(size: size)
        case .coach:              WhisperCoachBadge(size: size)
        case .director:           WhisperDirectorBadge(size: size)
        case .blogger:            WhisperBloggerBadge(size: size)
        case .teen:               WhisperTeenBadge(size: size)
        case .adult:              WhisperAdultBadge(size: size)
        case .trusted:            WhisperTrustedBadge(size: size)
        case .guardianRole:       WhisperGuardianBadge(size: size)
        case .established:        WhisperEstablishedBadge(size: size)
        case .founding:           WhisperFoundingBadge(size: size)
        }
    }
}

/// Capsule chip for a badge kind — tinted fill + hairline ring. Near-black
/// accents (Whisper One, Director) flip to white in dark mode so the chip
/// never disappears into a dark background.
struct WhisperBadgeTextPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let kind: WhisperBadgeKind

    private var displayAccent: Color {
        if colorScheme == .dark, kind == .one || kind == .director {
            return .white
        }
        return kind.accent
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind.pillSymbol)
                .font(.caption2.weight(.bold))
            Text(kind.pillLabel)
                .font(.footnote.weight(.bold))
        }
        .foregroundStyle(displayAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 4.5)
        .background(
            displayAccent.opacity(colorScheme == .dark ? 0.16 : 0.10),
            in: Capsule()
        )
        .overlay {
            Capsule().strokeBorder(
                displayAccent.opacity(colorScheme == .dark ? 0.34 : 0.22),
                lineWidth: 0.75
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.title)
    }
}
