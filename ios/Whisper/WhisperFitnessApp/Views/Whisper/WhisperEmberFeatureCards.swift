import SwiftUI

// MARK: - EmberRole

/// Whisper roles Jasper tailors itself to — mirrors the web `EmberRole`.
nonisolated enum WhisperEmberRole: String, Sendable, CaseIterable {
    case member
    case creator
    case coach
    case athlete
    case recruiter
    case moderator
    case admin
    case owner

    var title: String {
        switch self {
        case .creator: return "Creator"
        case .coach: return "Coach"
        case .athlete: return "Athlete"
        case .recruiter: return "Recruiter"
        case .moderator: return "Moderator"
        case .admin: return "Admin"
        case .owner: return "Owner"
        default: return "Member"
        }
    }
}

/// Resolves the user's Whisper role from their profile flags + verification badge.
@MainActor
func resolveEmberRole() -> WhisperEmberRole {
    let myUsername = LeaderboardService.shared.savedUsername
        ?? AuthenticationService.shared.currentUser.username
        ?? ""
    let badge = UserVerificationService.shared.badge(forUsername: myUsername)
    if badge == .owner { return .owner }
    if badge == .admin { return .admin }
    if badge == .moderator { return .moderator }
    if WhisperCoachService.shared.isMeCoach { return .coach }
    if WhisperRecruiterService.shared.isMeRecruiter { return .recruiter }
    if WhisperAthleteService.shared.isMeAthlete { return .athlete }
    if badge == .verified { return .creator }
    return .member
}

/// Role-tailored quick suggestions for the Jasper empty state.
nonisolated func emberRoleSuggestions(_ role: WhisperEmberRole, hasWhisper: Bool) -> [String] {
    let jasper: [String] = hasWhisper ? ["Chart my steps for the last 7 days"] : []
    switch role {
    case .creator:
        return [
            "Chart my likes per post this month",
            "Write my next post \u{2014} something personal",
            "What do my top posts have in common?",
            "Punch up my bio for sponsors",
        ] + jasper
    case .coach:
        return [
            "Draft a post that attracts new clients",
            "How's my engagement trending?",
            "Write a check-in message for a quiet client",
            "Make my profile read more professional",
        ] + jasper
    case .athlete:
        return [
            "Turn this week's training into a post",
            "Chart my posting consistency",
            "How do I get noticed by recruiters?",
            "Write a PR announcement post",
        ] + jasper
    case .recruiter:
        return [
            "Draft an outreach DM to an athlete",
            "What makes an athlete profile credible?",
            "Write a post about what I look for",
            "How's my own engagement trending?",
        ]
    case .moderator, .admin, .owner:
        return [
            "Chart my posts per day this month",
            "Draft a community announcement",
            "Write a de-escalation reply to a heated thread",
            "What should we amplify this week?",
        ]
    default:
        return [
            "Write my next post for me",
            "Chart my likes this month",
            "Which community should I post in?",
            "Make my bio hit harder",
        ] + jasper
    }
}

// MARK: - EmberFeatureKind

/// Deterministic real-product card rendered inside Jasper for a social intent.
nonisolated enum WhisperEmberFeatureKind: String, Sendable, CaseIterable {
    case people
    case verification
    case profile
    case communities
    case brands
    case coaching
    case recruiting
    case moderation
    case collaboration
}

nonisolated struct WhisperEmberFeature: Sendable, Identifiable, Hashable {
    let id = UUID()
    let kind: WhisperEmberFeatureKind
    let title: String
    let subtitle: String
    var icon: String {
        switch kind {
        case .people: return "person.2.fill"
        case .verification: return "checkmark.seal.fill"
        case .profile: return "person.crop.circle.badge.plus"
        case .communities: return "safari.fill"
        case .brands: return "briefcase.fill"
        case .coaching: return "heart.text.square.fill"
        case .recruiting: return "magnifyingglass"
        case .moderation: return "shield.lefthalf.filled"
        case .collaboration: return "hand.raised.fill"
        }
    }
}

