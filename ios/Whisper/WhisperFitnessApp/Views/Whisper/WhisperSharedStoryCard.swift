import SwiftUI

/// A neutral reference card deliberately avoids unfurling restricted or expired media in a chat.
struct WhisperSharedStoryCard: View {
    let storyID: String
    @State private var isOpen: Bool = false
    @State private var generation: UUID = AccountStorage.generation

    var body: some View {
        Button {
            guard generation == AccountStorage.generation else { return }
            Haptics.tap(); isOpen = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "circle.dashed.inset.filled")
                    .font(.system(size: 27, weight: .medium)).frame(width: 52, height: 64)
                    .background(.primary.opacity(0.06), in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Shared a story").font(.subheadline.weight(.semibold))
                    Text("Open while it's available").font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
            }.padding(12)
                .background(.regularMaterial, in: .rect(cornerRadius: 22))
                .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.1), lineWidth: 1) }
        }
        .buttonStyle(.plain).accessibilityLabel("Open shared Story")
        .fullScreenCover(isPresented: $isOpen) { WhisperReferencedStoryView(storyID: storyID) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in isOpen = false }
    }
}
