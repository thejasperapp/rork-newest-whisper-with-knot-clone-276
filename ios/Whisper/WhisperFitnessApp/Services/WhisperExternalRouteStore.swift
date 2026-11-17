import Foundation
import Observation

/// Holds external navigation until authentication and the presenting screen are ready.
@MainActor @Observable final class WhisperExternalRouteStore {
    static let shared = WhisperExternalRouteStore()
    struct Request: Identifiable, Equatable {
        let id: UUID = UUID()
        let kind: String
        var userID: String = ""
        var username: String = ""
        var owner: String?
        var messageID: String = ""
        var threadID: String = ""
    }
    var pending: Request?
    var isPresenting: Bool = false

    func enqueue(_ request: Request) { pending = request }

    func enqueue(url: URL) {
        guard url.scheme?.lowercased() == "whisper", let host = url.host?.lowercased(),
              ["jasper", "ember", "imagine", "calendar", "coach", "stories", "inbox", "dm", "group", "activity", "thought"].contains(host) else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let owner = items.first { $0.name == "owner" }?.value
        enqueue(Request(kind: host == "ember" ? "jasper" : host,
                        userID: items.first { $0.name == "uid" }?.value ?? "",
                        username: url.pathComponents.dropFirst().first ?? "", owner: owner ?? currentOwner,
                        threadID: items.first { $0.name == "thread" }?.value ?? ""))
    }

    var currentOwner: String? { UUID(uuidString: AccountStorage.currentUserID) == nil ? nil : AccountStorage.currentUserID.lowercased() }

    @discardableResult func enqueue(notification: [AnyHashable: Any]) -> Bool {
        guard let kind = notification["kind"] as? String,
              ["whisper_dm", "whisper_group", "whisper_missed_call", "whisper_call_invite"].contains(kind) else { return false }
        let owner = notification["recipientUID"] as? String
        let groupID = notification["groupID"] as? String ?? ""
        let isGroup = kind == "whisper_group" || UUID(uuidString: groupID) != nil
        enqueue(Request(kind: isGroup ? "group" : "dm",
                        userID: isGroup ? groupID : (notification["fromUID"] as? String ?? ""),
                        username: notification["fromUsername"] as? String ?? "",
                        owner: owner?.isEmpty == false ? owner?.lowercased() : currentOwner,
                        messageID: notification["messageID"] as? String ?? "",
                        threadID: notification["threadID"] as? String ?? ""))
        return true
    }

    func accountWillChange(to incomingOwner: String? = nil) {
        if let owner = pending?.owner, owner.lowercased() != incomingOwner?.lowercased() { pending = nil }
        isPresenting = false
    }
}