/// Intent router for the dynamic in-chat product cards. Heuristic matching
/// of natural phrasings — independent of LLM output formatting.
nonisolated func emberFeatureForMessage(_ message: String) -> WhisperEmberFeature? {
    let q = message.lowercased()
    func has(_ needles: String...) -> Bool { needles.contains { q.contains($0) } }

    if has("follower", "follow me", "follow people", "suggested people", "people who match",
          "match my interest", "meet people", "find people", "who should i follow", "collaborator") {
        return .init(kind: .people, title: "People for you",
                     subtitle: "Real Whisper profiles picked from your interests and role.")
    }
    if has("verified", "verification", "blue check", "get a check", "become a creator",
          "become a coach", "become an athlete", "apply for") {
        return .init(kind: .verification, title: "Find your verified path",
                     subtitle: "Pick a real Whisper application \u{2014} a person reviews every one.")
    }
    if has("bio", "profile", "profile picture", "profile photo", "pinned post",
          "make my profile", "improve my profile") {
        return .init(kind: .profile, title: "Your profile, sharpened",
                     subtitle: "Open your real profile settings or let Jasper draft a stronger bio.")
    }
    if has("community", "where should i post", "what should i post", "hashtag", "topic", "niche") {
        return .init(kind: .communities, title: "Find your corner of Whisper",
                     subtitle: "Explore communities and post where your people already are.")
    }
    if has("brand", "sponsor", "sponsorship", "deal", "media kit", "paid post") {
        return .init(kind: .brands, title: "Brand opportunities",
                     subtitle: "Browse live sponsorships with real budgets and escrow protection.")
    }
    if has("client", "coach", "program", "check-in", "coaching", "macro") {
        return .init(kind: .coaching, title: "Coach tools, ready",
                     subtitle: "Use your real Coach Studio to manage people, programs, and payments.")
    }
    if has("recruit", "scout", "prospect", "talent", "athlete search", "outreach") {
        return .init(kind: .recruiting, title: "Scout the right people",
                     subtitle: "Open the real recruiter pipeline and start a thoughtful outreach flow.")
    }
    if has("report", "moderate", "safety", "harassment", "block", "community health") {
        return .init(kind: .moderation, title: "Keep Whisper human",
                     subtitle: "Use real safety tools and team review flows \u{2014} never handle it alone.")
    }
    if has("collab", "project", "team up", "work together", "campaign", "challenge", "creator house") {
        return .init(kind: .collaboration, title: "Make something together",
                     subtitle: "Moderator-invited projects for creators, coaches, athletes, and recruiters.")
    }
    return nil
}

// MARK: - Feature card view

/// Renders a deterministic in-chat feature card with a tappable action button
/// that deep-links into the real Whisper flow for that feature.
struct WhisperEmberFeatureCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let feature: WhisperEmberFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: feature.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(width: 28, height: 28)
                    .background(WhisperTheme.ink(colorScheme), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(feature.title)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(feature.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                WhisperTheme.hairline(colorScheme).frame(height: 0.75)
            }

            // Action area
            VStack(alignment: .leading, spacing: 8) {
                if let helper = actionHelper {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        Text(helper)
                            .font(.system(size: 12.5))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(WhisperTheme.surface(colorScheme).opacity(0.5), in: .rect(cornerRadius: 12))
                }
                actionButton
            }
            .padding(14)
        }
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    // MARK: - Action

    private var actionLabel: String {
        switch feature.kind {
        case .people: return "Explore more people"
        case .verification: return "Apply for verification"
        case .profile: return "Open Edit profile"
        case .communities: return "Search all communities"
        case .brands: return "Browse sponsor brands"
        case .coaching: return "Open Coach Studio"
        case .recruiting: return "Open recruiter pipeline"
        case .moderation: return "Open safety tools"
        case .collaboration: return "Open Collab Projects"
        }
    }

    private var actionIcon: String {
        switch feature.kind {
        case .people: return "person.2.fill"
        case .verification: return "checkmark.seal.fill"
        case .profile: return "sparkles"
        case .communities: return "safari.fill"
        case .brands: return "briefcase.fill"
        case .coaching: return "heart.text.square.fill"
        case .recruiting: return "magnifyingglass"
        case .moderation: return "shield.lefthalf.filled"
        case .collaboration: return "hand.raised.fill"
        }
    }

    private var actionHelper: String? {
        switch feature.kind {
        case .brands: return "Live opportunities show real budgets, requirements, and payment terms before you apply."
        case .coaching: return "Manage clients, programs, and coaching income through the real studio."
        case .recruiting: return "Scout consistently, make thoughtful outreach, and keep every prospect in one place."
        case .moderation: return "Reports, trust, and community health work best when the whole team follows one process."
        case .collaboration: return "Invite creators, coaches, athletes, and recruiters into a shared campaign or challenge."
        case .profile: return "Update your name, bio, cover photo, and interests in the exact same profile editor the app uses."
        default: return nil
        }
    }

    private var actionButton: some View {
        Button {
            Haptics.tap()
            handleAction()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: actionIcon)
                    .font(.system(size: 12, weight: .bold))
                Text(actionLabel)
                    .font(.subheadline.weight(.bold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(WhisperTheme.ink(colorScheme), in: Capsule())
            .foregroundStyle(WhisperTheme.surface(colorScheme))
        }
        .buttonStyle(.plain)
    }

    /// Deep-links into the real Whisper flow for this feature through the
    /// Jasper action router (dismisses the chat sheet, then routes).
    private func handleAction() {
        let router = WhisperEmberActionRouter.shared
        switch feature.kind {
        case .people: router.navigate(route: "explore")
        case .verification: router.navigate(route: "verification")
        case .profile: router.navigate(route: "edit_profile")
        case .communities: router.navigate(route: "communities")
        case .brands: router.navigate(route: "brands")
        case .coaching: router.navigate(route: "coach_clients")
        case .recruiting: router.navigate(route: "recruiter")
        case .moderation: router.navigate(route: "security")
        case .collaboration: router.navigate(route: "communities")
        }
    }
}
