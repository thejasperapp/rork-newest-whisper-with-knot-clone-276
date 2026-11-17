import Foundation
import Supabase
import SwiftUI

// MARK: - Models

nonisolated struct WhisperFeaturedProfile: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let kind: String
    let name: String
    let username: String?
    let user_id: String?
    let photo_url: String?
    let tier: Int?
    let discipline: String?
    let age: String?
    let chips: [String]?
    let paragraphs: [String]?
    let highlights: [String]?
    let testimonials: [WhisperFeaturedTestimonial]?
    let cta_label: String?
    let cta_url: String?
    let sort_order: Int?
    let published: Bool?

    nonisolated enum CodingKeys: String, CodingKey {
        case id, kind, name, username, user_id, photo_url, tier, discipline, age
        case chips, paragraphs, highlights, testimonials, cta_label, cta_url
        case sort_order, published
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "coach"
        name = try c.decode(String.self, forKey: .name)
        username = try? c.decodeIfPresent(String.self, forKey: .username)
        user_id = try? c.decodeIfPresent(String.self, forKey: .user_id)
        photo_url = try? c.decodeIfPresent(String.self, forKey: .photo_url)
        tier = try? c.decodeIfPresent(Int.self, forKey: .tier)
        discipline = try? c.decodeIfPresent(String.self, forKey: .discipline)
        age = try? c.decodeIfPresent(String.self, forKey: .age)
        chips = try? c.decodeIfPresent([String].self, forKey: .chips)
        paragraphs = try? c.decodeIfPresent([String].self, forKey: .paragraphs)
        highlights = try? c.decodeIfPresent([String].self, forKey: .highlights)
        testimonials = try? c.decodeIfPresent([WhisperFeaturedTestimonial].self, forKey: .testimonials)
        cta_label = try? c.decodeIfPresent(String.self, forKey: .cta_label)
        cta_url = try? c.decodeIfPresent(String.self, forKey: .cta_url)
        sort_order = try? c.decodeIfPresent(Int.self, forKey: .sort_order)
        published = try? c.decodeIfPresent(Bool.self, forKey: .published)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(user_id, forKey: .user_id)
        try c.encodeIfPresent(photo_url, forKey: .photo_url)
        try c.encodeIfPresent(tier, forKey: .tier)
        try c.encodeIfPresent(discipline, forKey: .discipline)
        try c.encodeIfPresent(age, forKey: .age)
        try c.encodeIfPresent(chips, forKey: .chips)
        try c.encodeIfPresent(paragraphs, forKey: .paragraphs)
        try c.encodeIfPresent(highlights, forKey: .highlights)
        try c.encodeIfPresent(testimonials, forKey: .testimonials)
        try c.encodeIfPresent(cta_label, forKey: .cta_label)
        try c.encodeIfPresent(cta_url, forKey: .cta_url)
        try c.encodeIfPresent(sort_order, forKey: .sort_order)
        try c.encodeIfPresent(published, forKey: .published)
    }

    var kindEnum: FeaturedKind {
        FeaturedKind(rawValue: kind) ?? .coach
    }

    var ctaLabel: String {
        let label = cta_label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !label.isEmpty { return label }
        return kindEnum == .coach ? "Train with \(name)" : "Follow \(name)"
    }

    var ctaURL: URL? {
        let raw = cta_url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// Absolute photo URL. Admin-curated spotlight rows often store
    /// site-relative paths like "/coaches/hudson.jpeg" (they render fine on
    /// the web); AsyncImage needs a full URL, so relative paths are resolved
    /// against the public web origin.
    var resolvedPhotoURL: URL? {
        Self.resolvePhotoURL(photo_url)
    }

    nonisolated static func resolvePhotoURL(_ raw: String?) -> URL? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        let path = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        return URL(string: WhisperBillingBackend.webOrigin + path)
    }
}

nonisolated struct WhisperFeaturedTestimonial: Codable, Sendable, Hashable {
    let quote: String?
    let name: String?
    let result: String?
}

nonisolated enum FeaturedKind: String, Sendable {
    case coach
    case athlete
    case creator
    case director
}

// MARK: - Shared kind styling

/// Single source of truth for spotlight identity styling. Every surface
/// (search cards, featured rails, detail sheets, profile banners) pulls the
/// same seal colour, icon, and label so special accounts read as one
/// consistent system instead of each screen inventing its own palette.
extension FeaturedKind {
    /// Seal colour — the ONLY place colour appears on spotlight surfaces.
    /// Everything else stays in Whisper's black & white language.
    var sealColor: Color {
        switch self {
        case .coach:    return WhisperTheme.coachAccent
        case .athlete:  return Color(red: 0.88, green: 0.11, blue: 0.28)
        case .creator:  return Color(red: 0.13, green: 0.55, blue: 0.96)
        case .director: return Color(red: 0.10, green: 0.10, blue: 0.10)
        }
    }

