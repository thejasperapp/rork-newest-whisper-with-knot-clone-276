import SwiftUI

nonisolated extension WhisperKnotRecordedActivity {
    var pairFamily: String? {
        switch kind {
        case "skill_read_started", "skill_read_complete": "skill_read"
        case "conversation_memory_started", "conversation_memory_complete", "conversation_memory_unavailable": "conversation_memory"
        case "connection_check_started", "connection_verified": "connection"
        case "search_requested", "search_complete", "search_unavailable": "search"
        case "calculation_started", "calculation_complete": "calculation"
        case "browser_read_started", "browser_read_complete", "browser_read_unavailable": "browser_read"
        case "document_content_started", "document_content_complete", "document_content_unconfirmed", "document_content_unavailable": "document_content"
        case "document_proof_started", "document_proof_complete", "document_proof_unavailable": "document_proof"
        case "document_review_started", "document_review_complete", "document_review_unavailable", "document_quality_qualified", "document_visual_incomplete": "document_review"
        case "browser_start_intent", "browser_start_complete": "browser_start"
        case "browser_navigate_intent", "browser_navigate_complete": "browser_navigate"
        case "browser_input_intent", "browser_input_complete": "browser_input"
        case "browser_stop_intent", "browser_stop_complete": "browser_stop"
        default: nil
        }
    }
    var startsOperation: Bool { kind.hasSuffix("_started") || kind.hasSuffix("_intent") || ["search_requested", "connection_check_started"].contains(kind) }
    var confirmsOperation: Bool {
        ["skill_read_complete", "conversation_memory_complete", "connection_verified", "search_complete", "calculation_complete", "browser_read_complete", "browser_start_complete", "browser_navigate_complete", "browser_input_complete", "browser_stop_complete", "document_review_complete", "document_proof_complete", "document_content_complete"].contains(kind)
    }
    /// Completion of a check is separate from its verdict. Unavailable and
    /// qualified outcomes finish the attempt without manufacturing a quality pass.
    var endsOperation: Bool {
        confirmsOperation || kind.hasSuffix("_unavailable") || ["document_content_unconfirmed", "document_quality_qualified", "document_visual_incomplete", "complete"].contains(kind)
    }
    var selectionTerminationLabel: String? {
        switch detail?.terminationExit {
        case "repeated_identical_failure": "Repeated invalid selection"
        case "repair_attempts_exhausted": "Repair limit reached"
        case "deadline_insufficient": "Not enough time for another attempt"
        case "budget_exhausted": "Work limit reached"
        case "timeout_retry_exhausted": "Selection timed out"
        case "upstream_empty": "No selection returned"
        case "upstream_shape_invalid": "Selection could not be read"
        case "size_capacity_exceeded": "Document exceeds supported size"
        case "client_capacity_exceeded": "App update needed for this document size"
        default: nil
        }
    }
    var selectionOutcomeLabel: String? {
        switch detail?.outcome {
        case "recovered": "Recovered"
        case "degraded": "Finished with limits"
        case "ended": "Ended"
        case "pending": "Repairing"
        default: nil
        }
    }
    var needsAttention: Bool {
        if detail?.selectionIncident != nil, detail?.outcome == "recovered" { return false }
        return detail?.outcome == "degraded" || kind.hasSuffix("_unavailable") || ["error", "rejected", "tool_selection_rejected", "tool_request_rejected", "browser_action_uncertain"].contains(kind)
    }
    var bookkeeping: Bool { ["accepted", "work_routing", "generating", "finalizing", "complete", "shell_review_ready", "connection_check_started", "connection_verified"].contains(kind) }
    var readableOutcome: String {
        if detail?.outcome == "recovered" { return "The next step was selected after a correction." }
        if let termination = selectionTerminationLabel { return termination + "." }
        switch detail?.reason {
        case "document_authoring_timeout": return "Writing timed out before the complete document was ready."
        case "upstream_quota_exhausted": return "The AI provider’s quota was exhausted."
        case "upstream_rate_limited": return "The AI provider rate-limited the request."
        case "upstream_http_rejection" where detail?.status == 402: return "Replies are unavailable until service billing is resolved."
        case "document_bytes_changed": return "The file changed; its delivery could not be confirmed."
        case "document_proof_required", "document_proof_coverage_incomplete": return "Required file checks could not be confirmed."
        case "continuation_already_dispatched", "distinct_command_required_no_replay": return "This operation was already recorded and was not repeated."
        case "model_refusal": return "The AI provider declined this request."
        case "provider_content_filter": return "The AI provider filtered this request."
        default: break
        }
        switch kind {
        case "connection_check_started": return "Workspace connection check requested."
        case "connection_verified": return "Workspace connection verified."
        case "skill_read_started", "conversation_memory_started": return "Reading workspace context and guidance."
        case "skill_read_complete": return "Communication guidance read."
        case "conversation_memory_complete": return "Saved workspace memory read."
        case "conversation_memory_unavailable": return "Saved workspace memory could not be read."
        case "document_program_started", "document_program_attempt": return "Writing the document’s content and layout."
        case "document_program_retry": return "Correcting the current writing segment."
        case "document_program_slice": return "A writing segment was saved."
        case "document_program_sealed": return "The complete document program is ready to build."
        case "document_content_started": return "Content comparison requested."
        case "document_content_complete": return "Content comparison passed."
        case "document_content_unconfirmed": return "Content review finished without a usable verdict."
        case "document_content_unavailable": return "Content review could not confirm a deliverable file."
        case "document_proof_started": return "Final-file checks prepared."
        case "document_proof_complete": return "Final-file mechanical checks passed."
        case "document_proof_unavailable": return "Required final-file checks could not be confirmed."
        case "document_review_started": return "File capture and visual review requested."
        case "document_review_complete": return "The file was captured and visual review passed."
        case "document_review_unavailable": return "Visual review finished without a usable verdict."
        case "document_quality_qualified": return "The file was captured with quality shortfalls."
        case "document_visual_incomplete": return "All-page visual review did not pass."
        case "document_work_unavailable": return "Document work ended before delivery."
        case "search_requested": return "Searching for sources."
        case "search_complete": return "The source search returned results."
        case "search_unavailable": return "The source search returned no usable result."
        case "calculation_started": return "Calculation requested."
        case "calculation_complete": return "The calculation returned a result."
        case "browser_read_started": return "Browser observation requested."
        case "browser_read_complete": return "The browser returned an observation."
        case "browser_read_unavailable": return "The browser observation was unavailable."
        case "browser_start_complete": return "Browser start confirmed."
        case "browser_navigate_complete": return "Browser navigation acknowledged."
        case "browser_input_complete": return "Browser input acknowledged."
        case "browser_stop_complete": return "Browser stop confirmed."
        case "browser_action_uncertain": return "The browser action is unconfirmed."
        case "tool_selection_attempt", "work_routing": return "Choosing the next operation."
        case "tool_selection_retry": return "Correcting the next operation before execution."
        case "tool_selection_rejected", "tool_request_rejected": return "The proposed operation could not be prepared."
        case "tool_selection_unavailable", "tool_unavailable": return "The next operation was unavailable."
        case "shell_review_ready": return "The next workspace command is prepared."
        case "model_transport_attempt": return "The writing request started."
        case "model_transport_retry": return "The writing connection is being retried."
        case "model_transport_outcome": return detail?.transportOutcome == "recovered" ? "The writing connection recovered." : "The writing request ended."
        case "cancelled": return "The response was stopped; remote execution status is recorded separately."
        case "error", "rejected": return "The response ended before completion."
        case "generating", "finalizing": return "Preparing the reply."
        case "complete": return "The response was prepared."
        default: return "An observation was recorded."
        }
    }
    var exactObservation: WhisperKnotReceiptJSON {
        if let rawRecord { return rawRecord }
        guard let data = try? JSONEncoder().encode(self), let value = try? JSONDecoder().decode(WhisperKnotReceiptJSON.self, from: data) else { return .null }
        return value
    }
}

