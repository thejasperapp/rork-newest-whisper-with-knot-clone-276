import SwiftUI

struct WhisperPaymentBenefit: View {
    let symbol: String
    let title: String
    let detail: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.body.weight(.medium))
                .frame(width: 24, height: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(WhisperTheme.ink(colorScheme))
    }
}
