import Foundation

/// A display-only projection inside an already owner/root-linked task. The
/// original records remain intact; neither grouping nor a reply proves delivery.
struct KnotActivityStep: Identifiable {
    let id: String
    let title: String
    var taskObject = "your file"
    var records: [WhisperKnotShellReplay.Record] = []
    var observations: [WhisperKnotRecordedActivity] = []
    var documents: [WhisperKnotDocument] = []
    var active = false
    var preparedDates: (first: Date, last: Date)? = nil
    var preparedStageWord: String? = nil
    var authoredStep: WhisperKnotRecordedActivity? { observations.first { $0.kind == "activity_open" && $0.detail?.stepLabel != nil } }
    var authoredOpen: Bool { authoredStep != nil && !observations.contains { $0.kind == "activity_close" } }
    var stageWord: String {
        if let authored = authoredStep?.detail?.stepLabel { return authored }
        if let preparedStageWord { return preparedStageWord }
        if let record = records.last { return record.spec.title }
        if id == "selection" {
            let selection = observations.filter { $0.presentationStage == "selection" }
            // Transport retries can omit the phase. Carry it only within the
            // newest request, never from another request grouped into this row.
            let latest = selection.max { lhs, rhs in
                if lhs.requestID == rhs.requestID { return lhs.sequence < rhs.sequence }
                return lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date < rhs.date
            }
            let phase = latest.flatMap { latest in
                selection.filter { $0.requestID == latest.requestID && $0.sequence <= latest.sequence && $0.detail?.selectionPhase != nil }
                    .max { $0.sequence < $1.sequence }?.detail?.selectionPhase
            }
            switch phase {
            case "document_authoring", "artifact_authoring", "document_build": return "Preparing \(taskObject)"
            case "browser_choice": return "Planning the browser action"
            case "closing_choice": return "Preparing your reply"
            case "tool_choice": return "Preparing your request"
            default: return "Preparing \(taskObject)"
            }
        }
        return switch id {
        case "authoring", "source": "Writing \(taskObject)"
        case "reply": "Writing your reply"
        case "building": "Building \(taskObject)"
        case "checking": "Checking \(taskObject)"
        case "delivery": "Delivering \(taskObject)"
        case "preparing": "Checking your workspace"
        case "selection": "Preparing \(taskObject)"
        case "stopped": "Work stopped"
        case "search": "Researching your request"
        case "calculation": "Calculating your result"
        case "browser_read": "Reading the current page"
        case "browser_start": "Opening the browser"
        case "browser_navigate": "Opening the requested page"
        case "browser_input": "Working on the browser page"
        case "browser_stop": "Closing the browser"
        default: "Working on your request"
        }
    }
    private var dates: [Date] { records.map(\.date) + observations.map(\.date) + documents.compactMap { try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0.createdAt) } }
    var lastDate: Date { preparedDates?.last ?? dates.max() ?? .distantPast }
    var date: Date { preparedDates?.first ?? dates.min() ?? .distantPast }
    func prepared() -> Self {
        var value = self
        let dates = dates
        value.preparedDates = (dates.min() ?? .distantPast, dates.max() ?? .distantPast)
        value.preparedStageWord = stageWord
        return value
    }
    var state: String {
        if authoredStep != nil {
            if authoredOpen { return active ? "Working" : "Stopped" }
            // Closing a presentation step is not an execution/quality pass.
            if observations.contains(where: { $0.kind.hasSuffix("_unavailable") || $0.kind.hasSuffix("_rejected") || $0.kind == "document_visual_incomplete" }) { return "Needs attention" }
            return "Finished"
        }
        if id == "stopped" { return "Stopped" }
        if id == "delivery" { return documents.isEmpty ? (active ? "Working" : "Stopped") : "Done" }
        let execution = records.map { WhisperKnotExecutionAppearance.label($0.result, state: $0.state, complete: $0.receiptOutputComplete, truncated: $0.receiptTruncated) }
        if execution.contains(where: { ["Working", "Waiting for receipt", "Stop requested", "Preparing"].contains($0) }) { return active ? "Working" : "Stopped" }
        if execution.contains("Failed") { return "Failed" }
        if execution.contains(where: { ["Not confirmed", "Output incomplete"].contains($0) }) { return "Not confirmed" }
        if zip(records, execution).contains(where: { $0.0.cachedData == nil && $0.1 != "Step finished" }) { return "Not started" }
        if observations.contains(where: { ["document_content_unconfirmed", "document_quality_qualified", "document_visual_incomplete"].contains($0.kind) }) { return "Needs attention" }
        if observations.contains(where: { $0.kind.hasSuffix("_unavailable") || $0.kind == "browser_action_uncertain" }) { return "Not confirmed" }
        if id == "authoring" {
            // A sealed program completes authoring only, never execution.
            let programs = Dictionary(grouping: observations.filter { $0.kind.hasPrefix("document_program_") }, by: { $0.detail?.programID ?? $0.requestID })
            let sealed = !programs.isEmpty && programs.values.allSatisfy { $0.contains(where: { $0.kind == "document_program_sealed" }) }
            return sealed ? "Done" : active ? "Working" : "Stopped"
        }
        if id == "selection" {
            let requests = Dictionary(grouping: observations, by: \.requestID)
            let selected = requests.values.allSatisfy { rows in
                rows.last?.detail?.outcome == "recovered" || rows.contains(where: { ["shell_review_ready", "document_program_started", "generating", "complete"].contains($0.kind) })
            }
            return selected ? "Done" : active ? "Working" : "Stopped"
        }
        // Pair each actual start with its own request/family completion. A later
        // unrelated operation cannot manufacture a green check for this one.
        let starts = observations.filter(\.startsOperation)
        if !starts.isEmpty {
            var used = Set<String>()
            let confirmed = starts.allSatisfy { start in
                guard let end = observations.first(where: { end in !used.contains(end.id) && end.requestID == start.requestID && end.pairFamily == start.pairFamily && start.pairFamily != nil && end.sequence > start.sequence && end.confirmsOperation }) else { return false }
                used.insert(end.id)
                return true
            }
            if confirmed { return "Done" }
            return active ? "Working" : "Stopped"
        }
        if observations.contains(where: \.confirmsOperation) || id == "reply" && observations.contains(where: { $0.kind == "complete" }) || !records.isEmpty && zip(records, execution).allSatisfy({ $0.0.cachedData != nil || $0.1 == "Step finished" }) { return "Done" }
        return active ? "Working" : "Stopped"
    }
    var subtitle: String {
        if let authoredStep {
            return observations.last(where: { $0.detail?.stepResult != nil })?.detail?.stepResult
                ?? authoredStep.detail?.stepPurpose ?? ""
        }
        if id == "delivery" { return documents.map(\.name).joined(separator: " · ") }
        if id == "stopped" {
            if observations.contains(where: { $0.detail?.check == "provider_timeout" || $0.detail?.reason == "document_authoring_timeout" }) { return "The document authoring request timed out." }
            if observations.contains(where: { $0.kind == "cancelled" }) { return "The response was stopped. Execution receipts are retained." }
            return "Open the evidence for the recorded cause."
        }
        if let outcome = observations.last(where: { $0.endsOperation && !$0.bookkeeping }) { return outcome.readableOutcome }
        if !records.isEmpty, state != "Working" {
            var seen = Set<String>()
            return records.map(\.humanResult).filter { seen.insert($0).inserted }.joined(separator: " ")
        }
        if id == "authoring" { return state == "Done" ? "The complete authored source is saved; execution is separate." : "Writing the document’s full content." }
        if id == "reply" { return state == "Done" ? "The reply is ready." : "Write the response to your request." }
        if id == "preparing" { return "Read workspace context and relevant guidance." }
        if id == "selection" { return "Choose the next operation for this request." }
        if id == "building" { return "Run the document build from the authored source." }
        if id == "checking" {
            if observations.contains(where: { $0.kind == "document_content_unconfirmed" }) { return "File captured; content review incomplete." }
            return "Inspect the document’s output and recorded checks."
        }
        if let record = records.first { return record.spec.documentInvocation?.path ?? (state == "Done" ? "Execution receipt received." : "Open the step for its execution receipt.") }
        switch id {
        case "search": return "Look up sources for this request."
        case "calculation": return "Evaluate the requested calculation."
        case "browser_read": return "Read the current browser page."
        case "browser_navigate": return "Navigate to the requested page."
        case "browser_input": return "Interact with the current page."
        default: return "Open the step for its recorded evidence."
        }
    }
}

