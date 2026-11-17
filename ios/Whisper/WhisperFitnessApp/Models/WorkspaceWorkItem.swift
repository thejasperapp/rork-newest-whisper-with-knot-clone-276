import Foundation

nonisolated struct WorkspaceWorkItem: Decodable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let brief: String
    let alternatives: String
    let deadline: String
    let reviewOn: String
    let assigneeId: String
    let createdBy: String
    let requesterId: String
    let status: String
    let outcome: String
    let internalNote: String
    let category: String
    let priority: String
    let revision: Int
    let updatedAt: String
    let client: Person?
    let publishedVersion: Int?
    let versions: [Version]
    let comments: [Comment]
    let events: [Event]
    let canManage: Bool
    let canDecide: Bool
    let canRespond: Bool
    let external: Bool

    nonisolated struct Person: Decodable, Identifiable { let id: String; let username: String }
    nonisolated struct Version: Decodable, Identifiable {
        let number: Int; let title: String; let summary: String; let url: String; let milestones: String; let at: String; let response: Response?
        var id: Int { number }
        nonisolated struct Response: Decodable { let status: String; let text: String; let actor: String; let at: String }
    }
    nonisolated struct Comment: Decodable, Identifiable { let id: String; let author: String; let text: String; let audience: String; let at: String }
    nonisolated struct Event: Decodable, Identifiable { let id: String; let actor: String; let action: String; let at: String; let detail: String?; let contentRevision: Int? }
    nonisolated struct Summary: Decodable, Identifiable, Hashable {
        let id: String; let kind: String; let title: String; let status: String; let deadline: String; let reviewOn: String; let assigneeId: String; let revision: Int; let updatedAt: String; let external: Bool
        var needsAttention: Bool {
            let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
            if status == "decided" { return !reviewOn.isEmpty && reviewOn <= today }
            return !["archived", "reviewed", "completed", "declined", "accepted"].contains(status) && ((!deadline.isEmpty && deadline <= today) || ["submitted", "awaiting_approval", "changes_requested", "in_review"].contains(status))
        }
    }
    nonisolated struct Board: Decodable { let items: [Summary]; let member: Bool; let owner: Bool; let canSubmit: Bool; let intakeInstructions: String; let checkedAt: String }
    nonisolated struct Intake: Decodable { let revision: Int; let people: [Person]; let instructions: String; let assigneeId: String; let turnaroundDays: Int }
    nonisolated struct Team: Decodable, Identifiable { let id: String; let name: String }
    static func name(_ kind: String) -> String { switch kind { case "decision": "Decision rooms"; case "delivery": "Client deliveries"; default: "Intake & approvals" } }
    static func icon(_ kind: String) -> String { switch kind { case "decision": "scale.3d"; case "delivery": "shippingbox"; default: "tray.and.arrow.down" } }
    static func statusLabel(_ value: String) -> String { value.replacingOccurrences(of: "_", with: " ").capitalized }
}
