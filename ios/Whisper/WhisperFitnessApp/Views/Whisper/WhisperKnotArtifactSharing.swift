import SwiftUI
import Supabase

nonisolated enum WhisperKnotArtifactWire {
    static let prefix = "::whisper-artifact-v1::"
    static func messageID(_ body: String) -> UUID? {
        guard body.utf8.count <= 1024, body.hasPrefix(prefix),
              let line = body.split(separator: "\n", omittingEmptySubsequences: false).first else { return nil }
        return UUID(uuidString: String(line.dropFirst(prefix.count)))
    }
}

/// Explicit ordinary-DM scope, not an AI-consent exception for Knot threads.
/// Only a successful authenticated resolution registers an attachment context.
@MainActor enum WhisperKnotDMArtifacts {
    static let storageBot = "dm-artifact"
    private struct Registration { let owner: String; let generation: UUID }
    private static var contexts: [UUID: Registration] = [:]
    static func register(_ id: UUID) { contexts[id] = Registration(owner: AccountStorage.currentUserID.lowercased(), generation: AccountStorage.generation) }
    static func allowed(_ id: UUID) -> Bool {
        contexts[id]?.owner == AccountStorage.currentUserID.lowercased() && contexts[id]?.generation == AccountStorage.generation
    }
    static func remove(_ id: UUID) {
        if let registration = contexts.removeValue(forKey: id) {
            WhisperKnotHTMLSessions.clear(owner: registration.owner, conversationID: id)
            NotificationCenter.default.post(name: .init("WhisperKnotFilesDeleted"), object: id)
        }
    }
    static func clear(owner: String) { contexts = contexts.filter { $0.value.owner != owner.lowercased() } }
}

