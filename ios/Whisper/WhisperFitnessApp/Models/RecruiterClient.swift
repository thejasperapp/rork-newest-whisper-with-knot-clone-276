import Foundation

/// Account-private relationship data; never serialized as a shared team card.
nonisolated struct RecruiterClient: Codable, Sendable {
    struct StageEntry: Codable, Sendable, Identifiable {
        let stage: String
        let at: String
        var id: String { "\(at):\(stage)" }
    }
    var revision: Int = 0
    var email: String = ""
    var phone: String = ""
    var preferences: String = ""
    var relationshipNotes: String = ""
    var meetingIds: [String] = []
    var followUp: String = ""
    var followUpDue: String = ""
    var nextMeetingAt: String = ""
    var stage: String = ""
    var stageEnteredAt: String?
    var stageHistory: [StageEntry] = []

    func stageAge(status: String) -> Int? {
        guard stage == status, let date = stageEnteredAt.flatMap(WhisperBackendService.parseISO) else { return nil }
        return max(0, Int(Date().timeIntervalSince(date) / 86400))
    }
}
