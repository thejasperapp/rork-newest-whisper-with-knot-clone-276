import Foundation

nonisolated enum WhisperProfileTab: String, CaseIterable, Hashable {
    case threads, waves, replies, reposts, media

    var label: String {
        switch self {
        case .threads: "Whisps"
        case .waves: "Waves"
        case .replies: "Replies"
        case .reposts: "Reposts"
        case .media: "Media"
        }
    }
}
