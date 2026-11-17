import SwiftUI

/// The photo itself bridges the cover and the edge-to-edge details sheet.
struct WhisperProfileIdentityView<Avatar: View, Stats: View>: View {
    let displayName: String
    var username: String? = nil
    var onSwitchAccount: (() -> Void)? = nil
    var biography: AnyView? = nil
    /// Explicit app-owned branding; never inferred from a user's chosen name.
    var nameArtwork: AnyView? = nil
    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let stats: () -> Stats
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 14) {
            avatar()
                // A narrow portrait rim, not an extra raised backing disc.
                .background {
                    // Behind all avatar chrome so the rim cannot slash across +.
                    Circle().stroke(WhisperTheme.surface(colorScheme), lineWidth: 4)
                        .allowsHitTesting(false)
                }
                .zIndex(1)
            HStack(spacing: 6) {
                if onSwitchAccount != nil { Color.clear.frame(width: 44, height: 44).accessibilityHidden(true) }
                if let nameArtwork {
                    nameArtwork
                } else {
                    Text(displayName)
                        .font(.title.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .multilineTextAlignment(.center)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                }
                if let username {
                    VerifiedBadge(
                        badge: UserVerificationService.shared.badge(forUsername: username),
                        size: 18,
                        username: username
                    )
                }
                if let onSwitchAccount {
                    Button(action: onSwitchAccount) {
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Switch account")
                }
            }
            VStack(spacing: 10) {
                if let username {
                    Text("@\(username)")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .textSelection(.enabled)
                }
                if let username { WhisperProfessionalRolesText(username: username) }
                biography
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            stats().frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, -96)
        .padding(.bottom, 4)
    }
}
