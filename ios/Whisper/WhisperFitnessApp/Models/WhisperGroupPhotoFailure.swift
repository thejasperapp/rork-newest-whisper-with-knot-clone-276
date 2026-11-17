import Foundation

nonisolated enum WhisperGroupPhotoFailure: LocalizedError {
    case unreadable, tooLarge, ownerOnly, upload, confirmation

    var errorDescription: String? {
        switch self {
        case .unreadable: return "This picture couldn't be opened. Choose another photo."
        case .tooLarge: return "This photo is too large. Choose a smaller picture."
        case .ownerOnly: return "Only the group creator can change its picture. Reopen the group to refresh your access."
        case .upload: return "The picture couldn't be uploaded. Check your connection and retry. If it keeps failing, reopen the group to refresh your access."
        case .confirmation: return "The upload finished, but the picture change couldn't be confirmed. Reopen the group before trying again."
        }
    }
}
