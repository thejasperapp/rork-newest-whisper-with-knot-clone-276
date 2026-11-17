import XCTest
import Foundation
@testable import Whisper

private let legacyQualityDocumentJSON = #"{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","name":"report.pdf","format":"pdf","contentType":"application/pdf","size":100,"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","pages":2,"proofPages":[1],"createdAt":"2026-11-12T00:00:00Z","expiresAt":"2026-11-19T00:00:00Z","proposalID":"00000000-0000-4000-8000-000000000001","review":"visual_ai","sampled":true}"#

final class WhisperKnotDocumentQualityTests: XCTestCase {
    @MainActor func testLegacyDocumentsDecodeWithoutNewReviewFieldsOrSilentUpgrade() throws {
        let document = try JSONDecoder().decode(WhisperKnotDocument.self, from: Data(legacyQualityDocumentJSON.utf8))
        XCTAssertTrue(document.valid)
        XCTAssertNil(document.visualReview)
        XCTAssertNil(document.qualityShortfalls)
        XCTAssertTrue(document.reviewDescription.contains("first, middle and last pages only"))
        XCTAssertFalse(document.reviewDescription.contains("Every rendered page"))
    }
    @MainActor func testPerFileDeliveryNotesRoundTripWithoutChangingOriginalOrQuality() throws {
        let original = try JSONDecoder().decode(WhisperKnotDocument.self, from: Data(legacyQualityDocumentJSON.utf8))
        XCTAssertNil(original.chatDeliveryNote)
        var reviewed = original
        reviewed.deliveryNote = "Route guide: two pages covering the trail. Only selected page images were reviewed; facts remain unverified."
        let restored = try JSONDecoder().decode(WhisperKnotDocument.self, from: JSONEncoder().encode(reviewed))
        XCTAssertEqual(restored.chatDeliveryNote, reviewed.deliveryNote)
        XCTAssertTrue(original.identifiesSameOriginal(as: restored))
        XCTAssertEqual(original.reviewDescription, restored.reviewDescription)
        XCTAssertEqual(original.proofPages, restored.proofPages)
        for unsafe in ["", "<control>", "`command`", "First\nSecond", String(repeating: "x", count: 1201)] {
            reviewed.deliveryNote = unsafe
            XCTAssertNil(reviewed.chatDeliveryNote)
            XCTAssertTrue(reviewed.valid)
        }
    }
    @MainActor func testEveryPageReviewIsIndependentOfStoredPreviewsAndSurvivesCoding() throws {
        var document = try JSONDecoder().decode(WhisperKnotDocument.self, from: Data(legacyQualityDocumentJSON.utf8))
        document.visualReview = .init(version: "knot_document_visual_v1", finalSHA256: document.sha256, scope: "all_pages", status: "pass", pages: (1...2).map { .init(page: $0, sha256: String(repeating: "c", count: 64), verdict: "pass", issues: []) })
        let restored = try JSONDecoder().decode(WhisperKnotDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(restored.proofPages, [1])
        XCTAssertEqual(restored.visualReview?.pages.count, 2)
        XCTAssertTrue(restored.reviewDescription.contains("Every rendered page passed"))
        XCTAssertTrue(restored.reviewDescription.contains("Only selected previews"))
        XCTAssertTrue(restored.reviewDescription.contains("not human certification"))
        XCTAssertEqual(KnotActivityTask(id: "offline", title: "Report", documents: [restored]).summary, "Done")
    }
    @MainActor func testQualifiedDeliveryNeverClaimsOverallPass() throws {
        var document = try JSONDecoder().decode(WhisperKnotDocument.self, from: Data(legacyQualityDocumentJSON.utf8))
        document.qualityShortfalls = ["Sizing remains thin."]
        let restored = try JSONDecoder().decode(WhisperKnotDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(restored.qualityShortfalls, ["Sizing remains thin."])
        XCTAssertTrue(restored.reviewLabel.contains("quality shortfalls in Events"))
        XCTAssertTrue(restored.reviewDescription.contains("not an overall quality pass"))
        let task = KnotActivityTask(id: "offline", title: "Report", documents: [restored])
        XCTAssertTrue(task.activities.isEmpty)
        XCTAssertEqual(task.steps.last?.state, "Done", "Capturing the file remains separate from review quality")
        XCTAssertEqual(task.summary, "Needs attention", "Captured quality metadata must not depend on loading the activity timeline")
    }
    @MainActor func testUnconfirmedContentActivityIsNeutralNotPassOrFailure() throws {
        let activity = WhisperKnotRecordedActivity(id: "unconfirmed", requestID: "owned-request", sequence: 1, kind: "document_content_unconfirmed", label: "Content verdict unconfirmed", recordedAt: "2026-11-12T21:00:00Z")
        XCTAssertEqual(activity.pairFamily, "document_content")
        XCTAssertFalse(activity.confirmsOperation)
        XCTAssertFalse(activity.needsAttention)
        XCTAssertEqual(activity.readableOutcome, "Content review finished without a usable verdict.")
        XCTAssertFalse(activity.readableOutcome.localizedCaseInsensitiveContains("passed"))
        XCTAssertTrue(activity.endsOperation)
    }
    @MainActor func testCheckerAttemptRetainsExactVitalsWithoutInventingFindings() throws {
        let json = #"{"sequence":1,"proposalID":"owned-source","kind":"document_content_check_attempt","recordedAt":"2026-11-12T21:00:00Z","attempt":2,"model":"openai/gpt-4o","durationMs":15000,"tokenLimit":10000,"finishReason":"length","responseBytes":1234,"contentBytes":900,"httpStatus":200,"reason":"content_check_finish_length","outcome":"unconfirmed"}"#
        let event = try JSONDecoder().decode(WhisperKnotExecutorEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.title, "Document content checker run recorded")
        XCTAssertEqual(event.raw["reason"], .string("content_check_finish_length"))
        XCTAssertEqual(event.raw["durationMs"], .number(15000))
        XCTAssertEqual(event.raw["tokenLimit"], .number(10000))
        XCTAssertEqual(event.raw["responseBytes"], .number(1234))
        XCTAssertTrue(event.contentFindings.isEmpty)
    }
    @MainActor func testInvalidOrIssueMetadataCannotFallBackToHistoricalPassWording() throws {
        for scenario in ["wrong-final", "omission", "duplicate", "uncertain", "issues"] {
            var document = try JSONDecoder().decode(WhisperKnotDocument.self, from: Data(legacyQualityDocumentJSON.utf8))
            var pages: [WhisperKnotDocument.VisualReview.Page] = (1...2).map { .init(page: $0, sha256: String(repeating: "c", count: 64), verdict: "pass", issues: []) }
            if scenario == "omission" { pages.removeLast() }
            if scenario == "duplicate" { pages[1] = pages[0] }
            if scenario == "uncertain" { pages[0] = .init(page: 1, sha256: String(repeating: "c", count: 64), verdict: "uncertain", issues: []) }
            if scenario == "issues" { pages[0] = .init(page: 1, sha256: String(repeating: "c", count: 64), verdict: "issues", issues: ["Clipped title"]) }
            document.visualReview = .init(version: "knot_document_visual_v1", finalSHA256: scenario == "wrong-final" ? String(repeating: "f", count: 64) : document.sha256, scope: "all_pages", status: scenario == "issues" ? "issues" : "pass", pages: pages)
            XCTAssertFalse(document.reviewDescription.contains("passed"), scenario)
            XCTAssertFalse(document.reviewLabel.contains("every page"), scenario)
            let task = KnotActivityTask(id: "offline", title: "Report", documents: [document])
            XCTAssertEqual(task.steps.last?.state, "Done", scenario)
            XCTAssertEqual(task.summary, "Needs attention", scenario)
        }
    }
}
