import SwiftUI

/// Shared, reachable chrome for the Story's focused editors.
struct WhisperStoryToolHeader: View {
    var title: String = ""
    var inline: Bool = false
    var confirmation: String = "Done"
    var canConfirm: Bool = true
    var onConfirm: (() -> Void)? = nil
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if inline {
                Button("Cancel", action: onCancel).font(.subheadline.weight(.medium)).frame(minWidth: 64, minHeight: 44)
            } else { WhisperStoryControl(symbol: "xmark", label: "Cancel", action: onCancel) }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if let onConfirm {
                Button(action: onConfirm) {
                    Text(confirmation)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .foregroundStyle(inline ? .white : .black)
                        .background(inline ? Color.clear : .white.opacity(canConfirm ? 1 : 0.35), in: .capsule)
                        .opacity(canConfirm ? 1 : 0.45)
                }
                .disabled(!canConfirm)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .fixedSize(horizontal: false, vertical: true)
    }
}
