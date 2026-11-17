import Foundation

nonisolated struct WhisperHistoryCursor: Equatable, Sendable {
    let createdAt: String?
    let id: String

    var beforeFilter: String? {
        guard UUID(uuidString: id) != nil else { return nil }
        guard let createdAt else { return "and(created_at.is.null,id.lt.\(id))" }
        guard createdAt.range(of: #"^\d{4}-\d\d-\d\dT[\d:.]+(?:Z|[+-]\d\d:\d\d)$"#, options: .regularExpression) != nil else { return nil }
        return "created_at.lt.\(createdAt),and(created_at.eq.\(createdAt),id.lt.\(id)),created_at.is.null"
    }
}

nonisolated enum WhisperMessageHistory {
    static let recentLimit = 100
    static let olderLimit = 50

    /// Input is newest-first with one extra sentinel. Hidden/collapsed rows
    /// must not change the continuation point.
    static func page(_ rows: [WhisperMessageRow], limit: Int) -> (rows: [WhisperMessageRow], next: WhisperHistoryCursor?) {
        let selected = Array(rows.prefix(limit))
        let next = rows.count > limit ? selected.last.map { WhisperHistoryCursor(createdAt: $0.created_at, id: $0.id) } : nil
        return (selected.reversed(), next)
    }

    /// Reconcile SELECT with mutations received after it started, including
    /// removals. An old response must not undo a realtime unsend or edit.
    static func reconcile(fetched: [WhisperMessageRow], baseline: [WhisperMessageRow], current: [WhisperMessageRow], keepingHistory: Bool, deletedIDs: Set<String> = []) -> [WhisperMessageRow] {
        let before = Dictionary(baseline.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let now = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result = Dictionary((keepingHistory ? baseline : []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for row in fetched where !deletedIDs.contains(row.id) { result[row.id] = row }
        for id in before.keys where now[id] == nil { result.removeValue(forKey: id) }
        for (id, row) in now where before[id] != row || id.hasPrefix("local-") { result[id] = row }
        for id in deletedIDs { result.removeValue(forKey: id) }
        return result.values.sorted {
            let a = WhisperBackendService.parseISO($0.created_at) ?? .distantPast
            let b = WhisperBackendService.parseISO($1.created_at) ?? .distantPast
            return a == b ? $0.id < $1.id : a < b
        }
    }
}

nonisolated struct WhisperHistoryState: Sendable {
    var next: WhisperHistoryCursor?
    var isLoading = false
    var hasLoaded = false
    var error: String?
    var retryOlder = false
}