struct WhisperKnotStepIndicator: View {
    let state: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var completed: Bool { ["Done", "Step finished", "Finished", "Recovered"].contains(state) }
    private var running: Bool { ["Working", "Preparing", "Waiting for receipt", "Repairing", "Stop requested"].contains(state) }
    private var symbol: String {
        switch state {
        case "Done", "Step finished", "Finished", "Recovered": "checkmark.circle.fill"
        case "Working", "Preparing", "Waiting for receipt", "Repairing": "circle.dotted"
        case "Stopped", "Stop requested": "stop.circle"
        case "Failed", "Output incomplete", "Not confirmed": "exclamationmark.circle"
        default: "circle"
        }
    }
    var body: some View {
        Group {
            if running && !reduceMotion && scenePhase == .active {
                ProgressView().controlSize(.small).tint(.orange)
            } else {
                Image(systemName: symbol)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(completed ? Color.green : running ? Color.orange : ["Failed", "Not confirmed", "Output incomplete", "Needs attention"].contains(state) ? Color.orange : Color.secondary)
        .frame(width: 24, height: 26).accessibilityLabel(state)
    }
}

/// A command-only landing page. Service observations stay retained, not displayed.
struct WhisperKnotStageDetail: View {
    let step: KnotActivityStep
    var events: [WhisperKnotExecutorEvent] = []
    let bot: WhisperKnotBot
    let conversationID: UUID
    var enabled = true
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(step.stageWord).font(.title3.weight(.semibold))
                Label { Text(step.state) } icon: { WhisperKnotStepIndicator(state: step.state) }
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(step.records) { record in
                    WhisperKnotInlineExecution(record: record)
                }
            }.padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
        }.background(.black).navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .environment(\.colorScheme, .dark).tint(.white)
    }
}

