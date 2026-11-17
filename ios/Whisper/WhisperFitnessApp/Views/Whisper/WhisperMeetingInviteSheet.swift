import SwiftUI
import Supabase

/// Invite friends to a meeting by username — loads the following list and
/// sends each selected person a DM with the meeting link, which renders as
/// an invitation card in their inbox (WhisperMeetingDMBubble).
struct WhisperMeetingInviteSheet: View {
    let meetingID: String
    var socialLink: String? = nil
    private var invitationLink: String { socialLink ?? WhisperMeetingService.link(for: meetingID) }
    @Environment(\.dismiss) private var dismiss

    @State private var following: [WhisperUserRow] = []
    @State private var loading: Bool = true
    @State private var query: String = ""
    @State private var sending: String?
    @State private var sent: Set<String> = []
    @State private var sendError: String? = nil

    private var myUserID: String {
        AccountStorage.currentUserID.lowercased()
    }

    private var myUsername: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    private var filtered: [WhisperUserRow] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return following }
        return following.filter {
            $0.username.lowercased().contains(needle)
            || ($0.display_name?.lowercased().contains(needle) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("", text: $query, prompt: Text("Search friends…").foregroundStyle(.secondary))
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemBackground), in: Capsule())
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // List
                if loading {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading friends…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        WhisperMeetDoodle(symbol: "person.2", height: 120)
                        Text(following.isEmpty ? "Follow people to invite them to meetings." : "No friends match your search.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 40)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { person in
                                inviteRow(person)
                            }
                        }
                    }
                }

                if let sendError { Text(sendError).font(.footnote).foregroundStyle(.red).padding(12) }

                // Copy link fallback
                Divider()
                ShareLink(item: URL(string: invitationLink) ?? URL(string: "https://mydailywhisper.com")!) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc")
                            .font(.subheadline.weight(.semibold))
                        Text("Copy meeting link instead")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationTitle("Invite to meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadFollowing() }
        }
    }

    @ViewBuilder
    private func inviteRow(_ person: WhisperUserRow) -> some View {
        Button {
            Haptics.tap()
            Task { await sendInvite(to: person) }
        } label: {
            HStack(spacing: 12) {
                WhisperAvatar(
                    username: person.username,
                    size: 40,
                    imageURL: person.profile_image_url.flatMap { URL(string: $0) }
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.display_name ?? person.username)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("@\(person.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if sent.contains(person.user_id) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                } else if sending == person.user_id {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor, in: Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(sent.contains(person.user_id) || sending != nil)
        .overlay(alignment: .bottom) {
            if person.user_id != filtered.last?.user_id {
                Divider().opacity(0.5).padding(.leading, 68)
            }
        }
    }

    // MARK: - Data

    private func loadFollowing() async {
        loading = true
        let generation = AccountStorage.generation
        var list = await WhisperFollowService.shared.followingProfiles(limit: 100)
        guard generation == AccountStorage.generation, !Task.isCancelled else { return }
        let me = myUserID
        var seen = Set<String>()
        list = list.filter { row in
            let key = row.user_id.lowercased()
            guard key != me, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        following = list
        loading = false
    }

    private func sendInvite(to person: WhisperUserRow) async {
        guard sending == nil, !sent.contains(person.user_id) else { return }
        let generation = AccountStorage.generation
        sending = person.user_id
        sendError = nil
        let link = invitationLink
        let body = "Join my meeting: \(link)"
        let delivered = await WhisperBackendService.shared.sendMessage(
            toUserID: person.user_id,
            toUsername: person.username,
            body: body
        )
        guard generation == AccountStorage.generation, !Task.isCancelled else { return }
        if delivered { sent.insert(person.user_id) }
        else { sendError = "Invitation wasn’t sent. Tap the person to try again." }
        sending = nil
    }
}
