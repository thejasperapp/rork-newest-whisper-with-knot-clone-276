import Foundation

nonisolated enum WhisperAdPlacement: String, Sendable {
    case feed, reels, comments

    var limit: Int {
        switch self {
        case .feed: 6
        case .reels: 4
        case .comments: 1
        }
    }
}