struct KnotActivityTask: Identifiable {
    let id: String
    let title: String
    var records: [WhisperKnotShellReplay.Record] = []
    var activities: [WhisperKnotRecordedActivity] = []
    var messages: [WhisperKnotMessageEvent] = []
    var executorEvents: [WhisperKnotExecutorEvent] = []
    var documents: [WhisperKnotDocument] = []
    var active = false
    var preparedSteps: [KnotActivityStep]? = nil
    var preparedCurrentStep: KnotActivityStep? = nil
    var currentStepPrepared = false
    var displayTitle: String {
        let name = documents.first?.displayTitle ?? records.compactMap { $0.taskTitle ?? $0.spec.taskTitle }.first(where: { !$0.isEmpty }) ?? title
        let firstLine = name.components(separatedBy: .newlines).first ?? name
        return firstLine.count > 90 ? String(firstLine.prefix(87)) + "…" : firstLine
    }
    var date: Date { messages.first?.date ?? records.first?.date ?? activities.first?.date ?? .distantPast }
    var symbol: String { activities.contains(where: { $0.kind.hasPrefix("browser_") }) ? "globe" : records.isEmpty ? "bubble.left.and.bubble.right" : "checklist" }
    var isDocument: Bool { activities.contains(where: { $0.kind.hasPrefix("document_") }) || records.contains(where: { $0.spec.documentInvocation != nil }) }
    /// Terminal server ownership wins over stale local working flags and late
    /// transport observations; none of these labels invent execution receipts.
    var serverLifecycle: String? {
        for kind in ["background_stopped", "background_degraded", "background_completed", "background_started"] {
            if activities.contains(where: { $0.kind == kind }) { return kind }
        }
        return nil
    }
    var summary: String {
        if serverLifecycle == "background_stopped" { return "Stopped" }
        if serverLifecycle == "background_degraded" { return "Needs attention" }
        if serverLifecycle == "background_completed" { return documents.contains(where: \.reviewNeedsAttention) ? "Needs attention" : "Done" }
        if active { return "Working" }
        let rows = steps
        if rows.contains(where: { $0.state == "Failed" }) { return "Failed" }
        if documents.contains(where: \.reviewNeedsAttention) || rows.contains(where: { $0.state == "Needs attention" }) { return "Needs attention" }
        if rows.contains(where: { $0.state == "Not confirmed" }) { return "Not confirmed" }
        if rows.contains(where: { !["Done", "Finished"].contains($0.state) }) { return "Stopped" }
        if !documents.isEmpty || !isDocument && messages.contains(where: { !$0.fromUser }) { return "Done" }
        return "Stopped"
    }
    /// The current row of this rollup is also the header's only stage source.
    var currentStep: KnotActivityStep? {
        if currentStepPrepared { return preparedCurrentStep }
        let rows = steps
        if rows.contains(where: { $0.authoredStep != nil }) || activities.contains(where: { $0.detail?.stepPresentation == "authored_v1" }) { return active ? rows.last(where: \.authoredOpen) : nil }
        let latest = activities.filter { $0.presentationStage != nil && $0.presentationStage != "stopped" }.max {
            if $0.requestID == $1.requestID { return $0.sequence < $1.sequence }
            return $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
        }
        if let latest, let row = rows.first(where: { $0.id == latest.presentationStage || $0.observations.contains(where: { $0.id == latest.id }) }) {
            if let delivery = rows.first(where: { $0.id == "delivery" }), delivery.lastDate >= latest.date { return delivery }
            if let execution = rows.filter({ !$0.records.isEmpty && $0.lastDate > latest.date }).max(by: { $0.lastDate < $1.lastDate }) { return execution }
            return row
        }
        return rows.filter { $0.id != "stopped" }.max { $0.lastDate < $1.lastDate }
    }
    var overview: String {
        if serverLifecycle == "background_degraded" { return "The available result is saved in the originating chat. Some requested work remains incomplete; see Events for the confirmed steps." }
        if serverLifecycle == "background_stopped" { return "Stop was requested. Execution receipts show whether remote work has ended." }
        if serverLifecycle == "background_completed", documents.isEmpty { return "The result is saved in the originating chat." }
        if !documents.isEmpty {
            let delivery = "Saved \(documents.map(\.name).joined(separator: ", "))."
            if ["Needs attention", "Not confirmed"].contains(summary) { return delivery + " Some checks need attention; see the recorded steps below." }
            return delivery
        }
        if summary == "Working" { return "Working through the steps for your request." }
        if isDocument { return "Document work ended without a captured delivery." }
        return messages.contains(where: { !$0.fromUser }) ? "A response is saved with this conversation." : "The request and its recorded steps are saved here."
    }
    /// Events shows each dispatched command once, not presentation/planning stages.
    /// Keep the full observations intact for the header and retained evidence.
    var commandSteps: [KnotActivityStep] {
        var seen = Set<String>()
        return records.filter { record in
            record.cachedData == nil && seen.insert(record.id.lowercased()).inserted &&
                (record.result.sessionID != nil || ["running", "dispatching"].contains(record.state))
        }.sorted { lhs, rhs in
            if let left = lhs.commandSequence, let right = rhs.commandSequence, left != right { return left < right }
            return lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date < rhs.date
        }.map { record in
            KnotActivityStep(id: record.id, title: record.spec.title, records: [record], active: active).prepared()
        }
    }
    var steps: [KnotActivityStep] {
        if let preparedSteps { return preparedSteps }
        let authored = activities.filter { $0.kind == "activity_open" && $0.detail?.stepID != nil && $0.detail?.stepLabel != nil }
        if !authored.isEmpty || activities.contains(where: { $0.detail?.stepPresentation == "authored_v1" }) {
            // Actual agent-authored operations, never stage grouping or a fixed vocabulary.
            // Exact receipt IDs bind execution. Unbound plumbing stays in raw evidence.
            var seen = Set<String>()
            return authored.compactMap { start in
                guard let stepID = start.detail?.stepID, seen.insert(stepID).inserted else { return nil }
                let observations = activities.filter { $0.detail?.stepID == stepID }
                let receipts = Set(observations.compactMap { $0.detail?.stepReceiptID?.lowercased() })
                let linked = records.filter { receipts.contains($0.id.lowercased()) }
                return KnotActivityStep(id: stepID, title: start.detail?.stepLabel ?? start.label, records: linked, observations: observations, active: active).prepared()
            }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        }
        let path = documents.first?.name ?? records.reversed().compactMap { $0.spec.documentInvocation?.path }.first ?? ""
        let taskObject: String = switch (path as NSString).pathExtension.lowercased() {
        case "pdf": "your PDF"
        case "docx": "your document"
        case "xlsx", "csv": "your spreadsheet"
        case "pptx": "your presentation"
        case "html": isDocument ? "your document" : "your interactive file"
        default:
            if activities.contains(where: { $0.detail?.selectionPhase == "artifact_authoring" }) { "your interactive file" }
            else if isDocument || activities.contains(where: { ["document_authoring", "document_build"].contains($0.detail?.selectionPhase ?? "") }) { "your document" }
            else { "your file" }
        }
        var grouped: [String: KnotActivityStep] = [:]
        func add(_ key: String, _ title: String, record: WhisperKnotShellReplay.Record? = nil, observation: WhisperKnotRecordedActivity? = nil) {
            if grouped[key] == nil { grouped[key] = .init(id: key, title: title, taskObject: taskObject, active: active) }
            if let record { grouped[key]?.records.append(record) }
            if let observation { grouped[key]?.observations.append(observation) }
        }
        for record in records {
            let key = record.presentationStage
            add(key, KnotActivityStage.title(key, fallback: record.spec.title), record: record)
        }
        for activity in activities {
            if let key = activity.presentationStage { add(key, KnotActivityStage.title(key), observation: activity) }
            // Other infrastructure/unknown observations remain in Service
            // timeline. Unknown kinds never turn into invented successful steps.
        }
        if grouped["selection"] != nil {
            grouped["selection"]?.observations += activities.filter { $0.kind == "document_program_started" || $0.kind == "complete" || $0.kind == "generating" && $0.detail?.stage != "conversation_memory" }
        }
        if grouped["reply"] != nil { grouped["reply"]?.observations += activities.filter { $0.kind == "complete" } }
        if !documents.isEmpty { grouped["delivery"] = .init(id: "delivery", title: "Deliver the document", taskObject: taskObject, documents: documents, active: active) }
        // Selection is plumbing for adjacent real work, not its own chip.
        // Preserve every observation under that step's evidence.
        if let selection = grouped["selection"], let neighbour = grouped.values
            .filter({ !["selection", "preparing", "stopped", "delivery", "reply"].contains($0.id) })
            .min(by: { abs($0.date.timeIntervalSince(selection.date)) < abs($1.date.timeIntervalSince(selection.date)) }) {
            grouped[neighbour.id]?.observations += selection.observations
            grouped.removeValue(forKey: "selection")
        }
        return grouped.values.map { $0.prepared() }.sorted {
            if $0.id == "delivery" || $1.id == "delivery" { return $1.id == "delivery" }
            if $0.id == "stopped" || $1.id == "stopped" { return $1.id == "stopped" }
            return $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
        }
    }
}
