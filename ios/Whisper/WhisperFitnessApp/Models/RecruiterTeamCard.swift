import Foundation

nonisolated struct RecruiterTeamCard: Codable, Identifiable, Sendable {
    let id: String
    let publisherId: String
    let name: String
    let role: String
    let stage: String
    let update: String
    let publishedAt: String
    let revision: Int
    var identity: String { "\(publisherId):\(id)" }
}
