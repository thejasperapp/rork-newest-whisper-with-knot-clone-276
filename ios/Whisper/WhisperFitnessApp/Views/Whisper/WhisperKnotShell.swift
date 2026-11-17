import SwiftUI
import Supabase

/// Server-owned command identity is persisted independently of regenerated UI turn IDs.
nonisolated struct WhisperKnotShellSpec: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let bot: String
    let conversationID: String
    let tool: String
    let title: String
    let command: String
    let timeoutMs: Int
    let expiresAt: Double
    var taskID: String? = nil
    var taskTitle: String? = nil
    var sourceMessageID: String? = nil
    var operation: String? = nil
    var receiptKind: String? = nil
    struct DocumentInvocation: Codable, Hashable, Sendable {
        let stage: String
        let interpreter: String
        let code: String
        let path: String
    }
    var documentInvocation: DocumentInvocation? = nil
    private var commandByteLimit: Int {
        // Ingress only: the server independently regenerates the exact command
        // from its owned workflow. A marker/tool name is never execution authority.
        guard tool == "document_script", let invocation = documentInvocation,
              ["source", "build", "existing", "final"].contains(invocation.stage),
              ["python3", "bash", "knot-doc"].contains(invocation.interpreter),
              invocation.code.unicodeScalars.count <= 64_000,
              invocation.code.utf8.count <= 74_000, !invocation.code.contains("\0"),
              !invocation.path.isEmpty, invocation.path.utf8.count <= 240,
              command.hasPrefix("command -p python3 -I - <<'KNOT_DOCUMENT_INVOKE'\n") || command.hasPrefix("command -p python3 -I - <<'KNOT_RAW_DOCUMENT_INVOKE'\n") else { return 12_000 }
        return 160_000
    }
    var valid: Bool {
        UUID(uuidString: id) != nil && UUID(uuidString: conversationID) != nil &&
        ["main", "writer", "researcher", "planner", "social"].contains(bot) &&
        command.utf8.count <= commandByteLimit && !command.isEmpty && !command.contains("\0") &&
        !title.isEmpty && title.count <= 120 && (1000...600000).contains(timeoutMs) &&
        !tool.isEmpty && tool.utf8.count <= 64 && tool.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }
}
nonisolated struct WhisperKnotShellResult: Codable, Hashable, Sendable {
    let proposalID: String
    let bot: String
    let conversationID: String
    let status: String
    let stdout: String
    let stderr: String
    let exitCode: Int?
    let outputComplete: Bool
    let truncated: Bool
    let terminationConfirmed: Bool
    let reason: String
    var sessionID: String? = nil
    var providerStatus: String? = nil
    var providerReceipt: WhisperKnotReceiptJSON? = nil
    var commandReceipt: WhisperKnotReceiptJSON? = nil
    var providerStartedAt: String? = nil
    var providerEndedAt: String? = nil
    var durationMs: Int? = nil
    var durationSource: String? = nil
    var hasCompleteCommandReceipt: Bool {
        terminationConfirmed && outputComplete && !truncated && commandReceipt != nil && exitCode != nil
    }
    func canReplace(_ previous: Self?) -> Bool {
        guard let previous else { return true }
        if previous.terminationConfirmed && !terminationConfirmed { return false }
        if previous.hasCompleteCommandReceipt && !hasCompleteCommandReceipt { return false }
        return true
    }
    static func notStarted(_ spec: WhisperKnotShellSpec, reason: String) -> Self {
        .init(proposalID: spec.id, bot: spec.bot, conversationID: spec.conversationID, status: "failed", stdout: "", stderr: "", exitCode: nil, outputComplete: true, truncated: false, terminationConfirmed: true, reason: reason)
    }
    static func uncertain(_ spec: WhisperKnotShellSpec) -> Self {
        .init(proposalID: spec.id, bot: spec.bot, conversationID: spec.conversationID, status: "uncertain", stdout: "", stderr: "", exitCode: nil, outputComplete: false, truncated: false, terminationConfirmed: false, reason: "Execution may have started. Stopping is not confirmed; do not run it again.")
    }
}
nonisolated struct WhisperKnotShellProposal: Codable, Hashable, Sendable, Identifiable {
    let spec: WhisperKnotShellSpec
    var state = "review"
    var result: WhisperKnotShellResult?
    var continued = false
    var id: String { spec.id }
    var showsExecutionReceipt: Bool {
        // A session proves ownership, not that this was member-facing work.
        // Unknown legacy records fail closed; their full evidence stays in Events.
        guard spec.operation == "work", spec.tool == "session_input",
              spec.receiptKind == nil || spec.receiptKind == "execution" else { return false }
        let internalMarkers = ["KNOT_DOCUMENT_", "KNOT_RAW_DOCUMENT_", "KNOT_FINAL_FILE_PROOF", "KNOT_RECOVERY_PROOF", "KNOT_PDF_", "KNOT_RESIDENT_", "KNOT_SKILL_"]
        guard !internalMarkers.contains(where: spec.command.contains) else { return false }
        return state == "dispatching" || state == "running" || result?.sessionID != nil
    }
    var executionStatus: String {
        if let result {
            if result.terminationConfirmed, result.exitCode == 0, result.outputComplete, !result.truncated { return "Completed" }
            if result.status == "cancelled" { return "Stopped" }
            if result.terminationConfirmed, result.exitCode != nil { return "Couldn’t finish" }
            return "Result not confirmed"
        }
        return state == "dispatching" || state == "running" ? "Working…" : "Result not confirmed"
    }
    var reviewable: Bool { state == "review" && spec.valid && Date().timeIntervalSince1970 * 1000 < spec.expiresAt }
    var label: String {
        if let result {
            guard let providerStatus = result.providerStatus else { return state == "declined" ? "Cancelled · nothing run" : result.terminationConfirmed || result.status == "awaiting_approval" ? "Not started" : "Execution not confirmed" }
            if result.commandReceipt != nil, result.terminationConfirmed {
                return result.exitCode.map { "Command finished · exit \($0)" } ?? "Command ended"
            }
            if providerStatus == "live" { return result.status == "stopping" ? "Shell live · stop requested" : "Shell live" }
            if ["exited", "killed", "reaped"].contains(providerStatus) {
                return result.exitCode.map { "\(providerStatus.capitalized) · exit \($0)" } ?? providerStatus.capitalized
            }
            return providerStatus
        }
        switch state { case "review": return reviewable ? "Preparing workspace" : "Command expired"
        case "running", "dispatching": return "Waiting for shell receipt"
        case "declined": return "Cancelled · nothing run"
        default: return "Command expired · nothing restarted" }
    }
    func restored() -> Self {
        var copy = self
        if state == "review" { copy.state = "expired" }
        if state == "running" || state == "dispatching" { copy.state = "uncertain" }
        return copy
    }
}

