import SwiftUI
import Foundation
import Supabase

// MARK: - Business+ company card wire payload (camelCase, web-ready)

/// The live company card a Business+ member presents into a meeting — the
/// exact camelCase payload web meetings broadcast on the "business-card"
/// app event, so cards shared from either platform render on both.
nonisolated struct WhisperBusinessCardWire: Codable, Sendable, Hashable {
    nonisolated struct Role: Codable, Sendable, Hashable {
        var title: String
        var blurb: String?
    }

    nonisolated struct TeamMate: Codable, Sendable, Hashable {
        var username: String
        var roleTitle: String?
        var accent: String?
    }

    var presenterUserId: String
    var presenterName: String
    var businessId: String?
    /// "company" | "roles" | "team" — unknown modes coerce to "company".
    var mode: String?
    var company: String
    var about: String?
    var industry: String?
    var logoUrl: String?
    var positions: [String]?
    var roles: [Role]?
    var team: [TeamMate]?
    var applyUrl: String?
    /// Bumped per fresh present so viewers re-arm their hand-raise button.
    var rev: Double?

    var displayMode: String {
        mode == "roles" || mode == "team" ? (mode ?? "company") : "company"
    }

    nonisolated static func decode(fromAny dict: [String: Any]) -> WhisperBusinessCardWire? {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(WhisperBusinessCardWire.self, from: data)
    }

    nonisolated func encodeToDict() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }
}

// MARK: - Kit — entitlement, card building, meeting leads

/// Business+ features inside meetings: resolves the caller's Business+
/// context (owner or team seat), builds the live company card off the real
/// suite tables, and files a viewer's hand-raise as a lead in the business's
/// hiring pipeline — the same rows the web Business+ hiring tab reads.
@MainActor
enum WhisperBusinessMeetingKit {

    struct Context {
        let businessId: String
        let companyName: String
    }

    private nonisolated struct BizRow: Codable, Sendable {
        let user_id: String
        let company_name: String?
        let status: String?
    }

    private nonisolated struct SeatRow: Codable, Sendable {
        let business_id: String
    }

    private nonisolated struct PositionRow: Codable, Sendable {
        let title: String
        let blurb: String?
        let is_open: Bool?
    }

    private nonisolated struct TeamRow: Codable, Sendable {
        let username: String
        let role_title: String?
        let accent: String?
    }

    private nonisolated struct IdRow: Codable, Sendable {
        let id: String
    }

    private nonisolated struct LeadInsert: Codable, Sendable {
        nonisolated struct Answer: Codable, Sendable {
            let prompt: String
            let answer: String
        }
        let business_id: String
        let applicant_id: String
        let applicant_username: String
        let answers: [Answer]
        let position_scores: [String: Int]
        let match_score: Int
        let status: String
    }

    private static func activeBusiness(ownedBy userId: String) async -> BizRow? {
        let client = SupabaseService.shared.client
        let rows: [BizRow]? = try? await client.from("whisper_business_plus")
            .select("user_id, company_name, status")
            .eq("user_id", value: userId)
            .eq("status", value: "active")
            .limit(1)
            .execute()
            .value
        return rows?.first
    }

    /// The caller's Business+ context — a plan they own, or a team seat on
    /// someone else's. Nil when they have neither (menu stays hidden).
    static func myBusinessPlus() async -> Context? {
        guard let uid = SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased(),
              !uid.isEmpty else { return nil }
        if let own = await activeBusiness(ownedBy: uid) {
            return Context(businessId: own.user_id, companyName: own.company_name ?? "")
        }
        let seats: [SeatRow]? = try? await SupabaseService.shared.client
            .from("whisper_business_team")
            .select("business_id")
            .eq("user_id", value: uid)
            .limit(1)
            .execute()
            .value
        guard let seat = seats?.first,
              let biz = await activeBusiness(ownedBy: seat.business_id) else { return nil }
        return Context(businessId: biz.user_id, companyName: biz.company_name ?? "")
    }

