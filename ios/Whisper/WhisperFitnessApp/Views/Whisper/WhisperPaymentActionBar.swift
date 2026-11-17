import SwiftUI

struct WhisperPaymentActionBar: View {
    let title: String
    let isBusy: Bool
    let isDisabled: Bool
    let refreshDisabled: Bool
    let action: () -> Void
    let refresh: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 2) {
            Button(action: action) {
                HStack(spacing: 10) {
                    if isBusy { ProgressView().tint(WhisperTheme.surface(colorScheme)) }
                    Text(isBusy ? "One moment…" : title).font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16).padding(.vertical, 17)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 23, style: .continuous))
                .foregroundStyle(WhisperTheme.surface(colorScheme))
            }
            .buttonStyle(.plain).disabled(isDisabled)
            Button("Already purchased? Refresh access", action: refresh)
                .font(.caption).frame(minHeight: 44).disabled(refreshDisabled)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.horizontal, 20).padding(.top, 12)
        .frame(maxWidth: 560).frame(maxWidth: .infinity)
        .background(WhisperTheme.surface(colorScheme))
        .overlay(alignment: .top) { Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(height: 0.5) }
    }
}