@MainActor enum WhisperKnotArtifactSharing {
    struct Resolved: Decodable {
        let document: WhisperKnotDocument
        let senderName: String
        let sentAt: String
        let saved: Bool
    }
    struct SaveProgress: Decodable {
        let done: Bool
        let progress: Double
        let document: WhisperKnotDocument?
        let path: String?
    }
    /// Plain-language reason for the latest failed send, shown in the share sheet.
    static private(set) var lastSendFailure: String?
    static func send(document: WhisperKnotDocument, bot: String, conversationID: UUID, recipient: String, username: String, messageID: UUID) async -> Bool {
        lastSendFailure = nil
        let sent = await attemptSend(document: document, bot: bot, conversationID: conversationID, recipient: recipient, username: username, messageID: messageID)
        if !sent, lastSendFailure == nil { lastSendFailure = "The message couldn’t be delivered." }
        return sent
    }
    private static func attemptSend(document: WhisperKnotDocument, bot: String, conversationID: UUID, recipient: String, username: String, messageID: UUID) async -> Bool {
        let generation = AccountStorage.generation, permission = WhisperKnotContextPermission.revision
        do {
            var fields: [String: WhisperKnotReceiptJSON] = ["messageID": .string(messageID.uuidString.lowercased()), "recipientID": .string(recipient.lowercased())]
            if bot == WhisperKnotDMArtifacts.storageBot {
                fields["sourceMessageID"] = .string(conversationID.uuidString.lowercased())
            } else {
                guard WhisperKnotContextPermission.allowed else {
                    lastSendFailure = "Turn Knot file access back on to send its files."; return false
                }
                fields["bot"] = .string(bot); fields["conversationID"] = .string(conversationID.uuidString.lowercased()); fields["documentID"] = .string(document.id)
            }
            struct Prepared: Decodable { let body: String }
            let prepared = try JSONDecoder().decode(Prepared.self, from: await request("prepare", fields: fields))
            guard generation == AccountStorage.generation, !Task.isCancelled,
                  bot == WhisperKnotDMArtifacts.storageBot || (WhisperKnotContextPermission.allowed && permission == WhisperKnotContextPermission.revision),
                  WhisperKnotArtifactWire.messageID(prepared.body) == messageID else { return false }
            return await WhisperBackendService.shared.sendMessage(toUserID: recipient, toUsername: username, body: prepared.body, requiresConfirmedDelivery: true, messageID: messageID)
        } catch let error as SharingError {
            lastSendFailure = error.sendDescription; return false
        } catch is CancellationError { return false
        } catch { lastSendFailure = "Whisper couldn’t reach the file service."; return false }
    }
    static func resolve(_ id: UUID) async throws -> Resolved {
        let result = try JSONDecoder().decode(Resolved.self, from: await request("resolve", fields: ["messageID": .string(id.uuidString.lowercased())]))
        guard result.document.valid else { throw URLError(.cannotDecodeContentData) }
        WhisperKnotDMArtifacts.register(id)
        return result
    }
    static func resource(_ id: UUID, action: String, resourceID: Int? = nil) async throws -> Data {
        guard WhisperKnotDMArtifacts.allowed(id) else { throw CancellationError() }
        var fields: [String: WhisperKnotReceiptJSON] = ["messageID": .string(id.uuidString.lowercased()), "action": .string(action)]
        if let resourceID { fields["resourceID"] = .number(Double(resourceID)) }
        return try await request("resource", fields: fields, maximum: 50_000_000)
    }
    static func saveStep(_ id: UUID) async throws -> SaveProgress {
        try JSONDecoder().decode(SaveProgress.self, from: await request("save", fields: ["messageID": .string(id.uuidString.lowercased()), "confirm": .bool(true)]))
    }
    private static func request(_ action: String, fields: [String: WhisperKnotReceiptJSON], maximum: Int = 150_000) async throws -> Data {
        let owner = AccountStorage.currentUserID.lowercased(), generation = AccountStorage.generation
        let auth = try await SupabaseService.shared.client.auth.session
        guard owner == auth.user.id.uuidString.lowercased(), generation == AccountStorage.generation, !Task.isCancelled else { throw CancellationError() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.timeoutIntervalForRequest = 75; configuration.timeoutIntervalForResource = 90
        let transport = URLSession(configuration: configuration)
        let cancellation = WhisperKnotRequestCancellation()
        let observer = NotificationCenter.default.addObserver(forName: .init("WhisperMeetingAccountWillChange"), object: nil, queue: nil) { _ in cancellation.cancel() }
        defer { NotificationCenter.default.removeObserver(observer); transport.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: WhisperKnotBackend.origin + "/knot/artifacts/" + action)!)
        request.httpMethod = "POST"; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "X-Whisper-Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(fields)
        return try await withTaskCancellationHandler {
            let (bytes, response) = try await transport.bytes(for: request, delegate: cancellation)
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            let data = try await collect(bytes, limit: success ? maximum : 4096, cancellation: cancellation)
            guard generation == AccountStorage.generation, owner == AccountStorage.currentUserID.lowercased(), !Task.isCancelled else { throw CancellationError() }
            try cancellation.check()
            guard success else {
                let result = try? JSONDecoder().decode(WhisperKnotReceiptJSON.self, from: data)
                throw SharingError.server(result?["error"]?.text ?? "sharing_unavailable")
            }
            return data
        } onCancel: { cancellation.cancel() }
    }
    @concurrent private static func collect(_ bytes: URLSession.AsyncBytes, limit: Int, cancellation: WhisperKnotRequestCancellation) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            if data.count % 4096 == 0 { try Task.checkCancellation(); try cancellation.check() }
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
    nonisolated enum SharingError: LocalizedError {
        case server(String)
        var accessRevoked: Bool {
            switch self {
            case .server("sharing_access_denied"), .server("document_removed"): true
            default: false
            }
        }
        /// Sender-side wording; recipients keep `errorDescription`.
        var sendDescription: String {
            switch self {
            case .server("sharing_access_denied"): "You can’t message this person right now."
            case .server("document_removed"): "This file is no longer stored for sharing (Knot keeps shareable originals for 7 days). Ask Knot to make it again to send it."
            case .server("document_identity_changed"), .server("share_identity_conflict"): "This file changed since it was opened. Close it, reopen the latest copy and try again."
            case .server("document_storage_full"): "File sharing storage is full. Delete older Knot files, then try again."
            case .server("document_original_unavailable"), .server("document_refetch_unavailable"): "The original file couldn’t be read from the workspace."
            case .server("invalid_share"): "This file can’t be shared from here."
            default: "The file service didn’t respond."
            }
        }
        var errorDescription: String? {
            switch self {
            case .server("sharing_access_denied"): "This share is no longer available with the current messaging permissions."
            case .server("document_removed"): "The original file is no longer available. No replacement was generated."
            case .server("save_uncertain"): "The save couldn’t be confirmed yet. Wait a moment, then retry; the previous transfer will not be replayed."
            case .server("workspace_save_failed"), .server("workspace_file_conflict"): "This transfer stopped without replacing existing files. It won’t be replayed; ask for a fresh share if you need another transfer."
            case .server("save_in_progress"): "This copy is already being saved. Wait a moment, then retry to check its progress."
            default: "This file couldn’t be shared or saved right now. Please try again."
            }
        }
    }
}

