import XCTest
import Observation
@testable import Whisper

final class WhisperKnotReplyStreamTests: XCTestCase {
    @MainActor func testRapidUpdatesPublishLatestOnceInsteadOfEveryToken() async throws {
        let stream = WhisperKnotReplyStream()
        for count in 1...200 { stream.offer(String(repeating: "x", count: count)) }
        XCTAssertEqual(stream.displayed, "")
        XCTAssertEqual(stream.latest.count, 200)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(stream.displayed.count, 200)
    }

    @MainActor func testFingerAndMomentumScrollingKeepLayoutStableWithoutLosingText() {
        let stream = WhisperKnotReplyStream()
        stream.replace("First")
        stream.setPaused(true)
        for count in 1...100 { stream.offer("Latest \(count)") }
        stream.flush()
        XCTAssertEqual(stream.displayed, "First")
        XCTAssertEqual(stream.latest, "Latest 100")
        stream.setPaused(false)
        stream.flush()
        XCTAssertEqual(stream.displayed, "Latest 100")
    }

    @MainActor func testStopOrAccountClearCannotBeRepopulatedByScheduledText() async throws {
        let stream = WhisperKnotReplyStream()
        stream.offer("An old pending answer")
        stream.replace("")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(stream.displayed, "")
        XCTAssertEqual(stream.latest, "")
        stream.offer("New owned answer")
        stream.flush()
        XCTAssertEqual(stream.displayed, "New owned answer")
    }

    @MainActor func testTransportClearIsImmediateEvenWhileScrolling() {
        let stream = WhisperKnotReplyStream()
        stream.replace("Provisional")
        stream.setPaused(true)
        stream.offer("New provisional")
        stream.offer("")
        XCTAssertEqual(stream.displayed, "")
        XCTAssertEqual(stream.latest, "")
        stream.setPaused(false)
        stream.flush()
        XCTAssertEqual(stream.displayed, "")
    }
}
