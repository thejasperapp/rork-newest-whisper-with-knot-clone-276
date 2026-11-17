import XCTest
import Foundation
import Dispatch
@testable import Whisper

/// Synthetic, offline checks of production code. No login, provider, shell or capture.
final class WhisperKnotResponsivenessTests: XCTestCase {
    private final class Bytes: @unchecked Sendable {
        private let lock = NSLock()
        private let data: [UInt8]
        private var offset = 0
        private var mainThreadReads = 0
        init(_ data: Data) { self.data = Array(data) }
        func next() -> UInt8? {
            lock.withLock {
                if Thread.isMainThread { mainThreadReads += 1 }
                guard offset < data.count else { return nil }
                defer { offset += 1 }
                return data[offset]
            }
        }
        var readsOnMain: Int { lock.withLock { mainThreadReads } }
        var stream: AsyncStream<UInt8> { AsyncStream(unfolding: { self.next() }) }
    }

    @MainActor func testProductionStreamFramesOffMainAndAwaitsEveryOrderedDelivery() async throws {
        let wire = (1...128).map { index in
            "data: {\"v\":1,\"requestID\":\"offline\",\"sequence\":\(index),\"type\":\"text\",\"text\":\"" + String(repeating: "é", count: 256) + "\"}\r\n\r\n"
        }.joined() + "data: {\"v\":1,\"requestID\":\"offline\",\"sequence\":129,\"type\":\"complete\",\"reply\":\"Finished\"}\n\n"
        let source = Bytes(Data(wire.utf8))
        var delivered: [Int] = []
        var receiving = false
        let started = DispatchTime.now().uptimeNanoseconds
        let result = try await WhisperKnotLiveService.consumeEvents(source.stream, cancellation: .init()) { event in
            MainActor.assertIsolated()
            XCTAssertFalse(receiving, "Delivery callbacks must not overlap while an earlier callback is suspended")
            receiving = true
            await Task.yield()
            delivered.append(event.sequence)
            XCTAssertEqual(event.sequence, delivered.count)
            receiving = false
            return event.type == "complete" ? event.reply : nil
        }
        XCTAssertEqual(result, "Finished")
        XCTAssertEqual(delivered, Array(1...129))
        XCTAssertEqual(source.readsOnMain, 0, "Production byte framing must not run on the UI thread")
        print("[KnotPerformance] offlineStreamBytes=\(wire.utf8.count) delivered=\(delivered.count) mainThreadByteReads=\(source.readsOnMain) elapsedMs=\(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)")
    }

    @MainActor func testStopDuringDeliveryPreventsEveryLaterBufferedEvent() async throws {
        let wire = (1...3).map { "data: {\"v\":1,\"requestID\":\"offline\",\"sequence\":\($0),\"type\":\"text\",\"text\":\"Buffered\"}\n\n" }.joined()
        let cancellation = WhisperKnotRequestCancellation()
        var delivered: [Int] = []
        do {
            _ = try await WhisperKnotLiveService.consumeEvents(Bytes(Data(wire.utf8)).stream, cancellation: cancellation) { event in
                delivered.append(event.sequence)
                cancellation.cancel()
                return nil
            }
            XCTFail("Stop must throw rather than consume the remaining buffered stream")
        } catch is CancellationError { }
        XCTAssertEqual(delivered, [1])
    }

    @MainActor func testAlreadyStoppedStreamCannotDeliverItsFirstEvent() async throws {
        let cancellation = WhisperKnotRequestCancellation()
        cancellation.cancel()
        var delivered = 0
        do {
            _ = try await WhisperKnotLiveService.consumeEvents(Bytes(Data("data: {\"v\":1,\"requestID\":\"offline\",\"sequence\":1,\"type\":\"accepted\"}\n\n".utf8)).stream, cancellation: cancellation) { _ in delivered += 1; return nil }
            XCTFail("A pre-existing cancellation must be honored")
        } catch is CancellationError { }
        XCTAssertEqual(delivered, 0)
    }

    @MainActor func testIncompleteEOFDoesNotInventCompletion() async throws {
        var delivered = 0
        let result = try await WhisperKnotLiveService.consumeEvents(Bytes(Data("data: {\"v\":1,\"requestID\":\"offline\",\"sequence\":1,\"type\":\"complete\",\"reply\":\"Unterminated\"}".utf8)).stream, cancellation: .init()) { _ in delivered += 1; return "Not allowed" }
        XCTAssertNil(result)
        XCTAssertEqual(delivered, 0)
    }

