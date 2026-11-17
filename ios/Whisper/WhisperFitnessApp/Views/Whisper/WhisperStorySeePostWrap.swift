import SwiftUI

/// Instagram's two-tap grammar for a post or wave shared into a story: the
/// FIRST tap on the card arms a "See post ›" pill in its top-right corner
/// (it fades out again after a few seconds); tapping the PILL opens the
/// original. A shared post never yanks you out of the story by accident.
struct WhisperStorySeePostWrap<Content: View>: View {
    let label: String
    let onOpen: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var armed: Bool = false
    @State private var disarmTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                let h = UIImpactFeedbackGenerator(style: .light)
                h.impactOccurred()
                arm()
            } label: {
                content()
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if armed {
                Button {
                    let h = UIImpactFeedbackGenerator(style: .medium)
                    h.impactOccurred()
                    disarmTask?.cancel()
                    onOpen()
                } label: {
                    HStack(spacing: 4) {
                        Text(label)
                            .font(.system(size: 15, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.top, 44)
                .padding(.trailing, -14)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: armed)
    }

    private func arm() {
        disarmTask?.cancel()
        armed = true
        disarmTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            armed = false
        }
    }
}
