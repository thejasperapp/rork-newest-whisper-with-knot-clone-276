import Foundation

nonisolated struct WhisperGroupThemeRecord: Decodable, Sendable {
    let group_id: UUID
    let theme: WhisperChatThemeDesign
    let revision: Int
    private enum CodingKeys: String, CodingKey { case group_id, theme, revision }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        group_id = try values.decode(UUID.self, forKey: .group_id)
        revision = try values.decode(Int.self, forKey: .revision)
        theme = (try? values.decode(WhisperChatThemeDesign.self, forKey: .theme)) ?? .init(theme: .classic)
    }
}

nonisolated enum WhisperThemeFailure: LocalizedError {
    case unavailable, conflict, generation, limited
    var errorDescription: String? {
        switch self {
        case .unavailable: "Refresh the group before changing its theme."
        case .conflict: "Someone changed the theme while you were browsing. Review the current theme, then apply again if you still want yours."
        case .generation: "Couldn't design a theme. Your current theme hasn't changed. Please try again."
        case .limited: "Theme design is temporarily unavailable. Please try again later."
        }
    }
}
