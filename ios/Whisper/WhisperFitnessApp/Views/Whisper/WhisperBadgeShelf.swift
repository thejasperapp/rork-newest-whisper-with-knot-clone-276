import SwiftUI

/// Full horizontal list of every trust & identity chip a user has earned,
/// rendered as a row of labelled pills on the profile page. The inline
/// `VerifiedBadge` strip next to the username only shows the top 2 chips
/// to avoid clutter — this shelf is where the rest live so people can
/// still see them.
///
/// Tapping any chip (or the info "i" button on the right) opens the
/// `WhisperBadgeInfoSheet` explainer so other users know exactly what
/// each badge means.
struct WhisperBadgeShelf: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Username this shelf is rendered for. Keys the Liar Liar lookup.
    let username: String?
    /// User id — keys every safety / reputation flag.
    let userID: String?

    @State private var liar = WhisperLiarLiarService.shared
    @State private var safety = WhisperSafetyService.shared
    @State private var presentInfo: Bool = false
    @State private var focusedKind: WhisperBadgeKind?

    private var chips: [WhisperBadgeKind] {
        WhisperBadgeKind.active(forUsername: username, userID: userID, liar: liar, safety: safety)
    }

    var body: some View {
        if chips.isEmpty {
            // Even when there are no chips, surface the info button so new
            // users can still learn what badges exist on the platform.
            infoOnlyRow
        } else {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(chips.enumerated()), id: \.offset) { _, kind in
                            chipPill(kind)
                        }
                    }
                }
                infoButton
            }
            .padding(.horizontal, 16)
            .sheet(isPresented: $presentInfo) {
                WhisperBadgeInfoSheet(highlight: focusedKind)
            }
        }
    }

    private var infoOnlyRow: some View {
        HStack {
            Spacer()
            infoButton
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $presentInfo) {
            WhisperBadgeInfoSheet(highlight: focusedKind)
        }
    }

    private var infoButton: some View {
        Button {
            Haptics.tap()
            focusedKind = nil
            presentInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About badges")
    }

    private func chipPill(_ kind: WhisperBadgeKind) -> some View {
        Button {
            Haptics.tap()
            focusedKind = kind
            presentInfo = true
        } label: {
            HStack(spacing: 6) {
                kind.view(size: 14, liar: liar)
                Text(kind.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(WhisperTheme.card(colorScheme))
                    .overlay(
                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WhisperBadgeShelf(username: "preview", userID: nil)
        .padding()
}
