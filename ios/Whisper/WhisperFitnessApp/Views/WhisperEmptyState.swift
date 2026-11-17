import SwiftUI

/// Successful empty content uses the same native pastel drawing as empty meeting
/// days. Callers own loading, access and failure states; emptiness is not failure.
struct WhisperEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var isCard: Bool = true
    var compact: Bool = false
    var illustration: WhisperIllustrationKind? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            WhisperMeetDoodle(symbol: icon, height: compact ? 96 : 144, illustration: illustration)
                .frame(maxWidth: 300)
            VStack(spacing: 6) {
                Text(title)
                    .font(compact ? .headline : .title3.bold())
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .accessibilityAddTraits(.isHeader)
                if !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 22)
                        .frame(minHeight: 44)
                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(compact ? 16 : 22)
        .frame(maxWidth: .infinity)
        .background(isCard ? WhisperTheme.card(colorScheme) : Color.clear, in: .rect(cornerRadius: 24))
        .overlay {
            if isCard {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
            }
        }
    }
}

/// Compatibility entry for profile grids; artwork never waits on an entrance
/// animation or network request, including when the profile is preloaded.
struct WhisperProfileEmptyState: View {
    var illustration: WhisperIllustrationKind = .photos
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        WhisperEmptyState(icon: "photo.on.rectangle", title: title, message: message,
            actionTitle: actionTitle, action: action, illustration: illustration)
    }
}