    @MainActor func testMalformedJSONAndUTF8NeverReachDelivery() async throws {
        for wire in [Data("data: {broken}\n\n".utf8), Data("data: ".utf8) + Data([0xFF, 10, 10])] {
            var delivered = 0
            do {
                _ = try await WhisperKnotLiveService.consumeEvents(Bytes(wire).stream, cancellation: .init()) { _ in delivered += 1; return nil }
                XCTFail("Malformed bytes must be rejected")
            } catch { XCTAssertFalse(error is CancellationError) }
            XCTAssertEqual(delivered, 0)
        }
    }

    @MainActor func testDeliveryErrorStopsWithoutReadingTheNextEvent() async throws {
        let wire = (1...2).map { "data: {\"v\":1,\"requestID\":\"offline\",\"sequence\":\($0),\"type\":\"accepted\"}\n\n" }.joined()
        var delivered: [Int] = []
        do {
            _ = try await WhisperKnotLiveService.consumeEvents(Bytes(Data(wire.utf8)).stream, cancellation: .init()) { event in
                delivered.append(event.sequence)
                throw WhisperKnotLiveError.rejected
            }
            XCTFail("Ownership/validation errors from the consumer must remain terminal")
        } catch WhisperKnotLiveError.rejected { }
        XCTAssertEqual(delivered, [1])
    }

