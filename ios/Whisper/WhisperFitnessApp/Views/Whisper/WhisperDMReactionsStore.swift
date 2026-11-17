import Foundation
import Observation
import Supabase
import UIKit

nonisolated struct WhisperSharedReaction: Decodable, Identifiable, Sendable, Equatable {
    let message_id: String
    let emoji: String
    let reaction_count: Int
    let mine: Bool
    var id: String { emoji }
}

/// One visible conversation's shared state. Legacy device-only selections are never uploaded.
@Observable @MainActor
final class WhisperDMReactionsStore {
    private var rows: [String: [WhisperSharedReaction]] = [:]
    private var landings: [String: [String: UUID]] = [:]
    private var pendingLanding: [String: String] = [:]
    private var visible: Set<String> = []
    private var busy: Set<String> = []
    private var generation = AccountStorage.generation
    private var revision: UInt = 0
    var failure: String?
    private var fetchID: UUID?
    private var fetching: Bool { fetchID != nil }
    @ObservationIgnored private var visibilityRefresh: Task<Void, Never>?
    private var visibilityRefreshID = UUID()
    private var watchID: UUID?
    private var trailingRefresh = false
    private var pollDelay: TimeInterval = 3
    private var nextPoll = Date.distantPast

    private var current: Bool { generation == AccountStorage.generation }
    func reactions(for id: String) -> [WhisperSharedReaction] {
        current ? rows[id.lowercased()] ?? [] : []
    }
    func landingIDs(for id: String) -> [String: UUID] {
        current ? landings[id.lowercased()] ?? [:] : [:]
    }
    func selected(for id: String) -> String? { reactions(for: id).first(where: \.mine)?.emoji }
    func show(_ id: String) {
        if !current { reset() }
        guard UUID(uuidString: id) != nil else { return }
        guard visible.insert(id.lowercased()).inserted else { return }
        pollDelay = 3
        scheduleVisibilityRefresh()
    }
    func hide(_ id: String) {
        visible.remove(id.lowercased())
        if visible.isEmpty {
            visibilityRefreshID = UUID(); visibilityRefresh?.cancel(); visibilityRefresh = nil
            trailingRefresh = false
        }
    }
    private func scheduleVisibilityRefresh() {
        guard watchID != nil, current, !visible.isEmpty else { return }
        if fetching { trailingRefresh = true; return }
        guard visibilityRefresh == nil else { return }
        trailingRefresh = false
        let token = generation
        let lifecycle = watchID
        let operation = UUID(); visibilityRefreshID = operation
        visibilityRefresh = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard let self, !Task.isCancelled, self.generation == token, self.watchID == lifecycle,
                  self.visibilityRefreshID == operation else { return }
            defer {
                if self.visibilityRefreshID == operation {
                    self.visibilityRefresh = nil
                    if self.trailingRefresh { self.scheduleVisibilityRefresh() }
                }
            }
            await self.refresh()
        }
    }
    func reset() {
        generation = AccountStorage.generation
        revision &+= 1
        rows.removeAll(); landings.removeAll(); pendingLanding.removeAll()
        visible.removeAll(); busy.removeAll(); failure = nil
        visibilityRefreshID = UUID(); visibilityRefresh?.cancel(); visibilityRefresh = nil
        fetchID = nil; trailingRefresh = false; pollDelay = 3; nextPoll = .distantPast
    }
    func watch() async {
        let lifecycle = UUID(); watchID = lifecycle
        var wasActive = false
        defer {
            if watchID == lifecycle {
                watchID = nil
                visibilityRefreshID = UUID(); visibilityRefresh?.cancel(); visibilityRefresh = nil
                trailingRefresh = false
            }
        }
        // Retained conversation tasks can survive account reset. Individual
        // reads still require the current generation, auth account and lifecycle.
        while !Task.isCancelled, watchID == lifecycle {
            let active = UIApplication.shared.applicationState == .active
            if active, !wasActive { nextPoll = .distantPast; pollDelay = 3 }
            if active, Date() >= nextPoll { await refresh() }
            wasActive = active
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }
    func refresh() async {
        guard !Task.isCancelled, watchID != nil, current, !visible.isEmpty,
              UIApplication.shared.applicationState == .active else { return }
        guard !fetching else { trailingRefresh = true; return }
        let account = AccountStorage.currentUserID
        let token = generation
        guard SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased() == account.lowercased() else { return }
        let version = revision
        let lifecycle = watchID
        let operation = UUID(); fetchID = operation
        defer {
            if fetchID == operation {
                fetchID = nil
                if trailingRefresh, visibilityRefresh == nil { scheduleVisibilityRefresh() }
            }
        }
        let ids = Array(visible).sorted()
        var changed = false
        do {
            for start in stride(from: 0, to: ids.count, by: 200) {
                let batch = Array(ids[start..<min(start + 200, ids.count)])
                let fetched: [WhisperSharedReaction] = try await SupabaseService.shared.client
                    .rpc("whisper_get_message_reactions", params: ReadParams(p_message_ids: batch)).execute().value
                guard !Task.isCancelled, token == AccountStorage.generation, token == generation, version == revision,
                      watchID == lifecycle, fetchID == operation,
                      UIApplication.shared.applicationState == .active else { return }
                let grouped = Dictionary(grouping: fetched, by: { $0.message_id.lowercased() })
                for id in batch where visible.contains(id) || busy.contains(id) {
                    let confirmed = (grouped[id] ?? []).sorted { $0.emoji < $1.emoji }
                    if rows[id] != confirmed { changed = true }
                    let previous = rows[id]
                    var arrivals = landings[id] ?? [:]
                    for reaction in confirmed where visible.contains(id) {
                        let increased = previous.map { old in
                            reaction.reaction_count > (old.first(where: { $0.emoji == reaction.emoji })?.reaction_count ?? 0)
                        } ?? false
                        let justConfirmedMine = pendingLanding[id] == reaction.emoji && reaction.mine
                        if increased || justConfirmedMine { arrivals[reaction.emoji] = UUID() }
                    }
                    // An initial history read is not a new reaction. Only a
                    // later confirmed increase or our confirmed tap can land.
                    landings[id] = arrivals.filter { emoji, _ in confirmed.contains(where: { $0.emoji == emoji }) }
                    pendingLanding.removeValue(forKey: id)
                    rows[id] = confirmed
                }
            }
            // Keep only rendered rows and any mutation in progress; never grow with account history.
            rows = rows.filter { visible.contains($0.key) || busy.contains($0.key) }
            landings = landings.filter { rows[$0.key] != nil }
            pendingLanding = pendingLanding.filter { visible.contains($0.key) || busy.contains($0.key) }
        } catch {
            // Poll errors retain already-confirmed badges. Explicit mutations surface actionable errors.
        }
        guard token == generation, current, watchID == lifecycle, fetchID == operation else { return }
        // Fresh/changed conversations stay responsive; quiet or failing reads
        // back off to 12 seconds. New visibility, foreground and writes reset it.
        pollDelay = changed ? 3 : min(12, pollDelay * 2)
        nextPoll = Date().addingTimeInterval(pollDelay)
    }
    func toggle(_ emoji: String, on id: String, legacyGroup: Bool = false) {
        guard current else { return }
        guard !legacyGroup else {
            failure = "This older group message has no shared identity. Reactions are available on new messages sent from the updated app."
            return
        }
        guard UUID(uuidString: id) != nil else { failure = "Wait for this message to finish sending, then try again."; return }
        let key = id.lowercased()
        guard !busy.contains(key) else { return }
        let token = generation
        let account = AccountStorage.currentUserID.lowercased()
        guard SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased() == account else { return }
        busy.insert(key)
        pollDelay = 3; nextPoll = .distantPast
        revision &+= 1
        Task {
            defer { if generation == token { busy.remove(key) } }
            do {
                guard !Task.isCancelled, token == generation, token == AccountStorage.generation,
                      account == AccountStorage.currentUserID.lowercased(),
                      SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased() == account else { return }
                // The server toggles against the current user's locked row, even before our first read completes.
                try await SupabaseService.shared.client.rpc("whisper_toggle_message_reaction", params: WriteParams(
                    p_message_id: id, p_emoji: emoji, p_operation_id: UUID().uuidString)).execute()
                guard token == generation, token == AccountStorage.generation, account == AccountStorage.currentUserID.lowercased() else { return }
                revision &+= 1
                if visible.contains(key) { pendingLanding[key] = emoji }
                // A polling read started before this mutation must not overwrite its result.
                while fetching && token == generation && !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(50))
                }
                await refresh()
            } catch {
                guard token == generation, token == AccountStorage.generation else { return }
                failure = "Couldn't confirm your reaction. Check your connection and try again. If the message was removed or access changed, it can no longer be reacted to."
                await refresh()
            }
        }
    }

    nonisolated private struct ReadParams: Encodable, Sendable { let p_message_ids: [String] }
    nonisolated private struct WriteParams: Encodable, Sendable {
        let p_message_id: String
        let p_emoji: String?
        let p_operation_id: String
        enum CodingKeys: String, CodingKey { case p_message_id, p_emoji, p_operation_id }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(p_message_id, forKey: .p_message_id)
            try c.encode(p_emoji, forKey: .p_emoji) // Explicit null removes, rather than omitting the RPC argument.
            try c.encode(p_operation_id, forKey: .p_operation_id)
        }
    }
}
