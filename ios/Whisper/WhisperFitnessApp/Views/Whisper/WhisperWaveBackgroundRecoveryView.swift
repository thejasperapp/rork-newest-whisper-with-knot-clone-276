import SwiftUI

/// Recovery for an existing take/draft, not a second background-selection tool.
struct WhisperWaveBackgroundRecoveryView: View {
    let remove: () -> Void
    @State private var confirm: Bool = false
    var body: some View {
        Button("Remove recorded background…") { confirm = true }
            .font(.caption).frame(minHeight: 44)
            .confirmationDialog("Show the original surroundings?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Remove background", role: .destructive, action: remove)
                Button("Keep background", role: .cancel) { }
            } message: {
                Text("This exposes the original room in this clip. Other edits remain. Choose backgrounds for new takes in Record Wave.")
            }
    }
}