    /// Builds the broadcast payload from the live suite tables. Brand extras
    /// (logo/about/industry) are web-first; a card built on iOS ships the
    /// company, open roles, team, and apply link — web viewers render it fine.
    static func buildCard(
        mode: String,
        context: Context,
        presenterUserId: String,
        presenterName: String
    ) async -> WhisperBusinessCardWire {
        let client = SupabaseService.shared.client
        let positions: [PositionRow]? = try? await client.from("whisper_business_positions")
            .select("title, blurb, is_open")
            .eq("business_id", value: context.businessId)
            .order("created_at", ascending: true)
            .limit(20)
            .execute()
            .value
        let team: [TeamRow]? = try? await client.from("whisper_business_team")
            .select("username, role_title, accent")
            .eq("business_id", value: context.businessId)
            .order("added_at", ascending: true)
            .limit(12)
            .execute()
            .value

        let open = (positions ?? []).filter { $0.is_open ?? true }
        let company = context.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayCompany = company.isEmpty ? "@\(presenterName)'s company" : company
        var applyUrl = "https://mydailywhisper.com/work-with/\(context.businessId)"
        if !company.isEmpty,
           let encoded = company.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            applyUrl += "?co=\(encoded)"
        }

        return WhisperBusinessCardWire(
            presenterUserId: presenterUserId,
            presenterName: presenterName,
            businessId: context.businessId,
            mode: mode,
            company: displayCompany,
            about: nil,
            industry: nil,
            logoUrl: nil,
            positions: open.prefix(3).map { $0.title },
            roles: open.prefix(4).map {
                WhisperBusinessCardWire.Role(title: $0.title, blurb: String(($0.blurb ?? "").prefix(90)))
            },
            team: (team ?? []).prefix(6).map {
                WhisperBusinessCardWire.TeamMate(
                    username: $0.username,
                    roleTitle: $0.role_title,
                    accent: $0.accent
                )
            },
            applyUrl: applyUrl,
            rev: Date().timeIntervalSince1970 * 1000
        )
    }

    /// Files a meeting hand-raise as a lead in the business's applicant
    /// pipeline — one row per person per business, marked "How we met" so
    /// the hiring tab badges it as a meeting lead. Mirrors the web exactly.
    static func recordMeetingInterest(
        businessId: String,
        userId: String,
        username: String,
        company: String
    ) async {
        guard !businessId.isEmpty, !userId.isEmpty else { return }
        let client = SupabaseService.shared.client
        let existing: [IdRow]? = try? await client.from("whisper_business_applications")
            .select("id")
            .eq("business_id", value: businessId)
            .eq("applicant_id", value: userId)
            .limit(1)
            .execute()
            .value
        if let existing, !existing.isEmpty { return }
        let lead = LeadInsert(
            business_id: businessId,
            applicant_id: userId,
            applicant_username: username,
            answers: [
                LeadInsert.Answer(
                    prompt: "How we met",
                    answer: "Raised a hand while \(company) presented live in a Whisper meeting."
                ),
            ],
            position_scores: [:],
            match_score: 0,
            status: "new"
        )
        _ = try? await client.from("whisper_business_applications").insert(lead).execute()
    }
}

// MARK: - The floating company card overlay

/// The pinned Business+ card inside a meeting — company / roles / team modes,
/// with Apply + 👋 I'm-interested for viewers and the live interested strip
/// for the presenter. Compact by design; it rides the same top-trailing rail
/// as the presented-client and creator-analytics mini cards.
struct WhisperBusinessCardOverlay: View {
    let card: WhisperBusinessCardWire
    let isMine: Bool
    let interested: [String]
    let handRaised: Bool
    let onInterested: () -> Void
    let onEnd: () -> Void

    @Environment(\.openURL) private var openURL

    private static let indigo = Color(red: 0.353, green: 0.373, blue: 0.910)

