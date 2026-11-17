import UIKit

/// Opens existing Notes links without transferring sessions, copying notes, or changing access.
@MainActor enum WhisperNotesHandoff {
    static func open(_ link: WhisperNotesLink) async -> Bool {
        let generation = AccountStorage.generation
        return await open(link, using: { url in
            guard !Task.isCancelled, generation == AccountStorage.generation else { return false }
            return await UIApplication.shared.open(url, options: [:])
        })
    }

    static func open(_ link: WhisperNotesLink, using openURL: @MainActor (URL) async -> Bool) async -> Bool {
        guard let appURL = link.appURL, let webURL = link.webURL else { return false }
        if await openURL(appURL) { return true }
        return await openURL(webURL)
    }
}
