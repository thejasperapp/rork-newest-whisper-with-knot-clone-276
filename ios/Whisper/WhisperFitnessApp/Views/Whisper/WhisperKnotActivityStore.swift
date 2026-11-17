import Foundation
import Observation

/// A fixed projection of the same observations and execution records in Events.
/// Transport labels and elapsed-time animations never classify a stage.
enum KnotActivityStage {
    static func title(_ key: String, fallback: String = "Carry out the next step") -> String {
        switch key {
        case "preparing": "Prepare the task"
        case "selection": "Choose the next step"
        case "authoring": "Write the document"
        case "source": "Create the document source"
        case "building": "Build the document"
        case "checking": "Check the document"
        case "delivery": "Deliver the document"
        case "reply": "Write the reply"
        case "stopped": "Task stopped"
        case "search": "Research the request"
        case "calculation": "Calculate the result"
        case "browser_read": "Read the browser page"
        case "browser_start": "Open the browser"
        case "browser_navigate": "Navigate the browser"
        case "browser_input": "Use the browser page"
        case "browser_stop": "Close the browser"
        default: fallback.components(separatedBy: ";").first ?? fallback
        }
    }
}

extension WhisperKnotRecordedActivity {
    var presentationStage: String? {
        if ["document_work_unavailable", "error", "rejected", "cancelled"].contains(kind) { return "stopped" }
        if kind.hasPrefix("document_program_") || (kind.hasPrefix("model_transport_") || kind == "tool_request_rejected") && detail?.stage == "document_authoring" { return "authoring" }
        if kind.hasPrefix("tool_selection_") || kind.hasPrefix("model_transport_") || ["shell_review_ready", "work_routing", "tool_request_rejected"].contains(kind) { return "selection" }
        if kind == "complete", detail?.stage == "document_capture" { return "delivery" }
        if kind.hasPrefix("document_") { return "checking" }
        if kind.hasPrefix("skill_read_") || kind.hasPrefix("conversation_memory_") || kind.hasPrefix("connection_") { return "preparing" }
        if kind == "generating" { return detail?.stage == "conversation_memory" ? "preparing" : "reply" }
        if kind == "finalizing" { return "reply" }
        return pairFamily
    }
}

extension WhisperKnotShellReplay.Record {
    var presentationStage: String {
        if plumbing == true || ["memory_read", "skill_read", "skill_index", "workspace_inventory", "workspace_read"].contains(operation ?? "") { return "preparing" }
        if let stage = spec.documentInvocation?.stage {
            switch stage {
            case "build": return "building"
            case "measure", "existing", "final", "proof": return "checking"
            default: return "source"
            }
        }
        return "command:" + id
    }
}

nonisolated struct KnotPillTransition: Codable, Hashable, Sendable {
    let stage: String
    let stepID: String
    let observedAt: Double
    let evidenceID: String?
}

/// View-owned text projection. Scroll/header invalidations and pill timestamps
/// must not run output sanitization across the whole conversation repeatedly.
@MainActor final class WhisperKnotMessageProjection {
    private var context = ""
    private var cleaned: [UUID: (source: String, user: Bool, text: String)] = [:]
    func messages(_ turns: [WhisperEmberChatView.Turn], context: String) -> [WhisperKnotMessageEvent] {
        if self.context != context { self.context = context; cleaned = [:] }
        let ids = Set(turns.map(\.id))
        cleaned = cleaned.filter { ids.contains($0.key) }
        return turns.compactMap { turn in
            let user = turn.role == .user
            let text: String
            if let cached = cleaned[turn.id], cached.source == turn.text, cached.user == user { text = cached.text }
            else {
                text = (user ? turn.text : WhisperKnotOutput.clean(turn.text)).trimmingCharacters(in: .whitespacesAndNewlines)
                cleaned[turn.id] = (turn.text, user, text)
            }
            guard !text.isEmpty || turn.attachmentLabel != nil || turn.block != nil else { return nil }
            return .init(id: turn.id, date: turn.createdAt > 0 ? Date(timeIntervalSince1970: turn.createdAt / 1000) : .distantPast,
                text: text.isEmpty ? (turn.attachmentLabel ?? "Reply with shared content") : text, fromUser: user, pillTimeline: turn.pillTimeline ?? [])
        }
    }
}

