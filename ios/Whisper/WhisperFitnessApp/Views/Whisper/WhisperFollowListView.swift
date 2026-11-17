import SwiftUI
import Supabase

/// Instagram-style Followers / Following list, backed by the real
/// `whisper_follows` table. Tapping a row opens that user's Whisper profile;
/// tapping Message opens a DM thread. Redesigned with larger avatars, clean
/// typography, and clear follow actions.
struct WhisperFollowListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let userID: String
    let username: String
    let initialTab: Tab

    enum Tab: String, CaseIterable, Hashable, Identifiable {
        case followers = "Followers"
        case following = "Following"
        var id: String { rawValue }
    }

    @State private var follows = WhisperFollowService.shared
    @State private var users = WhisperUserService.shared
    @State private var tab: Tab
    @State private var followerRows: [WhisperFollowRow] = []
    @State private var followingRows: [WhisperFollowRow] = []
    @State private var profileByID: [String: WhisperUserRow] = [:]
    @State private var loading: Bool = false
    /// True while usernames/avatars are being hydrated — rows render as
    /// shimmer skeletons instead of flashing a fake "@user" placeholder.
    @State private var hydrating: Bool = false
    @State private var query: String = ""
    @State private var openThread: WhisperConversationSummary?
    @State private var openProfile: WhisperUserRow?
    /// Follower pending removal — set from the row's long-press menu,
    /// confirmed via alert before the edge is actually deleted.
    @State private var confirmRemove: WhisperFollowRow?

    init(userID: String, username: String, initialTab: Tab = .followers) {
        self.userID = userID
        self.username = username
        self.initialTab = initialTab
        _tab = State(initialValue: initialTab)
    }

    private var rows: [WhisperFollowRow] {
        tab == .followers ? followerRows : followingRows
    }

    private var filteredRows: [WhisperFollowRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter { row in
            let name = (tab == .followers ? cachedUsername(forUserID: row.follower_id) : row.followee_username).lowercased()
            let otherID = tab == .followers ? row.follower_id : row.followee_id
            let profile = profileByID[otherID.lowercased()]
            return WhisperUserSearch.matches(q, username: profile?.username ?? name, displayName: profile?.display_name)
        }
    }

    private func cachedUsername(forUserID id: String) -> String {
        if let u = profileByID[id.lowercased()]?.username,
           !u.isEmpty, u.lowercased() != "user" {
            return u
        }
        return "user"
    }

    private func bestUsername(forUserID id: String, stored: String) -> String {
        if let u = profileByID[id.lowercased()]?.username,
           !u.isEmpty, u.lowercased() != "user" {
            return u
        }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "user" : trimmed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                VStack(spacing: 0) {
                    segmented
                    searchField
                    if loading && rows.isEmpty {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.1)
                            .padding(.top, 80)
                        Spacer()
                    } else if filteredRows.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredRows, id: \.self) { row in
                                    rowView(row)
                                }
                            }
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .navigationTitle("@\(username)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .accessibilityLabel("Done")
                }
            }
            .task { await load() }
            .whisperRefreshable { await load() }
            .alert("Remove follower?", isPresented: Binding(
                get: { confirmRemove != nil },
                set: { if !$0 { confirmRemove = nil } }
            )) {
                Button("Remove", role: .destructive) {
                    if let row = confirmRemove {
                        let id = row.follower_id
                        Task {
                            let ok = await follows.removeFollower(userID: id)
                            if ok {
                                withAnimation(.whisperSnappy) {
                                    followerRows.removeAll { $0.follower_id == id }
                                }
                                Haptics.success()
                            } else {
                                Haptics.warning()
                            }
                        }
                    }
                    confirmRemove = nil
                }
                Button("Cancel", role: .cancel) { confirmRemove = nil }
            } message: {
                Text("They won't be notified, and they can follow you again later.")
            }
            .fullScreenCover(item: $openThread) { thread in
                WhisperDMThreadView(otherUserID: thread.otherUserID, otherUsername: thread.otherUsername)
            }
            .navigationDestination(item: $openProfile) { user in
                WhisperUserProfileView(user: user)
            }
        }
    }

    private var segmented: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3)) { tab = t }
                } label: {
                    let count = t == .followers ? followerRows.count : followingRows.count
                    VStack(spacing: 4) {
                        Text(t.rawValue)
                            .font(.subheadline.weight(.semibold))
                        Text("\(count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tab == t ? WhisperTheme.surface(colorScheme).opacity(0.8) : WhisperTheme.muted(colorScheme))
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(tab == t ? WhisperTheme.ink(colorScheme) : Color.clear, in: .rect(cornerRadius: 12))
                    .foregroundStyle(tab == t ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Search", text: $query)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func rowView(_ row: WhisperFollowRow) -> some View {
        let otherID = tab == .followers ? row.follower_id : row.followee_id
        let profile = profileByID[otherID.lowercased()]
        // While profiles hydrate, followers rows have no username yet —
        // show a shimmer skeleton instead of a fake "@user".
        if profile == nil && hydrating && tab == .followers {
            skeletonRow
        } else {
            resolvedRow(row, otherID: otherID, profile: profile)
        }
    }

    /// Placeholder row shown while the profile lookup is in flight.
    private var skeletonRow: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(WhisperTheme.card(colorScheme))
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(WhisperTheme.card(colorScheme))
                    .frame(width: 120, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(WhisperTheme.card(colorScheme))
                    .frame(width: 80, height: 9)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func resolvedRow(_ row: WhisperFollowRow, otherID: String, profile: WhisperUserRow?) -> some View {
        let otherName = tab == .followers
            ? cachedUsername(forUserID: otherID)
            : bestUsername(forUserID: otherID, stored: row.followee_username)
        let imageURL = profile?.profile_image_url.flatMap(URL.init(string:))
        let isFollowedByMe = follows.isFollowing(userID: otherID)
        let isMe = otherID == AccountStorage.currentUserID

        HStack(spacing: 14) {
            Button {
                Haptics.tap()
                openProfile = profile ?? WhisperUserRow(
                    user_id: otherID,
                    username: otherName,
                    display_name: nil,
                    bio: nil,
                    interests: nil,
                    profile_image_url: nil,
                    onboarded_at: nil,
                    is_private: nil
                )
            } label: {
                HStack(spacing: 14) {
                    WhisperAvatar(username: otherName, size: 52, imageURL: imageURL, ring: false)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("@\(otherName)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .lineLimit(1)
                            VerifiedBadge(
                                badge: UserVerificationService.shared.badge(forUsername: otherName),
                                size: 12,
                                username: otherName
                            )
                        }
                        if let dn = profile?.display_name, !dn.isEmpty {
                            Text(dn)
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .lineLimit(1)
                        } else if let bio = profile?.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if !isMe {
                HStack(spacing: 10) {
                    Button {
                        Haptics.tap()
                        openThread = WhisperConversationSummary(
                            otherUserID: otherID,
                            otherUsername: otherName,
                            lastMessage: "",
                            lastDate: Date()
                        )
                    } label: {
                        Image(systemName: "ellipsis.bubble")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .frame(width: 34, height: 34)
                            .background(WhisperTheme.card(colorScheme), in: Circle())
                            .overlay { Circle().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Message")

                    // One reactive follow state everywhere: if I follow
                    // them → "Following" (tap unfollows IN PLACE — the row
                    // stays and flips to Follow so the action is undoable).
                    // If I don't → "Follow" / "Follow back" on my own
                    // followers tab.
                    if isFollowedByMe {
                        Button {
                            Haptics.tap()
                            Task { await follows.unfollow(userID: otherID) }
                        } label: {
                            Text("Following")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(WhisperTheme.card(colorScheme), in: Capsule())
                                .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            Haptics.tap()
                            Task { await follows.follow(userID: otherID, username: otherName) }
                        } label: {
                            Text(isOwnList && tab == .followers ? "Follow back" : "Follow")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WhisperTheme.surface(colorScheme))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(WhisperTheme.ink(colorScheme), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(WhisperTheme.surface(colorScheme))
        .overlay(alignment: .bottom) {
            Divider()
                .background(WhisperTheme.hairline(colorScheme))
                .padding(.leading, 82)
        }
        .contextMenu {
            if isOwnList && tab == .followers && !isMe {
                Button(role: .destructive) {
                    confirmRemove = row
                } label: {
                    Label("Remove follower", systemImage: "person.badge.minus")
                }
            }
        }
    }

    private var isOwnList: Bool { userID == AccountStorage.currentUserID }

    private var emptyState: some View {
        VStack(spacing: 10) {
            WhisperMeetDoodle(symbol: "person.2", height: 144)
            Text(tab == .followers ? "No followers yet" : "Not following anyone yet")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text(tab == .followers
                 ? "When people follow @\(username), they'll appear here."
                 : "Follows will show up here.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        loading = true
        async let fol: [WhisperFollowRow] = follows.followers(forUserID: userID)
        async let foll: [WhisperFollowRow] = follows.following(forUserID: userID)
        let (a, b) = await (fol, foll)
        followerRows = a
        followingRows = b
        loading = false
        hydrating = true
        await hydrateProfiles()
        hydrating = false
    }

    private func hydrateProfiles() async {
        var needed: [String: String] = [:]
        for r in followerRows { needed[r.follower_id.lowercased()] = r.follower_id }
        for r in followingRows { needed[r.followee_id.lowercased()] = r.followee_id }
        let missing = Set(needed.keys).subtracting(profileByID.keys)
        guard !missing.isEmpty else { return }
        let rows = await fetchProfiles(ids: missing.compactMap { needed[$0] })
        for row in rows { profileByID[row.user_id.lowercased()] = row }
        // Warm the verification cache so the badge next to each name
        // renders on first paint.
        await UserVerificationService.shared.preload(usernames: rows.map { $0.username })
    }

    private func fetchProfiles(ids: [String]) async -> [WhisperUserRow] {
        guard !ids.isEmpty else { return [] }
        do {
            let rows: [WhisperUserRow] = try await SupabaseService.shared.client
                .from("whisper_profiles")
                .select()
                .in("user_id", values: ids)
                .execute()
                .value
            return rows
        } catch {
            return []
        }
    }
}