    var sealIcon: String {
        switch self {
        case .coach:    return "figure.strengthtraining.traditional"
        case .athlete:  return "trophy.fill"
        case .creator:  return "checkmark.seal.fill"
        case .director: return "movieclapper.fill"
        }
    }

    var displayLabel: String {
        switch self {
        case .coach:    return "Coach"
        case .athlete:  return "Athlete"
        case .creator:  return "Creator"
        case .director: return "Director"
        }
    }
}

// MARK: - Service

/// Fetches admin-curated featured spotlight profiles from Supabase (anon
/// read, RLS-guarded) and enriches in-app profile views with spotlight data.
/// Mirrors the web app's `fetchFeaturedProfiles` and
/// `fetchFeaturedProfileByUsername`.
@MainActor
@Observable
final class WhisperFeaturedService {
    static let shared = WhisperFeaturedService()

    private let client = SupabaseService.shared.client

    /// Cache: kind → published profiles. Refreshed on demand.
    var profilesByKind: [FeaturedKind: [WhisperFeaturedProfile]] = [:]
    /// Cache: lowercased username → featured profile. Populated alongside
    /// `profilesByKind` so the search and profile views can enrich real
    /// user rows with spotlight data in one lookup.
    var profileByUsername: [String: WhisperFeaturedProfile] = [:]
    var lastError: String?

    private init() {}

    /// Fetches all published featured profiles of a given kind.
    func fetchProfiles(kind: FeaturedKind) async -> [WhisperFeaturedProfile] {
        if let cached = profilesByKind[kind], !cached.isEmpty { return cached }
        do {
            let rows: [WhisperFeaturedProfile] = try await client
                .from("whisper_featured_profiles")
                .select()
                .eq("kind", value: kind.rawValue)
                .eq("published", value: true)
                .order("sort_order", ascending: true)
                .order("created_at", ascending: true)
                .execute()
                .value
            profilesByKind[kind] = rows
            for row in rows {
                if let uname = row.username?.lowercased(), !uname.isEmpty {
                    profileByUsername[uname] = row
                }
            }
            return rows
        } catch {
            // Table may not exist yet — return empty, don't surface error.
            lastError = error.localizedDescription
            return []
        }
    }

    /// Looks up a featured profile by username (case-insensitive).
    func fetchByUsername(_ username: String) async -> WhisperFeaturedProfile? {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
        if !clean.isEmpty, let cached = profileByUsername[clean] {
            return cached
        }
        guard !clean.isEmpty else { return nil }
        do {
            let rows: [WhisperFeaturedProfile] = try await client
                .from("whisper_featured_profiles")
                .select()
                .ilike("username", value: clean)
                .eq("published", value: true)
                .limit(1)
                .execute()
                .value
            if let row = rows.first {
                profileByUsername[clean] = row
                return row
            }
        } catch {
            lastError = error.localizedDescription
        }
        return nil
    }

    /// Clears the cache so the next fetch hits Supabase fresh.
    func clearCache() {
        profilesByKind.removeAll()
        profileByUsername.removeAll()
    }
}

// MARK: - Spotlight card (compact, for search results)

/// Compact spotlight card for featured profiles in search results — shows
/// photo, name, badge, discipline, and a CTA. Mirrors the web's
/// CoachSearchCard spotlight style.
struct WhisperFeaturedSpotlightCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let profile: WhisperFeaturedProfile

    private var kind: FeaturedKind { profile.kindEnum }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo — quiet monochrome fallback, small kind seal. The image
            // is anchored to the TOP of the panel (not centered) so portrait
            // photos keep faces in frame and crop from the bottom instead of
            // slicing heads off in the middle.
            ZStack(alignment: .topLeading) {
                WhisperTheme.card(colorScheme)
                    .frame(height: 190)
                    .overlay(alignment: .top) {
                        if let url = profile.resolvedPhotoURL {
                            WhisperCachedAsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .allowsHitTesting(false)
                                default:
                                    photoFallback
                                }
                            }
                        } else {
                            photoFallback
                        }
                    }
                    .clipped()

                Image(systemName: kind.sealIcon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(kind.sealColor, in: Circle())
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                    }
                    .padding(10)
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(profile.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    Image(systemName: kind.sealIcon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(kind.sealColor)
                }
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
                if let firstParagraph = profile.paragraphs?.first, !firstParagraph.isEmpty {
                    Text(firstParagraph)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(2)
                        .padding(.top, 1)
                }
                HStack(spacing: 4) {
                    Text(profile.ctaLabel)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    Image(systemName: profile.ctaURL != nil ? "arrow.up.right" : "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(.top, 4)
            }
            .padding(14)
        }
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 18))
        .contentShape(.rect)
    }

    /// Dot-separated identity line — kind · discipline (no chip clutter).
    private var metaLine: String {
        var parts: [String] = [kind.displayLabel]
        if let discipline = profile.discipline, !discipline.isEmpty {
            parts.append(discipline)
        }
        return parts.joined(separator: " · ")
    }

    private var photoFallback: some View {
        ZStack {
            WhisperTheme.card(colorScheme)
            Image(systemName: kind.sealIcon)
                .font(.title.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.5))
        }
    }
}