    private func accentColor(_ hex: String?) -> Color {
        guard let hex, let color = WhisperPost.color(fromHex: hex) else { return Self.indigo }
        return color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            modeBody
            footer
        }
        .padding(14)
        .frame(width: 296, alignment: .leading)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Self.indigo.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Group {
                if let logo = card.logoUrl, let url = URL(string: logo) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            logoFallback
                        }
                    }
                } else {
                    logoFallback
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(card.company)
                    .font(.system(size: 14.5, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(headerSubline)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isMine {
                Button(action: onEnd) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("End company card")
            }
        }
    }

    private var headerSubline: String {
        if let industry = card.industry, !industry.isEmpty {
            return "\(industry) · @\(card.presenterName)"
        }
        return "presented by @\(card.presenterName)"
    }

    private var logoFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Self.indigo, Color(red: 0.545, green: 0.561, blue: 0.961)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(card.company.prefix(1)).uppercased())
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var modeBody: some View {
        switch card.displayMode {
        case "roles":
            VStack(alignment: .leading, spacing: 7) {
                Text("WE'RE HIRING")
                    .font(.system(size: 9.5, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(Self.indigo.opacity(0.95))
                if let roles = card.roles, !roles.isEmpty {
                    ForEach(roles.prefix(4), id: \.self) { role in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(role.title)
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if let blurb = role.blurb, !blurb.isEmpty {
                                Text(blurb)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(2)
                            }
                        }
                    }
                } else {
                    Text("Roles are being written — ask @\(card.presenterName).")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        case "team":
            VStack(alignment: .leading, spacing: 7) {
                Text("MEET THE TEAM")
                    .font(.system(size: 9.5, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(Self.indigo.opacity(0.95))
                if let team = card.team, !team.isEmpty {
                    ForEach(team.prefix(5), id: \.self) { mate in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(accentColor(mate.accent))
                                .frame(width: 8, height: 8)
                            Text("@\(mate.username)")
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if let role = mate.roleTitle, !role.isEmpty {
                                Text(role)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    if let count = card.team?.count, count > 5 {
                        Text("+\(count - 5) more on the team")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    Text("The roster is warming up.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        default:
            VStack(alignment: .leading, spacing: 7) {
                if let about = card.about, !about.isEmpty {
                    Text(about)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(3)
                }
                if let positions = card.positions, !positions.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(positions.prefix(3), id: \.self) { title in
                            Text(title)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Self.indigo.opacity(0.35), in: Capsule())
                        }
                    }
                } else if card.about == nil || card.about?.isEmpty == true {
                    Text("Say hi — @\(card.presenterName) is presenting their company.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private var interestedLine: String {
        let names = interested.prefix(3).map { "@\($0)" }.joined(separator: ", ")
        let suffix = interested.count > 3 ? "…" : ""
        return "👋 \(interested.count) interested — \(names)\(suffix)"
    }

    @ViewBuilder
    private var footer: some View {
        if isMine {
            if interested.isEmpty {
                Text("Viewers see Apply + a 👋 hand-raise — hands land in your hiring tab.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text(interestedLine)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.47, green: 0.92, blue: 0.75))
                    .lineLimit(2)
            }
        } else {
            HStack(spacing: 8) {
                if let apply = card.applyUrl, let url = URL(string: apply) {
                    Button {
                        openURL(url)
                    } label: {
                        Text("Apply")
                            .font(.system(size: 12.5, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(Self.indigo, in: Capsule())
                    }
                }
                Button(action: onInterested) {
                    Text(handRaised ? "Hand raised ✓" : "👋 I'm interested")
                        .font(.system(size: 12.5, weight: .heavy))
                        .foregroundStyle(handRaised ? .white.opacity(0.55) : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Color.white.opacity(handRaised ? 0.08 : 0.14), in: Capsule())
                }
                .disabled(handRaised)
            }
        }
    }
}
