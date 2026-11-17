import Foundation

/// Read-only inbox authority, independent of the open conversation's history.
nonisolated struct WhisperInboxSummaryRow: Decodable, Sendable {
    let peer_id: String
    let conversation_kind: WhisperConversationKind
    let last_message_id: String
    let last_created_at: String?
    let peer_username: String?
    let unread_count: Int
    let last_message: WhisperMessageRow

    var key: String { conversation_kind.localKey(peer: peer_id) }

    func summary(owner: String) -> WhisperConversationSummary {
        let fromMe = last_message.from_user_id.lowercased() == owner.lowercased()
        return WhisperConversationSummary(otherUserID: peer_id.lowercased(),
            otherUsername: peer_username ?? (fromMe ? last_message.to_username : last_message.from_username),
            lastMessage: last_message.body,
            lastDate: WhisperBackendService.parseISO(last_created_at) ?? .distantPast,
            lastFromMe: fromMe, lastReadByMe: unread_count == 0, kind: conversation_kind)
    }
}

nonisolated enum WhisperInboxPaging {
    static let limit = 50

    static func page(_ rows: [WhisperInboxSummaryRow]) -> (rows: [WhisperInboxSummaryRow], next: WhisperHistoryCursor?) {
        let selected = Array(rows.prefix(limit))
        return (selected, rows.count > limit ? selected.last.map {
            WhisperHistoryCursor(createdAt: $0.last_created_at, id: $0.last_message_id)
        } : nil)
    }

    /// Earlier pages win overlap. A local history read must never rebuild or
    /// erase summaries for peers whose messages have not been downloaded.
    static func append(_ rows: [WhisperInboxSummaryRow], to existing: [WhisperInboxSummaryRow]) -> [WhisperInboxSummaryRow] {
        var keys = Set(existing.map(\.key))
        return existing + rows.filter { keys.insert($0.key).inserted }
    }
}

nonisolated struct WhisperInboxSummaryParams: Encodable, Sendable {
    let p_limit = WhisperInboxPaging.limit
    let p_before_at: String?
    let p_before_id: String?
    let p_hidden_ids: [String]
}
