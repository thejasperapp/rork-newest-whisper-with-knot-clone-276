import SwiftUI
import PhotosUI

/// Frozen media selected explicitly for the existing post review/publish flow.
struct WhisperCapturePostHandoff: Identifiable {
    let id: UUID = UUID()
    let photos: [Data]
    let items: [PhotosPickerItem]
}