struct WhisperKnotArtifactShareSheet: View {
    let document: WhisperKnotDocument
    let bot: String
    let conversationID: UUID
    var body: some View {
        WhisperRecipientShareSheet(payload: document.displayTitle, directOnly: true, deliverPayload: { recipient, username, messageID in
            await WhisperKnotArtifactSharing.send(document: document, bot: bot, conversationID: conversationID, recipient: recipient, username: username, messageID: messageID)
        }, payloadFailureReason: { WhisperKnotArtifactSharing.lastSendFailure }) { EmptyView() }
    }
}

/// Uses the original file card and its retained interactive WebKit page. The
/// message contains a pointer, never client-authored file metadata or attribution.
struct WhisperKnotDMArtifactCard: View {
    let messageID: UUID
    let mine: Bool
    @State private var resolved: WhisperKnotArtifactSharing.Resolved?
    @State private var issue: String?
    @State private var retry = UUID()
    @State private var progress: Double?
    @State private var savedPath: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var saveRevision = UUID()
    @State private var resolutionFailed = false
    @State private var resolutionRevision = UUID()
    @State private var generation = AccountStorage.generation
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let resolved {
                Text(mine ? "You sent a file" : "\(resolved.senderName) sent you \(resolved.document.styleLabel.localizedCaseInsensitiveContains("game") ? "a game" : "a file")")
                    .font(.caption).foregroundStyle(.secondary)
                WhisperKnotDocumentRows(documents: [resolved.document], bot: .main, conversationID: messageID, directMessage: true).id(resolutionRevision)
                if !mine {
                    if resolved.saved || savedPath != nil {
                        Label("Saved to your workspace", systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(.secondary)
                        Text("Original file · your own copy and progress").font(.caption2).foregroundStyle(.secondary)
                    } else if let progress {
                        ProgressView(value: progress) { Text("Saving your copy…").font(.footnote) }
                        Button("Pause saving") { pauseSaving() }.font(.footnote).frame(minHeight: 44)
                    } else {
                        Button { beginSave() } label: { Label("Save to my workspace", systemImage: "folder.badge.plus").font(.subheadline.weight(.medium)) }.frame(minHeight: 44)
                    }
                }
            } else {
                Label("Shared file", systemImage: "doc.fill").font(.subheadline.weight(.medium))
                if issue == nil { ProgressView("Opening file…").font(.footnote) }
            }
            if let issue {
                Text(issue).font(.footnote).foregroundStyle(.secondary)
                Button("Retry") { if resolved == nil || resolutionFailed { retry = UUID() } else { beginSave() } }.font(.footnote).frame(minHeight: 44)
            }
        }
        .padding(12).frame(maxWidth: 340, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 24))
        .task(id: "\(retry):\(phase)") { if phase == .active { await load() } }
        .onDisappear { pauseSaving() }
        .onChange(of: phase) { _, phase in if phase != .active { pauseSaving() } }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in retry = UUID() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in
            pauseSaving(); resolved = nil; issue = nil; savedPath = nil
            WhisperKnotDMArtifacts.remove(messageID)
        }
    }
    private func load() async {
        do {
            let result = try await WhisperKnotArtifactSharing.resolve(messageID)
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            resolved = result; issue = nil; resolutionFailed = false; resolutionRevision = UUID()
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            if resolved == nil || (error as? WhisperKnotArtifactSharing.SharingError)?.accessRevoked == true {
                pauseSaving(); resolved = nil
                WhisperKnotDMArtifacts.remove(messageID)
            }
            resolutionFailed = true; issue = error.localizedDescription
        }
    }
    private func pauseSaving() {
        saveRevision = UUID(); saveTask?.cancel(); saveTask = nil; progress = nil
    }
    private func beginSave() {
        guard saveTask == nil, generation == AccountStorage.generation else { return }
        issue = nil; resolutionFailed = false; progress = 0
        let revision = UUID(); saveRevision = revision
        saveTask = Task {
            defer { if generation == AccountStorage.generation, saveRevision == revision { progress = nil; saveTask = nil } }
            do {
                while !Task.isCancelled {
                    let step = try await WhisperKnotArtifactSharing.saveStep(messageID)
                    guard generation == AccountStorage.generation, saveRevision == revision, !Task.isCancelled else { return }
                    progress = step.progress
                    if step.done {
                        savedPath = step.path
                        Haptics.success()
                        // Preserve the already mounted DM page and its progress.
                        return
                    }
                    try await Task.sleep(for: .milliseconds(350))
                }
            } catch {
                guard generation == AccountStorage.generation, saveRevision == revision, !Task.isCancelled else { return }
                issue = error.localizedDescription
            }
        }
    }
}
