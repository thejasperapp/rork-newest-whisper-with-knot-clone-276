import XCTest
import Foundation
@testable import Whisper

final class WhisperKnotTaskPresentationTests: XCTestCase {
    @MainActor func testSyntheticTimeoutShapeCollapsesTransportAndKeepsAllEvidence() throws {
        // Synthetic shape from the operator note, NOT the owner's c1291eed replay.
        let request = UUID().uuidString.lowercased()
        let kinds = ["tool_selection_attempt", "shell_review_ready", "document_program_started", "document_program_attempt", "model_transport_attempt", "model_transport_retry", "model_transport_attempt", "model_transport_retry", "model_transport_attempt", "model_transport_outcome", "tool_request_rejected", "document_work_unavailable", "complete"]
        let activities = kinds.enumerated().map { index, kind in
            WhisperKnotRecordedActivity(detail: .init(stage: index >= 2 ? "document_authoring" : "tool_selection", check: kind == "document_work_unavailable" ? "provider_timeout" : nil), id: "\(request):\(index)", requestID: request, sequence: index, kind: kind, label: "\(kind); original disclaimer", recordedAt: "2026-11-13T22:50:56Z")
        }
        let before = try JSONEncoder().encode(activities)
        let task = KnotActivityTask(id: request, title: "Create a guide", activities: activities)
        XCTAssertEqual(Set(task.steps.map(\.id)), Set(["authoring", "stopped"]))
        XCTAssertEqual(task.steps.first(where: { $0.id == "authoring" })?.observations.filter { $0.kind.hasPrefix("model_transport_") }.count, 6)
        XCTAssertEqual(task.steps.first(where: { $0.id == "authoring" })?.state, "Stopped")
        XCTAssertEqual(task.steps.filter { $0.id == "stopped" }.count, 1)
        XCTAssertEqual(task.summary, "Stopped")
        XCTAssertTrue(task.steps.allSatisfy { !$0.title.contains(";") && ["Working", "Done", "Stopped"].contains($0.state) })
        XCTAssertEqual(task.activities.count, kinds.count)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(task.activities), try encoder.encode(try JSONDecoder().decode([WhisperKnotRecordedActivity].self, from: before)))
    }
    @MainActor func testSealedProgramDoesNotInventExecutionOrDelivery() {
        let request = UUID().uuidString
        let activity = WhisperKnotRecordedActivity(id: "sealed", requestID: request, sequence: 1, kind: "document_program_sealed", label: "Complete program sealed; not yet executed", recordedAt: "2026-11-13T22:50:56Z")
        let task = KnotActivityTask(id: request, title: "Create PDF", activities: [activity], messages: [.init(id: UUID(), date: .now, text: "A control reply", fromUser: false)])
        XCTAssertEqual(task.steps.map(\.state), ["Done"])
        XCTAssertFalse(task.steps.contains { $0.id == "building" || $0.id == "delivery" })
        XCTAssertEqual(task.summary, "Stopped")
    }
    @MainActor func testCaptureAddsDeliveryWithoutInventingQualityPass() throws {
        let proposal = UUID().uuidString
        let document = WhisperKnotDocument(id: String(repeating: "a", count: 64), name: "guide.md", format: "md", title: "Guide", deliveryLabel: nil, contentType: "text/markdown", size: 2500, sha256: String(repeating: "b", count: 64), pages: 1, proofPages: [], createdAt: "2026-11-13T22:50:56.000Z", expiresAt: "2026-11-14T22:50:56.000Z", proposalID: proposal, review: "not_requested", sampled: false, sourceMessageID: nil, sourcePath: nil, bundle: nil)
        XCTAssertTrue(document.valid)
        let activity = WhisperKnotRecordedActivity(id: "quality", requestID: proposal, sequence: 1, kind: "document_content_unconfirmed", label: "Content unconfirmed; not a pass", recordedAt: "2026-11-13T22:50:56Z")
        let task = KnotActivityTask(id: proposal, title: "Create guide", activities: [activity], documents: [document])
        XCTAssertEqual(task.steps.last?.id, "delivery")
        XCTAssertEqual(task.steps.last?.state, "Done")
        XCTAssertEqual(task.steps.last?.subtitle, "guide.md")
        XCTAssertEqual(task.steps.first?.state, "Needs attention")
        XCTAssertEqual(task.summary, "Needs attention")
        XCTAssertFalse(task.steps.first!.observations.first!.confirmsOperation)
        XCTAssertEqual(task.steps.first?.observations.first?.readableOutcome, "Content review finished without a usable verdict.")
        XCTAssertEqual(task.documents.first?.sha256, document.sha256)
    }
    @MainActor func testRecoveredSelectionDoesNotBecomeAFailureSibling() {
        let request = UUID().uuidString.lowercased()
        let rows = ["tool_selection_attempt", "tool_selection_rejected", "tool_selection_retry", "tool_selection_outcome"].enumerated().map { index, kind in
            WhisperKnotRecordedActivity(detail: .init(selectionIncident: request + ":1", outcome: "recovered"), id: "\(index)", requestID: request, sequence: index, kind: kind, label: kind, recordedAt: "2026-11-13T22:50:56Z")
        }
        let task = KnotActivityTask(id: request, title: "Look up a source", activities: rows)
        XCTAssertEqual(task.steps.count, 1)
        XCTAssertEqual(task.steps.first?.state, "Done")
        XCTAssertEqual(task.steps.first?.observations.count, 4)
    }
    @MainActor func testUnknownObservationsStayInServiceTimelineWithoutGreenChecks() {
        let observation = WhisperKnotRecordedActivity(id: "unknown", requestID: "request", sequence: 1, kind: "future_observation", label: "Unknown observation", recordedAt: "2026-11-13T22:50:56Z")
        let task = KnotActivityTask(id: "task", title: "Unknown task", activities: [observation])
        XCTAssertTrue(task.steps.isEmpty)
        XCTAssertEqual(task.activities.first?.id, observation.id)
        XCTAssertEqual(task.summary, "Stopped")
    }
    @MainActor func testDifferentRequestCannotCompleteAnEarlierRead() {
        let started = WhisperKnotRecordedActivity(id: "start", requestID: "one", sequence: 1, kind: "browser_read_started", label: "Reading", recordedAt: "2026-11-13T22:50:56Z")
        let complete = WhisperKnotRecordedActivity(id: "end", requestID: "two", sequence: 2, kind: "browser_read_complete", label: "Read", recordedAt: "2026-11-13T22:50:57Z")
        var task = KnotActivityTask(id: "task", title: "Read a page", activities: [started, complete], active: true)
        XCTAssertEqual(task.steps.first?.state, "Working")
        task.active = false
        XCTAssertEqual(task.steps.first?.state, "Stopped")
    }
    @MainActor func testMemoryAndSkillReadsRollUpButKeepExactCommand() {
        let spec = WhisperKnotShellSpec(id: UUID().uuidString, bot: "main", conversationID: UUID().uuidString, tool: "session_input", title: "Read memory", command: "cat MEMORY.md", timeoutMs: 1000, expiresAt: 1e15)
        let record = WhisperKnotShellReplay.Record(spec: spec, state: "finished", result: .init(proposalID: spec.id, bot: spec.bot, conversationID: spec.conversationID, status: "completed", stdout: "Exact retained output", stderr: "", exitCode: 0, outputComplete: true, truncated: false, terminationConfirmed: true, reason: "", sessionID: "owned-session"), operation: "memory_read")
        let task = KnotActivityTask(id: "task", title: "Prepare", records: [record])
        XCTAssertEqual(task.steps.first?.title, "Prepare the task")
        XCTAssertEqual(task.steps.first?.state, "Done")
        XCTAssertEqual(task.steps.first?.records.first?.spec.command, "cat MEMORY.md")
        XCTAssertEqual(task.steps.first?.records.first?.result.stdout, "Exact retained output")
    }
    @MainActor func testOneCompletionCannotCompleteTwoStarts() {
        let first = WhisperKnotRecordedActivity(id: "start1", requestID: "one", sequence: 1, kind: "browser_read_started", label: "Read", recordedAt: "2026-11-13T22:50:56Z")
        let second = WhisperKnotRecordedActivity(id: "start2", requestID: "one", sequence: 2, kind: "browser_read_started", label: "Read again", recordedAt: "2026-11-13T22:50:57Z")
        let end = WhisperKnotRecordedActivity(id: "end", requestID: "one", sequence: 3, kind: "browser_read_complete", label: "Read returned", recordedAt: "2026-11-13T22:50:58Z")
        let task = KnotActivityTask(id: "task", title: "Read", activities: [first, second, end])
        XCTAssertEqual(task.steps.first?.state, "Stopped")
        XCTAssertEqual(task.steps.first?.observations.count, 3)
    }
    @MainActor func testConfirmedChecksAndCapturedDeliveryCanFinishWithoutRetryRows() {
        let request = UUID().uuidString
        let document = WhisperKnotDocument(id: String(repeating: "a", count: 64), name: "guide.pdf", format: "pdf", title: "Guide", deliveryLabel: nil, contentType: "application/pdf", size: 2500, sha256: String(repeating: "b", count: 64), pages: 1, proofPages: [1], createdAt: "2026-11-13T22:50:59.000Z", expiresAt: "2026-11-14T22:50:56.000Z", proposalID: request, review: "visual_ai", sampled: false, sourceMessageID: nil, sourcePath: nil, bundle: nil)
        let kinds = ["document_program_started", "document_program_retry", "document_program_sealed", "document_proof_started", "document_proof_complete", "document_review_started", "document_review_complete"]
        let activities = kinds.enumerated().map { index, kind in WhisperKnotRecordedActivity(id: "\(index)", requestID: request, sequence: index, kind: kind, label: kind, recordedAt: "2026-11-13T22:50:56Z") }
        let task = KnotActivityTask(id: request, title: "Create guide", activities: activities, documents: [document])
        XCTAssertEqual(task.summary, "Done")
        XCTAssertEqual(task.steps.map(\.id), ["authoring", "checking", "delivery"])
        XCTAssertTrue(task.steps.allSatisfy { $0.state == "Done" })
        XCTAssertEqual(task.activities.count, kinds.count)
    }
    @MainActor func testLiveRollupSuppliesTheSameCurrentRowAcrossRepeatedStages() {
        let source = UUID(), root = UUID().uuidString.lowercased()
        let kinds = ["connection_check_started", "connection_verified", "document_program_started", "document_program_slice", "document_proof_started", "document_content_unconfirmed", "document_program_attempt", "document_program_slice", "document_review_started"]
        var rows: [WhisperKnotRecordedActivity] = []
        var actual: [String] = []
        for (index, kind) in kinds.enumerated() {
            rows.append(.init(id: "\(root):\(index)", requestID: root, taskID: root, sourceMessageID: source.uuidString.lowercased(), sequence: index, kind: kind, label: "Transport label must not become the header", recordedAt: "2026-11-14T10:00:00Z"))
            let tasks = WhisperKnotActivityStore.rollup(replay: nil, live: rows, proposals: [], messages: [.init(id: source, date: .now, text: "Make recipes", fromUser: true)], working: true, sourceID: source)
            let current = tasks.first(where: \.active)?.currentStep
            XCTAssertNotNil(current)
            XCTAssertTrue(tasks.first?.steps.contains(where: { $0.id == current?.id }) == true)
            actual.append(current?.stageWord ?? "Working on your request")
        }
        XCTAssertEqual(actual, ["Checking your workspace", "Checking your workspace", "Writing your document", "Writing your document", "Checking your document", "Checking your document", "Writing your document", "Writing your document", "Checking your document"])
    }
    @MainActor func testCompletedUnavailableCheckRemainsUnconfirmedNotDone() {
        let root = UUID().uuidString
        let rows = ["document_review_started", "document_review_unavailable"].enumerated().map { index, kind in
            WhisperKnotRecordedActivity(id: "\(index)", requestID: root, sequence: index, kind: kind, label: kind, recordedAt: "2026-11-14T10:00:00Z")
        }
        let task = KnotActivityTask(id: root, title: "Recipes", activities: rows)
        XCTAssertEqual(task.steps.first?.state, "Not confirmed")
        XCTAssertFalse(rows.last!.confirmsOperation)
        XCTAssertTrue(rows.last!.endsOperation)
        XCTAssertFalse(task.steps.contains { $0.id == "delivery" })
        XCTAssertEqual(task.summary, "Not confirmed")
    }
    @MainActor func testLiveAndPersistedObservationsDeduplicateWithoutLosingRawFacts() throws {
        let source = UUID(), root = UUID().uuidString.lowercased()
        let json = """
        {"id":"\(root):1","requestID":"\(root)","taskID":"\(root)","sourceMessageID":"\(source.uuidString.lowercased())","sequence":1,"kind":"document_program_sealed","label":"Recorded","recordedAt":"2026-11-14T10:00:00Z","detail":{"programBytes":31166,"authoringResponses":6,"authoringElapsedMs":151000,"authoringBytesPerSecond":206,"futureEvidence":"retained"}}
        """
        let row = try JSONDecoder().decode(WhisperKnotRecordedActivity.self, from: Data(json.utf8))
        let replay = WhisperKnotShellReplay(records: [], events: [], retentionHours: 24, activities: [row])
        let tasks = WhisperKnotActivityStore.rollup(replay: replay, live: [row], proposals: [], messages: [.init(id: source, date: .now, text: "Recipes", fromUser: true)], working: true, sourceID: source)
        XCTAssertEqual(tasks.first?.activities.count, 1)
        XCTAssertEqual(tasks.first?.currentStep?.stageWord, "Writing your document")
        XCTAssertEqual(row.detail?.programBytes, 31166)
        XCTAssertEqual(row.exactObservation["detail"]?["futureEvidence"]?.text, "retained")
    }
    @MainActor func testOnlyExplicitSourceOwnsCurrentTask() {
        let first = UUID(), second = UUID()
        let messages: [WhisperKnotMessageEvent] = [.init(id: first, date: .now, text: "First", fromUser: true), .init(id: second, date: .now, text: "Second", fromUser: true)]
        let tasks = WhisperKnotActivityStore.rollup(replay: nil, proposals: [], messages: messages, working: true, sourceID: first)
        XCTAssertEqual(tasks.filter(\.active).map(\.id), ["message:" + first.uuidString.lowercased()])
        XCTAssertNil(tasks.first(where: \.active)?.currentStep)
        XCTAssertTrue(WhisperKnotActivityStore.rollup(replay: nil, proposals: [], messages: messages, working: false, sourceID: first).allSatisfy { !$0.active })
    }
    @MainActor func testSelectionPhasesDescribePreparationNotDispatchedExecution() throws {
        let phases = ["document_authoring", "artifact_authoring", "document_build", "browser_choice", "closing_choice", "tool_choice", "unknown_future_phase"]
        let expected = ["Preparing your document", "Preparing your interactive file", "Preparing your document", "Planning the browser action", "Preparing your reply", "Preparing your request", "Preparing your file"]
        for (phase, label) in zip(phases, expected) {
            let row = WhisperKnotRecordedActivity(detail: .init(selectionPhase: phase, commandDispatched: false), id: phase, requestID: "request", sequence: 1, kind: "tool_selection_attempt", label: "Raw transport label", recordedAt: "2026-11-14T10:00:00Z")
            let before = row.exactObservation
            let task = KnotActivityTask(id: "task", title: "Create", activities: [row], active: true)
            XCTAssertEqual(task.currentStep?.stageWord, label)
            XCTAssertEqual(task.currentStep?.id, "selection")
            XCTAssertFalse(task.steps.contains { $0.id == "building" })
            XCTAssertEqual(row.exactObservation, before)
        }
    }
    @MainActor func testTransportOnlyCarriesSelectionPhaseWithinItsOwnRequest() {
        let phase = WhisperKnotRecordedActivity(detail: .init(selectionPhase: "document_build", commandDispatched: false), id: "phase", requestID: "one", sequence: 1, kind: "tool_selection_attempt", label: "Prepare", recordedAt: "2026-11-14T10:00:00Z")
        let retry = WhisperKnotRecordedActivity(id: "retry", requestID: "one", sequence: 2, kind: "model_transport_retry", label: "Retry", recordedAt: "2026-11-14T10:00:01Z")
        let unrelated = WhisperKnotRecordedActivity(id: "other", requestID: "two", sequence: 1, kind: "model_transport_attempt", label: "Other", recordedAt: "2026-11-14T10:00:02Z")
        XCTAssertEqual(KnotActivityTask(id: "task", title: "Create", activities: [phase, retry]).currentStep?.stageWord, "Preparing your document")
        XCTAssertEqual(KnotActivityTask(id: "task", title: "Create", activities: [phase, retry, unrelated]).currentStep?.stageWord, "Preparing your document")
        let writing = WhisperKnotRecordedActivity(id: "writing", requestID: "two", sequence: 2, kind: "document_program_started", label: "Started", recordedAt: "2026-11-14T10:00:03Z")
        XCTAssertEqual(KnotActivityTask(id: "task", title: "Create", activities: [phase, retry, unrelated, writing]).currentStep?.stageWord, "Writing your document")
    }
    @MainActor func testMissingCurrentSourceCannotActivateTheLastQuestion() {
        let question = WhisperKnotMessageEvent(id: UUID(), date: .now, text: "Old question", fromUser: true)
        let tasks = WhisperKnotActivityStore.rollup(replay: nil, proposals: [], messages: [question], working: true, sourceID: nil)
        XCTAssertTrue(tasks.allSatisfy { !$0.active })
    }
    @MainActor func testCachedCurrentStepIsTheSameEvidenceAsTheUncachedProjection() {
        let source = UUID()
        let row = WhisperKnotRecordedActivity(detail: .init(selectionPhase: "artifact_authoring", commandDispatched: false), id: "phase", requestID: "request", taskID: "root", sourceMessageID: source.uuidString, sequence: 1, kind: "tool_selection_attempt", label: "Raw", recordedAt: "2026-11-14T10:00:00Z")
        let task = WhisperKnotActivityStore.rollup(replay: nil, live: [row], proposals: [], messages: [.init(id: source, date: .now, text: "Make a game", fromUser: true)], working: true, sourceID: source).first!
        XCTAssertTrue(task.currentStepPrepared)
        XCTAssertEqual(task.currentStep?.stageWord, "Preparing your interactive file")
        var uncached = task; uncached.currentStepPrepared = false; uncached.preparedSteps = nil
        XCTAssertEqual(task.currentStep?.stageWord, uncached.currentStep?.stageWord)
        XCTAssertEqual(task.currentStep?.observations.map(\.id), uncached.currentStep?.observations.map(\.id))
    }
    @MainActor func testPillTimelineRoundTripsOnTurnRecord() throws {
        var message = WhisperEmberConversation.Message(role: "user", text: "Recipes")
        message.pillTimeline = [.init(stage: "Writing", stepID: "authoring", observedAt: 1000, evidenceID: "record:3"), .init(stage: "Checking", stepID: "checking", observedAt: 2000, evidenceID: "record:4")]
        let restored = try JSONDecoder().decode(WhisperEmberConversation.Message.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(restored.pillTimeline, message.pillTimeline)
    }
    @MainActor func testTransportVitalsRoundTripToExactEvidence() throws {
        let json = #"{"id":"a","requestID":"r","sequence":1,"kind":"model_transport_outcome","label":"Original; no execution claimed","recordedAt":"2026-11-13T22:50:56Z","detail":{"transportAttempt":3,"transportDelayMs":0,"transportOutcome":"ended","transportCallCount":3,"transportElapsedMs":60000,"transportFirstTokenMs":1000,"transportChunkCount":8,"transportMaxIdleMs":60000,"transportTimeoutKind":"idle","transportStreaming":true}}"#
        let value = try JSONDecoder().decode(WhisperKnotRecordedActivity.self, from: Data(json.utf8))
        let restored = try JSONDecoder().decode(WhisperKnotRecordedActivity.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored.detail?.transportCallCount, 3)
        XCTAssertEqual(restored.detail?.transportFirstTokenMs, 1000)
        XCTAssertEqual(restored.detail?.transportTimeoutKind, "idle")
        XCTAssertEqual(restored.detail?.transportChunkCount, 8)
        XCTAssertEqual(restored.detail?.transportStreaming, true)
    }
}
