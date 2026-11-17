import SwiftUI
import Supabase

@MainActor @Observable
final class WhisperGroupThemeStore {
    let groupID: UUID
    private(set) var design = WhisperChatThemeDesign(theme: .classic)
    private(set) var revision: Int = 0
    private(set) var isReady: Bool = false
    private(set) var error: String? = nil
    private let epoch = AccountStorage.generation
    private let account = AccountStorage.currentUserID
    private var client: SupabaseClient { SupabaseService.shared.client }
    @ObservationIgnored private var readID: UUID = UUID()

    init(groupID: UUID) { self.groupID = groupID }

    func clear() { readID = UUID(); design = .init(theme: .classic); revision = 0; isReady = false }

    func refresh() async {
        let operation = UUID(); readID = operation
        do {
            try WhisperChatMediaService.checkAccount(account, generation: epoch)
            let session = try await client.auth.session
            guard session.user.id.uuidString.lowercased() == account.lowercased() else { throw CancellationError() }
            // A missing theme isn't evidence of membership: separately verify the registry under RLS.
            let memberships: [WhisperGroupRegistryRow] = try await client.from("whisper_group_threads").select()
                .eq("id", value: groupID.uuidString).limit(1).execute().value
            try WhisperChatMediaService.checkAccount(account, generation: epoch)
            guard !memberships.isEmpty else { clear(); error = "This group is no longer available."; return }
            let rows: [WhisperGroupThemeRecord] = try await client.from("whisper_group_themes").select()
                .eq("group_id", value: groupID.uuidString).limit(1).execute().value
            try WhisperChatMediaService.checkAccount(account, generation: epoch)
            guard readID == operation else { return }
            if let row = rows.first, row.revision >= revision { adopt(row) }
            isReady = true; error = nil
        } catch {
            guard epoch == AccountStorage.generation, !Task.isCancelled, readID == operation else { return }
            self.error = "Couldn't refresh the shared theme. Try again when you're connected."
        }
    }

    func apply(_ next: WhisperChatThemeDesign, expectedRevision: Int, operationID: UUID) async throws {
        try WhisperChatMediaService.checkAccount(account, generation: epoch)
        guard isReady, next.isValid else { throw WhisperThemeFailure.unavailable }
        let session = try await client.auth.session
        try WhisperChatMediaService.checkAccount(account, generation: epoch)
        guard session.user.id.uuidString.lowercased() == account.lowercased() else { throw CancellationError() }
        struct Parameters: Encodable {
            let p_group_id: UUID
            let p_expected_revision: Int
            let p_theme: WhisperChatThemeDesign
            let p_operation_id: UUID
        }
        do {
            let row: WhisperGroupThemeRecord = try await client.rpc("whisper_set_group_theme", params: Parameters(
                p_group_id: groupID, p_expected_revision: expectedRevision, p_theme: next, p_operation_id: operationID
            )).execute().value
            try WhisperChatMediaService.checkAccount(account, generation: epoch)
            readID = UUID()
            adopt(row); error = nil
        } catch {
            if let failure = error as? PostgrestError, failure.code == "40001" {
                await refresh()
                throw WhisperThemeFailure.conflict
            }
            throw error
        }
    }

    func observe() async {
        let channel = client.realtimeV2.channel("group-theme-\(groupID)-\(epoch)")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "whisper_group_themes", filter: "group_id=eq.\(groupID.uuidString.lowercased())")
        let listener = Task { @MainActor in
            await channel.subscribe()
            for await _ in changes {
                guard !Task.isCancelled, epoch == AccountStorage.generation else { break }
                await refresh()
            }
        }
        defer {
            listener.cancel()
            Task { await client.realtimeV2.removeChannel(channel) }
        }
        while !Task.isCancelled && epoch == AccountStorage.generation {
            if UIApplication.shared.applicationState == .active { await refresh() }
            do { try await Task.sleep(for: .seconds(6)) } catch { break }
        }
    }

    private func adopt(_ row: WhisperGroupThemeRecord) {
        guard row.group_id == groupID, row.revision >= revision else { return }
        revision = row.revision
        design = row.theme.isValid ? row.theme : .init(theme: .classic)
    }
}
