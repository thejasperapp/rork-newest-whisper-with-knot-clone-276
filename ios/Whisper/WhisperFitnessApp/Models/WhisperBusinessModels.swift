import Foundation

/// Supabase row contracts shared with the Business+ web workspace.
nonisolated enum WhisperBusinessModels {
    struct Plan: Codable, Identifiable, Sendable {
        let id: String
        let user_id: String
        let plan: String
        let status: String
        var company_name: String?
        var displayName: String {
            let name = company_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "Your company" : name
        }
    }
    struct Member: Codable, Identifiable, Sendable {
        let business_id: String
        let user_id: String
        let username: String
        var role_title: String
        let accent: String
        var id: String { user_id }
    }
    struct Event: Codable, Identifiable, Sendable {
        let id: String
        let business_id: String?
        let created_by: String
        let created_by_username: String?
        let title: String
        let description: String?
        let start_time: String
        let end_time: String?
        let meeting_link: String?
        var start: Date? {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: start_time) ?? ISO8601DateFormatter().date(from: start_time)
        }
    }
    enum Failure: LocalizedError {
        case access, save, notFound, owner, eventOwner, contextChanged
        var errorDescription: String? {
            switch self {
            case .access: "Business+ couldn't load. Check your connection and try again."
            case .save: "The change wasn't saved. Please try again."
            case .notFound: "That username wasn't found. Check the spelling and try again."
            case .owner: "Only the business owner can make this change."
            case .eventOwner: "Only the event creator can delete this event."
            case .contextChanged: "Your account or workspace changed. Reopen it to see the latest information."
            }
        }
    }
}
