import Foundation

nonisolated struct WhisperGroupHistoryEnvelope: Decodable, Sendable {
    let cursor_at: String
    let cursor_id: String
    let messages: [WhisperMessageRow]
}

nonisolated struct WhisperGroupHistoryParams: Encodable, Sendable {
    let p_group_id: String
    let p_limit: Int
    let p_before_at: String?
    let p_before_id: String?
}

nonisolated struct WhisperGroupSummaryParticipant: Decodable, Sendable {
    let user_id: String
    let username: String?
}

nonisolated struct WhisperGroupInboxSummary: Decodable, Sendable {
    let group_id: UUID
    let last_created_at: String
    let last_message_id: String
    let unread_count: Int
    let last_message: WhisperMessageRow
    let participants: [WhisperGroupSummaryParticipant]
}

nonisolated enum WhisperGroupInboxPaging {
    static func page(_ rows: [WhisperGroupInboxSummary]) -> (rows: [WhisperGroupInboxSummary], next: WhisperHistoryCursor?) {
        let selected = Array(rows.prefix(50))
        let next = rows.count > 50 ? selected.last.map {
            WhisperHistoryCursor(createdAt: $0.last_created_at, id: $0.last_message_id)
        } : nil
        return (selected, next)
    }
}

nonisolated enum WhisperGroupHistory {
    static func belongs(_ row: WhisperMessageRow, to groupID: UUID) -> Bool {
        WhisperGroupChatService.parse(row.body)?.groupID == groupID
    }

    static func identity(_ row: WhisperMessageRow) -> String {
        let body = WhisperGroupChatService.parse(row.body)?.body ?? row.body
        let bucket = row.created_at.map { String($0.prefix(18)) } ?? row.id
        let identity = row.logical_group_message_id.map { "message:\($0.lowercased())" }
            ?? WhisperMeetMessageIdentity.eventID(in: body).map { "meet:\($0)" }
            ?? "\(body)|\(bucket)"
        return "\(row.from_user_id.lowercased())|\(identity)"
    }

    static func page(_ envelopes: [WhisperGroupHistoryEnvelope], limit: Int) -> (rows: [WhisperMessageRow], next: WhisperHistoryCursor?) {
        let selected = Array(envelopes.prefix(limit))
        let next = envelopes.count > limit ? selected.last.map { WhisperHistoryCursor(createdAt: $0.cursor_at, id: $0.cursor_id) } : nil
        var seen = Set<String>()
        return (selected.reversed().flatMap(\.messages).filter { seen.insert($0.id.lowercased()).inserted }, next)
    }

    /// Keep whole logical messages, including every authorized recipient copy.
    /// Pending sends never count against the confirmed-history window.
    static func recent(_ rows: [WhisperMessageRow], limit: Int = WhisperMessageHistory.recentLimit) -> [WhisperMessageRow] {
        let confirmed = rows.filter { !$0.id.hasPrefix("local-") }
            .sorted { ($0.created_at ?? "", $0.id) < ($1.created_at ?? "", $1.id) }
        var ordered: [String] = []; var seen = Set<String>()
        for row in confirmed {
            let key = identity(row)
            if seen.insert(key).inserted { ordered.append(key) }
        }
        let retained = Set(ordered.suffix(limit))
        return rows.filter { $0.id.hasPrefix("local-") || retained.contains(identity($0)) }
    }
}