struct WhisperKnotRecordedStepDetail: View {
    let observations: [WhisperKnotRecordedActivity]
    let state: String
    var body: some View {
        let stage = observations.last?.presentationStage ?? "preparing"
        List {
            Section {
                Text(KnotActivityStage.title(stage)).font(.title2.bold())
                Text(["Working", "Done", "Stopped", "Failed", "Needs attention", "Not confirmed"].contains(state) ? state : "Not confirmed").font(.subheadline.weight(.semibold))
                Text("What ran").font(.headline)
                Text(KnotActivityStage.title(stage))
                Text("Result").font(.headline)
                Text(observations.last?.readableOutcome ?? "No result was recorded.")
            }
        }.navigationTitle("Step details").navigationBarTitleDisplayMode(.inline)
    }
}

struct WhisperKnotStageRawRecord: View {
    let step: KnotActivityStep
    var events: [WhisperKnotExecutorEvent] = []
    var body: some View {
        List {
            Section("Service observations") {
                ForEach(step.observations) { observation in
                    NavigationLink(observation.label) { WhisperKnotExactEvidenceView(title: "Raw record", source: .json(observation.exactObservation)) }
                }
            }
            Section("Execution records") {
                ForEach(step.records) { record in
                    NavigationLink(record.spec.title) { WhisperKnotShellEventsView(proposal: record.proposal, embedded: true, rawRecord: true) }
                }
            }
            Section("Executor events") {
                ForEach(events) { event in NavigationLink(event.title) { WhisperKnotExactEvidenceView(title: "Raw record", source: .json(event.raw)) } }
            }
        }.navigationTitle("Raw record").navigationBarTitleDisplayMode(.inline)
    }
}

struct WhisperKnotTaskRawRecord: View {
    let task: KnotActivityTask
    var body: some View {
        WhisperKnotStageRawRecord(step: .init(id: "task", title: task.title, records: task.records, observations: task.activities, documents: task.documents), events: task.executorEvents)
    }
}

extension WhisperKnotShellReplay.Record {
    var humanTitle: String {
        spec.title
    }
    var humanState: String {
        if cachedData != nil { return "Done" }
        let label = WhisperKnotExecutionAppearance.label(result, state: state, complete: receiptOutputComplete, truncated: receiptTruncated)
        if label == "Step finished" { return "Done" }
        return label
    }
    var humanResult: String {
        if cachedData != nil { return "Saved guidance was reused from this session." }
        if humanState == "Done" {
            switch operation {
            case "memory_read": return "Workspace memory was read."
            case "skill_index": return "The available workspace guides were listed."
            case "skill_read": return "The requested workspace guidance was read."
            case "workspace_inventory": return "The workspace file listing was received."
            case "workspace_read": return "The requested workspace file was read."
            default:
                if let invocation = spec.documentInvocation {
                    let file = (invocation.path as NSString).lastPathComponent
                    switch invocation.stage {
                    case "source": return "Created \(file); the finished file still needs building and checking."
                    case "build", "final": return "Created and measured \(file); delivery is recorded separately."
                    default: return "Completed the recorded checks for \(file)."
                    }
                }
                return "The requested workspace step finished. File delivery and interactive checks are recorded separately."
            }
        }
        if humanState == "Working" { return "Waiting for the workspace execution receipt." }
        if !result.terminationConfirmed { return "The execution outcome is unconfirmed." }
        if result.status == "cancelled" { return "The operation was stopped." }
        if let exit = result.exitCode, exit != 0 { return "The operation ended with exit code \(exit)." }
        if !(receiptOutputComplete ?? result.outputComplete) || (receiptTruncated ?? result.truncated) { return "The complete operation output could not be confirmed." }
        return "The operation did not produce a confirmed successful result."
    }
}

