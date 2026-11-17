import Foundation
import Observation

/// Screen-owned server state. No persisted/device-local permission grants or automatic conflict replay.
@MainActor @Observable
final class WhisperChatMeetPermissionsViewModel {
    private(set) var rows: [WhisperChatMeetPermission] = []
    private(set) var hasLoaded: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var isSaving: Bool = false
    private(set) var error: String?
    private(set) var notice: String?
    private let peer: UUID?
    private let owner: UUID? = UUID(uuidString: AccountStorage.currentUserID)
    private let generation: UUID = AccountStorage.generation
    private var isActive: Bool = false
    private var accountInvalidated: Bool = false
    @ObservationIgnored private var operation: UUID = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(peerID: String) { peer = UUID(uuidString: peerID) }

    var incoming: WhisperChatMeetPermission? { rows.first { $0.organizerID == peer && $0.recipientID == owner } }
    var outgoing: WhisperChatMeetPermission? { rows.first { $0.organizerID == owner && $0.recipientID == peer } }
    var canInteract: Bool { isCurrent && hasLoaded && !isLoading && !isSaving }
    private var isCurrent: Bool {
        isActive && !accountInvalidated && generation == AccountStorage.generation
            && owner != nil && owner == UUID(uuidString: AccountStorage.currentUserID)
            && peer != nil && peer != owner
    }

    func setActive(_ active: Bool) {
        stop()
        isActive = active
        if active { refresh() }
    }

    func invalidateAccount() {
        accountInvalidated = true
        stop()
    }

    func stop() {
        isActive = false
        operation = UUID()
        task?.cancel(); task = nil
        rows = []; hasLoaded = false; isLoading = false; isSaving = false
        error = nil; notice = nil
    }

    func refresh() {
        guard isCurrent, !isSaving, !isLoading else { return }
        let token = UUID(); operation = token
        rows = []; hasLoaded = false; error = nil; notice = nil; isLoading = true
        task = Task {
            defer { if operation == token { isLoading = false; task = nil } }
            do { try await readCurrent(token: token) }
            catch {
                guard owns(token) else { return }
                rows = []; hasLoaded = false
                self.error = "Couldn't refresh Meet permissions. \(error.localizedDescription)"
            }
        }
    }

    func change(_ action: WhisperChatMeetPermission.Action, snapshot: WhisperChatMeetPermission? = nil) {
        guard canInteract, let peer else { return }
        if action.requiresRollout && WhisperChatMeetService.holdsNewInvitations {
            error = WhisperChatMeetService.Failure.clientRolloutHold.localizedDescription
            return
        }
        if action != .request {
            guard let snapshot, snapshot.recipientID == owner, snapshot.organizerID == peer,
                  snapshot == incoming else { return }
        }
        let token = UUID(); operation = token
        isSaving = true; error = nil; notice = nil
        task = Task {
            defer { if operation == token { isSaving = false; task = nil } }
            do {
                // Refetch first; never silently substitute a newer revision for the choice the user saw.
                try await readCurrent(token: token)
                guard owns(token) else { return }
                if action == .request {
                    if outgoing != nil {
                        notice = "An outgoing permission already exists. Its current state has not been reset."
                        return
                    }
                } else {
                    guard let snapshot, let latest = incoming,
                          latest.revision == snapshot.revision, latest.state == snapshot.state else {
                        throw WhisperChatMeetService.Failure.permissionConflict
                    }
                    if action == .accept && (latest.state == .denied || latest.state == .revoked) {
                        throw WhisperChatMeetService.Failure.permissionRevoked
                    }
                    if latest.state == action.resultingState {
                        notice = "The server already shows this state. No further change was sent."
                        return
                    }
                }
                _ = try await WhisperChatMeetService.permission(peerID: peer, action: action,
                                                               expectedRevision: action == .request ? nil : snapshot?.revision)
                guard owns(token) else { return }
                try await readCurrent(token: token)
                guard owns(token) else { return }
                notice = "Meet permission state refreshed. This does not RSVP or join a meeting."
            } catch {
                guard owns(token) else { return }
                rows = []; hasLoaded = false
                self.error = error.localizedDescription
                // A conflict or lost response may follow a committed change. Read, but do not replay it.
                do {
                    try await readCurrent(token: token)
                    guard owns(token) else { return }
                    notice = "Latest server state loaded. Review it before choosing another action; nothing was automatically resubmitted."
                } catch {
                    guard owns(token) else { return }
                    rows = []; hasLoaded = false
                    notice = "The latest state couldn't be loaded. Refresh before making another change."
                }
            }
        }
    }

    private func owns(_ token: UUID) -> Bool { !Task.isCancelled && isCurrent && operation == token }

    private func readCurrent(token: UUID) async throws {
        let latest = try await WhisperChatMeetService.permissions()
        guard owns(token) else { throw CancellationError() }
        rows = latest.filter { ($0.organizerID == peer && $0.recipientID == owner) || ($0.organizerID == owner && $0.recipientID == peer) }
        hasLoaded = true
    }
}
