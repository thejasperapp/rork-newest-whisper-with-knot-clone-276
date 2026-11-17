import Foundation

/// Continuation comes from raw server order, before ranking, safety filtering
/// or hidden/reel projections. A full page plus one sentinel detects the end.
nonisolated enum WhisperFeedPaging {
    static let pageSize = 24

    static func page(_ rows: [WhisperPostRow]) -> (rows: [WhisperPostRow], next: WhisperHistoryCursor?) {
        let selected = Array(rows.prefix(pageSize))
        let next = rows.count > pageSize ? selected.last.map {
            WhisperHistoryCursor(createdAt: $0.created_at, id: $0.id)
        } : nil
        return (selected, next)
    }

    /// Pagination must not move the reader's existing posts or replace a newer
    /// realtime edit with an older page response. Server deletions win too.
    static func append(_ arrivals: [WhisperPostRow], to current: [WhisperPostRow], deleted: Set<String>) -> [WhisperPostRow] {
        var seen = Set(current.map { $0.id.lowercased() })
        return current.filter { !deleted.contains($0.id.lowercased()) } + arrivals.filter {
            !deleted.contains($0.id.lowercased()) && seen.insert($0.id.lowercased()).inserted
        }
    }
}