/// Read-only exact commands and recorded output alongside their truthful result.
struct WhisperKnotInlineExecution: View {
    let record: WhisperKnotShellReplay.Record
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Command").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            WhisperKnotInlineEvidenceText(text: record.spec.command)
            if !record.result.stdout.isEmpty {
                Text("Standard output").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                WhisperKnotInlineEvidenceText(text: record.result.stdout)
            }
            if !record.result.stderr.isEmpty {
                Text("Standard error").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                WhisperKnotInlineEvidenceText(text: record.result.stderr)
            }
            if record.result.stdout.isEmpty && record.result.stderr.isEmpty {
                Text("No output recorded.").font(.footnote).foregroundStyle(.secondary)
            }
            if record.cachedData == nil {
                if let exit = record.result.exitCode { Text("Exit code \(exit)").font(.footnote).foregroundStyle(.secondary) }
                if !(record.receiptOutputComplete ?? record.result.outputComplete) || (record.receiptTruncated ?? record.result.truncated) {
                    Text("This recorded output is incomplete. It is not proof of success.").font(.footnote).foregroundStyle(.orange)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Split retained bytes for layout, without truncating, summarizing or rerunning.
private struct WhisperKnotInlineEvidenceText: View {
    let text: String
    @State private var parts: [String] = []
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(parts.indices, id: \.self) { index in
                Text(verbatim: parts[index]).font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: text) {
            let next = await Self.split(text)
            guard !Task.isCancelled else { return }
            parts = next
        }
    }
    @concurrent private static func split(_ text: String) async -> [String] {
        var parts: [String] = [], start = text.startIndex
        while start < text.endIndex {
            guard !Task.isCancelled else { return [] }
            let end = text.index(start, offsetBy: 4096, limitedBy: text.endIndex) ?? text.endIndex
            parts.append(String(text[start..<end])); start = end
        }
        return parts
    }
}

struct WhisperKnotReadableExecutionView: View {
    let record: WhisperKnotShellReplay.Record
    let proposal: WhisperKnotShellProposal
    var continueTask: (() -> Void)? = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(record.humanTitle).font(.title3.weight(.semibold))
                Label { Text(record.humanState) } icon: { WhisperKnotStepIndicator(state: record.humanState) }
                    .font(.caption).foregroundStyle(.secondary)
                WhisperKnotInlineExecution(record: record)
            }.padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
        }.background(.black).navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .environment(\.colorScheme, .dark).tint(.white)
    }
}

struct WhisperKnotExecutorEventDetail: View {
    let event: WhisperKnotExecutorEvent
    var body: some View {
        List {
            Section {
                Text(event.title.components(separatedBy: ";").first ?? "Execution record").font(.title2.bold())
                Text(event.kind == "stop_requested" ? "Working" : ["execution_unconfirmed", "review_declined"].contains(event.kind) ? "Stopped" : "Done").font(.subheadline.weight(.semibold))
                Text("What ran").font(.headline)
                Text("A recorded workspace operation.")
                Text("Result").font(.headline)
                Text(event.title.components(separatedBy: ";").first ?? "An execution observation was recorded.")
            }
            Section("Evidence") { ForEach(Array(event.contentFindings.enumerated()), id: \.offset) { _, finding in Text(finding).textSelection(.enabled) } }
            Section("Recorded event") { WhisperKnotInlineEvidenceText(text: event.raw.formatted) }
        }.navigationTitle("Step details").navigationBarTitleDisplayMode(.inline)
    }
}
