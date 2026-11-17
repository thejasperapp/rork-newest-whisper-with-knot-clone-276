import SwiftUI
import UIKit

/// Thin SwiftUI wrapper around `UIActivityViewController` for share/invite
/// flows. Used by Whisper profile invite and share sheets.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
