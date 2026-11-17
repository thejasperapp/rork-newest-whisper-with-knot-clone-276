import XCTest
import Foundation
@testable import Whisper

final class WhisperKnotTurnProgressTests: XCTestCase {
    @MainActor func testDancePresentationReplayNeverProjectsStageDirectionsIntoChat() throws {
        let source = UUID(), request = UUID().uuidString
        let events = [
            WhisperKnotRecordedActivity(detail: .init(stepID: "dance-thinking", stepLabel: "Consider the dance request", stepPurpose: "Considering how to respond to a request about dance."), id: "dance:1", requestID: request, sourceMessageID: source.uuidString, sequence: 1, kind: "activity_open", label: "Consider the dance request", recordedAt: "2026-11-15T22:00:00Z"),
            WhisperKnotRecordedActivity(detail: .init(stepID: "dance-memory", stepLabel: "Read dance memory", stepPurpose: "Access memory related to the dance request.", stepResult: "Dance memory read."), id: "dance:2", requestID: request, sourceMessageID: source.uuidString, sequence: 2, kind: "activity_result", label: "Read dance memory", recordedAt: "2026-11-15T22:00:01Z")
        ]
        for replay in [events, try events.map { try JSONDecoder().decode(WhisperKnotRecordedActivity.self, from: JSONEncoder().encode($0)) }] {
            let progress = WhisperKnotTurnProgress()
            progress.begin(sourceID: source)
            for event in replay { progress.observe(event) }
            XCTAssertEqual(progress.updates, [], "Live and reattached Events must never become stage-direction chat bubbles")
            XCTAssertEqual(replay.first?.detail?.stepPurpose, "Considering how to respond to a request about dance.")
            XCTAssertEqual(replay.last?.detail?.stepPurpose, "Access memory related to the dance request.")
            progress.end()
        }
    }

    @MainActor func testOnlyExplicitSourceBoundNewsEntersChatAndStopRejectsLateNews() throws {
        let source = UUID()
        let progress = WhisperKnotTurnProgress()
        progress.begin(sourceID: source)
        var event = WhisperKnotRecordedActivity(detail: .init(stepID: "music", stepPurpose: "Read dance memory.", stepResult: "Memory read.", chatUpdate: "Your saved routine is missing its music track."), id: "music:1", requestID: UUID().uuidString, sourceMessageID: UUID().uuidString, sequence: 1, kind: "activity_result", label: "Read dance memory", recordedAt: "2026-11-15T22:01:00Z")
        progress.observe(event)
        XCTAssertTrue(progress.updates.isEmpty)
        event.sourceMessageID = source.uuidString
        let restored = try JSONDecoder().decode(WhisperKnotRecordedActivity.self, from: JSONEncoder().encode(event))
        progress.observe(restored)
        progress.observe(restored)
        XCTAssertEqual(progress.updates, ["Your saved routine is missing its music track."])
        progress.end()
        progress.observe(restored)
        XCTAssertTrue(progress.updates.isEmpty)
    }

