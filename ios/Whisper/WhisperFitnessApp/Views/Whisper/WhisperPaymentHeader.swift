import SwiftUI

struct WhisperPaymentHeader: View {
    let title: String
    let symbol: String
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.subheadline.weight(.bold))
                .frame(width: 30, height: 30)
                .background(WhisperTheme.card(colorScheme), in: Circle())
            Text(title).font(.subheadline.weight(.semibold))
            Spacer(minLength: 4)
            Button(action: close) {
                Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44).contentShape(Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Close")
        }
        .foregroundStyle(WhisperTheme.ink(colorScheme))
        .padding(.leading, 24).padding(.trailing, 12).padding(.top, 8)
        .background(WhisperTheme.surface(colorScheme))
    }
}
