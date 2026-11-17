import SwiftUI

/// Settings screen — manage accounts the user has blocked.
struct WhisperBlockedAccountsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var blocks = WhisperBlockService.shared
    @State private var loading: Bool = true

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            if blocks.blocks.isEmpty && !loading {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(blocks.blocks) { row in
                            blockRow(row)
                            if row.id != blocks.blocks.last?.id {
                                Rectangle()
                                    .fill(WhisperTheme.hairline(colorScheme))
                                    .frame(height: 0.5)
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
        }
        .navigationTitle("Blocked accounts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await blocks.refresh()
            loading = false
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            WhisperMeetDoodle(symbol: "person.crop.circle.badge.xmark", height: 144)
            Text("Nobody blocked")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Accounts you block can't see your stories, posts, or DMs.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func blockRow(_ row: WhisperBlockRow) -> some View {
        HStack(spacing: 12) {
            WhisperAvatar(username: row.blocked_username, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(row.blocked_username)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Blocked")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Button {
                Haptics.tap()
                Task {
                    await blocks.unblock(userID: row.blocked_user_id, username: row.blocked_username)
                }
            } label: {
                Text("Unblock")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(WhisperTheme.surface(colorScheme), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
