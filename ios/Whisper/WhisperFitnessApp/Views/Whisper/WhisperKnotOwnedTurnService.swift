import Foundation
import Observation
import Supabase
import UIKit

/// Server-driven pill labels for owned turns, keyed by lowercased task ID.
/// The backend decides what is shown; nil means no pill.
@MainActor @Observable final class WhisperKnotServerActivity {
    static let shared = WhisperKnotServerActivity()
    private(set) var labels: [String: String] = [:]
    func label(for taskID: UUID?) -> String? { taskID.flatMap { labels[$0.uuidString.lowercased()] } }
    func set(_ label: String?, for taskID: String) {
        let key = taskID.lowercased()
        if labels[key] != label { labels[key] = label }
    }
}

/// Submission transfers ownership. Polling and view cancellation only detach;
/// Stop is a separate, durable, account-qualified server operation.
@MainActor enum WhisperKnotOwnedTurnService {
    nonisolated struct TaskInfo: Decodable, Sendable, Identifiable {
        let id: UUID
        let bot: String
        let conversationID: UUID
        let sourceMessageID: UUID
        let replyID: UUID
        let state: String
        let createdAt: Double
        let sequence: Int
        var running: Bool { ["admitting", "queued", "running", "delivering"].contains(state) }
    }
    private nonisolated struct Index: Decodable, Sendable { let tasks: [TaskInfo]; let approvalEpoch: String }
    private nonisolated struct Receipt: Decodable, Sendable { let task: TaskInfo }
    /// iOS suspends a closed app within seconds. Until the server has durably
    /// admitted the task, nothing exists to keep running, so the hand-off asks
    /// for a short background grace period. It ends as soon as admission is
    /// confirmed or fails; execution itself never depends on this phone.
    private static var admissionHolds: [String: UIBackgroundTaskIdentifier] = [:]
    static func holdAdmission(_ taskID: String) {
        guard admissionHolds[taskID] == nil else { return }
        let id = UIApplication.shared.beginBackgroundTask(withName: "Knot task hand-off") {
            MainActor.assumeIsolated { releaseAdmission(taskID) }
        }
        if id != .invalid { admissionHolds[taskID] = id }
    }
    static func releaseAdmission(_ taskID: String) {
        guard let id = admissionHolds.removeValue(forKey: taskID) else { return }
        UIApplication.shared.endBackgroundTask(id)
    }
    static func replyID(for source: UUID) -> UUID {
        let id = source.uuidString.lowercased()
        let nibble = Int(String(id.prefix(1)), radix: 16) ?? 0
        return UUID(uuidString: String(nibble ^ 8, radix: 16) + id.dropFirst())!
    }
    private static func request(_ path: String = "", method: String = "GET", body: Data? = nil, generation: UUID) async throws -> Data {
        try Task.checkCancellation()
        guard generation == AccountStorage.generation, AccountStorage.currentUserID != "guest" else { throw CancellationError() }
        let auth = try await SupabaseService.shared.client.auth.session
        guard generation == AccountStorage.generation, auth.user.id.uuidString.lowercased() == AccountStorage.currentUserID.lowercased() else { throw CancellationError() }
        var request = URLRequest(url: URL(string: WhisperKnotBackend.origin + "/knot/turns" + path)!)
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "X-Whisper-Authorization")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard generation == AccountStorage.generation else { throw CancellationError() }
        guard data.count <= 1_000_000, let http = response as? HTTPURLResponse else { throw WhisperKnotLiveError.unavailable }
        if [400,401,403,404,409,410,413,429].contains(http.statusCode) { throw WhisperKnotLiveError.rejected }
        guard (200..<300).contains(http.statusCode) else { throw WhisperKnotLiveError.unavailable }
        return data
    }
    static func tasks(conversationID: UUID) async throws -> [TaskInfo] {
        let generation = AccountStorage.generation
        let index = try JSONDecoder().decode(Index.self, from: await request(generation: generation))
        return index.tasks.filter { $0.conversationID == conversationID }
    }
    static func stopPending(_ taskID: UUID) -> Bool {
        (AccountStorage.object(forKey: "knot_owned_pending_stops_v1") as? [String] ?? []).contains(taskID.uuidString.lowercased())
    }
    static func cancel(_ taskID: UUID) {
        // Persist a pending Stop before networking. A later foreground sync
        // retries Stop only, never submission or execution.
        var ids = Set(AccountStorage.object(forKey: "knot_owned_pending_stops_v1") as? [String] ?? [])
        ids.insert(taskID.uuidString.lowercased())
        AccountStorage.set(Array(ids), forKey: "knot_owned_pending_stops_v1")
        Task { await flushStops() }
    }
    static func flushStops() async {
        let generation = AccountStorage.generation
        let ids = AccountStorage.object(forKey: "knot_owned_pending_stops_v1") as? [String] ?? []
        for id in ids {
            do {
                _ = try await request("/" + id + "/cancel", method: "POST", body: Data("{}".utf8), generation: generation)
                guard generation == AccountStorage.generation else { return }
                var remaining = Set(AccountStorage.object(forKey: "knot_owned_pending_stops_v1") as? [String] ?? [])
                remaining.remove(id); AccountStorage.set(Array(remaining), forKey: "knot_owned_pending_stops_v1")
            } catch { return }
        }
    }
    static func run(body: Data, taskID: String, receive: @escaping @Sendable @MainActor (WhisperKnotLiveService.Event) async throws -> String?) async throws -> String? {
        let generation = AccountStorage.generation
        defer { releaseAdmission(taskID) }
        holdAdmission(taskID)
        await flushStops()
        guard WhisperKnotContextPermission.allowed, !AccountStorage.bool(forKey: "knot_background_pause_pending_v1") else { throw CancellationError() }
        let index = try JSONDecoder().decode(Index.self, from: await request(generation: generation))
        var object = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        object["backgroundApprovalEpoch"] = index.approvalEpoch
        let submission = try JSONSerialization.data(withJSONObject: object)
        do {
            let saved = try JSONDecoder().decode(Receipt.self, from: await request(method: "POST", body: submission, generation: generation))
            guard saved.task.id.uuidString.lowercased() == taskID else { throw WhisperKnotLiveError.interrupted }
        } catch {
            try Task.checkCancellation()
            // Ambiguous POST: attach by the original identity. Never silently
            // create a second task, retry a command, or use another provider.
            if case WhisperKnotLiveError.rejected = error { throw error }
            _ = try await request("/" + taskID, generation: generation)
        }
        // The server owns execution from here; closing the app only detaches.
        releaseAdmission(taskID)
        return try await attach(taskID: taskID, receive: receive)
    }
    static func attach(taskID: String, receive: @escaping @Sendable @MainActor (WhisperKnotLiveService.Event) async throws -> String?) async throws -> String? {
        let generation = AccountStorage.generation, revision = WhisperKnotContextPermission.revision
        var after = 0
        var sourceKey = taskID
        defer {
            WhisperKnotServerActivity.shared.set(nil, for: taskID)
            WhisperKnotServerActivity.shared.set(nil, for: sourceKey)
        }
        while true {
            try Task.checkCancellation()
            guard generation == AccountStorage.generation, WhisperKnotContextPermission.allowed, revision == WhisperKnotContextPermission.revision else { throw CancellationError() }
            let data: Data
            do { data = try await request("/" + taskID + "?after=\(after)", generation: generation) }
            catch {
                try Task.checkCancellation()
                if case WhisperKnotLiveError.rejected = error { throw error }
                // Offline affects the viewer only; retain its cursor and attach
                // when connectivity returns instead of reporting task failure.
                try await Task.sleep(for: .seconds(3)); continue
            }
            guard let page = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawEvents = page["events"] as? [[String: Any]], let next = page["next"] as? Int,
                  let task = page["task"] as? [String: Any], task["id"] as? String == taskID,
                  next >= after else { throw WhisperKnotLiveError.interrupted }
            let activity = (page["currentActivity"] as? [String: Any])?["label"] as? String
            sourceKey = task["sourceMessageID"] as? String ?? taskID
            let label = page["terminal"] as? Bool == true ? nil : activity
            WhisperKnotServerActivity.shared.set(label, for: taskID)
            WhisperKnotServerActivity.shared.set(label, for: sourceKey)
            for var raw in rawEvents {
                guard (raw["sequence"] as? Int) == after + 1 else { throw WhisperKnotLiveError.interrupted }
                let type = raw["type"] as? String ?? ""
                // The server executes prepared commands and commits final
                // delivery. These frames are observations, not client work.
                if ["shell_proposal", "complete", "rejected", "error", "document_work_unavailable"].contains(type) { raw["type"] = "accepted" }
                let event = try JSONDecoder().decode(WhisperKnotLiveService.Event.self, from: JSONSerialization.data(withJSONObject: raw))
                _ = try await receive(event)
                after = event.sequence
            }
            guard after == next else { throw WhisperKnotLiveError.interrupted }
            if page["terminal"] as? Bool == true, page["hasMore"] as? Bool != true {
                guard task["state"] as? String != "cancelled" else { throw CancellationError() }
                guard let result = page["result"] as? [String: Any], let reply = result["reply"] as? String else { throw WhisperKnotLiveError.interrupted }
                var raw: [String: Any] = ["v": 1, "requestID": taskID, "sequence": after + 1, "type": "complete", "reply": reply]
                if let clarification = result["clarification"] { raw["clarification"] = clarification }
                let event = try JSONDecoder().decode(WhisperKnotLiveService.Event.self, from: JSONSerialization.data(withJSONObject: raw))
                return try await receive(event)
            }
            if page["hasMore"] as? Bool != true { try await Task.sleep(for: .milliseconds(850)) }
        }
    }
}
