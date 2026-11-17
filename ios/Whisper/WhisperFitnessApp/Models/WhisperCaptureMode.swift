import Foundation

nonisolated enum WhisperCaptureMode: String, CaseIterable, Identifiable {
    case post = "Post", story = "Story", waves = "Waves", live = "Live"
    var id: String { rawValue }
}
