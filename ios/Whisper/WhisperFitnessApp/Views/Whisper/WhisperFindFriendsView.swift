import SwiftUI
import Contacts

/// Find-Friends-from-Contacts sheet. Asks for Contacts permission, scans
/// the address book, hashes phone/email locally, queries Supabase for any
/// users with matching identity hashes, and lets the user follow them.
/// Anyone in the address book who isn't on Whisper shows up in an "Invite"
/// list that opens the system share sheet pre-filled with a join message.
struct WhisperFindFriendsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var contacts = WhisperContactsService.shared
    @State private var follows = WhisperFollowService.shared
    @State private var didLoad: Bool = false
    @State private var shareItem: ShareItem?
    @State private var openUser: WhisperUserRow?

    private struct ShareItem: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                content
            }
            .navigationTitle("Find friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .navigationDestination(item: $openUser) { user in
                WhisperUserProfileView(user: user)
            }
            .sheet(item: $shareItem) { item in
                WhisperInviteShareSheet(text: item.text)
            }
            .task {
                contacts.refreshPermission()
                if (contacts.permission == .authorized || contacts.permission == .limited), !didLoad {
                    didLoad = true
                    await contacts.publishMyIdentities()
                    await contacts.findFriends()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch contacts.permission {
        case .authorized, .limited:
            results
        case .denied, .restricted:
            denied
        case .notDetermined:
            permissionPrompt
        @unknown default:
            permissionPrompt
        }
    }

    private var permissionPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(.bottom, 4)
            Text("Find friends on Whisper")
                .font(.title2.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("We'll match your contacts against Whisper using one-way hashes. Your address book stays on your device — only matches come back.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 24)
            Button {
                Haptics.tap()
                Task {
                    let ok = await contacts.requestAccess()
                    if ok {
                        didLoad = true
                        await contacts.publishMyIdentities()
                        await contacts.findFriends()
                    }
                }
            } label: {
                Text("Connect contacts")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            Spacer()
        }
        .padding(.top, 40)
    }

    private var denied: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Text("Contacts access is off")
                .font(.title3.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Enable Contacts for Whisper in Settings to find friends already on the app.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 32)
            Button {
                Haptics.tap()
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            Spacer()
        }
        .padding(.top, 60)
    }

    @ViewBuilder
    private var results: some View {
        if contacts.isLoading && contacts.matches.isEmpty {
            VStack(spacing: 12) {
                ProgressView().tint(WhisperTheme.ink(colorScheme))
                Text("Looking for your people…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 18) {
                    if contacts.matches.isEmpty {
                        VStack(spacing: 8) {
                            WhisperMeetDoodle(symbol: "person.2", height: 120)
                            Text("No matches yet")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            Text("None of your contacts are on Whisper yet. Invite a few below.")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .padding(.horizontal, 32)
                        }
                        .padding(.top, 24)
                    } else {
                        matchesSection
                    }
                    inviteSection
                    Color.clear.frame(height: 24)
                }
                .padding(.top, 12)
            }
            .whisperRefreshable {
                await contacts.publishMyIdentities()
                await contacts.findFriends()
            }
        }
    }

    private var matchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("On Whisper")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                Text("\(contacts.matches.count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 16)
            VStack(spacing: 0) {
                ForEach(contacts.matches) { match in
                    matchRow(match)
                    if match.id != contacts.matches.last?.id {
                        Divider().background(WhisperTheme.hairline(colorScheme))
                    }
                }
            }
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .padding(.horizontal, 16)
        }
    }

    private func matchRow(_ match: WhisperContactMatch) -> some View {
        let user = match.profile
        let following = follows.isFollowing(userID: user.user_id)
        return Button {
            Haptics.tap()
            openUser = user
        } label: {
            HStack(spacing: 12) {
                WhisperAvatar(
                    username: user.username,
                    size: 44,
                    imageURL: user.profile_image_url.flatMap { URL(string: $0) }
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.contactName ?? (user.display_name ?? user.username))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    Text("@\(user.username)")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    Haptics.tap()
                    Task {
                        if following {
                            _ = await follows.unfollow(userID: user.user_id)
                        } else {
                            _ = await follows.follow(userID: user.user_id, username: user.username)
                        }
                    }
                } label: {
                    Text(following ? "Following" : "Follow")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(following ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(following ? WhisperTheme.card(colorScheme) : WhisperTheme.ink(colorScheme), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: following ? 1 : 0)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var inviteSection: some View {
        let invitePool = contacts.inviteCandidates
            .filter { c in
                // Hide contacts that already resolved to a Whisper account
                // (we matched their hash). Best-effort by name.
                !contacts.matches.contains(where: { ($0.contactName ?? "").caseInsensitiveCompare(c.name) == .orderedSame })
            }
            .prefix(40)
        if !invitePool.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Invite to Whisper")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Spacer()
                }
                .padding(.horizontal, 16)
                VStack(spacing: 0) {
                    ForEach(Array(invitePool), id: \.id) { contact in
                        inviteRow(contact)
                        if contact.id != invitePool.last?.id {
                            Divider().background(WhisperTheme.hairline(colorScheme))
                        }
                    }
                }
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func inviteRow(_ contact: WhisperInviteContact) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(WhisperTheme.muted(colorScheme).opacity(0.18))
                Text(String(contact.name.first ?? "?").uppercased())
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                if let detail = contact.phone ?? contact.email {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                Haptics.tap()
                let me = LeaderboardService.shared.savedUsername
                    ?? AuthenticationService.shared.currentUser.username
                    ?? "a friend"
                shareItem = ShareItem(text: "\(me) thinks you'd love Whisper — the quiet fitness community. Join here: https://www.mydailywhisper.com")
                Analytics.record("contact_invite_tap")
            } label: {
                Text("Invite")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                    .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Share sheet wrapper

private struct WhisperInviteShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