private struct WhisperKnotShellRejected: Error { let reason: String }

/// Owns a single foreground operation. Teardown uses the captured outgoing token,
/// never a new account's session. Transport failure never replays execution.
@Observable final class WhisperKnotShellController {
    private(set) var active: WhisperKnotShellSpec?
    private var token: String?
    private var task: Task<Void, Never>?
    private var update: ((WhisperKnotShellProposal) -> Void)?
    private var operation = UUID()
    private var observers: [NSObjectProtocol] = []
    private var latestResult: WhisperKnotShellResult?
    init() {
        for name in ["WhisperMeetingAccountWillChange", "WhisperKnotContextChanged"] {
            observers.append(NotificationCenter.default.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            })
        }
    }
    var busy: Bool { active != nil }
    func run(_ proposal: WhisperKnotShellProposal, isCurrent: @escaping () -> Bool, update: @escaping (WhisperKnotShellProposal) -> Void) {
        guard !busy, proposal.reviewable, isCurrent(), WhisperKnotContextPermission.allowed else { return }
        let generation = AccountStorage.generation, revision = WhisperKnotContextPermission.revision
        let owner = AccountStorage.currentUserID.lowercased()
        let op = UUID(); operation = op; active = proposal.spec; self.update = update; latestResult = nil
        var running = proposal; running.state = "dispatching"; update(running)
        task = Task {
            do {
                let session = try await SupabaseService.shared.client.auth.session
                guard operation == op, isCurrent(), !Task.isCancelled, WhisperKnotContextPermission.allowed,
                      generation == AccountStorage.generation, revision == WhisperKnotContextPermission.revision,
                      owner == AccountStorage.currentUserID.lowercased(), session.user.id.uuidString.lowercased() == owner else {
                    throw WhisperKnotShellRejected(reason: "The active account or conversation changed. Nothing was dispatched.")
                }
                let auth = session.accessToken
                token = auth
                // Status reads update the same chip from actual server receipts while dispatch waits.
                let poll = Task { @MainActor in
                    while !Task.isCancelled, self.operation == op, isCurrent() {
                        do { try await Task.sleep(for: .seconds(1)) } catch { break }
                        guard self.operation == op, !Task.isCancelled, isCurrent() else { break }
                        if let status = try? await self.request("status", spec: proposal.spec, token: auth) {
                            guard self.operation == op, !Task.isCancelled, isCurrent() else { break }
                            guard status.canReplace(self.latestResult) else { continue }
                            self.latestResult = status
                            var observed = running; observed.result = status
                            observed.state = status.terminationConfirmed ? "finished" : "dispatching"
                            update(observed)
                            if status.hasCompleteCommandReceipt || status.sessionID == nil && status.terminationConfirmed || status.status == "cancelled" { break }
                        }
                    }
                }
                defer { poll.cancel() }
                // Fresh foreground commands dispatch directly; there is no
                // shell-enabling request, stored grant or command approval.
                let result = try await request("execute", spec: proposal.spec, token: auth)
                guard operation == op else { return }
                if result.canReplace(latestResult) { latestResult = result }
                var finished = running; finished.result = latestResult; finished.state = latestResult?.terminationConfirmed == true ? "finished" : "uncertain"
                update(finished)
                await recoverOutput(spec: proposal.spec, token: auth, operation: op, running: running, isCurrent: isCurrent, update: update)
            } catch {
                guard operation == op else { return }
                var recovered = running
                if let rejection = error as? WhisperKnotShellRejected {
                    let notStarted = WhisperKnotShellResult.notStarted(proposal.spec, reason: rejection.reason)
                    if notStarted.canReplace(latestResult) {
                        recovered.result = notStarted; recovered.continued = true
                    } else { recovered.result = latestResult }
                } else { recovered.result = latestResult ?? .uncertain(proposal.spec) }
                latestResult = recovered.result
                recovered.state = recovered.result?.terminationConfirmed == true ? "finished" : "uncertain"
                update(recovered)
                if recovered.result?.terminationConfirmed != true, let token,
                   let result = try? await request("cancel", spec: proposal.spec, token: token), operation == op {
                    if result.canReplace(latestResult) { latestResult = result }
                    recovered.result = latestResult
                    recovered.state = latestResult?.terminationConfirmed == true ? "finished" : "uncertain"; update(recovered)
                }
                if !(error is WhisperKnotShellRejected), let token, operation == op {
                    await recoverOutput(spec: proposal.spec, token: token, operation: op, running: running, isCurrent: isCurrent, update: update)
                }
            }
            guard operation == op else { return }
            let completed = latestResult
            active = nil; token = nil; task = nil; self.update = nil; latestResult = nil
            // Publish after releasing ownership, so continuation cannot lose a busy race.
            if let completed, completed.terminationConfirmed, isCurrent() {
                var finished = running; finished.result = completed; finished.state = "finished"; update(finished)
            }
        }
    }
    private func recoverOutput(spec: WhisperKnotShellSpec, token: String, operation op: UUID, running: WhisperKnotShellProposal, isCurrent: () -> Bool, update: (WhisperKnotShellProposal) -> Void) async {
        guard let initial = latestResult, initial.terminationConfirmed, !initial.hasCompleteCommandReceipt,
              initial.sessionID != nil, initial.status != "cancelled" else { return }
        // Read only, bounded to the server's late-output window. Ownership is
        // retained until recovery ends, so automatic continuation cannot race it.
        let deadline = Date().addingTimeInterval(15)
        while operation == op, isCurrent(), !Task.isCancelled, WhisperKnotContextPermission.allowed,
              Date() < deadline, latestResult?.hasCompleteCommandReceipt != true {
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            guard operation == op, isCurrent(), !Task.isCancelled, Date() < deadline else { return }
            do {
                let status = try await request("status", spec: spec, token: token, deadline: deadline)
                guard operation == op, isCurrent(), !Task.isCancelled else { return }
                if status.canReplace(latestResult) {
                    latestResult = status
                    var observed = running; observed.result = status
                    observed.state = status.terminationConfirmed ? "finished" : "uncertain"
                    update(observed)
                }
            } catch { /* No replay or mutation; retain the strongest owned receipt. */ }
        }
    }
    func stop() {
        guard let spec = active else { return }
        let auth = token; let callback = update
        operation = UUID(); task?.cancel()
        var stopped = WhisperKnotShellProposal(spec: spec); stopped.result = latestResult ?? .uncertain(spec)
        // A stop/dismissal suppresses automatic explanation, even if exit raced with cancellation.
        stopped.continued = true
        stopped.state = stopped.result?.terminationConfirmed == true ? "finished" : "uncertain"
        callback?(stopped)
        active = nil; token = nil; task = nil; update = nil; latestResult = nil
        if let auth {
            Task {
                if let result = try? await request("cancel", spec: spec, token: auth),
                   result.canReplace(stopped.result) {
                    var finished = stopped; finished.result = result; finished.state = result.terminationConfirmed ? "finished" : "uncertain"
                    callback?(finished)
                }
            }
        }
    }
    func refresh(_ proposal: WhisperKnotShellProposal) async -> WhisperKnotShellProposal {
        let generation = AccountStorage.generation
        var refreshed = proposal
        do {
            let auth = try await SupabaseService.shared.client.auth.session.accessToken
            guard generation == AccountStorage.generation, !Task.isCancelled else { return proposal }
            let result = try await request("status", spec: proposal.spec, token: auth)
            guard generation == AccountStorage.generation, !Task.isCancelled else { return proposal }
            if result.canReplace(proposal.result) {
                refreshed.result = result; refreshed.state = result.terminationConfirmed ? "finished" : "uncertain"
            }
        } catch { /* Retain known result; status is a read, never a retry of execution. */ }
        return refreshed
    }
    func cancel(_ proposal: WhisperKnotShellProposal) async -> WhisperKnotShellProposal {
        var copy = proposal
        let generation = AccountStorage.generation
        do {
            let auth = try await SupabaseService.shared.client.auth.session.accessToken
            guard generation == AccountStorage.generation, !Task.isCancelled else { return proposal }
            let result = try await request("cancel", spec: proposal.spec, token: auth)
            guard generation == AccountStorage.generation else { return proposal }
            if result.canReplace(proposal.result) {
                copy.result = result; copy.state = result.terminationConfirmed ? "finished" : "uncertain"
            }
        } catch { if copy.result?.terminationConfirmed != true { copy.state = "uncertain"; if copy.result == nil { copy.result = .uncertain(proposal.spec) } } }
        return copy
    }
    private func request(_ action: String, spec: WhisperKnotShellSpec, token: String, deadline: Date? = nil) async throws -> WhisperKnotShellResult {
        try Task.checkCancellation()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = action == "execute" ? 155 : 25
        config.timeoutIntervalForResource = action == "execute" ? 160 : 30
        if let deadline {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw URLError(.timedOut) }
            config.timeoutIntervalForRequest = min(config.timeoutIntervalForRequest, remaining)
            config.timeoutIntervalForResource = min(config.timeoutIntervalForResource, remaining)
        }
        config.urlCache = nil
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        var req = URLRequest(url: URL(string: WhisperKnotBackend.origin + "/knot/shell/\(action)")!)
        req.httpMethod = "POST"; req.timeoutInterval = config.timeoutIntervalForRequest
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "X-Whisper-Authorization")
        var body: [String: Any] = ["proposalID": spec.id, "bot": spec.bot, "conversationID": spec.conversationID]
        if action == "execute" {
            body["executionVersion"] = "knot_shell_automatic_v1"
            body["command"] = spec.command; body["timeoutMs"] = spec.timeoutMs
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport.data(for: req)
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode
        guard status == 200, data.count <= 400_000 else {
            if action == "execute", data.count <= 4096 {
                struct Rejection: Decodable { let error: String; var dispatchAccepted: Bool? }
                if let rejection = try? JSONDecoder().decode(Rejection.self, from: data), rejection.dispatchAccepted == false {
                    let reason: String
                    switch rejection.error {
                    case "workspace_busy_or_uncertain": reason = "Previous work has not been confirmed stopped. Nothing new started."
                    case "exact_command_expired", "exact_command_expired_or_mismatched": reason = "This command expired. Nothing started."
                    default: reason = "The workspace could not start this command. Nothing was dispatched."
                    }
                    throw WhisperKnotShellRejected(reason: reason)
                }
                if status == 401 || status == 403 { throw WhisperKnotShellRejected(reason: "Sign-in could not be verified. Nothing was dispatched.") }
            }
            throw URLError(.badServerResponse)
        }
        let result = try JSONDecoder().decode(WhisperKnotShellResult.self, from: data)
        guard result.proposalID == spec.id, result.bot == spec.bot,
              result.conversationID.lowercased() == spec.conversationID.lowercased(),
              ["awaiting_approval", "running", "stopping", "uncertain", "completed", "cancelled", "failed"].contains(result.status) else { throw URLError(.badServerResponse) }
        return result
    }
}

