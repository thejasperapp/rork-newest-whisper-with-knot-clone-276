import SwiftUI

/// Instagram-style "Discover people" sheet. Replaces the legacy `FriendsView`
/// in places where the only useful action is to find new accounts to follow
/// on Whisper.
///
/// The list shows recently-onboarded Whisper accounts. Each row has a
/// follow / following toggle wired straight into `WhisperFollowService`.
/// Tapping a row opens the user's full Whisper profile.
struct WhisperFollowSuggestionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var follows = WhisperFollowService.shared
    @State private var suggestions: [WhisperUserRow] = []
    @State private var query: String = ""
    @State private var isLoading: Bool = true
    @State private var openUser: WhisperUserRow?

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        searchField
                        if isLoading && suggestions.isEmpty {
                            ProgressView()
                                .tint(WhisperTheme.ink(colorScheme))
                                .padding(.top, 40)
                        } else if filtered.isEmpty {
                            emptyState
                        } else {
                            list
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Suggested for you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .task {
                await follows.refresh()
                suggestions = await WhisperUserService.shared.suggestions(limit: 50)
                isLoading = false
            }
            .whisperRefreshable {
                await follows.refresh()
                suggestions = await WhisperUserService.shared.suggestions(limit: 50)
            }
            .navigationDestination(item: $openUser) { u in
                WhisperUserProfileView(user: u)
            }
        }
    }

    private var filtered: [WhisperUserRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return suggestions }
        return suggestions.filter {
            $0.username.lowercased().contains(q)
                || ($0.display_name?.lowercased().contains(q) ?? false)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Search Whisper", text: $query)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            WhisperMeetDoodle(symbol: "person.2", height: 120)
            Text("No suggestions yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Once people join Whisper, they'll appear here.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, u in
                row(u)
                if idx < filtered.count - 1 {
                    Divider().background(WhisperTheme.hairline(colorScheme))
                        .padding(.leading, 70)
                }
            }
        }
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private func row(_ u: WhisperUserRow) -> some View {
        let followed = follows.isFollowing(userID: u.user_id)
        let url = u.profile_image_url.flatMap(URL.init(string:))
        return HStack(spacing: 12) {
            Button {
                Haptics.tap()
                openUser = u
            } label: {
                HStack(spacing: 12) {
                    WhisperAvatar(username: u.username, size: 44, imageURL: url, ring: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(u.display_name?.isEmpty == false ? u.display_name! : u.username)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .lineLimit(1)
                        Text("@\(u.username)")
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button {
                Haptics.tap()
                Task {
                    if followed { await follows.unfollow(userID: u.user_id) }
                    else { await follows.follow(userID: u.user_id, username: u.username) }
                }
            } label: {
                Text(followed ? "Following" : "Follow")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(followed ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(followed ? WhisperTheme.card(colorScheme) : WhisperTheme.ink(colorScheme), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: followed ? 1 : 0)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
