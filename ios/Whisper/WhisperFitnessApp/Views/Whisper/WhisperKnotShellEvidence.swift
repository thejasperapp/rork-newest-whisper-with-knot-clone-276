import SwiftUI
import Supabase
import CryptoKit

/// Nested receipt fields retain their names and values. Not a model-authored event type.
nonisolated indirect enum WhisperKnotReceiptJSON: Codable, Hashable, Sendable {
    case object([String: Self]), array([Self]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: Self].self) { self = .object(v) }
        else { self = .array(try c.decode([Self].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var text: String {
        if case .string(let value) = self { return value }
        return ""
    }
    var formatted: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    subscript(_ key: String) -> Self? { if case .object(let v) = self { return v[key] }; return nil }
}

nonisolated struct WhisperKnotExecutorEvent: Decodable, Identifiable, Sendable {
    let sequence: Int
    let proposalID: String
    let kind: String
    let recordedAt: String
    let raw: WhisperKnotReceiptJSON
    var id: Int { sequence }
    init(from decoder: Decoder) throws {
        raw = try WhisperKnotReceiptJSON(from: decoder)
        enum Keys: String, CodingKey { case sequence, proposalID, kind, recordedAt }
        let c = try decoder.container(keyedBy: Keys.self)
        sequence = try c.decode(Int.self, forKey: .sequence)
        proposalID = try c.decode(String.self, forKey: .proposalID)
        kind = try c.decode(String.self, forKey: .kind)
        recordedAt = try c.decode(String.self, forKey: .recordedAt)
    }
    var title: String {
        switch kind {
        case "review_created": return "Command prepared"
        case "dispatch_intent": return "Dispatch recorded"
        case "provider_record": return "Shell record received"
        case "input_intent": return "Exact input recorded"
        case "input_receipt": return "Input acknowledgment received"
        case "execution_finished": return "Terminal result recorded"
        case "output_recovered": return "Retained output updated"
        case "stop_receipt": return "Stop acknowledgment received"
        case "execution_unconfirmed": return "Execution not confirmed"
        case "stop_requested": return "Stop requested"
        case "log_unavailable": return "Output log unavailable"
        case "review_declined": return "Declined before execution"
        case "document_proof_passed": return "Final-file mechanical proof passed"
        case "document_proof_blocked": return "Document proof incomplete; delivery blocked"
        case "document_content_check_attempt": return "Document content checker run recorded"
        case "document_source_unconfirmed": return "Source quality verdict unconfirmed; nonblocking"
        case "document_content_unconfirmed": return "Content verdict unconfirmed; not a pass"
        case "document_source_reviewed": return "Source completeness passed; final proof still required"
        case "document_source_blocked": return "Source content or evidence needs attention"
        case "document_content_reviewed": return "Rendered document content comparison passed"
        case "document_content_blocked": return "Document content check blocked delivery"
        case "document_content_qualified": return "Content captured with checked shortfalls; not a pass"
        case "document_visual_reviewed": return "Every rendered page passed visual AI review"
        case "document_visual_qualified": return "Every page reviewed; visual shortfalls retained"
        case "document_visual_blocked": return "All-page visual review blocked delivery"
        case "document_quality_shortfalls": return "Delivered with remaining quality shortfalls"
        case "document_captured": return "Private original captured"
        case "skill_draft_written": return "Workspace skill draft saved; not promoted"
        case "skill_draft_amended": return "Workspace skill draft amended; not promoted"
        case "skill_data_cached": return "Installed guide data reused; no new execution"
        case "skill_data_unavailable": return "Prior guide read incomplete; not replayed"
        case "document_completion_projected": return "Remaining document checks projected; not executed"
        case "document_build_latched": return "Original build retained; no repeat execution"
        case "document_build_continued": return "Continuing checks on the original successful build"
        default: return "Execution event"
        }
    }
    var contentFindings: [String] {
        guard ["document_source_blocked", "document_content_blocked", "document_visual_blocked", "document_quality_shortfalls"].contains(kind),
              case .array(let values)? = raw["observations"] else { return [] }
        return values.compactMap { value -> String? in
            if case .string(let text) = value { return text }
            return nil
        }
    }
}
nonisolated struct WhisperKnotRecordedActivity: Codable, Identifiable, Sendable {
    struct Detail: Codable, Sendable {
        var stepPresentation: String? = nil
        var stepID: String? = nil
        var stepLabel: String? = nil
        var stepPurpose: String? = nil
        var stepResult: String? = nil
        var chatUpdate: String? = nil
        var stepReceiptID: String? = nil
        var reason: String? = nil
        var tool: String? = nil
        var fields: [String]? = nil
        var terminationExit: String? = nil
        var schemaHash: String? = nil
        var model: String? = nil
        var finishReason: String? = nil
        var choicesPresent: Bool? = nil
        var messagePresent: Bool? = nil
        var toolCallsPresent: Bool? = nil
        var argumentBytes: Int? = nil
        var contentBytes: Int? = nil
        var contentShape: String? = nil
        var completionTokens: Int? = nil
        var promptTokens: Int? = nil
        var reasoningTokens: Int? = nil
        var deadlineMs: Int? = nil
        var elapsedMs: Int? = nil
        var promptBytes: Int? = nil
        var strategy: String? = nil
        var promptSections: [String: Int]? = nil
        var sizeFacts: [String: Int]? = nil
        var promptTargetExceeded: Bool? = nil
        var selectionPhase: String? = nil
        var commandDispatched: Bool? = nil
        var selectionIncident: String? = nil
        var attempt: Int? = nil
        var attempts: Int? = nil
        var repairAttempts: Int? = nil
        var tokenLimit: Int? = nil
        var attemptedTokenLimit: Int? = nil
        var escalatedRetryRan: Bool? = nil
        var outcome: String? = nil
        var selectionRecovered: Bool? = nil
        var invalidCall: Int? = nil
        var inputKind: String? = nil
        var stage: String? = nil
        var status: Int? = nil
        var commands: Int? = nil
        var commandLimit: Int? = nil
        var sourceMeasured: Bool? = nil
        var finalMeasured: Bool? = nil
        var proofPrepared: Bool? = nil
        var proofConfirmed: Bool? = nil
        var branch: String? = nil
        var fieldPath: String? = nil
        var expectedShape: String? = nil
        var receivedShape: String? = nil
        var unexplained: Bool? = nil
        var rejectionID: String? = nil
        var rejectedBodySHA256: String? = nil
        var retentionStatus: String? = nil
        var check: String? = nil
        var programID: String? = nil
        var programSHA256: String? = nil
        var sliceCount: Int? = nil
        var sliceIndex: Int? = nil
        var sliceCharacters: Int? = nil
        var sliceCharacterLimit: Int? = nil
        var sliceByteLimit: Int? = nil
        var requestedCharacters: Int? = nil
        var expiresAt: Double? = nil
        var deadlineSource: String? = nil
        var transportAttempt: Int? = nil
        var transportDelayMs: Int? = nil
        var transportOutcome: String? = nil
        var transportCallCount: Int? = nil
        var transportElapsedMs: Int? = nil
        var transportFirstTokenMs: Int? = nil
        var transportChunkCount: Int? = nil
        var transportMaxIdleMs: Int? = nil
        var transportTimeoutKind: String? = nil
        var transportStreaming: Bool? = nil
        var programBytes: Int? = nil
        var authoringResponses: Int? = nil
        var authoringElapsedMs: Int? = nil
        var authoringBytesPerSecond: Int? = nil
        var programByteCeiling: Int? = nil
        var budgetBytesPerSecond: Int? = nil
        var marginPermille: Int? = nil
        var authoringBudgetMs: Int? = nil
        var completionReserveMs: Int? = nil
        var turnBudgetMs: Int? = nil
        var authoringBasePromptBytes: Int? = nil
        var authoringPromptTargetExceeded: Bool? = nil
    }
    var rawRecord: WhisperKnotReceiptJSON? = nil
    enum CodingKeys: String, CodingKey { case detail, id, requestID, taskID, sourceMessageID, messageID, emoji, revision, sequence, kind, label, recordedAt }
    var detail: Detail? = nil
    let id: String
    let requestID: String
    var taskID: String? = nil
    var sourceMessageID: String? = nil
    var messageID: String? = nil
    var emoji: String? = nil
    var revision: Int? = nil
    let sequence: Int
    let kind: String
    let label: String
    let recordedAt: String
    var decodedDate: Date? = nil
    var date: Date {
        decodedDate ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(recordedAt)) ?? (try? Date.ISO8601FormatStyle().parse(recordedAt)) ?? .distantPast
    }
}

nonisolated extension WhisperKnotRecordedActivity {
    init(from decoder: Decoder) throws {
        rawRecord = try WhisperKnotReceiptJSON(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        detail = try c.decodeIfPresent(Detail.self, forKey: .detail)
        id = try c.decode(String.self, forKey: .id)
        requestID = try c.decode(String.self, forKey: .requestID)
        taskID = try c.decodeIfPresent(String.self, forKey: .taskID)
        sourceMessageID = try c.decodeIfPresent(String.self, forKey: .sourceMessageID)
        messageID = try c.decodeIfPresent(String.self, forKey: .messageID)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        revision = try c.decodeIfPresent(Int.self, forKey: .revision)
        sequence = try c.decode(Int.self, forKey: .sequence)
        kind = try c.decode(String.self, forKey: .kind)
        label = try c.decode(String.self, forKey: .label)
        recordedAt = try c.decode(String.self, forKey: .recordedAt)
        decodedDate = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(recordedAt)) ?? (try? Date.ISO8601FormatStyle().parse(recordedAt)) ?? .distantPast
    }
}

nonisolated struct WhisperKnotShellReplay: Decodable, Sendable {
    struct Record: Decodable, Sendable, Identifiable {
        let spec: WhisperKnotShellSpec
        let state: String
        let result: WhisperKnotShellResult
        var taskID: String? = nil
        var taskTitle: String? = nil
        var sourceMessageID: String? = nil
        var recordedAt: String? = nil
        var operation: String? = nil
        var accounting: String? = nil
        var plumbing: Bool? = nil
        var workCost: Int? = nil
        var workCommands: Int? = nil
        var commandLimit: Int? = nil
        var commandOrder: Int? = nil
        var commandSequence: Int? = nil
        var orderSource: String? = nil
        var newExecution: Bool? = nil
        var cachedData: WhisperKnotReceiptJSON? = nil
        var receiptOutputComplete: Bool? = nil
        var receiptTruncated: Bool? = nil
        var id: String { spec.id }
        var date: Date {
            if let recordedAt, let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(recordedAt)) ?? (try? Date.ISO8601FormatStyle().parse(recordedAt)) { return date }
            return Date(timeIntervalSince1970: (spec.expiresAt - 600000) / 1000)
        }
        var proposal: WhisperKnotShellProposal {
            var value = WhisperKnotShellProposal(spec: spec)
            value.state = state; value.result = result
            return value
        }
    }
    let records: [Record]
    let events: [WhisperKnotExecutorEvent]
    let retentionHours: Int
    var activities: [WhisperKnotRecordedActivity]? = nil
    var documents: [WhisperKnotDocument]? = nil
    var fingerprint: String? = nil
}

