import Foundation
import Supabase

/// Versioned, authenticated live transport. It never runs or approves an app action.
nonisolated enum WhisperKnotLiveError: Error {
    case unavailable
    case rejected
    case billingUnavailable
    case quotaUnavailable
    case rateLimited
    case interrupted
    case browserNeedsStop
    case browserUnavailable
    case workspaceIncomplete
}

nonisolated struct WhisperKnotLiveService: Sendable {
    private nonisolated struct Body: Encodable {
        let requestID: String
        let consentVersion = "knot_ai_consent_v4"
        let message: String
        let bot: String
        let healthContext: String
        let history: [WhisperEmberBrainService.ChatMessage]
        let isWebQuery: Bool
        let interpreterOutput: String?
        let sharedConversation: Bool
        let timezone: String
        let conversationID: String?
        let shellResultID: String?
        let sourceMessageID: String?
        let documentReviewConsentVersion: String?
        let foregroundBrowserVersion: String?
        let browserPreviewVersion: String?
        let taskModelConsentVersion: String?
        let taskExperienceVersion: String?
        let clarificationVersion: String?
        let reactionVersion: String?
        let sourceCreatedAt: Double?
        let browserContinuationVersion: String?
        let browserContinuationID: String?
        let foregroundTurnVersion: String?
        let workProgressVersion = "knot_work_progress_v1"
        let documentProgramVersion = "knot_document_program_v3"
    }
    nonisolated struct Event: Decodable, Sendable {
        let v: Int
        let requestID: String
        let sequence: Int
        let type: String
        let phase: String?
        let stage: String?
        let text: String?
        let reply: String?
        let readOnlyBrowser: Bool?
        let browserContinuationID: String?
        let workIncomplete: Bool?
        let action: String?
        let error: String?
        let reason: String?
        let status: Int?
        let briefing: String?
        let creative: Bool?
        let clarification: WhisperKnotClarification?
        let reaction: WhisperKnotReaction?
        let proposal: WhisperKnotShellSpec?
        let calculation: WhisperKnotCalculationReceipt?
        let activity: WhisperKnotRecordedActivity?
    }

    static func workActivity(for event: Event) throws -> String? {
        if event.type == "generating" {
            // Legacy-compatible generating frames also carry memory plumbing.
            // They do not mean answer generation or creative work has started.
            return event.stage == "conversation_memory" ? "Reading your message…" : "Writing reply…"
        }
        guard event.type == "work_phase" else { return nil }
        switch event.phase {
        case "reading": return "Reading your message…"
        case "researching": return "Reading sources…"
        case "working": return "Working on your request…"
        case "preparing": return "Preparing your file…"
        case "creating": return "Creating your file…"
        case "checking": return "Checking the result…"
        case "calculating": return "Calculating…"
        case "writing": return "Writing reply…"
        default: throw WhisperKnotLiveError.interrupted
        }
    }

    static func checkWorkTerminal(eventType: String, workIncomplete: Bool = false) throws {
        // This document stop is terminal, unlike intermediate proof/content
        // observations that may still be repaired. Do not wait for another SSE
        // frame to release the owned chat/header if completion is lost in transit.
        if eventType == "document_work_unavailable" || eventType == "complete" && workIncomplete {
            throw WhisperKnotLiveError.workspaceIncomplete
        }
    }

    static func completionReply(_ reply: String?, workIncomplete: Bool) throws -> String {
        // Explicit incomplete work is an Events-only terminal outcome, including
        // older servers that still supplied failure/promise prose. It must never
        // fall through as a blank success or a generic transport-error bubble.
        try checkWorkTerminal(eventType: "complete", workIncomplete: workIncomplete)
        guard let reply, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (reply.utf8.count <= 256_000 || WhisperKnotMessageSkills.completeDocumentProposal(reply) != nil) else { throw WhisperKnotLiveError.interrupted }
        return reply
    }

    @MainActor
    func chat(
        message: String,
        bot: WhisperKnotBot,
        context: String,
        history: [WhisperEmberBrainService.ChatMessage],
        isWebQuery: Bool,
        interpreterOutput: String?,
        sharedConversation: Bool,
        conversationID: UUID? = nil,
        shellResultID: String? = nil,
        sourceMessageID: UUID? = nil,
        sourceCreatedAt: Double? = nil,
        browserContinuationID: String? = nil,
        continuationDepth: Int = 0,
        onActivity: (@Sendable @MainActor (String) -> Void)?,
        onText: (@Sendable @MainActor (String) -> Void)?,
        onBrowserActivity: (@Sendable @MainActor () -> Void)? = nil,
        onReaction: (@Sendable @MainActor (WhisperKnotReaction) -> Void)? = nil,
        onShellProposal: (@Sendable @MainActor (WhisperKnotShellSpec) async throws -> Void)? = nil,
        onCalculation: (@Sendable @MainActor (WhisperKnotCalculationReceipt) -> Void)? = nil,
        onClarification: (@Sendable @MainActor (WhisperKnotClarification) -> Void)? = nil,
        onTaskPlan: (@Sendable @MainActor (String, Bool) -> Void)? = nil,
        onObservation: (@Sendable @MainActor (WhisperKnotRecordedActivity) -> Void)? = nil,
        taskModelsAllowed: Bool = false
    ) async throws -> String {
        let generation = AccountStorage.generation
        let revision = WhisperKnotContextPermission.revision
        func checkOwnership() throws {
            try Task.checkCancellation()
            guard generation == AccountStorage.generation, WhisperKnotContextPermission.allowed,
                  revision == WhisperKnotContextPermission.revision else { throw CancellationError() }
        }
        try checkOwnership()
        let token: String
        do { token = try await SupabaseService.shared.client.auth.session.accessToken }
        catch { try checkOwnership(); throw WhisperKnotLiveError.rejected }
        try checkOwnership()
        // This project's permanent alias, not an old clone's billing/AI deployment.
        guard let url = URL(string: WhisperKnotBackend.origin + "/knot/chat/stream") else {
            throw WhisperKnotLiveError.unavailable
        }
        // Voice/shared/legacy continuations retain their existing foreground path.
        let serverOwned = !sharedConversation && taskModelsAllowed && shellResultID == nil && browserContinuationID == nil && conversationID != nil && sourceMessageID != nil && onShellProposal != nil
        let requestID = serverOwned ? sourceMessageID!.uuidString.lowercased() : UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "X-Whisper-Authorization")
        request.httpBody = try JSONEncoder().encode(Body(
            requestID: requestID, message: message, bot: bot.rawValue,
            healthContext: sharedConversation ? "" : context,
            history: sharedConversation ? [] : Array(history.suffix(10)),
            isWebQuery: isWebQuery,
            interpreterOutput: sharedConversation ? nil : interpreterOutput,
            sharedConversation: sharedConversation,
            timezone: TimeZone.current.identifier,
            conversationID: sharedConversation ? nil : conversationID?.uuidString.lowercased(),
            shellResultID: sharedConversation ? nil : shellResultID,
            sourceMessageID: sharedConversation ? nil : sourceMessageID?.uuidString.lowercased(),
            documentReviewConsentVersion: !sharedConversation && WhisperKnotContextPermission.documentReviewAllowed ? "knot_document_review_v1" : nil,
            foregroundBrowserVersion: !sharedConversation && conversationID != nil ? "knot_native_browser_v1" : nil,
            browserPreviewVersion: !sharedConversation && conversationID != nil ? "knot_browser_preview_v1" : nil,
            taskModelConsentVersion: !sharedConversation && taskModelsAllowed && WhisperKnotContextPermission.taskModelsAllowed ? "knot_task_models_v1" : nil,
            taskExperienceVersion: !sharedConversation && shellResultID == nil && sourceMessageID != nil && onTaskPlan != nil ? "knot_task_experience_v1" : nil,
            clarificationVersion: !sharedConversation && shellResultID == nil && sourceMessageID != nil && onClarification != nil ? "knot_clarification_v1" : nil,
            reactionVersion: !sharedConversation && shellResultID == nil && sourceMessageID != nil && onReaction != nil ? "knot_reactions_v1" : nil,
            sourceCreatedAt: !sharedConversation && shellResultID == nil ? sourceCreatedAt : nil,
            browserContinuationVersion: !sharedConversation && conversationID != nil ? "knot_browser_continuation_v1" : nil,
            browserContinuationID: !sharedConversation ? browserContinuationID : nil,
            foregroundTurnVersion: !sharedConversation && conversationID != nil && sourceMessageID != nil && onShellProposal != nil && onCalculation != nil ? "knot_foreground_turn_v1" : nil
        ))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        // Server creation budget: 74000 B / 200 B/s × 1.5 + 360 s = 915 s.
        // Keep transport outside that absolute budget; idle/Stop stay unchanged.
        configuration.timeoutIntervalForResource = !sharedConversation && conversationID != nil ? 945 : 65
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        let cancellation = WhisperKnotRequestCancellation()
        // Shared questions use this transport too: withdrawal/account changes must
        // close their socket immediately, not wait for the next provider event.
        let accountObserver = NotificationCenter.default.addObserver(forName: .init("WhisperMeetingAccountWillChange"), object: nil, queue: nil) { _ in
            cancellation.cancel()
        }
        let consentObserver = NotificationCenter.default.addObserver(forName: .init("WhisperKnotContextChanged"), object: nil, queue: nil) { _ in
            cancellation.cancel()
        }
        defer {
            NotificationCenter.default.removeObserver(accountObserver)
            NotificationCenter.default.removeObserver(consentObserver)
            session.invalidateAndCancel()
        }
        var receivedText = false, sequence = 0, status = 0, stage = "request"
        do {
            return try await withTaskCancellationHandler {
                try checkOwnership()
                try cancellation.check()
                var fullText = ""
                let receive: @Sendable @MainActor (Event) async throws -> String? = { event in
                    try checkOwnership()
                    try cancellation.check()
                    guard event.v == 1, event.requestID == requestID, event.sequence == sequence + 1 else {
                        throw WhisperKnotLiveError.interrupted
                    }
                    sequence = event.sequence
                    if let activity = event.activity {
                        guard !sharedConversation,
                              activity.requestID == event.requestID,
                              activity.sequence == event.sequence,
                              activity.id == "\(event.requestID):\(event.sequence)",
                              activity.taskID.flatMap(UUID.init(uuidString:)) != nil,
                              sourceMessageID == nil || activity.sourceMessageID?.lowercased() == sourceMessageID?.uuidString.lowercased() else { throw WhisperKnotLiveError.interrupted }
                        onObservation?(activity)
                    }
                    switch event.type {
                    // Private Events retain these observations. They are not
                    // task phases and must never enter the member-facing header.
                    case "work_routing":
                        if let briefing = event.briefing, let onTaskPlan {
                            guard !sharedConversation, shellResultID == nil, briefing.utf16.count <= 240,
                                  !briefing.isEmpty, !briefing.contains("\n"), event.creative == true else { throw WhisperKnotLiveError.interrupted }
                            onTaskPlan(briefing, true)
                        }
                    case "accepted", "connection_check_started", "connection_verified",
                         "search_unavailable", "skill_read_started", "skill_read_complete",
                         "reaction_guide_cached", "reaction_guide_default", "reaction_unavailable", "reaction_unsupported",
                         "tool_selection_retry", "tool_selection_rejected", "tool_selection_unavailable", "tool_request_rejected": break
                    case "work_phase":
                        guard !sharedConversation else { throw WhisperKnotLiveError.interrupted }
                        if let label = try Self.workActivity(for: event) { onActivity?(label) }
                    case "search_requested", "search_complete": onActivity?("Reading sources…")
                    case "browser_activity":
                        guard let action = event.action, ["state", "start", "navigate", "input", "screenshot", "content"].contains(action) else { throw WhisperKnotLiveError.interrupted }
                        onBrowserActivity?()
                        onActivity?("Reading sources…")
                    case "browser_read_started", "browser_read_complete": onActivity?("Reading sources…")
                    case "document_content_started", "document_proof_started", "document_review_started": onActivity?("Checking the result…")
                    case "document_work_unavailable":
                        try Self.checkWorkTerminal(eventType: event.type)
                    case "browser_read_unavailable", "document_content_complete", "document_content_unconfirmed", "document_content_unavailable",
                         "document_proof_complete", "document_proof_unavailable",
                         "document_review_complete", "document_review_unavailable", "calculation_complete",
                         "tool_unavailable", "shell_review_ready": break
                    case "calculation_started": onActivity?("Calculating…")
                    case "shell_proposal":
                        guard !sharedConversation, let onShellProposal, let spec = event.proposal,
                              spec.valid, spec.bot == bot.rawValue,
                              spec.conversationID.lowercased() == conversationID?.uuidString.lowercased(),
                              spec.sourceMessageID?.lowercased() == sourceMessageID?.uuidString.lowercased(),
                              spec.taskID?.lowercased() == requestID.lowercased(),
                              fullText.isEmpty else { throw WhisperKnotLiveError.interrupted }
                        try await onShellProposal(spec)
                        try checkOwnership()
                        try cancellation.check()
                    case "calculation_receipt":
                        guard !sharedConversation, let onCalculation, let calculation = event.calculation,
                              calculation.valid, calculation.conversationID == conversationID,
                              calculation.sourceMessageID == sourceMessageID else { throw WhisperKnotLiveError.interrupted }
                        onCalculation(calculation)
                    case "reaction":
                        guard !sharedConversation, shellResultID == nil, let reaction = event.reaction,
                              reaction.valid, reaction.messageID == sourceMessageID, onReaction != nil else { throw WhisperKnotLiveError.interrupted }
                        try checkOwnership()
                        try cancellation.check()
                        onReaction?(reaction)
                    case "generating":
                        if let label = try Self.workActivity(for: event) { onActivity?(label) }
                    case "text":
                        guard let text = event.text else { throw WhisperKnotLiveError.interrupted }
                        fullText += text
                        guard fullText.utf8.count <= 128_000 else { throw WhisperKnotLiveError.interrupted }
                        receivedText = true
                        onActivity?("Receiving reply…")
                        onText?(WhisperKnotOutput.streaming(fullText))
                    case "finalizing": onActivity?("Formatting reply…")
                    case "complete":
                        try checkOwnership()
                        try cancellation.check()
                        let reply = try Self.completionReply(event.reply, workIncomplete: event.workIncomplete == true)
                        if let clarification = event.clarification {
                            guard !sharedConversation, shellResultID == nil, let onClarification,
                                  clarification.valid, clarification.bot == bot.rawValue,
                                  clarification.conversationID == conversationID, clarification.sourceMessageID == sourceMessageID,
                                  reply == clarification.question, fullText.isEmpty else { throw WhisperKnotLiveError.interrupted }
                            onClarification(clarification)
                            return clarification.question
                        }
                        if event.readOnlyBrowser == true {
                            // Browser evidence cannot enter the legacy command,
                            // action, sharing or Responsibility envelope parsers.
                            let findings = reply.replacingOccurrences(of: "`", with: "’")
                            let trimmed = findings.trimmingCharacters(in: .whitespacesAndNewlines)
                            let progress = trimmed.hasPrefix("{") || trimmed.hasPrefix("[") ? "Browser findings:\n\n" + findings : findings
                            if let next = event.browserContinuationID, UUID(uuidString: next) != nil, !sharedConversation, conversationID != nil {
                                // Each run is independently leased and bounded. Continue
                                // only inside this foreground-owned Task; Stop, privacy,
                                // account and conversation cancellation still fence it.
                                if continuationDepth < 2 {
                                    onText?(progress + "\n\nContinuing the remaining pages…")
                                    onActivity?("Continuing the page-by-page review…")
                                    do {
                                        try checkOwnership()
                                        return try await chat(message: message, bot: bot, context: "", history: [], isWebQuery: false,
                                            interpreterOutput: nil, sharedConversation: false, conversationID: conversationID,
                                            sourceMessageID: nil, browserContinuationID: next, continuationDepth: continuationDepth + 1,
                                            onActivity: onActivity, onText: onText, onBrowserActivity: onBrowserActivity, onReaction: nil,
                                            onTaskPlan: nil, onObservation: onObservation, taskModelsAllowed: taskModelsAllowed)
                                    } catch {
                                        try checkOwnership()
                                        if case WhisperKnotLiveError.browserNeedsStop = error {
                                            return progress + "\n\nThe last browser action is unconfirmed. Open Computer and choose Stop before continuing."
                                        }
                                        return progress + "\n\nThe saved review remains partial. Ask me to continue the review to pick up the remaining work; no uncertain input will be repeated."
                                    }
                                }
                                return progress + "\n\nThe review remains in progress. Ask me to continue the review to pick up the remaining work."
                            }
                            return progress
                        }
                        return reply
                    case "rejected":
                        onText?("")
                        // A rejected stream still arrives over HTTP 200. Retain
                        // its explicit upstream status; never retry billing or
                        // switch providers after this deterministic rejection.
                        if event.reason == "upstream_quota_exhausted" { throw WhisperKnotLiveError.quotaUnavailable }
                        if event.reason == "upstream_rate_limited" { throw WhisperKnotLiveError.rateLimited }
                        if event.reason == "upstream_http_rejection", event.status == 402 {
                            throw WhisperKnotLiveError.billingUnavailable
                        }
                        throw WhisperKnotLiveError.rejected
                    case "error":
                        if event.error == "browser_needs_stop" { throw WhisperKnotLiveError.browserNeedsStop }
                        if event.error == "browser_task_unavailable" { throw WhisperKnotLiveError.browserUnavailable }
                        throw receivedText ? WhisperKnotLiveError.interrupted : WhisperKnotLiveError.unavailable
                    default: throw WhisperKnotLiveError.interrupted
                    }
                    return nil
                }
                let completed: String?
                if serverOwned {
                    stage = "owned_task"
                    completed = try await WhisperKnotOwnedTurnService.run(body: request.httpBody!, taskID: requestID, receive: receive)
                } else {
                    let (bytes, response) = try await session.bytes(for: request, delegate: cancellation)
                    try checkOwnership()
                    try cancellation.check()
                    guard let http = response as? HTTPURLResponse else { throw WhisperKnotLiveError.unavailable }
                    status = http.statusCode
                    if status == 402 { throw WhisperKnotLiveError.billingUnavailable }
                    if [400, 401, 403, 413, 429].contains(status) { throw WhisperKnotLiveError.rejected }
                    guard status == 200, http.value(forHTTPHeaderField: "Content-Type")?.localizedCaseInsensitiveContains("text/event-stream") == true else { throw WhisperKnotLiveError.unavailable }
                    stage = "stream"
                    completed = try await Self.consumeEvents(bytes, cancellation: cancellation, receive: receive)
                }
                if let completed { return completed }
                stage = "incomplete_eof"
                throw receivedText ? WhisperKnotLiveError.interrupted : WhisperKnotLiveError.unavailable
            } onCancel: { cancellation.cancel() }
        } catch {
            diagnose(stage: stage, status: status, sequence: sequence, error: error)
            try checkOwnership()
            try cancellation.check()
            if let known = error as? WhisperKnotLiveError { throw known }
            throw receivedText ? WhisperKnotLiveError.interrupted : WhisperKnotLiveError.unavailable
        }
    }

    /// Frame/decode away from the UI executor, with one awaited delivery at a
    /// time. No event queue, dropped transitions or delay to owner/Stop handling.
    // Generic only over the byte source so offline tests exercise this exact
    // production framing/decoding/delivery loop without a network or AI call.
    @concurrent static func consumeEvents<Bytes: AsyncSequence & Sendable>(
        _ bytes: Bytes,
        cancellation: WhisperKnotRequestCancellation,
        receive: @Sendable @MainActor (Event) async throws -> String?
    ) async throws -> String? where Bytes.Element == UInt8 {
        var framer = WhisperKnotEventFramer()
        let decoder = JSONDecoder()
        for try await byte in bytes {
            if framer.byteCount % 4096 == 0 {
                try Task.checkCancellation()
                try cancellation.check()
            }
            guard let data = try framer.append(byte) else { continue }
            try Task.checkCancellation()
            try cancellation.check()
            let event = try decoder.decode(Event.self, from: data)
            if let completed = try await receive(event) { return completed }
        }
        return nil
    }

    private func diagnose(stage: String, status: Int, sequence: Int, error: Error) {
        #if DEBUG
        // Only fixed stages/categories and numeric transport metadata. Never log
        // prompts, reply/event bodies, URLs, tokens or account/conversation IDs.
        let category: String
        if error is CancellationError { category = "cancelled" }
        else if let network = error as? URLError {
            switch network.code {
            case .cancelled: category = "cancelled"
            case .timedOut: category = "timeout"
            default: category = "network"
            }
        } else if error is DecodingError { category = "invalid_event" }
        else if let known = error as? WhisperKnotLiveError {
            switch known {
            case .unavailable: category = "unavailable"
            case .rejected: category = "rejected"
            case .billingUnavailable: category = "billing_unavailable"
            case .quotaUnavailable: category = "provider_quota_exhausted"
            case .rateLimited: category = "provider_rate_limited"
            case .interrupted: category = "interrupted"
            case .browserNeedsStop: category = "browser_needs_stop"
            case .browserUnavailable: category = "browser_unavailable"
            case .workspaceIncomplete: category = "workspace_incomplete"
            }
        } else { category = "transport" }
        print("[KnotLive] stage=\(stage) http=\(status) sequence=\(sequence) failure=\(category)")
        #endif
    }
}
