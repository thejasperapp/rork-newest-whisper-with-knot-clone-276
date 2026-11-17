import SwiftUI

/// Lightweight CRM-style tags for DM threads. Lets the user mark a
/// conversation as a lead, brand opportunity, collab, client, or
/// follow-up so business chats stay organized inside the inbox.
/// Tags are private to the account (stored locally, never sent).
nonisolated enum WhisperThreadTag: String, CaseIterable, Codable, Sendable, Identifiable {
    case lead
    case brandOpportunity = "brand_opportunity"
    case collab
    case client
    case followUp = "follow_up"

    nonisolated var id: String { rawValue }

    nonisolated var label: String {
        switch self {
        case .lead: return "Lead"
        case .brandOpportunity: return "Brand opp"
        case .collab: return "Collab"
        case .client: return "Client"
        case .followUp: return "Follow up"
        }
    }

    nonisolated var icon: String {
        switch self {
        case .lead: return "person.crop.circle.badge.plus"
        case .brandOpportunity: return "briefcase.fill"
        case .collab: return "person.2.fill"
        case .client: return "figure.strengthtraining.traditional"
        case .followUp: return "arrow.uturn.left.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .lead: return Color(red: 0.13, green: 0.77, blue: 0.37)
        case .brandOpportunity: return Color(red: 0.66, green: 0.33, blue: 0.91)
        case .collab: return Color(red: 0.23, green: 0.51, blue: 0.96)
        case .client: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .followUp: return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }
}

/// Per-account persistence for thread tags. Keyed by the other user's ID
/// (lowercased) so a tag follows the conversation regardless of how the
/// thread row is rebuilt.
@MainActor
@Observable
final class WhisperThreadTagsService {
    static let shared = WhisperThreadTagsService()
    private static let storageKey = "whisper_thread_tags_v1"

    /// otherUserID (lowercased) -> tag rawValue
    private(set) var tagsByUserID: [String: String] = [:]

    private init() { load() }

    func tag(for userID: String) -> WhisperThreadTag? {
        tagsByUserID[userID.lowercased()].flatMap(WhisperThreadTag.init(rawValue:))
    }

    /// Sets (or clears, when nil) the tag for a conversation.
    func setTag(_ tag: WhisperThreadTag?, for userID: String) {
        let key = userID.lowercased()
        if let tag {
            tagsByUserID[key] = tag.rawValue
        } else {
            tagsByUserID.removeValue(forKey: key)
        }
        save()
    }

    /// Distinct tags currently in use — drives the inbox tag filter row.
    var usedTags: [WhisperThreadTag] {
        let raw = Set(tagsByUserID.values)
        return WhisperThreadTag.allCases.filter { raw.contains($0.rawValue) }
    }

    private func load() {
        guard let data = AccountStorage.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        tagsByUserID = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tagsByUserID) {
            AccountStorage.set(data, forKey: Self.storageKey)
        }
    }
}

/// Small colored capsule chip rendering a thread tag — shown inline in
/// inbox rows next to the username.
struct WhisperThreadTagChip: View {
    let tag: WhisperThreadTag
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: tag.icon)
                .font(.system(size: 8, weight: .heavy))
            Text(tag.label)
                .font(.system(size: 9, weight: .heavy))
        }
        .foregroundStyle(tag.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(tag.color.opacity(0.14), in: Capsule())
    }
}