    @MainActor func testRepeatedProjectionCacheIsFasterThanRebuildingTheSameProductionProjection() throws {
        try withGuestConsent {
            let sourceIDs = (0..<20).map { _ in UUID() }
            let messages = sourceIDs.map { WhisperKnotMessageEvent(id: $0, date: Date(timeIntervalSince1970: 1794650400), text: "Synthetic document request", fromUser: true) }
            let json: [[String: Any]] = (0..<600).map { index in
                let source = sourceIDs[index / 30].uuidString.lowercased()
                return ["id": "\(source):\(index)", "requestID": source, "taskID": source, "sourceMessageID": source, "sequence": index, "kind": index % 30 == 29 ? "document_program_sealed" : "document_program_slice", "label": "Synthetic writing observation", "recordedAt": "2026-11-14T10:00:00.000Z", "detail": ["programBytes": 21975, "futureEvidence": "retained"]]
            }
            let rows = try JSONDecoder().decode([WhisperKnotRecordedActivity].self, from: JSONSerialization.data(withJSONObject: json))
            let store = WhisperKnotActivityStore()
            store.prepare("offline-benchmark")
            for row in rows { store.observe(row, context: "offline-benchmark") }
            let warm = store.tasks(context: "offline-benchmark", proposals: [], messages: messages, working: true, sourceID: sourceIDs.last)
            XCTAssertEqual(warm.count, 20)
            XCTAssertEqual(warm.reduce(0) { $0 + $1.activities.count }, 600)
            XCTAssertTrue(warm.allSatisfy { $0.preparedSteps != nil })
            XCTAssertEqual(warm.first(where: \.active)?.currentStep?.stageWord, "Writing your document")
            var cachedSamples: [Double] = [], uncachedSamples: [Double] = []
            var cachedCount = 0, uncachedCount = 0
            for batch in 0..<5 {
                // Alternate order to avoid always giving one path a warm CPU.
                for cached in batch % 2 == 0 ? [false, true] : [true, false] {
                    let start = DispatchTime.now().uptimeNanoseconds
                    for _ in 0..<10 {
                        let value = cached
                            ? store.tasks(context: "offline-benchmark", proposals: [], messages: messages, working: true, sourceID: sourceIDs.last)
                            : WhisperKnotActivityStore.rollup(replay: nil, live: rows, proposals: [], messages: messages, working: true, sourceID: sourceIDs.last)
                        XCTAssertEqual(value.first(where: \.active)?.currentStep?.stageWord, "Writing your document")
                        if cached { cachedCount += value.count } else { uncachedCount += value.count }
                    }
                    let msPerRead = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 / 10
                    if cached { cachedSamples.append(msPerRead) } else { uncachedSamples.append(msPerRead) }
                }
            }
            XCTAssertEqual(cachedCount, uncachedCount)
            let cached = cachedSamples.sorted()[2], uncached = uncachedSamples.sorted()[2]
            XCTAssertLessThan(cached, uncached * 0.5, "Repeated owner-valid projections should save at least half of the local reconstruction cost")
            let result: [String: Any] = ["scope": "synthetic_simulator_cached_vs_uncached_current_production_projection_not_historical_or_end_to_end", "tasks": 20, "activities": 600, "readsPerPath": 50, "cachedMedianMsPerRead": cached, "uncachedMedianMsPerRead": uncached, "cachedSamplesMs": cachedSamples, "uncachedSamplesMs": uncachedSamples, "localSpeedup": uncached / max(cached, 0.000001), "providerCalls": 0, "commands": 0]
            let report = String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self)
            print("[KnotPerformance] " + report)
            let attachment = XCTAttachment(string: report); attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    @MainActor func testProjectionCacheInvalidatesForNewEvidenceMessagesAndWorkingState() throws {
        try withGuestConsent {
            let source = UUID(), store = WhisperKnotActivityStore()
            let message = WhisperKnotMessageEvent(id: source, date: .now, text: "Synthetic request", fromUser: true)
            store.prepare("one")
            store.observe(.init(id: "start", requestID: "request", taskID: "request", sourceMessageID: source.uuidString.lowercased(), sequence: 1, kind: "document_program_started", label: "Writing", recordedAt: "2026-11-14T10:00:00Z"), context: "one")
            XCTAssertEqual(store.tasks(context: "one", proposals: [], messages: [message], working: true, sourceID: source).first?.currentStep?.state, "Working")
            store.observe(.init(id: "stop", requestID: "request", taskID: "request", sourceMessageID: source.uuidString.lowercased(), sequence: 2, kind: "document_work_unavailable", label: "Stopped", recordedAt: "2026-11-14T10:00:01Z"), context: "one")
            let stopped = store.tasks(context: "one", proposals: [], messages: [message], working: false, sourceID: source)
            XCTAssertEqual(stopped.first?.activities.count, 2)
            XCTAssertEqual(stopped.first?.summary, "Stopped")
            let reply = WhisperKnotMessageEvent(id: UUID(), date: .now, text: "Synthetic response", fromUser: false)
            XCTAssertEqual(store.tasks(context: "one", proposals: [], messages: [message, reply], working: false, sourceID: source).first?.messages.count, 2)
            XCTAssertTrue(store.tasks(context: "different", proposals: [], messages: [message], working: false, sourceID: source).isEmpty)
            AccountStorage.set(false, forKey: "knot_ai_consent_v4")
            XCTAssertTrue(store.tasks(context: "one", proposals: [], messages: [message], working: false, sourceID: source).isEmpty)
            store.clear()
            AccountStorage.set(true, forKey: "knot_ai_consent_v4")
            store.prepare("two")
            XCTAssertTrue(store.tasks(context: "two", proposals: [], messages: [], working: false, sourceID: nil).isEmpty)
        }
    }

    @MainActor func testMessageProjectionRefreshesTextAndPillsWithoutMixingConversationContexts() {
        let projection = WhisperKnotMessageProjection()
        var turn = WhisperEmberChatView.Turn(role: .user, text: "First", block: nil)
        let first = projection.messages([turn], context: "one")
        XCTAssertEqual(first.first?.text, "First")
        turn.pillTimeline = [.init(stage: "Preparing the document build", stepID: "selection", observedAt: 10, evidenceID: "phase")]
        let changed = projection.messages([turn], context: "one")
        XCTAssertEqual(changed.first?.pillTimeline, turn.pillTimeline)
        XCTAssertEqual(changed.first?.text, "First")
        let replacement = WhisperEmberChatView.Turn(id: turn.id, role: .user, text: "Changed", block: nil)
        XCTAssertEqual(projection.messages([replacement], context: "one").first?.text, "Changed")
        XCTAssertTrue(projection.messages([], context: "two").isEmpty)
        XCTAssertEqual(projection.messages([replacement], context: "two").map(\.id), [replacement.id])
    }

    @MainActor private func withGuestConsent(_ body: () throws -> Void) throws {
        // Only the fresh test runner's unauthenticated local defaults; never alter
        // a real signed-in account or use its data to build a benchmark fixture.
        guard AccountStorage.currentUserID == "guest" else {
            XCTFail("Requires an isolated guest test host; no account settings were changed")
            return
        }
        let original = AccountStorage.object(forKey: "knot_ai_consent_v4")
        defer {
            if let original { AccountStorage.set(original, forKey: "knot_ai_consent_v4") }
            else { AccountStorage.removeObject(forKey: "knot_ai_consent_v4") }
        }
        AccountStorage.set(true, forKey: "knot_ai_consent_v4")
        try body()
    }
}
