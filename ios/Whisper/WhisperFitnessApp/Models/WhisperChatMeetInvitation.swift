import Foundation

/// Shared invitation state returned by Meet's authenticated scheduling contract.
nonisolated struct WhisperChatMeetInvitation: Codable, Sendable {
    struct Invitee: Codable, Identifiable, Sendable {
        let userID: String
        let username: String
        let status: String?
        var id: String { userID }
        var responseLabel: String {
            switch status { case "going": "Going"; case "declined": "Not going"; case nil: "Awaiting response"; default: "Response unavailable" }
        }
    }
    let eventID: String
    let meetingID: String
    let title: String
    let startTime: String
    let endTime: String
    let cancelled: Bool
    let invitees: [Invitee]
    /// True only after the invitation is durably available to every authorized chat recipient.
    let deliveryComplete: Bool
}