@MainActor enum WhisperKnotShellEvidenceService {
    static func fetch(_ action: String, bot: String? = nil, conversationID: String? = nil, proposalID: String? = nil, browser: Bool = false, fields: [String: WhisperKnotReceiptJSON] = [:]) async throws -> Data {
        let generation = AccountStorage.generation, revision = WhisperKnotContextPermission.revision
        let owner = AccountStorage.currentUserID.lowercased()
        try Task.checkCancellation()
        guard WhisperKnotContextPermission.allowed else { throw CancellationError() }
        let auth = try await SupabaseService.shared.client.auth.session
        guard owner == auth.user.id.uuidString.lowercased(), generation == AccountStorage.generation,
              revision == WhisperKnotContextPermission.revision, !Task.isCancelled else { throw CancellationError() }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = browser && ["navigate", "download", "tab_open"].contains(action) ? 50 : action == "documents" ? 60 : 20
        config.timeoutIntervalForResource = browser && ["navigate", "download", "tab_open"].contains(action) ? 55 : action == "documents" ? 75 : 25
        let transport = URLSession(configuration: config)
        let cancellation = WhisperKnotRequestCancellation()
        let accountObserver = NotificationCenter.default.addObserver(forName: .init("WhisperMeetingAccountWillChange"), object: nil, queue: nil) { _ in cancellation.cancel() }
        let contextObserver = NotificationCenter.default.addObserver(forName: .init("WhisperKnotContextChanged"), object: nil, queue: nil) { _ in cancellation.cancel() }
        defer { NotificationCenter.default.removeObserver(accountObserver); NotificationCenter.default.removeObserver(contextObserver); transport.invalidateAndCancel() }
        var req = URLRequest(url: URL(string: WhisperKnotBackend.origin + "/knot/\(browser ? "browser" : "shell")/\(action)")!)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.httpMethod = !browser && action == "capabilities" ? "GET" : "POST"
        req.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "X-Whisper-Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if browser || action != "capabilities" {
            var body = fields
            if let bot { body["bot"] = .string(bot) }
            if let conversationID { body["conversationID"] = .string(conversationID.lowercased()) }
            if let proposalID { body["proposalID"] = .string(proposalID) }
            if browser {
                body["consentVersion"] = .string("knot_browser_v1")
                if ["start", "navigate", "input", "stop", "tab_open", "tab_activate", "tab_close", "back", "forward", "find", "download"].contains(action) {
                    body["actionID"] = .string(UUID().uuidString.lowercased())
                    body["expiresAt"] = .number(floor(Date().timeIntervalSince1970 * 1000) + 45000)
                }
            }
            req.httpBody = try JSONEncoder().encode(body)
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try cancellation.check()
            let (bytes, response) = try await transport.bytes(for: req, delegate: cancellation)
            try cancellation.check()
            let successful = (response as? HTTPURLResponse)?.statusCode == 200
            let maximum = !successful ? 4096 : browser ? (action == "screenshot" ? 4_000_000 : 850_000) : (action == "documents" ? (["file", "asset"].contains(fields["action"]?.text ?? "") ? 50_000_000 : fields["action"]?.text == "preview" ? 1_800_000 : 2_000_000) : action == "log" || action == "events" ? 6_500_000 : 100_000)
            let data = try await collect(bytes, maximum: maximum, cancellation: cancellation)
            try cancellation.check()
            guard generation == AccountStorage.generation, owner == AccountStorage.currentUserID.lowercased(),
                  revision == WhisperKnotContextPermission.revision, WhisperKnotContextPermission.allowed, !Task.isCancelled else { throw CancellationError() }
            guard successful else {
                if browser {
                    let value = try? JSONDecoder().decode(WhisperKnotReceiptJSON.self, from: data)
                    throw WhisperKnotBrowserError.server(value?["error"]?.text ?? "browser_unavailable")
                }
                if action == "documents" {
                    let value = try? JSONDecoder().decode(WhisperKnotReceiptJSON.self, from: data)
                    throw WhisperKnotFileError.server(value?["error"]?.text ?? "document_unavailable")
                }
                throw URLError(.badServerResponse)
            }
            if browser && action == "screenshot" {
                guard (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("image/png") == true,
                      data.count >= 24, Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] else { throw URLError(.cannotDecodeContentData) }
            }
            return data
        } onCancel: { cancellation.cancel() }
    }
    // Byte iteration and JSON decoding run off the UI actor. Large exact logs
    // stay bounded and cancellation-aware without freezing tab presentation.
    @concurrent private static func collect(_ bytes: URLSession.AsyncBytes, maximum: Int, cancellation: WhisperKnotRequestCancellation) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            if data.count % 4096 == 0 { try Task.checkCancellation(); try cancellation.check() }
            guard data.count < maximum else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
    @concurrent private static func decodeReplay(_ data: Data) async throws -> WhisperKnotShellReplay {
        try Task.checkCancellation()
        var value = try JSONDecoder().decode(WhisperKnotShellReplay.self, from: data)
        value.fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return value
    }
    static func replay(bot: String, conversationID: String, proposalID: String? = nil) async throws -> WhisperKnotShellReplay {
        let data = try await fetch("events", bot: bot, conversationID: conversationID, proposalID: proposalID)
        return try await decodeReplay(data)
    }
}

