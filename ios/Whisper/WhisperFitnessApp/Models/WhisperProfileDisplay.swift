import Foundation

/// Only identity artwork and self-authored display text; excludes account grants and onboarding state.
nonisolated struct WhisperProfileDisplay: Codable, Sendable, Equatable {
    let user_id: String
    let username: String
    let display_name: String?
    let bio: String?
    let interests: [String]?
    let profile_image_url: String?
    let professional_category: String?

    init(_ row: WhisperUserRow) {
        user_id = row.user_id
        username = row.username
        display_name = row.display_name
        bio = row.bio
        interests = row.interests
        profile_image_url = row.profile_image_url
        professional_category = row.professional_category
    }
}
