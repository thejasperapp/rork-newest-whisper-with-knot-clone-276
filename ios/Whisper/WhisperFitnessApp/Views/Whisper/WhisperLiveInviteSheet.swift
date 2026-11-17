import SwiftUI

/// Multi-select friend picker for group lives. Used both on the "Go Live"
/// screen (invite co-hosts before starting) and inside a live (host invites
/// mid-broadcast, Instagram-style). Capped so host + invitees never exceed
/// the 4-person broadcast limit.
struct WhisperLiveInviteSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    /// How many invite slots remain (4 minus current broadcasters).
    let maxSelectable: Int
    /// User IDs already invited or already broadcasting — shown as locked.
    var alreadyIn: Set<String> = []
    let onInvite: ([WhisperUserRow]) -> Void

    @State private var candidates: [WhisperUserRow] = []
    @State private var selected: Set<String> = []
    @State private var loading = true
    @State private var query = ""

    private var filtered: [WhisperUserRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return candidates }
        return candidates.filter {
            $0.username.lowercased().contains(q)
                || ($0.display_name?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    searchField
                    if loading {
                        Spacer()
                        ProgressView().tint(WhisperTheme.ink(colorScheme))
                        Spacer()
                    } else if filtered.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            WhisperMeetDoodle(symbol: "person.2", height: 120)
                            Text(candidates.isEmpty ? "Follow people to invite them" : "No matches")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filtered) { user in
                                    row(user)
                                }
                            }
                            .padding(.bottom, 90)
                        }
                    }
                }

                VStack {
                    Spacer()
                    inviteButton
                }
            }
            .navigationTitle("Go live together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.subheadline)
                .foregroundStyle(Color(red: 0.95, green: 0.15, blue: 0.35))
            Text("Up to 4 people can broadcast together. \(maxSelectable) slot\(maxSelectable == 1 ? "" : "s") left.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Search people", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func row(_ user: WhisperUserRow) -> some View {
        let locked = alreadyIn.contains(user.user_id.lowercased()) || alreadyIn.contains(user.user_id)
        let isSelected = selected.contains(user.user_id)
        Button {
            guard !locked else { return }
            Haptics.tap()
            if isSelected {
                selected.remove(user.user_id)
            } else if selected.count < maxSelectable {
                selected.insert(user.user_id)
            }
        } label: {
            HStack(spacing: 12) {
                WhisperAvatar(
                    username: user.username,
                    size: 44,
                    imageURL: user.profile_image_url.flatMap { URL(string: $0) }
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.username)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    if let display = user.display_name, !display.isEmpty {
                        Text(display)
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
                Spacer()
                if locked {
                    Text("In live")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(WhisperTheme.card(colorScheme), in: Capsule())
                } else {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                isSelected ? Color(red: 0.95, green: 0.15, blue: 0.35) : WhisperTheme.muted(colorScheme).opacity(0.4),
                                lineWidth: 2
                            )
                            .frame(width: 26, height: 26)
                        if isSelected {
                            Circle()
                                .fill(Color(red: 0.95, green: 0.15, blue: 0.35))
                                .frame(width: 18, height: 18)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(locked ? 0.55 : 1)
    }

    private var inviteButton: some View {
        Button {
            Haptics.tap()
            let chosen = candidates.filter { selected.contains($0.user_id) }
            onInvite(chosen)
            dismiss()
        } label: {
            Text(selected.isEmpty ? "Select people to invite" : "Invite \(selected.count) to go live")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    selected.isEmpty
                        ? AnyShapeStyle(Color.gray.opacity(0.5))
                        : AnyShapeStyle(LinearGradient(
                            colors: [Color(red: 0.95, green: 0.15, blue: 0.35), Color(red: 1.0, green: 0.45, blue: 0.25)],
                            startPoint: .leading, endPoint: .trailing
                        )),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(selected.isEmpty)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func load() async {
        var list = await WhisperFollowService.shared.followingProfiles(limit: 100)
        // De-dupe and drop self.
        let me = AccountStorage.currentUserID.lowercased()
        var seen = Set<String>()
        list = list.filter { row in
            let key = row.user_id.lowercased()
            guard key != me, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        candidates = list
        loading = false
    }
}
