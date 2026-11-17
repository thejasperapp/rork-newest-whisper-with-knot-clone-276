import Foundation

nonisolated enum WhisperReelPage: Identifiable {
    case reel(WhisperPost)
    case ad(WhisperServedAd, after: UUID)

    static func reelID(_ id: UUID) -> String { "reel-\(id.uuidString.lowercased())" }
    var id: String {
        switch self {
        case .reel(let post): Self.reelID(post.id)
        case .ad(let ad, after: let anchor): "ad-\(anchor.uuidString.lowercased())-\(ad.id)"
        }
    }
}