struct WhisperKnotShellEventsView: View {
    let proposal: WhisperKnotShellProposal
    var continueTask: (() -> Void)? = nil
    var embedded = false
    var rawRecord = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var replay: WhisperKnotShellReplay?
    @State private var issue: String?
    @State private var loading = true
    @State private var invalidated = false
    private var record: WhisperKnotShellReplay.Record? { replay?.records.first { $0.spec.id == proposal.id } }
    private var result: WhisperKnotShellResult? { record?.result ?? proposal.result }
    private var isCached: Bool { record?.cachedData != nil }
    var body: some View {
        Group {
            if embedded { content }
            else { NavigationStack { content } }
        }
        .task(id: scenePhase) { if scenePhase == .active { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in clear() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in clear() }
    }
    private var content: some View {
        Group {
            if rawRecord { rawContent }
            else {
                WhisperKnotReadableExecutionView(record: record ?? .init(spec: proposal.spec, state: proposal.state, result: proposal.result ?? .notStarted(proposal.spec, reason: "No execution receipt yet.")), proposal: proposal, continueTask: continuation)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        }
    }
    private var continuation: (() -> Void)? {
        guard !invalidated, !proposal.continued, result?.terminationConfirmed == true,
              result?.sessionID != nil, result?.status != "cancelled", let continueTask else { return nil }
        return { dismiss(); continueTask() }
    }
    private var rawContent: some View {
            List {
                Section(isCached ? "Cached guide data" : "Execution") {
                    Text(proposal.spec.title).font(.headline)
                    if let result {
                        if isCached { Text("Reused complete data from the original owned-session read. No new execution.").font(.subheadline) }
                        else { LabeledContent("Shell status", value: result.providerStatus ?? "No provider stamp") }
                        if let id = result.sessionID { LabeledContent("Session", value: id).textSelection(.enabled) }
                        if let code = result.exitCode { LabeledContent("Exit code", value: String(code)) }
                        if let start = result.providerStartedAt { LabeledContent("Started", value: start) }
                        if let end = result.providerEndedAt { LabeledContent("Ended", value: end) }
                        if let duration = result.durationMs {
                            LabeledContent("Duration", value: "\(duration) ms")
                        }
                        Text(result.reason).font(.footnote)
                        if let receipt = result.providerReceipt {
                            NavigationLink(isCached ? "Exact cached-data receipt" : "Exact provider record") { WhisperKnotExactEvidenceView(title: isCached ? "Cached-data receipt" : "Provider record", source: .json(receipt)) }
                        }
                    }
                    NavigationLink(isCached ? "Original read command" : "Exact command") { WhisperKnotExactEvidenceView(title: isCached ? "Original read command" : "Recorded command", source: .text(proposal.spec.command)) }
                }
                if !proposal.continued, result?.terminationConfirmed == true, result?.sessionID != nil, result?.status != "cancelled", let continueTask {
                    Section {
                        Button("Continue task from this receipt") { dismiss(); continueTask() }
                    }
                }
                Section(isCached ? "Retained cached data" : "Provider log") {
                    NavigationLink(isCached ? "Open complete cached data" : "Open exact provider log") {
                        WhisperKnotExactEvidenceView(title: isCached ? "Cached guide data" : "Provider log", source: .log(bot: proposal.spec.bot, conversationID: proposal.spec.conversationID, proposalID: proposal.id))
                    }
                }
                if let replay {
                    let findings = replay.events.filter { $0.proposalID == proposal.id && !$0.contentFindings.isEmpty }
                    if !findings.isEmpty {
                        Section("Document content findings") {
                            ForEach(findings) { event in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(event.title).font(.headline)
                                    ForEach(event.contentFindings.indices, id: \.self) { index in
                                        Text(event.contentFindings[index]).font(.body).textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }
                }
                Section("Events") {
                    if let replay {
                        ForEach(replay.events.filter { $0.proposalID == proposal.id }) { event in
                            NavigationLink {
                                WhisperKnotExactEvidenceView(title: event.title, source: .json(event.raw))
                            } label: {
                                VStack(alignment: .leading, spacing: 4) { Text(event.title); Text(event.recordedAt).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    if loading { ProgressView("Reading execution history") }
                    if let issue { Text(issue).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Raw record").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    private func clear() { invalidated = true; replay = nil; dismiss() }
    private func load() async {
        guard !invalidated, !Task.isCancelled, scenePhase == .active else { return }
        loading = replay == nil
        defer { loading = false }
        do {
            let value = try await WhisperKnotShellEvidenceService.replay(bot: proposal.spec.bot, conversationID: proposal.spec.conversationID, proposalID: proposal.id)
            guard !invalidated, !Task.isCancelled, scenePhase == .active else { return }
            replay = value
        } catch { if !invalidated, !Task.isCancelled, scenePhase == .active { issue = "Execution history is unavailable. No command was retried." } }
    }
}
