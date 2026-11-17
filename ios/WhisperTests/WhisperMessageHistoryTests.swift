import Foundation
import Testing
@testable import Whisper

struct WhisperMessageHistoryTests {
    private func row(_ index: Int, body: String = "confirmed", time: String? = "2026-11-05T00:00:00.123456Z") -> WhisperMessageRow {
        WhisperMessageRow(id: String(format: "11111111-1111-4111-8111-%012d", index),
            from_user_id: "11111111-1111-4111-8111-111111111111", from_username: "sender",
            to_user_id: "22222222-2222-4222-8222-222222222222", to_username: "recipient",
            body: body, created_at: time)
    }

    @Test func recentPageHas100RowsAndContinuationUsesLastIncludedRow() {
        let input = (1...101).reversed().map { row($0) }
        let page = WhisperMessageHistory.page(input, limit: WhisperMessageHistory.recentLimit)
        #expect(page.rows.count == 100)
        #expect(page.rows.first?.id == row(2).id)
        #expect(page.rows.last?.id == row(101).id)
        #expect(page.next?.id == row(2).id)
        #expect(page.next?.createdAt == input[99].created_at)
    }

    @Test func olderPageHas50RowsAndNoCursorAtExactEnd() {
        let input = (1...50).reversed().map { row($0) }
        let page = WhisperMessageHistory.page(input, limit: WhisperMessageHistory.olderLimit)
        #expect(page.rows.count == 50)
        #expect(page.next == nil)
        let empty = WhisperMessageHistory.page([], limit: 100)
        #expect(empty.rows.isEmpty)
        #expect(empty.next == nil)
    }

    @Test func continuationIncludesStrictIDTieBreakAndLegacyNullTimes() {
        let id = row(50).id
        let time = "2026-11-05T00:00:00.123456Z"
        let cursor = WhisperHistoryCursor(createdAt: time, id: id)
        #expect(cursor.beforeFilter == "created_at.lt.\(time),and(created_at.eq.\(time),id.lt.\(id)),created_at.is.null")
        #expect(WhisperHistoryCursor(createdAt: nil, id: id).beforeFilter == "and(created_at.is.null,id.lt.\(id))")
        #expect(WhisperHistoryCursor(createdAt: nil, id: "not-a-uuid").beforeFilter == nil)
        #expect(WhisperHistoryCursor(createdAt: "2026-11-05),id.gt.1", id: id).beforeFilter == nil)
    }

    @Test func oldResponseCannotUndoAnEditReadReceiptOrUnsend() {
        let original = row(1)
        var updated = row(1, body: "edited")
        updated.read_at = "2026-11-05T01:00:00Z"
        let removed = row(2)
        let merged = WhisperMessageHistory.reconcile(fetched: [original, removed], baseline: [original, removed], current: [updated], keepingHistory: false)
        #expect(merged == [updated])
    }

    @Test func deletionOutsideTheBaselineCannotReappearFromAnOlderPage() {
        let existing = row(100)
        let deletedOlder = row(1)
        let merged = WhisperMessageHistory.reconcile(fetched: [deletedOlder], baseline: [existing], current: [existing], keepingHistory: true, deletedIDs: [deletedOlder.id])
        #expect(merged == [existing])
    }

    @Test func pendingSendSurvivesRefreshAndIsNotMarkedReadOrConfirmed() {
        let pending = WhisperMessageRow(id: "local-pending", from_user_id: row(1).from_user_id,
            from_username: "sender", to_user_id: row(1).to_user_id, to_username: "recipient",
            body: "sending", created_at: "2026-11-05T01:00:00Z")
        let merged = WhisperMessageHistory.reconcile(fetched: [row(1)], baseline: [pending], current: [pending], keepingHistory: false)
        #expect(merged.contains(pending))
        #expect(merged.last?.id == "local-pending")
        #expect(merged.last?.read_at == nil)
    }

    @Test func overlapIsDeduplicatedAndTimestampTiesUseIDOrder() {
        let merged = WhisperMessageHistory.reconcile(fetched: [row(3), row(2)], baseline: [row(2), row(1)], current: [row(2), row(1)], keepingHistory: true)
        #expect(merged.map(\.id) == [1, 2, 3].map { row($0).id })
    }

    @Test func authoritativeRefreshDropsUnverifiedRowsButRetainsNewArrivals() {
        let initial = row(1)
        let incoming = row(2)
        let merged = WhisperMessageHistory.reconcile(fetched: [], baseline: [initial], current: [initial, incoming], keepingHistory: false)
        #expect(merged == [incoming])
    }
}