/// Information only. The isolated workspace is built in, not user-enabled.
struct WhisperKnotShellInfoView: View {
    let bot: WhisperKnotBot
    var body: some View {
        Form {
            Section {
                Label("\(bot.displayName)’s workspace", systemImage: "terminal").font(.headline)
                Text("Knot automatically uses your account’s persistent workspace across tasks and bots for requested work, including memory and skill reads. There is nothing to enable and no command-by-command approval. Stop work at any time from the conversation.")
            }
            Section("Personal products stay separate") {
                Text("This workspace does not grant access to your connected apps, private records or device files. Reading personal-product data and posting, following, scheduling or making other account changes still follow their separate permissions and confirmations.")
            }
            Section("Data and retention") {
                Text("Commands and text embedded in them go through Whisper’s server to the operator-managed shell at knot-shell.mydailywhisper.com. Output, errors and exit status return through Whisper and may go from Whisper through Rork AI Cloud (via Vercel AI Gateway) to OpenAI so this Knot can explain the result. The workspace and its durable memory are isolated by account and shared across your tasks and bots. Command and private-delivery records stay tied to their original Knot and conversation. Only conversation calls with separate chat-tools permission can use commands through their originating Knot chat. Shared replies, welcome/invitation calls and Responsibilities cannot run shell commands.")
                Text("Don’t include passwords, keys or private app records. Commands can change files inside this workspace. Files stay on the droplet until explicitly deleted. Whisper retains command/results in chat history; server records expire after 24 hours, unused commands after 10 minutes. Unconfirmed ownership remains to prevent unsafe retries. Provider operational retention is managed by the operator. Stopping work does not erase previously processed data.").font(.footnote)
            }
            Section("Remote browser") {
                Text("Computer uses a separate internet-connected browser on the same operator-managed service. Pages and typed input are processed there; visible text and genuine screenshots may go to Knot’s AI providers while AI sharing is on. Browser profiles, including cookies and logins, persist in your account’s workspace across tasks and bots. The process starts on demand and may stop after 30 idle minutes; Stop browser does not erase its profile. For an explicit public-browsing request in native text chat, Knot can navigate, observe and use page search automatically while the chat stays active. No sign-ins, purchases or personal-account actions are authorized. Manual controls are not exclusive takeover.")
                Text("Turning off AI sharing clears the viewer and stops new input, but does not close the remote browser or erase its profile; use Stop browser beforehand.").font(.footnote)
            }
            Section("Bounded shell execution") {
                Text("Offline, without root, installs or production secrets. One owned shell is attached across tasks and turns, preserving its working directory and environment while live. The provider reaps it after two idle hours or a four-hour hard cap; durable files remain in the account workspace. Each command has a 120-second maximum, separate stream boundaries and its own exit result; a live shell is not proof a command finished. Limits: 512 MB memory, 1 GB swap, one CPU, 256 tasks and 2 GB workspace. Stop requests may take time; an unknown result is never automatically retried.").font(.footnote)
            }
        }
        .navigationTitle("Workspace").navigationBarTitleDisplayMode(.inline)
    }
}