/// One owner-scoped replay/live collection for both the header and Events.
@Observable @MainActor final class WhisperKnotActivityStore {
    private(set) var replay: WhisperKnotShellReplay?
    private(set) var loading = false
    private(set) var issue: String?
    private var live: [String: WhisperKnotRecordedActivity] = [:]
    private var identity = ""
    private var generation = AccountStorage.generation
    private var revision = WhisperKnotContextPermission.revision
    private var loadOperation: UUID?
    private var projectionRevision = 0
    @ObservationIgnored private var cachedProjection: (revision: Int, proposals: [WhisperKnotShellProposal], messages: [WhisperKnotMessageEvent], working: Bool, sourceID: UUID?, tasks: [KnotActivityTask])?

    func prepare(_ context: String) {
        guard identity != context || generation != AccountStorage.generation || revision != WhisperKnotContextPermission.revision else { return }
        clear()
        identity = context; generation = AccountStorage.generation; revision = WhisperKnotContextPermission.revision
    }
    func clear() { identity = ""; replay = nil; live = [:]; issue = nil; loading = false; loadOperation = nil; projectionRevision &+= 1; cachedProjection = nil }
    private func valid(_ context: String) -> Bool {
        identity == context && generation == AccountStorage.generation && revision == WhisperKnotContextPermission.revision && WhisperKnotContextPermission.allowed
    }
    func observe(_ value: WhisperKnotRecordedActivity, context: String) {
        prepare(context)
        guard valid(context), !Task.isCancelled else { return }
        live[value.id] = value
        projectionRevision &+= 1
    }
    func load(bot: WhisperKnotBot, conversationID: UUID, context: String) async {
        prepare(context)
        guard valid(context), !Task.isCancelled, loadOperation == nil else { return }
        let operation = UUID(); loadOperation = operation; loading = replay == nil
        defer { if loadOperation == operation { loading = false; loadOperation = nil } }
        do {
            let value = try await WhisperKnotShellEvidenceService.replay(bot: bot.rawValue, conversationID: conversationID.uuidString.lowercased())
            guard valid(context), !Task.isCancelled, loadOperation == operation else { return }
            var changed = replay?.fingerprint != value.fingerprint || replay == nil
            if changed { replay = value }
            // Persistence wins for matching IDs; keep not-yet-persisted live frames.
            for activity in value.activities ?? [] { if live.removeValue(forKey: activity.id) != nil { changed = true } }
            if changed { projectionRevision &+= 1 }
            issue = nil
        } catch {
            if valid(context), !Task.isCancelled, loadOperation == operation { issue = "Couldn’t refresh events. Saved steps remain available." }
        }
    }

    func tasks(context: String, proposals: [WhisperKnotShellProposal], messages: [WhisperKnotMessageEvent], working: Bool, sourceID: UUID?) -> [KnotActivityTask] {
        guard valid(context) else { return [] }
        let revision = projectionRevision
        if let cached = cachedProjection, cached.revision == revision, cached.working == working, cached.sourceID == sourceID, cached.proposals == proposals {
            if cached.messages == messages { return cached.tasks }
            if cached.messages.count == messages.count, zip(cached.messages, messages).allSatisfy({ old, new in old.id == new.id && old.date == new.date && old.text == new.text && old.fromUser == new.fromUser }) {
                // Only the locally recorded pill timeline changed. Keep the
                // expensive evidence/step projection; Events still sees new pills.
                let fresh = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                let tasks = cached.tasks.map { old in
                    var task = old; task.messages = old.messages.map { fresh[$0.id] ?? $0 }; return task
                }
                cachedProjection = (revision, proposals, messages, working, sourceID, tasks)
                return tasks
            }
        }
        let result = Self.rollup(replay: replay, live: Array(live.values), proposals: proposals, messages: messages, working: working, sourceID: sourceID)
        cachedProjection = (revision, proposals, messages, working, sourceID, result)
        return result
    }

