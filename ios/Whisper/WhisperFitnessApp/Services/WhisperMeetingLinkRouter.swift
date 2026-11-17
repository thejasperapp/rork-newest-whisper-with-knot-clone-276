import Foundation
import UIKit

/// Ordinary invitations leave social Whisper. Dating and call rooms retain their social routes.
@MainActor
enum WhisperMeetingLinkRouter {
    typealias Target = WhisperMeetingInvitation

    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard let target = parse(url) else { return false }
        Task { await open(target) }
        return true
    }

    nonisolated static func parse(_ url: URL) -> Target? {
        WhisperMeetingInvitation.parse(url)
    }

    @discardableResult
    static func open(_ target: Target) async -> Bool {
        guard WhisperMeetingInvitation.isIdentity(target.idOrCode) else { return false }
        let generation = AccountStorage.generation
        var target = target
        if WhisperMeetingService.isMeetingUUID(target.idOrCode) {
            let key = target.idOrCode.lowercased()
            if WhisperSpeedDating.knownRooms.contains(key) || WhisperSpeedDating.pendingRooms.contains(key) {
                target.speedDate = true
            }
        }
        if !target.isSocial {
            // Old group-call links used the ordinary URL shape. Read metadata only;
            // never use fetch(), which registers a meeting participant.
            if WhisperMeetingService.isMeetingUUID(target.idOrCode),
               let row = await WhisperMeetingService.shared.fetchArchived(id: target.idOrCode),
               row.isGroupCall || row.title.hasPrefix("Video call with @") || row.title.hasPrefix("Audio call with @") {
                guard generation == AccountStorage.generation, !Task.isCancelled else { return false }
                WhisperMeetingWindow.shared.present(row)
                return true
            }
            guard generation == AccountStorage.generation, !Task.isCancelled else { return false }
            return await WhisperMeetHandoff.open(target)
        }
        // Code resolution/creation is deliberately restricted to the existing dating flow.
        let roomID = WhisperMeetingService.resolveRoomID(target.idOrCode)
        if target.speedDate { WhisperSpeedDating.markKnownRoom(roomID) }
        if let current = WhisperMeetingWindow.shared.meeting, current.id.lowercased() == roomID,
           WhisperMeetingWindow.shared.isPresenting {
            WhisperMeetingWindow.shared.present(current)
            return true
        }
        if target.speedDate, !WhisperMeetingService.isMeetingUUID(target.idOrCode) {
            await WhisperMeetingService.shared.ensureRoom(id: roomID, title: "Blind date")
        }
        var row = await WhisperMeetingService.shared.fetch(id: roomID)
        var attempts = 0
        while row == nil, attempts < 6, !Task.isCancelled, generation == AccountStorage.generation {
            attempts += 1
            try? await Task.sleep(for: .seconds(2))
            row = await WhisperMeetingService.shared.fetch(id: roomID)
        }
        guard let row, !Task.isCancelled, generation == AccountStorage.generation else { return false }
        WhisperMeetingWindow.shared.present(row)
        return true
    }
}
