import SwiftUI
import Supabase

// MARK: - Coach directory

/// Tiny read-only directory of verified coaches — powers the "Coaches to
/// hire" feed shelf. Coaches are `whisper_profiles.is_coach = true` rows.
enum WhisperCoachDirectory {
    static func fetchCoaches(limit: Int = 12) async -> [WhisperUserRow] {
        do {
            let rows: [WhisperUserRow] = try await SupabaseService.shared.client
                .from("whisper_profiles")
                .select("user_id,username,display_name,bio,interests,profile_image_url,onboarded_at,is_private")
                .eq("is_coach", value: true)
                .limit(limit)
                .execute()
                .value
            let me = AccountStorage.currentUserID.lowercased()
            return rows.filter { !$0.username.isEmpty && $0.user_id.lowercased() != me }
        } catch {
            return []
        }
    }
}

// MARK: - Getting started checklist

/// New-user "tips" card near the top of the feed — a living checklist that
/// ticks itself off as the user completes each first step (bio, community,
/// first post, first reel, contact sync, Jasper link). Dismissible, and it
/// retires automatically once everything is done or the account matures.
struct WhisperGettingStartedCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var users = WhisperUserService.shared
    @State private var backend = WhisperBackendService.shared

    @AppStorage("whisper.gettingStarted.dismissed") private var dismissed: Bool = false
    @AppStorage("whisper.gettingStarted.contactsSynced") private var contactsSynced: Bool = false

    @State private var activeSheet: Sheet?

    private enum Sheet: String, Identifiable {
        case editProfile, communities, findFriends, jasperSettings
        var id: String { rawValue }
    }

    private struct Item: Identifiable {
        let id: String
        let icon: String
        let title: String
        let subtitle: String
        let done: Bool
    }

    private var mint: Color { WhisperEmberPillPalette.glow }
    private var myID: String { AccountStorage.currentUserID.lowercased() }

    private var myPosts: [WhisperPostRow] {
        backend.posts.filter { $0.user_id.lowercased() == myID }
    }

    private var hasBio: Bool {
        !(users.me?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var joinedCommunity: Bool {
        let catalogNames = Set(WhisperCommunity.catalog.map { $0.name.lowercased() })
        let mine = Set((users.me?.interests ?? []).map { $0.lowercased() })
        return !mine.isDisjoint(with: catalogNames)
    }

    private var hasPost: Bool { !myPosts.isEmpty }
    private var hasReel: Bool { myPosts.contains { $0.is_reel ?? false } }
    private var jasperLinked: Bool { JasperConnectClient.shared.connection != nil }

    private var items: [Item] {
        [
            Item(id: "bio", icon: "text.alignleft", title: "Write your bio",
                 subtitle: "One line about your training", done: hasBio),
            Item(id: "community", icon: "person.3.fill", title: "Join a community",
                 subtitle: "Find your people", done: joinedCommunity),
            Item(id: "post", icon: "square.and.pencil", title: "Make your first post",
                 subtitle: "Quiet wins. Loud progress.", done: hasPost),
            Item(id: "reel", icon: "play.rectangle.fill", title: "Post your first reel",
                 subtitle: "15 seconds is plenty", done: hasReel),
            Item(id: "contacts", icon: "person.crop.circle.badge.plus", title: "Sync your contacts",
                 subtitle: "Find friends privately", done: contactsSynced),
            Item(id: "jasper", icon: "sparkles", title: "Link your Jasper account",
                 subtitle: "Unlocks Jasper Circle + real-data answers", done: jasperLinked),
        ]
    }

    private var doneCount: Int { items.filter(\.done).count }

    /// Fresh accounts only — onboarded within 45 days, or (no timestamp)
    /// accounts that haven't posted yet.
    private var isNewish: Bool {
        if let stamp = users.me?.onboarded_at,
           let date = WhisperBackendService.parseISO(stamp) {
            return Date().timeIntervalSince(date) < 45 * 24 * 3600
        }
        return myPosts.isEmpty
    }

    private var visible: Bool {
        !dismissed && doneCount < items.count && isNewish
    }

    var body: some View {
        if visible {
            VStack(alignment: .leading, spacing: 0) {
                header
                progressTrack
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        itemRow(item)
                        if idx < items.count - 1 {
                            Divider()
                                .background(WhisperTheme.hairline(colorScheme))
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .padding(.vertical, 12)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(mint.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: mint.opacity(0.10), radius: 12, y: 4)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .editProfile:
                    WhisperEditProfileView()
                case .communities:
                    NavigationStack { WhisperCommunitiesView() }
                case .findFriends:
                    WhisperFindFriendsView()
                case .jasperSettings:
                    WhisperSettingsView()
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            WhisperEmberBadge(size: 26, isActive: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("GET STARTED")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(mint)
                Text("Make Whisper yours")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            Spacer()
            Text("\(doneCount)/\(items.count)")
                .font(.caption.weight(.black).monospacedDigit())
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    dismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .frame(width: 26, height: 26)
                    .background(WhisperTheme.surface(colorScheme), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss checklist")
        }
        .padding(.horizontal, 14)
    }

    private var progressTrack: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WhisperTheme.hairline(colorScheme))
                Capsule()
                    .fill(mint)
                    .frame(width: max(8, geo.size.width * CGFloat(doneCount) / CGFloat(max(1, items.count))))
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: doneCount)
            }
        }
        .frame(height: 5)
    }

    private func itemRow(_ item: Item) -> some View {
        Button {
            Haptics.tap()
            guard !item.done else { return }
            handleTap(item.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.done ? "checkmark" : item.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(item.done ? Color.white : mint)
                    .frame(width: 28, height: 28)
                    .background(item.done ? mint : mint.opacity(0.12), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(
                            item.done
                                ? WhisperTheme.muted(colorScheme)
                                : WhisperTheme.ink(colorScheme)
                        )
                        .strikethrough(item.done, color: WhisperTheme.muted(colorScheme))
                    Text(item.subtitle)
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if !item.done {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(item.done)
    }

    private func handleTap(_ id: String) {
        switch id {
        case "bio":
            activeSheet = .editProfile
        case "community":
            activeSheet = .communities
        case "post", "reel":
            WhisperEmberActionRouter.shared.openComposer(draft: "")
        case "contacts":
            contactsSynced = true
            activeSheet = .findFriends
        case "jasper":
            activeSheet = .jasperSettings
        default:
            break
        }
    }
}

// MARK: - Coaches to hire shelf

/// "Coaches to hire" inline shelf — same native break pattern as the reels
/// and people-to-follow carousels. Long-press a card for quick actions.
struct FeedCoachesCarousel: View {
    let coaches: [WhisperUserRow]
    let follows: WhisperFollowService
    let onOpenUser: (WhisperUserRow) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var mint: Color { WhisperEmberPillPalette.glow }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(coaches.prefix(10)) { c in
                        card(c)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 14)
        .background(WhisperTheme.surface(colorScheme))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Coaches to hire")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer()
            Text("Real plans, real people")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func card(_ u: WhisperUserRow) -> some View {
        let followed = follows.isFollowing(userID: u.user_id)
        let avatarURL = u.profile_image_url.flatMap(URL.init(string:))
        let name = (u.display_name?.isEmpty == false ? u.display_name! : u.username)
        return VStack(spacing: 9) {
            Button {
                Haptics.tap()
                onOpenUser(u)
            } label: {
                VStack(spacing: 7) {
                    WhisperAvatar(username: u.username, size: 62, imageURL: avatarURL, ring: false)
                    Text(name)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    Text("COACH")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.1)
                        .foregroundStyle(mint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(mint.opacity(0.12), in: Capsule())
                    Text(u.bio?.isEmpty == false ? u.bio! : "Training plans & check-ins")
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                        .frame(width: 118)
                }
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                onOpenUser(u)
            } label: {
                Text("View profile")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 146)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .contextMenu {
            Button {
                onOpenUser(u)
            } label: {
                Label("View profile", systemImage: "person.crop.circle")
            }
            Button {
                Task {
                    if followed {
                        await follows.unfollow(userID: u.user_id)
                    } else {
                        await follows.follow(userID: u.user_id, username: u.username)
                    }
                }
            } label: {
                Label(followed ? "Unfollow" : "Follow", systemImage: followed ? "person.badge.minus" : "person.badge.plus")
            }
        }
    }
}
