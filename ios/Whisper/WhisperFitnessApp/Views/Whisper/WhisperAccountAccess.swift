import SwiftUI

/// THE ACCOUNT LADDER — one place that says who gets what, so the feature
/// sets can never overlap by accident. Every gate in the app should read
/// from here instead of re-deriving "is this person a creator?" locally.
///
/// The tiers, from the bottom:
///
/// - PERSONAL (every account): post whisps, waves, stories, DMs, communities,
///   dating, meetings. No insights surface at all.
/// - PROFESSIONAL (self-selected at signup or in Settings — "creator" or
///   "business" `account_type`): everything personal PLUS **Analytics** — the
///   basic insights screen (30-day reach, interactions, followers, top
///   posts) — plus the niche line under the name and contact buttons.
///   NEVER Creator Studio. Anyone can flip this on for free, so it must
///   not unlock anything that's earned or paid.
/// - WHISPER ONE (paid membership): personal/professional PLUS the black +
///   badge, coach tools (3 client slots), longer posts, and Analytics
///   (the same insights screen professionals get — not Creator Studio).
/// - WHISPER PLUS (paid, the rung between One and Verified): everything One
///   has PLUS the Jasper Intelligence pro pack — unlimited Jasper chats,
///   voice mode, Imagine, /jasper in DMs and groups, the matchmaker and
///   meeting companion without daily caps, memory across chats, priority
///   answers. Never Creator Studio, never the blue check.
/// - VERIFIED CREATOR (applied, human-approved, then paid yearly): the blue
///   check PLUS **Creator Studio** (score ring, WPP creator pay, momentum,
///   top posts), pinned posts, the grid composer, articles, creator tools
///   in meetings, the 1.6× algorithm boost, the 1,500-character limit.
/// - VERIFIED COACH / BRAND / RECRUITER: their own studios (Coach Studio,
///   Business Suite, Recruiter HQ) — orthogonal to the creator ladder.
/// - STAFF (moderator / admin / owner): everything a verified creator has,
///   plus the admin console.
@MainActor
enum WhisperAccountAccess {
    // MARK: Identity checks

    /// The signed-in user's own profile row (nil while loading / signed out).
    private static var me: WhisperUserRow? { WhisperUserService.shared.me }

    /// Self-selected professional account (creator or business type).
    static var isProfessional: Bool { me?.isProfessionalAccount ?? false }

    /// Self-selected "business" type specifically.
    static var isBusinessType: Bool { (me?.account_type ?? "").lowercased() == "business" }

    /// Verified creator OR staff (the blue-check ladder).
    static func isVerifiedCreator(username: String) -> Bool {
        WhisperVerifiedPerks.isVerified(username: username)
    }

    /// Whisper One member (the paid + badge).
    static func isOneMember(username: String) -> Bool {
        WhisperOneService.shared.isOne(username: username)
            || WhisperOneService.shared.isOne(userID: AccountStorage.currentUserID)
    }

    /// Whisper Plus member — the Jasper Intelligence pro pack. Reads the
    /// `whisper_plus` entitlement flag on the profile row (migration
    /// supabase/whisper-plus.sql); staff and verified creators inherit it.
    static func isPlusMember(username: String) -> Bool {
        if isVerifiedCreator(username: username) { return true }
        return me?.is_plus ?? false
    }

    // MARK: Jasper Intelligence entitlements

    /// What each rung of the ladder gets from Jasper. The FREE tier is real
    /// and generous enough to fall in love with; Plus removes every cap.
    struct JasperEntitlements: Equatable {
        /// Daily chat turns in Jasper Intelligence (nil = unlimited).
        let dailyChats: Int?
        /// Daily Imagine renders (nil = unlimited).
        let dailyImagines: Int?
        /// Realtime voice mode.
        let voiceMode: Bool
        /// /jasper in DMs + groups, the matchmaker dock, meeting companion.
        let jasperInChats: Bool
        /// Memory that carries across conversations.
        let memory: Bool
        /// Live web research answers with sources.
        let webResearch: Bool
        /// Priority queue — answers ahead of free traffic.
        let priority: Bool
        let tierName: String
    }

    static let freeJasper = JasperEntitlements(
        dailyChats: 15, dailyImagines: 3, voiceMode: false, jasperInChats: true,
        memory: false, webResearch: false, priority: false, tierName: "Free"
    )
    static let oneJasper = JasperEntitlements(
        dailyChats: 60, dailyImagines: 15, voiceMode: true, jasperInChats: true,
        memory: false, webResearch: true, priority: false, tierName: "Whisper One"
    )
    static let plusJasper = JasperEntitlements(
        dailyChats: nil, dailyImagines: nil, voiceMode: true, jasperInChats: true,
        memory: true, webResearch: true, priority: true, tierName: "Whisper Plus"
    )

    /// The Jasper pack for the signed-in account.
    static func jasperEntitlements(username: String) -> JasperEntitlements {
        if isPlusMember(username: username) { return plusJasper }
        if isOneMember(username: username) { return oneJasper }
        return freeJasper
    }

    // MARK: The matrix

    /// Creator Studio — VERIFIED ONLY. Professional accounts and Whisper One
    /// members get `canOpenAnalytics` instead.
    static func canOpenCreatorStudio(username: String) -> Bool {
        isVerifiedCreator(username: username)
    }

    /// Analytics — the basic insights screen: professional accounts and One
    /// members. Verified creators don't need it (Creator Studio supersedes).
    static func canOpenAnalytics(username: String) -> Bool {
        guard !isVerifiedCreator(username: username) else { return false }
        return isProfessional || isOneMember(username: username)
    }

    /// The insights door shown top-left on the profile: nil (personal),
    /// `.analytics` (professional / One), or `.creatorStudio` (verified).
    static func insightsDoor(username: String) -> InsightsDoor? {
        if canOpenCreatorStudio(username: username) { return .creatorStudio }
        if canOpenAnalytics(username: username) { return .analytics }
        return nil
    }

    enum InsightsDoor: Equatable {
        case analytics, creatorStudio

        var title: String {
            switch self {
            case .analytics: return "Analytics"
            case .creatorStudio: return "Creator Studio"
            }
        }

        var icon: String {
            switch self {
            case .analytics: return "chart.bar.xaxis"
            case .creatorStudio: return "chart.line.uptrend.xyaxis"
            }
        }
    }

    /// The IG-style grid (photo) composer — verified creators only.
    static func canPostGrid(username: String) -> Bool {
        isVerifiedCreator(username: username)
    }

    /// Pinned posts on the profile — verified creators only.
    static func canPinPosts(username: String) -> Bool {
        isVerifiedCreator(username: username)
    }

    /// Long-form articles — verified creators, coaches, and staff.
    static func canWriteArticles(username: String) -> Bool {
        isVerifiedCreator(username: username) || WhisperCoachService.shared.isMeCoach
    }

    /// Human-readable tier label for the settings account header.
    static func tierLabel(username: String) -> String {
        let badge = UserVerificationService.shared.badge(forUsername: username)
        switch badge {
        case .owner: return "Owner"
        case .admin: return "Admin"
        case .moderator: return "Moderator"
        case .verified: return "Verified creator"
        default: break
        }
        if isPlusMember(username: username) { return "Whisper Plus" }
        if isOneMember(username: username) { return "Whisper One" }
        if isBusinessType { return "Business account" }
        if isProfessional { return "Creator account" }
        return "Personal account"
    }
}
