import SwiftUI

struct WhisperPinnedPostLabel: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Label("Pinned", systemImage: "pin.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(WhisperTheme.muted(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .accessibilityLabel("Pinned to this profile")
    }
}
