import SwiftUI

/// Inline banner shown at the top of a DM thread whenever the viewer is an
/// adult and the other participant is a teen (or vice-versa with a 3+ year
/// gap). Lets both sides know Jasper is silently monitoring for safety so the
/// deterrent effect kicks in *before* anything inappropriate is sent.
///
/// Renders nothing when both users are in the same age band, when either
/// band is unknown, or when the viewer dismisses it for the thread.
struct WhisperTeenSafetyBanner: View {
    let viewerUserID: String
    let otherUserID: String
    let otherUsername: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var safety = WhisperSafetyService.shared
    @State private var dismissed: Bool = false

    private var shouldShow: Bool {
        guard !dismissed else { return false }
        return safety.shouldScan(senderUserID: viewerUserID, recipientUserID: otherUserID)
    }

    private var viewerIsAdult: Bool { safety.isAdult(userID: viewerUserID) }

    var body: some View {
        if shouldShow {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.10, green: 0.58, blue: 0.34))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewerIsAdult ? "Teen account" : "Adult account")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(bodyText)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Button {
                    Haptics.tap()
                    withAnimation(.easeInOut(duration: 0.2)) { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.18, green: 0.78, blue: 0.45).opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(red: 0.18, green: 0.78, blue: 0.45).opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var bodyText: String {
        if viewerIsAdult {
            return "@\(otherUsername) is under 18. Jasper silently checks messages here for safety. Keep it respectful — strikes are reviewed by moderators."
        } else {
            return "@\(otherUsername) is an adult. Jasper silently watches this chat to keep you safe. If anything feels off, hit the report icon."
        }
    }
}
