import Foundation
import Observation

/// Presentation only. Executor events and failures remain independently recorded.
nonisolated struct WhisperKnotProgressState {
    enum Phase: String, CaseIterable {
        case reading = "Reading your request…"
        case researching = "Reading sources…"
        case working = "Working on your request…"
        case calculating = "Calculating…"
        case preparing = "Preparing your file…"
        case creating = "Creating your file…"
        case checking = "Checking the result…"
        case writing = "Writing reply…"
    }
    private(set) var current: Phase?
    private(set) var pending: Phase?
    private(set) var changedAt: TimeInterval = 0
    private(set) var changes = 0
    var nextChangeAt: TimeInterval? { pending == nil ? nil : changedAt + 2 }

    mutating func begin(now: TimeInterval) {
        self = Self()
        current = .reading; changedAt = now
    }
    mutating func end() { self = Self() }
    mutating func offer(_ phase: Phase, now: TimeInterval) {
        guard current != nil else { return }
        // The latest real observation wins, including a return to the displayed
        // phase while another phase is pending. Never play a stale phase later.
        guard phase != current else { pending = nil; return }
        pending = phase
        flush(now: now)
    }
    mutating func flush(now: TimeInterval) {
        guard let pending, current != nil, now >= changedAt + 2 else { return }
        // Bound vocabulary/cadence, not lifetime transitions: real repair can
        // return from checking to creation, and must still reach reply writing.
        current = pending; self.pending = nil
        changes += 1; changedAt = now
    }
    static func executionLabel(tool: String, operation: String?, receiptKind: String? = nil) -> String? {
        if tool == "document_script" { return Phase.creating.rawValue }
        switch operation {
        case "memory_read", "skill_index", "skill_read", "workspace_read", "workspace_inventory", "recovery_read": return Phase.reading.rawValue
        case "work": return receiptKind == "internal" ? nil : Phase.working.rawValue
        // Optional learning/memory housekeeping must not displace real checking
        // or reply writing. Unknown legacy commands do not establish a phase.
        default: return nil
        }
    }
    static func phase(for label: String) -> Phase? {
        // Deliberately no substring fallback: unknown/internal vocabulary is silent.
        switch label {
        case "Reading your request…", "Reading your message…", "Looking at your photo…", "Reading your file…": .reading
        case "Reading sources…": .researching
        case "Working on your request…", "Reading the command result…": .working
        case "Calculating…", "Checking your numbers…": .calculating
        case "Preparing your file…": .preparing
        case "Creating your file…": .creating
        case "Checking the result…", "Checking the shared posts…": .checking
        case "Writing reply…", "Receiving reply…", "Formatting reply…": .writing
        default: nil
        }
    }
}

@Observable final class WhisperKnotTurnProgress {
    private(set) var state = WhisperKnotProgressState()
    private var sourceID: UUID?
    private(set) var taskPlan: String?
    private(set) var updates: [String] = []
    func observe(_ observation: WhisperKnotRecordedActivity) {
        guard sourceID?.uuidString.lowercased() == observation.sourceMessageID?.lowercased() else { return }
        // Operation labels, purposes, results and plans are header/Events data.
        // Only a separately authored update addressed TO the member enters chat.
        let text = observation.kind == "activity_result" ? observation.detail?.chatUpdate : nil
        guard let text, !text.isEmpty, text.utf16.count <= 1200, updates.last != text else { return }
        updates.append(text)
        if updates.count > 6 { updates.removeFirst(updates.count - 6) }
    }
    private(set) var creativePlan = false
    private(set) var creativeWork = false
    func plan(_ text: String, creative: Bool) {
        guard sourceID != nil, taskPlan == nil, !text.isEmpty, text.utf16.count <= 240 else { return }
        taskPlan = text; creativePlan = creative
    }
    func working(creative: Bool) { creativeWork = sourceID != nil && creativePlan && creative }
    private var timer: Task<Void, Never>?
    var label: String? { state.current?.rawValue }
    func begin(sourceID: UUID) {
        guard self.sourceID != sourceID else { return }
        timer?.cancel(); self.sourceID = sourceID
        updates = []; taskPlan = nil; creativePlan = false; creativeWork = false
        state.begin(now: ProcessInfo.processInfo.systemUptime)
    }
    func end() { timer?.cancel(); timer = nil; sourceID = nil; updates = []; taskPlan = nil; creativePlan = false; creativeWork = false; state.end() }
    func offer(_ label: String) {
        guard let phase = WhisperKnotProgressState.phase(for: label) else { return }
        state.offer(phase, now: ProcessInfo.processInfo.systemUptime)
        timer?.cancel()
        guard let due = state.nextChangeAt else { return }
        let source = sourceID
        timer = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, due - ProcessInfo.processInfo.systemUptime))) }
            catch { return }
            guard let self, self.sourceID == source, !Task.isCancelled else { return }
            self.state.flush(now: ProcessInfo.processInfo.systemUptime)
        }
    }
}
