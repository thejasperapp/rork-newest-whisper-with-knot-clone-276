import XCTest
import SwiftUI
@testable import Whisper

final class WhisperKnotReplyTests: XCTestCase {
    func testMachineDispatchJSONIsNotAChatBubbleOrAnExecutionReceipt() {
        let payload = #"{"tool":"session_input","arguments":{"data":"python3 primes.py"}}"#
        XCTAssertEqual(WhisperKnotOutput.clean("The sum is 76,127.\n```json\n" + payload + "\n```"), "The sum is 76,127.")
        XCTAssertEqual(WhisperKnotOutput.clean(payload), "")
        XCTAssertEqual(WhisperKnotOutput.clean("The sum is 76,127.\n" + payload), "The sum is 76,127.")
        XCTAssertEqual(WhisperKnotOutput.clean("```json\n{\"result\":76127}\n```"), "```json\n{\"result\":76127}\n```")
        XCTAssertEqual(WhisperKnotOutput.clean("```python\nprint(76127)\n```"), "```python\nprint(76127)\n```")
    }
    @MainActor func testReleaseAdmissionDoesNotDependOnResetVisualGestureState() {
        let admission = WhisperKnotReplyGestureAdmission()
        XCTAssertTrue(admission.begin(enabled: true, startX: 80, translation: CGSize(width: 20, height: 2)))
        // The visual GestureState can reset before release; admission is separate.
        XCTAssertTrue(admission.end(enabled: true, translation: CGSize(width: 60, height: 4)))
        XCTAssertFalse(admission.end(enabled: true, translation: CGSize(width: 60, height: 4)))
    }
    @MainActor func testVerticalAndLeadingEdgeTouchesNeverCommit() {
        let admission = WhisperKnotReplyGestureAdmission()
        XCTAssertFalse(admission.begin(enabled: true, startX: 28, translation: CGSize(width: 20, height: 0)))
        XCTAssertFalse(admission.end(enabled: true, translation: CGSize(width: 80, height: 0)))
        XCTAssertFalse(admission.begin(enabled: true, startX: 80, translation: CGSize(width: 3, height: 20)))
        XCTAssertFalse(admission.end(enabled: true, translation: CGSize(width: 80, height: 0)))
    }
    @MainActor func testNewTouchOverwritesCancelledAdmissionAndReleaseRechecksDirectionAndAvailability() {
        let admission = WhisperKnotReplyGestureAdmission()
        XCTAssertTrue(admission.begin(enabled: true, startX: 80, translation: CGSize(width: 20, height: 0)))
        XCTAssertFalse(admission.begin(enabled: true, startX: 80, translation: CGSize(width: 0, height: 20)))
        XCTAssertFalse(admission.end(enabled: true, translation: CGSize(width: 80, height: 0)))
        XCTAssertTrue(admission.begin(enabled: true, startX: 80, translation: CGSize(width: 20, height: 0)))
        XCTAssertFalse(admission.end(enabled: false, translation: CGSize(width: 80, height: 0)))
        XCTAssertTrue(admission.begin(enabled: true, startX: 80, translation: CGSize(width: 20, height: 0)))
        XCTAssertFalse(admission.end(enabled: true, translation: CGSize(width: 55, height: 0)))
        XCTAssertTrue(admission.begin(enabled: true, startX: 80, translation: CGSize(width: 20, height: 0)))
        XCTAssertFalse(admission.end(enabled: true, translation: CGSize(width: 80, height: 80)))
    }
    @MainActor func testPageCardsShrinkProportionallyOnPhonesAndCapOnTablets() {
        XCTAssertEqual(WhisperKnotDocumentCardLayout.width(proposed: 320, pagePreview: true), 272)
        XCTAssertEqual(WhisperKnotDocumentCardLayout.width(proposed: 1000, pagePreview: true), 374)
        XCTAssertEqual(WhisperKnotDocumentCardLayout.width(proposed: nil, pagePreview: true), 374)
        XCTAssertEqual(WhisperKnotDocumentCardLayout.width(proposed: 280, pagePreview: false), 280)
        XCTAssertEqual(WhisperKnotDocumentCardLayout.width(proposed: 1000, pagePreview: false), 300)
    }
}
