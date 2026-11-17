import UIKit

/// A frozen, editor-owned upload attempt. Retrying never silently publishes different edits under the same ID.
struct WhisperStoryPublication {
    let image: UIImage
    let metadata: String?
    let music: WhisperStoryMusic?
    let videoURL: URL?
    let uploader: WhisperWaveUploadService = WhisperWaveUploadService()
}