struct WhisperKnotShellCard: View {
    let proposal: WhisperKnotShellProposal
    let busy: Bool
    let resume: () -> Void
    let decline: () -> Void
    let stop: () -> Void
    let refresh: () -> Void
    let continueReply: () -> Void
    @State private var showEvents = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(proposal.spec.title, systemImage: "terminal").font(.subheadline.weight(.semibold))
            Text(proposal.label).font(.caption).foregroundStyle(.secondary)
            if proposal.reviewable {
                Text("Runs automatically · \(proposal.spec.timeoutMs / 1000)s limit").font(.caption).foregroundStyle(.secondary)
                // Recovery only for an in-process command that never started;
                // normal fresh replies dispatch automatically without this tap.
                HStack { Button("Resume task", action: resume).buttonStyle(.bordered); Button("Cancel task", action: decline).buttonStyle(.bordered) }.disabled(busy)
            } else {
                Button { showEvents = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Events & provider log")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }.font(.subheadline)
                }.accessibilityIdentifier("knot.shell.events.\(proposal.id)")
                if proposal.state == "dispatching" || proposal.state == "running" {
                    Button("Stop command", role: .destructive, action: stop)
                } else if let result = proposal.result, !result.terminationConfirmed, result.sessionID != nil {
                    Button("Request stop", role: .destructive, action: stop).disabled(busy)
                }
            }
        }.modifier(WhisperKnotPanel())
        .sheet(isPresented: $showEvents) { WhisperKnotShellEventsView(proposal: proposal, continueTask: busy ? nil : continueReply) }
        .task(id: proposal.result?.providerStatus) {
            // Read-only recovery. Never replay execution or regenerate an explanation.
            if !busy, !proposal.reviewable, proposal.result?.terminationConfirmed != true { refresh() }
        }
    }
}
