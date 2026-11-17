import Foundation

/// Shared-post canvas appearance. Images stay local until the story is posted.
nonisolated enum WhisperStoryBackgroundSelection: Codable, Equatable, Sendable {
    case blurred
    case color(String)
    case photo
}
