import Foundation

nonisolated enum WhisperNotebookError: LocalizedError {
    case empty, tooLong, tooManySources, invalidResult, unavailable, accountChanged, storage, conflict, limit
    var errorDescription: String? {
        switch self {
        case .empty: "Write some notes or paste a transcript first."
        case .tooLong: "Jasper can read up to 24,000 characters per entry. Split this into smaller notes; your full writing is still saved."
        case .tooManySources: "This entry has more than 160 source passages. Split it into smaller notes before using Jasper."
        case .invalidResult: "Jasper couldn't produce a complete source-linked result. Your writing is unchanged. Please try again."
        case .unavailable: "Jasper couldn't be reached. Check your connection and try again; your writing is unchanged."
        case .accountChanged: "Your account changed. Reopen Notebook before continuing."
        case .storage: "Couldn't read or save this device's notes. Existing files have not been replaced. Export your draft and try again."
        case .conflict: "This note changed in another window. Export your draft, then reopen the note before editing."
        case .limit: "This notebook has reached its local limit. Export and remove an entry before adding more."
        }
    }
}
