import Foundation

/// Presentation identity only; every displayed card still reauthorizes through Meet.
nonisolated enum WhisperMeetMessageIdentity {
    static func eventID(in body: String) -> String? {
        guard let payload = WhisperCalendarEmbed.decode(body), payload.kind == "chat-meet",
              let id = UUID(uuidString: payload.eventID) else { return nil }
        return id.uuidString.lowercased()
    }

    static func collapse(_ rows: [WhisperMessageRow]) -> [WhisperMessageRow] {
        var seen: Set<String> = []
        return rows.filter { row in
            guard let event = eventID(in: row.body) else { return true }
            let key = "\(row.from_user_id.lowercased())|\(row.to_user_id.lowercased())|\(row.conversationKind)|\(event)"
            return seen.insert(key).inserted
        }
    }
}
