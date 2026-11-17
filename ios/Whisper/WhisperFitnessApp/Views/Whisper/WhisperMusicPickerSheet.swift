import SwiftUI
import MediaPlayer

/// System Apple Music library picker wrapped for SwiftUI. Lets the user
/// browse their actual music library (same UI as the Music app) and pick a
/// song to attach to a Whisper post. The selection comes back as a display
/// string ("Title \u2014 Artist") which we render as an Instagram-style audio tag.
///
/// Requires `NSAppleMusicUsageDescription` in Info.plist.
struct WhisperMusicPickerSheet: UIViewControllerRepresentable {
    let onPick: (String) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = false
        picker.showsCloudItems = true
        picker.showsItemsWithProtectedAssets = true
        picker.prompt = "Pick a song to share"
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let onPick: (String) -> Void
        let onCancel: () -> Void
        init(onPick: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        nonisolated func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
            let item = mediaItemCollection.items.first
            let title = item?.title ?? "Untitled"
            let artist = item?.artist
            let display: String
            if let artist, !artist.isEmpty {
                display = "\(title) \u{2014} \(artist)"
            } else {
                display = title
            }
            Task { @MainActor in
                self.onPick(display)
            }
        }

        nonisolated func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            Task { @MainActor in
                self.onCancel()
            }
        }
    }
}