// MARK: - Full spotlight detail (for profile tap-through)

/// Full-featured spotlight view shown when a user taps a spotlight card.
/// Shows the full profile with paragraphs, highlights, and testimonials.
struct WhisperFeaturedProfileDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let profile: WhisperFeaturedProfile

    private var accentColor: Color { profile.kindEnum.sealColor }

    private var kindIcon: String { profile.kindEnum.sealIcon }

    private let highlightIcons = [
        "figure.strengthtraining.traditional",
        "calendar.checkmark",
        "message.circle",
        "person.2.fill"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        // Photo header — top-anchored crop so faces stay in
                        // frame; overflow crops from the bottom.
                        ZStack(alignment: .bottomLeading) {
                            WhisperTheme.card(colorScheme)
                                .frame(height: 360)
                                .overlay(alignment: .top) {
                                    if let url = profile.resolvedPhotoURL {
                                        WhisperCachedAsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let img):
                                                img.resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .allowsHitTesting(false)
                                            default:
                                                LinearGradient(
                                                    colors: [accentColor.opacity(0.3), accentColor.opacity(0.1)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            }
                                        }
                                    } else {
                                        LinearGradient(
                                            colors: [accentColor.opacity(0.3), accentColor.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    }
                                }
                                .clipped()
                                .overlay(alignment: .topLeading) {
                                    Image(systemName: kindIcon)
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 30, height: 30)
                                        .background(accentColor, in: Circle())
                                        .overlay {
                                            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                                        }
                                        .padding(16)
                                }

                        }
                        .ignoresSafeArea(edges: .top)
                        .padding(.top, -48)

                        VStack(alignment: .leading, spacing: 16) {
                            // Name + badge
                            HStack(spacing: 8) {
                                Text(profile.name)
                                    .font(.largeTitle.weight(.black))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                Image(systemName: kindIcon)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(accentColor)
                            }

                            // Chips
                            chipRow

                            // Paragraphs
                            if let paragraphs = profile.paragraphs {
                                ForEach(paragraphs.indices, id: \.self) { i in
                                    Text(paragraphs[i])
                                        .font(.subheadline)
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                        .lineSpacing(4)
                                }
                            }

                            // Highlights
                            if let highlights = profile.highlights, !highlights.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(highlights.indices, id: \.self) { i in
                                        HStack(spacing: 10) {
                                            Image(systemName: highlightIcons[i % highlightIcons.count])
                                                .font(.body)
                                                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
                                                .frame(width: 24)
                                            Text(highlights[i])
                                                .font(.footnote.weight(.medium))
                                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                            Spacer()
                                        }
                                        .padding(.vertical, 6)
                                    }
                                }
                                .padding(14)
                                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }
                            }

                            // CTA
                            if let url = profile.ctaURL {
                                Button {
                                    Haptics.tap()
                                    WhisperInAppBrowser.shared.open(url)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(profile.ctaLabel)
                                            .font(.body.weight(.bold))
                                        Image(systemName: "arrow.up.right")
                                            .font(.subheadline.weight(.bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                                }
                                .buttonStyle(.plain)
                            } else if let username = profile.username, !username.isEmpty {
                                NavigationLink(value: username) {
                                    HStack(spacing: 4) {
                                        Text(profile.ctaLabel)
                                            .font(.body.weight(.bold))
                                        Image(systemName: "arrow.right")
                                            .font(.subheadline.weight(.bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                                }
                                .buttonStyle(.plain)
                            }

                            // Testimonials
                            if let testimonials = profile.testimonials, !testimonials.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(profile.kindEnum == .coach
                                         ? "What \(profile.name)'s clients say"
                                         : "What people say about \(profile.name)")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                                        .padding(.top, 8)

                                    ForEach(testimonials.indices, id: \.self) { i in
                                        testimonialCard(testimonials[i])
                                    }
                                }
                            }

                            Color.clear.frame(height: 32)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.25), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let tier = profile.tier {
                    chip("Tier \(tier)\(profile.discipline.map { " · \($0)" } ?? "")")
                } else if let discipline = profile.discipline, !discipline.isEmpty {
                    chip(discipline)
                }
                if let age = profile.age, !age.isEmpty {
                    chip(age)
                }
                ForEach(profile.chips ?? [], id: \.self) { chipText in
                    chip(chipText)
                }
                if let username = profile.username, !username.isEmpty {
                    chip("@\(username)")
                }
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(WhisperTheme.card(colorScheme), in: Capsule())
            .overlay {
                Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
    }

    private func testimonialCard(_ t: WhisperFeaturedTestimonial) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.body)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            if let quote = t.quote, !quote.isEmpty {
                Text(quote)
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineSpacing(3)
            }
            HStack {
                if let name = t.name, !name.isEmpty {
                    Text(name)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                Spacer()
                if let result = t.result, !result.isEmpty {
                    Text(result)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(WhisperTheme.card(colorScheme), in: Capsule())
                }
            }
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }
}
