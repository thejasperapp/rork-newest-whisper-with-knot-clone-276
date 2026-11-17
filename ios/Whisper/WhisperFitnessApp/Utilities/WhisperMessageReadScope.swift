import Foundation

/// Selects actual inbound rows, independent of attachment/card body format.
nonisolated enum WhisperMessageReadScope {
    static func unreadIDs(rows: [WhisperMessageRow], recipient: String, sender: String? = nil, groupID: UUID? = nil) -> [String] {
        let me = recipient.lowercased()
        return Array(Set(rows.compactMap { row -> String? in
            guard row.to_user_id.lowercased() == me, row.from_user_id.lowercased() != me,
                  row.read_at == nil, UUID(uuidString: row.id) != nil else { return nil }
            if let sender, row.from_user_id.lowercased() != sender.lowercased() { return nil }
            let parsed = WhisperGroupChatService.parse(row.body)
            if let groupID {
                guard parsed?.groupID == groupID else { return nil }
            } else if WhisperBackendService.isGroupWire(row.body) || WhisperCallSignal.isSignal(row.body) {
                return nil
            }
            return row.id
        })).sorted()
    }
}
