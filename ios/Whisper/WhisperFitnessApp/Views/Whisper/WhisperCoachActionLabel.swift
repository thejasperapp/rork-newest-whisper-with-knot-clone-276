import SwiftUI

/// Coaching actions share profile typography without changing request or purchase rules.
struct WhisperCoachActionLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    var prominent: Bool = false
    @Environment(\.colorScheme) private var scheme
    private var ink: Color { prominent ? WhisperTheme.surface(scheme) : WhisperTheme.ink(scheme) }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20, weight: .regular)).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(ink.opacity(0.65))
            }.multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if prominent { Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
        }.foregroundStyle(ink).padding(.horizontal, 16).padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(prominent ? WhisperTheme.ink(scheme) : WhisperTheme.card(scheme), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(WhisperTheme.hairline(scheme), lineWidth: prominent ? 0 : 0.75) }
    }
}