    @MainActor func testExpandedDocumentSpecAndEscapedFrameKeepOrdinaryCommandsBounded() throws {
        let code = "# Authored content may contain ```message and ``` fences\n" + String(repeating: "\"\\\n", count: 10000)
        var spec = WhisperKnotShellSpec(id: UUID().uuidString, bot: "main", conversationID: UUID().uuidString, tool: "document_script", title: "Complete source", command: "command -p python3 -I - <<'KNOT_DOCUMENT_INVOKE'\n" + String(repeating: "\\", count: 110000) + "\nKNOT_DOCUMENT_INVOKE", timeoutMs: 120000, expiresAt: 1e15)
        spec.documentInvocation = .init(stage: "source", interpreter: "python3", code: code, path: "fresh.html")
        XCTAssertTrue(spec.valid) // Ingress only, not server admission/execution proof.
        let data = try JSONEncoder().encode(["shellProposal": spec])
        let reply = "```message\n" + String(decoding: data, as: UTF8.self) + "\n```"
        XCTAssertGreaterThan(reply.utf8.count, 256000)
        XCTAssertEqual(try WhisperKnotLiveService.completionReply(reply, workIncomplete: false), reply)
        let parsed = WhisperKnotMessageSkills.parse(reply)
        XCTAssertEqual(parsed.shellProposal, spec)
        XCTAssertEqual(parsed.text, "")
        XCTAssertEqual(WhisperKnotMessageSkills.parse(String(decoding: data, as: UTF8.self)).shellProposal, spec)
        XCTAssertThrowsError(try WhisperKnotLiveService.completionReply("Untrusted preface\n" + reply, workIncomplete: false))
        XCTAssertThrowsError(try WhisperKnotLiveService.completionReply(reply + String(repeating: " ", count: 512000), workIncomplete: false))
        let wire = try JSONSerialization.data(withJSONObject: ["v": 1, "requestID": "source", "sequence": 1, "type": "complete", "reply": reply])
        XCTAssertGreaterThan(wire.count, 300000)
        XCTAssertLessThan(wire.count, 800000)
        var framer = WhisperKnotEventFramer(), frame: Data?
        for byte in Data("data: ".utf8) + wire + Data("\n\n".utf8) { if let value = try framer.append(byte) { frame = value } }
        let event = try JSONDecoder().decode(WhisperKnotLiveService.Event.self, from: XCTUnwrap(frame))
        XCTAssertEqual(event.reply, reply)
        spec.documentInvocation = nil
        XCTAssertFalse(spec.valid)
        for (command, tool, expected) in [(String(repeating: "x", count: 12001), "session_input", false), (String(repeating: "x", count: 12000), "session_input", true), ("echo KNOT_DOCUMENT_INVOKE " + String(repeating: "x", count: 12001), "document_script", false), ("command -p python3 -I - <<'KNOT_DOCUMENT_INVOKE'\n" + String(repeating: "x", count: 160000), "document_script", false)] {
            var candidate = WhisperKnotShellSpec(id: spec.id, bot: "main", conversationID: spec.conversationID, tool: tool, title: "Bounded input", command: command, timeoutMs: 120000, expiresAt: 1e15)
            candidate.documentInvocation = .init(stage: "source", interpreter: "python3", code: code, path: "fresh.html")
            XCTAssertEqual(candidate.valid, expected)
        }
    }
    @MainActor func testDocumentSizeFactsRoundTripWithoutImplyingExecution() throws {
        let sizes = ["codeCharacters": 64001, "codeCharacterLimit": 64000, "codeBytes": 64001, "argumentBytes": 64130, "argumentByteLimit": 74000]
        var activity = WhisperKnotRecordedActivity(detail: .init(reason: "invalid_tool_arguments", tool: "document_script", fields: ["arguments.code:size"], terminationExit: "size_capacity_exceeded", sizeFacts: sizes, commandDispatched: false), id: "size", requestID: UUID().uuidString, sequence: 20, kind: "document_work_unavailable", label: "Document work stopped before delivery", recordedAt: "2026-11-13T01:24:00Z")
        let restored = try JSONDecoder().decode(WhisperKnotRecordedActivity.self, from: JSONEncoder().encode(activity))
        XCTAssertEqual(restored.detail?.sizeFacts, sizes)
        XCTAssertEqual(restored.selectionTerminationLabel, "Document exceeds supported size")
        XCTAssertEqual(restored.readableOutcome, "Document exceeds supported size.")
        XCTAssertEqual(restored.detail?.commandDispatched, false)
        XCTAssertFalse(restored.confirmsOperation)
        XCTAssertTrue(restored.needsAttention)
        XCTAssertNil(WhisperKnotProgressState.phase(for: restored.label))
        activity.detail?.terminationExit = "client_capacity_exceeded"
        XCTAssertEqual(activity.readableOutcome, "App update needed for this document size.")
    }
    @MainActor func testLatestRealPhaseCancelsAnObsoletePendingPhase() {
        var state = WhisperKnotProgressState()
        state.begin(now: 0)
        state.offer(.working, now: 0.2)
        state.offer(.reading, now: 0.4)
        state.flush(now: 3)
        XCTAssertEqual(state.current, .reading)
        XCTAssertNil(state.pending)
        XCTAssertEqual(state.changes, 0)
    }
    @MainActor func testRealRepairReturnsToCreationAndStillReachesReplyAfterSixChanges() {
        var state = WhisperKnotProgressState()
        state.begin(now: 0)
        let phases: [WhisperKnotProgressState.Phase] = [.working, .creating, .checking, .creating, .checking, .creating, .checking, .writing]
        for (index, phase) in phases.enumerated() {
            state.offer(phase, now: Double(index + 1) * 3)
            XCTAssertEqual(state.current, phase)
        }
        XCTAssertEqual(state.changes, 8)
        state.flush(now: 1000)
        XCTAssertEqual(state.current, .writing) // No timer-generated cycling.
    }
    @MainActor func testPhasesDwellAndAllowOnlyObservedReturnsWithinAnOriginalTurn() {
        var state = WhisperKnotProgressState()
        state.begin(now: 0)
        state.offer(.working, now: 0.2)
        XCTAssertEqual(state.current, .reading)
        state.flush(now: 1.99)
        XCTAssertEqual(state.current, .reading)
        state.flush(now: 2)
        XCTAssertEqual(state.current, .working)
        state.offer(.reading, now: 5)
        XCTAssertEqual(state.current, .reading)
        XCTAssertEqual(state.changes, 2)
    }
    @MainActor func testBoundedVocabularyAndDoneClearsPending() {
        var state = WhisperKnotProgressState()
        state.begin(now: 0)
        for (index, phase) in WhisperKnotProgressState.Phase.allCases.dropFirst().enumerated() {
            state.offer(phase, now: Double(index + 1) * 2)
        }
        XCTAssertEqual(state.changes, WhisperKnotProgressState.Phase.allCases.count - 1)
        state.offer(.reading, now: 100)
        XCTAssertEqual(state.current, .reading)
        XCTAssertEqual(state.changes, WhisperKnotProgressState.Phase.allCases.count)
        state.end()
        state.flush(now: 200)
        XCTAssertNil(state.current)
        XCTAssertNil(state.pending)
        state.offer(.working, now: 201)
        XCTAssertNil(state.current)
        state.begin(now: 300)
        XCTAssertEqual(state.changes, 0)
        XCTAssertEqual(state.current, .reading)
    }
    @MainActor func testActualWirePhasesReachPresentationWithoutDiagnosticLabels() throws {
        var state = WhisperKnotProgressState()
        state.begin(now: 0)
        let phases = [("preparing", "Preparing your file…"), ("creating", "Creating your file…"), ("checking", "Checking the result…"), ("preparing", "Preparing your file…"), ("creating", "Creating your file…"), ("checking", "Checking the result…"), ("writing", "Writing reply…")]
        for (index, pair) in phases.enumerated() {
            let json = "{\"v\":1,\"requestID\":\"source\",\"sequence\":\(index + 1),\"type\":\"work_phase\",\"phase\":\"\(pair.0)\"}"
            var framer = WhisperKnotEventFramer()
            var frame: Data?
            for byte in Data(("data: " + json + "\n\n").utf8) {
                if let data = try framer.append(byte) { frame = data }
            }
            let event = try JSONDecoder().decode(WhisperKnotLiveService.Event.self, from: XCTUnwrap(frame))
            let label = try XCTUnwrap(WhisperKnotLiveService.workActivity(for: event))
            XCTAssertEqual(label, pair.1)
            state.offer(try XCTUnwrap(WhisperKnotProgressState.phase(for: label)), now: Double(index + 1) * 3)
            XCTAssertEqual(state.current?.rawValue, pair.1)
        }
        let diagnostic = try JSONDecoder().decode(WhisperKnotLiveService.Event.self, from: Data(#"{"v":1,"requestID":"source","sequence":8,"type":"tool_selection_retry","phase":"creating","reason":"selection_timeout"}"#.utf8))
        XCTAssertNil(try WhisperKnotLiveService.workActivity(for: diagnostic))
        let unknown = try JSONDecoder().decode(WhisperKnotLiveService.Event.self, from: Data(#"{"v":1,"requestID":"source","sequence":9,"type":"work_phase","phase":"provider private text"}"#.utf8))
        XCTAssertThrowsError(try WhisperKnotLiveService.workActivity(for: unknown))
        state.end()
        state.flush(now: 1000)
        XCTAssertNil(state.current)
    }
    @MainActor func testPrerequisiteAndHousekeepingCannotClaimCreationOrWriting() throws {
        XCTAssertEqual(WhisperKnotProgressState.executionLabel(tool: "session_input", operation: "skill_read"), "Reading your request…")
        XCTAssertEqual(WhisperKnotProgressState.executionLabel(tool: "session_input", operation: "workspace_read"), "Reading your request…")
        let prerequisite = try XCTUnwrap(WhisperKnotProgressState.executionLabel(tool: "session_input", operation: "skill_read"))
        XCTAssertEqual(WhisperKnotProgressState.phase(for: prerequisite), .reading)
        XCTAssertEqual(WhisperKnotProgressState.executionLabel(tool: "document_script", operation: "work"), "Creating your file…")
        XCTAssertEqual(WhisperKnotProgressState.executionLabel(tool: "session_input", operation: "work"), "Working on your request…")
        XCTAssertNil(WhisperKnotProgressState.executionLabel(tool: "session_input", operation: "work", receiptKind: "internal")) // Proof keeps its real checking phase.
        for operation in [nil, "memory_write", "skill_draft", "unknown"] {
            XCTAssertNil(WhisperKnotProgressState.executionLabel(tool: "session_input", operation: operation))
        }
        let memory = try JSONDecoder().decode(WhisperKnotLiveService.Event.self, from: Data(#"{"v":1,"requestID":"source","sequence":1,"type":"generating","stage":"conversation_memory"}"#.utf8))
        XCTAssertEqual(try WhisperKnotLiveService.workActivity(for: memory), "Reading your message…")
    }
    @MainActor func testInternalAndUnknownLabelsNeverBecomePhases() {
        for label in ["Checking connection…", "Tool selection rejected; nothing dispatched", "Skill loaded", "Reaction not confirmed", "Request sent · awaiting reply", "Repairing tool selection; nothing dispatched", "session_input", "arbitrary provider output"] {
            XCTAssertNil(WhisperKnotProgressState.phase(for: label))
        }
        XCTAssertEqual(WhisperKnotProgressState.phase(for: "Reading sources…"), .researching)
    }
    @MainActor func testPendingPhaseCannotSurviveStopOrFinish() {
        var state = WhisperKnotProgressState()
        state.begin(now: 10)
        state.offer(.working, now: 11)
        XCTAssertNotNil(state.pending)
        state.end()
        state.flush(now: 13)
        XCTAssertNil(state.current)
    }
    @MainActor func testRealCalculationPersistsWithoutShellIdentity() throws {
        let receipt = WhisperKnotCalculationReceipt(id: UUID(), conversationID: UUID(), sourceMessageID: UUID(), expression: "2 + 2", value: 4, completedAt: 1000)
        XCTAssertTrue(receipt.valid)
        var message = WhisperEmberConversation.Message(role: "ember", text: "")
        message.calculation = receipt
        let data = try JSONEncoder().encode(message)
        let restored = try JSONDecoder().decode(WhisperEmberConversation.Message.self, from: data)
        XCTAssertEqual(restored.calculation, receipt)
        XCTAssertNil(restored.shell)
        let legacy = try JSONDecoder().decode(WhisperEmberConversation.Message.self, from: Data("{\"role\":\"ember\",\"text\":\"Earlier reply\"}".utf8))
        XCTAssertNil(legacy.calculation)
    }
    @MainActor func testLegacyUnknownOperationStaysInEventsEvenWithASession() {
        let spec = WhisperKnotShellSpec(id: UUID().uuidString, bot: "main", conversationID: UUID().uuidString, tool: "session_input", title: "Read guidance", command: "cat /opt/knot-skills/writing/SKILL.md", timeoutMs: 1000, expiresAt: 1e15)
        var proposal = WhisperKnotShellProposal(spec: spec)
        proposal.state = "finished"
        proposal.result = .init(proposalID: spec.id, bot: spec.bot, conversationID: spec.conversationID, status: "completed", stdout: "---\nname: internal skill", stderr: "", exitCode: 0, outputComplete: true, truncated: false, terminationConfirmed: true, reason: "", sessionID: "actual-owned-session")
        XCTAssertFalse(proposal.showsExecutionReceipt)
        XCTAssertNotNil(proposal.result)
    }
    @MainActor func testDocumentWorkAndProofRemainInEvents() {
        for (tool, command) in [("document_script", "document authoring"), ("session_input", "command -p python3 -I - <<'KNOT_FINAL_FILE_PROOF'\n# proof\nKNOT_FINAL_FILE_PROOF")] {
            var spec = WhisperKnotShellSpec(id: UUID().uuidString, bot: "main", conversationID: UUID().uuidString, tool: tool, title: "Document protocol", command: command, timeoutMs: 1000, expiresAt: 1e15)
            spec.operation = "work"
            var proposal = WhisperKnotShellProposal(spec: spec)
            proposal.state = "running"
            XCTAssertFalse(proposal.showsExecutionReceipt)
        }
    }
    @MainActor func testSelectionIncidentDecodesOriginalFactsAndRecoveredOutcome() throws {
        let json = #"{"id":"00000000-0000-4000-8000-000000000001:20","requestID":"00000000-0000-4000-8000-000000000001","sequence":20,"kind":"tool_selection_rejected","label":"Tool selection recovered; task success not implied","recordedAt":"2026-11-12T05:40:48Z","detail":{"selectionIncident":"00000000-0000-4000-8000-000000000001:20","reason":"invalid_document_invocation","fields":["arguments.code:size"],"attempt":1,"attempts":2,"repairAttempts":1,"tokenLimit":6000,"outcome":"recovered","selectionRecovered":true,"argumentBytes":0,"contentBytes":60,"contentShape":"partial_json","completionTokens":6000}}"#
        let activity = try JSONDecoder().decode(WhisperKnotRecordedActivity.self, from: Data(json.utf8))
        XCTAssertEqual(activity.selectionOutcomeLabel, "Recovered")
        XCTAssertFalse(activity.needsAttention)
        XCTAssertFalse(activity.confirmsOperation)
        XCTAssertEqual(activity.detail?.fields, ["arguments.code:size"])
        XCTAssertEqual(activity.detail?.attempt, 1)
        XCTAssertEqual(activity.detail?.attempts, 2)
        XCTAssertEqual(activity.detail?.repairAttempts, 1)
        XCTAssertEqual(activity.detail?.tokenLimit, 6000)
        XCTAssertEqual(activity.detail?.argumentBytes, 0)
        XCTAssertEqual(activity.detail?.contentBytes, 60)
        XCTAssertEqual(activity.detail?.completionTokens, 6000)
        XCTAssertEqual(activity.readableOutcome, "The next step was selected after a correction.")
        XCTAssertEqual(activity.detail?.outcome, "recovered")
        let restored = try JSONDecoder().decode(WhisperKnotRecordedActivity.self, from: JSONEncoder().encode(activity))
        XCTAssertEqual(restored.detail?.contentShape, "partial_json")
        XCTAssertEqual(restored.detail?.outcome, "recovered")
    }
    @MainActor func testSelectionTimeoutVitalsRoundTripWithoutImplyingExecution() throws {
        let json = #"{"id":"timeout","requestID":"00000000-0000-4000-8000-000000000001","sequence":20,"kind":"tool_selection_retry","label":"Repairing tool selection; nothing dispatched","recordedAt":"2026-11-12T21:08:33Z","detail":{"reason":"selection_timeout","stage":"tool_selection","selectionPhase":"artifact_authoring","deadlineMs":90000,"elapsedMs":90003,"promptBytes":15432,"strategy":"timeout_clock_retry","promptSections":{"policyBytes":10000,"requestHistoryBytes":5430,"framingBytes":2,"receiptBytes":0,"assistantBytes":0,"contractBytes":1250},"promptTargetExceeded":false,"commandDispatched":false,"argumentBytes":0,"model":"openai/gpt-4o","attempt":1}}"#
        let activity = try JSONDecoder().decode(WhisperKnotRecordedActivity.self, from: Data(json.utf8))
        XCTAssertEqual(activity.detail?.deadlineMs, 90000)
        XCTAssertEqual(activity.detail?.elapsedMs, 90003)
        XCTAssertEqual(activity.detail?.promptBytes, 15432)
        XCTAssertEqual(activity.detail?.selectionPhase, "artifact_authoring")
        XCTAssertEqual(activity.detail?.commandDispatched, false)
        XCTAssertFalse(activity.confirmsOperation)
        XCTAssertNil(WhisperKnotProgressState.phase(for: activity.label))
        let restored = try JSONDecoder().decode(WhisperKnotRecordedActivity.self, from: JSONEncoder().encode(activity))
        XCTAssertEqual(restored.detail?.deadlineMs, activity.detail?.deadlineMs)
        XCTAssertEqual(restored.detail?.elapsedMs, activity.detail?.elapsedMs)
        XCTAssertEqual(restored.detail?.promptBytes, activity.detail?.promptBytes)
        XCTAssertEqual(restored.detail?.strategy, "timeout_clock_retry")
        XCTAssertEqual(restored.detail?.promptSections, ["policyBytes": 10000, "requestHistoryBytes": 5430, "framingBytes": 2, "receiptBytes": 0, "assistantBytes": 0, "contractBytes": 1250])
        XCTAssertEqual(restored.detail?.promptTargetExceeded, false)
        XCTAssertEqual(restored.detail?.selectionPhase, activity.detail?.selectionPhase)
        XCTAssertEqual(restored.detail?.commandDispatched, false)
    }
    @MainActor func testSelectionAttemptAndUnissuedRetryNeverClaimExecutionOrTaskSuccess() {
        var activity = WhisperKnotRecordedActivity(detail: .init(strategy: "initial", commandDispatched: false, attempt: 1, tokenLimit: 6000), id: "attempt", requestID: "00000000-0000-4000-8000-000000000001", sequence: 20, kind: "tool_selection_attempt", label: "Selection request started; no command dispatched", recordedAt: "2026-11-13T01:18:23Z")
        XCTAssertFalse(activity.confirmsOperation)
        XCTAssertFalse(activity.needsAttention)
        XCTAssertEqual(activity.readableOutcome, "Choosing the next operation.")
        XCTAssertEqual(activity.detail?.commandDispatched, false)
        XCTAssertNil(WhisperKnotProgressState.phase(for: activity.label))
        activity.detail?.reason = "selection_deadline_insufficient"
        activity.detail?.terminationExit = "deadline_insufficient"
        activity.detail?.attempts = 1
        activity.detail?.repairAttempts = 0
        XCTAssertEqual(activity.readableOutcome, "Not enough time for another attempt.")
        XCTAssertEqual(activity.detail?.attempts, 1)
        XCTAssertEqual(activity.detail?.repairAttempts, 0)
        XCTAssertFalse(activity.confirmsOperation)
    }
    @MainActor func testSelectionCorrectionDoesNotTurnDegradedOrStoppedResponseIntoSuccess() {
        var activity = WhisperKnotRecordedActivity(detail: .init(selectionIncident: "00000000-0000-4000-8000-000000000001:20", outcome: "degraded", selectionRecovered: true), id: "incident", requestID: "00000000-0000-4000-8000-000000000001", sequence: 20, kind: "tool_selection_outcome", label: "Selection incident", recordedAt: "2026-11-12T05:40:48Z")
        XCTAssertEqual(activity.selectionOutcomeLabel, "Finished with limits")
        XCTAssertTrue(activity.needsAttention)
        XCTAssertFalse(activity.confirmsOperation)
        XCTAssertEqual(activity.readableOutcome, "An observation was recorded.")
        XCTAssertEqual(activity.detail?.selectionRecovered, true)
        activity.detail?.outcome = "ended"
        XCTAssertEqual(activity.selectionOutcomeLabel, "Ended")
        XCTAssertEqual(activity.selectionOutcomeLabel, "Ended")
        XCTAssertFalse(activity.confirmsOperation)
        activity.detail?.outcome = "pending"
        XCTAssertEqual(activity.selectionOutcomeLabel, "Repairing")
    }
    @MainActor func testLegacySelectionEventsRemainReadableWithoutNewDiagnostics() throws {
        let json = #"{"id":"legacy","requestID":"00000000-0000-4000-8000-000000000001","sequence":20,"kind":"tool_selection_rejected","label":"Tool selection rejected","recordedAt":"2026-11-12T05:40:48Z","detail":{"reason":"selection_truncated","argumentBytes":0}}"#
        let activity = try JSONDecoder().decode(WhisperKnotRecordedActivity.self, from: Data(json.utf8))
        XCTAssertNil(activity.selectionOutcomeLabel)
        XCTAssertNil(activity.detail?.contentBytes)
        XCTAssertNil(activity.detail?.completionTokens)
        XCTAssertTrue(activity.needsAttention)
        XCTAssertEqual(activity.readableOutcome, "The proposed operation could not be prepared.")
        XCTAssertEqual(activity.detail?.reason, "selection_truncated")
    }
    @MainActor func testIncompleteCompletionCannotBecomeFailureOrPromiseProse() {
        let replies: [String?] = [nil, "", "I couldn’t finish this file.", "Your file is ready."]
        for reply in replies {
            XCTAssertThrowsError(try WhisperKnotLiveService.completionReply(reply, workIncomplete: true)) { error in
                guard case WhisperKnotLiveError.workspaceIncomplete = error else {
                    return XCTFail("Incomplete work must close through the Events-only outcome, not a transport failure or chat reply")
                }
            }
        }
    }
    @MainActor func testDocumentStopClosesWithoutWaitingForAnotherCompletionFrame() throws {
        XCTAssertThrowsError(try WhisperKnotLiveService.checkWorkTerminal(eventType: "document_work_unavailable")) { error in
            guard case WhisperKnotLiveError.workspaceIncomplete = error else {
                return XCTFail("The document stop must use quiet owned-turn cleanup, not wait for complete or EOF")
            }
        }
        // Intermediate observations may lead to a distinct repair, not closure.
        for type in ["document_content_unavailable", "document_proof_unavailable", "document_review_unavailable", "tool_selection_retry", "complete"] {
            XCTAssertNoThrow(try WhisperKnotLiveService.checkWorkTerminal(eventType: type))
        }
        var progress = WhisperKnotProgressState()
        progress.begin(now: 0)
        progress.offer(.working, now: 1)
        progress.end()
        progress.flush(now: 20)
        XCTAssertNil(progress.current)
        XCTAssertNil(progress.pending)
    }
    @MainActor func testDocumentTerminalDiagnosticsSurviveRoundTripInPrivateEvents() throws {
        let hash = String(repeating: "a", count: 64)
        let activity = WhisperKnotRecordedActivity(detail: .init(reason: "invalid_tool_arguments", tool: "document_script", fields: ["arguments.title:required"], terminationExit: "repeated_identical_failure", schemaHash: hash, commandDispatched: false, attempts: 3, repairAttempts: 2, outcome: "degraded", commands: 0, commandLimit: 10000), id: "terminal", requestID: "00000000-0000-4000-8000-000000000001", sequence: 20, kind: "document_work_unavailable", label: "Document work stopped before delivery", recordedAt: "2026-11-13T00:36:25Z")
        let restored = try JSONDecoder().decode(WhisperKnotRecordedActivity.self, from: JSONEncoder().encode(activity))
        XCTAssertEqual(restored.detail?.tool, "document_script")
        XCTAssertEqual(restored.detail?.fields, ["arguments.title:required"])
        XCTAssertEqual(restored.detail?.schemaHash, hash)
        XCTAssertEqual(restored.detail?.terminationExit, "repeated_identical_failure")
        XCTAssertEqual(restored.detail?.attempts, 3)
        XCTAssertEqual(restored.detail?.commands, 0)
        XCTAssertEqual(restored.selectionTerminationLabel, "Repeated invalid selection")
        XCTAssertTrue(restored.needsAttention)
        XCTAssertFalse(restored.confirmsOperation)
        XCTAssertNil(WhisperKnotProgressState.phase(for: restored.label))
    }
    @MainActor func testSliceDiagnosticWireFieldsSurvivePrivateEventsRoundTrip() throws {
        let programID = "00000000-0000-4000-8000-000000000005"
        let hash = String(repeating: "b", count: 64)
        let detail: [String: Any] = ["reason": "document_program_invalid", "check": "slice_parse", "tool": "document_prepare", "stage": "document_authoring", "programID": programID, "programSHA256": hash, "sliceCount": 1, "sliceIndex": 1, "attempt": 3, "attempts": 3, "model": "openai/gpt-4o", "finishReason": "stop", "schemaHash": hash, "deadlineMs": 60000, "elapsedMs": 512, "promptBytes": 42187, "contentBytes": 32, "sliceCharacters": 6001, "sliceCharacterLimit": 6000, "sliceByteLimit": 18000, "requestedCharacters": 1500, "expiresAt": 1794595000000, "deadlineSource": "owned_turn", "commandDispatched": false]
        let payload: [String: Any] = ["id": "terminal", "requestID": programID, "sequence": 28, "kind": "document_work_unavailable", "label": "Document work stopped before delivery", "recordedAt": "2026-11-13T18:24:53Z", "detail": detail]
        let decoded = try JSONDecoder().decode(WhisperKnotRecordedActivity.self, from: JSONSerialization.data(withJSONObject: payload))
        let restored = try JSONDecoder().decode(WhisperKnotRecordedActivity.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(restored.detail?.check, "slice_parse")
        XCTAssertEqual(restored.detail?.programID, programID)
        XCTAssertEqual(restored.detail?.programSHA256, hash)
        XCTAssertEqual(restored.detail?.sliceIndex, 1)
        XCTAssertEqual(restored.detail?.sliceCount, 1)
        XCTAssertEqual(restored.detail?.sliceCharacters, 6001)
        XCTAssertEqual(restored.detail?.sliceCharacterLimit, 6000)
        XCTAssertEqual(restored.detail?.sliceByteLimit, 18000)
        XCTAssertEqual(restored.detail?.requestedCharacters, 1500)
        XCTAssertEqual(restored.detail?.expiresAt, 1794595000000)
        XCTAssertEqual(restored.detail?.deadlineSource, "owned_turn")
        XCTAssertEqual(restored.detail?.schemaHash, hash)
        XCTAssertEqual(restored.detail?.attempts, 3)
        XCTAssertTrue(restored.needsAttention)
        XCTAssertFalse(restored.confirmsOperation)
        XCTAssertNil(WhisperKnotProgressState.phase(for: restored.label))
        var attempt = restored
        attempt = WhisperKnotRecordedActivity(detail: decoded.detail, id: "retry", requestID: programID, sequence: 27, kind: "document_program_retry", label: "Repairing the same uncommitted slice; accepted prefix unchanged", recordedAt: "2026-11-13T18:24:52Z")
        XCTAssertEqual(attempt.readableOutcome, "Correcting the current writing segment.")
        XCTAssertEqual(attempt.label, "Repairing the same uncommitted slice; accepted prefix unchanged")
        XCTAssertEqual(attempt.detail?.commandDispatched, false)
        XCTAssertFalse(attempt.confirmsOperation)
        XCTAssertNil(WhisperKnotProgressState.phase(for: attempt.label))
    }
    @MainActor func testSuccessfulCompletionStillNeedsBoundedNonblankText() throws {
        XCTAssertEqual(try WhisperKnotLiveService.completionReply("Your document is ready.", workIncomplete: false), "Your document is ready.")
        let replies: [String?] = [nil, "", " \n", String(repeating: "x", count: 256_001)]
        for reply in replies {
            XCTAssertThrowsError(try WhisperKnotLiveService.completionReply(reply, workIncomplete: false))
        }
    }
    @MainActor func testUnstartedOrPrerequisiteCommandsDoNotBecomeExecutionCards() {
        var spec = WhisperKnotShellSpec(id: UUID().uuidString, bot: "main", conversationID: UUID().uuidString, tool: "session_input", title: "Actual computation", command: "printf 4", timeoutMs: 1000, expiresAt: 1e15)
        spec.operation = "work"
        var proposal = WhisperKnotShellProposal(spec: spec)
        XCTAssertFalse(proposal.showsExecutionReceipt)
        proposal.state = "dispatching"
        XCTAssertTrue(proposal.showsExecutionReceipt)
        spec.operation = "memory_read"
        proposal = WhisperKnotShellProposal(spec: spec)
        proposal.state = "dispatching"
        XCTAssertFalse(proposal.showsExecutionReceipt)
        XCTAssertEqual(proposal.restored().state, "uncertain")
    }
}