    static func rollup(replay: WhisperKnotShellReplay?, live: [WhisperKnotRecordedActivity] = [], proposals: [WhisperKnotShellProposal], messages: [WhisperKnotMessageEvent], working: Bool, sourceID: UUID?) -> [KnotActivityTask] {
        var records = Dictionary((replay?.records ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
        for proposal in proposals {
            if var stored = records[proposal.id] {
                if let result = proposal.result, result != stored.result, result.canReplace(stored.result) {
                    stored = .init(spec: proposal.spec, state: proposal.state, result: result, taskID: stored.taskID, taskTitle: stored.taskTitle, sourceMessageID: stored.sourceMessageID, recordedAt: stored.recordedAt, operation: stored.operation, accounting: stored.accounting, plumbing: stored.plumbing, workCost: stored.workCost, workCommands: stored.workCommands, commandLimit: stored.commandLimit, commandOrder: stored.commandOrder, commandSequence: stored.commandSequence, orderSource: stored.orderSource, newExecution: stored.newExecution, cachedData: stored.cachedData, receiptOutputComplete: result.outputComplete, receiptTruncated: result.truncated)
                    records[proposal.id] = stored
                }
            } else {
                records[proposal.id] = .init(spec: proposal.spec, state: proposal.state, result: proposal.result ?? .notStarted(proposal.spec, reason: "No execution receipt yet."), taskID: proposal.spec.taskID, taskTitle: proposal.spec.taskTitle, sourceMessageID: proposal.spec.sourceMessageID)
            }
        }
        var grouped: [String: KnotActivityTask] = [:]
        var lastQuestion: String?
        var seenMessages = Set<UUID>()
        for message in messages where seenMessages.insert(message.id).inserted {
            if message.fromUser { lastQuestion = "message:" + message.id.uuidString.lowercased() }
            let key = lastQuestion ?? "message:" + message.id.uuidString.lowercased()
            if grouped[key] == nil { grouped[key] = KnotActivityTask(id: key, title: message.fromUser ? message.text : "Conversation task") }
            grouped[key]?.messages.append(message)
        }
        // Parse each record timestamp once per projection, never in a sort comparator.
        let recordDates = records.mapValues(\.date)
        let commands = Dictionary(grouping: records.values, by: { ($0.taskID ?? $0.spec.taskID ?? $0.id).lowercased() })
        let unique = Dictionary((live + (replay?.activities ?? [])).map { ($0.id, $0) }, uniquingKeysWith: { _, persisted in persisted })
        let stages = Dictionary(grouping: unique.values, by: { ($0.taskID ?? $0.requestID).lowercased() })
        for root in Set(commands.keys).union(stages.keys).sorted() {
            let rows = (commands[root] ?? []).sorted { recordDates[$0.id] == recordDates[$1.id] ? $0.id < $1.id : recordDates[$0.id, default: .distantPast] < recordDates[$1.id, default: .distantPast] }
            let activity = (stages[root] ?? []).sorted { $0.date == $1.date ? ($0.requestID == $1.requestID ? $0.sequence < $1.sequence : $0.id < $1.id) : $0.date < $1.date }
            let source = rows.compactMap { $0.sourceMessageID ?? $0.spec.sourceMessageID }.first ?? activity.compactMap(\.sourceMessageID).first
            let linked = source.map { "message:" + $0.lowercased() }
            let key = linked.flatMap { grouped[$0] != nil ? $0 : nil } ?? "task:" + root
            if grouped[key] == nil { grouped[key] = KnotActivityTask(id: key, title: rows.first?.taskTitle ?? rows.first?.spec.taskTitle ?? "Conversation task") }
            grouped[key]?.records += rows
            grouped[key]?.activities += activity
        }
        // An old last question is not evidence of ownership of the live turn.
        let activeKey = sourceID.map { "message:" + $0.uuidString.lowercased() }
        return grouped.values.map { original in
            var task = original
            task.records.sort { recordDates[$0.id] == recordDates[$1.id] ? $0.id < $1.id : recordDates[$0.id, default: .distantPast] < recordDates[$1.id, default: .distantPast] }
            task.activities.sort { $0.date == $1.date ? ($0.requestID == $1.requestID ? $0.sequence < $1.sequence : $0.id < $1.id) : $0.date < $1.date }
            let ids = Set(task.records.map { $0.id.lowercased() })
            task.executorEvents = (replay?.events ?? []).filter { ids.contains($0.proposalID.lowercased()) }.sorted { $0.sequence < $1.sequence }
            task.documents = (replay?.documents ?? []).filter { $0.valid && (ids.contains($0.proposalID.lowercased()) || $0.sourceMessageID.map { task.id == "message:" + $0.lowercased() } == true) }
            let lifecycle = task.serverLifecycle
            task.active = lifecycle == "background_started" || lifecycle == nil && working && task.id == activeKey
            task.preparedSteps = task.steps
            task.preparedCurrentStep = task.currentStep
            task.currentStepPrepared = true
            return task
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}
