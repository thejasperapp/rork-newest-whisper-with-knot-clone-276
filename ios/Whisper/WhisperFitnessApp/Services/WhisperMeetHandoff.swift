import UIKit

/// Uses the operating system, never an embedded browser, session transfer, or media startup.
@MainActor
enum WhisperMeetHandoff {
    static func open(_ invitation: WhisperMeetingInvitation) async -> Bool {
        await open(invitation, using: { url in
            await UIApplication.shared.open(url, options: [:])
        })
    }

    /// The opening boundary is injectable so success and failure are tested without launching another app.
    static func open(_ invitation: WhisperMeetingInvitation, using openURL: @MainActor (URL) async -> Bool) async -> Bool {
        let generation = AccountStorage.generation
        guard !Task.isCancelled, !invitation.isSocial, WhisperMeetingInvitation.isIdentity(invitation.idOrCode),
              let appURL = invitation.appURL, let webURL = invitation.webURL else { return false }
        if await openURL(appURL) { return true }
        guard !Task.isCancelled, generation == AccountStorage.generation else { return false }
        return await openURL(webURL)
    }
}
