import SwiftUI
import PhotosUI

/// Multi-pick + group composer. Lets you name the group, select members
/// from your follows/threads, and create it. On create, opens the group
/// thread view immediately so you can fire off the first message.
struct WhisperNewGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var groups = WhisperGroupChatService.shared
    @State private var follows = WhisperFollowService.shared
    @State private var users = WhisperUserService.shared
    @State private var backend = WhisperBackendService.shared

    @State private var name: String = ""
    @State private var query: String = ""
    @State private var candidates: [WhisperUserRow] = []
    @State private var searchResults: [WhisperUserRow] = []
    @State private var selected: [WhisperGroupMember] = []
    @State private var creating: Bool = false
    @State private var creationError: String?

    let onCreated: (WhisperGroup) -> Void

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let creationError { Text(creationError).font(.footnote).foregroundStyle(.red) }
                        nameField
                        if !selected.isEmpty { selectedChips }
                        searchField
                        userList
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { create() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selected.count >= 2 ? WhisperTheme.coachAccent : WhisperTheme.muted(colorScheme))
                        .disabled(selected.count < 2 || creating)
                }
            }
            .task {
                candidates = await follows.followingProfiles()
            }
            .onChange(of: query) { _, q in
                Task { await runSearch(q) }
            }
        }
    }

    private var nameField: some View {
        TextField("Group name (optional)", text: $name)
            .font(.subheadline)
            .padding(14)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
    }

    private var selectedChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selected) { m in
                    HStack(spacing: 6) {
                        WhisperAvatar(
                            username: m.username,
                            size: 22,
                            imageURL: m.profile_image_url.flatMap(URL.init(string:)),
                            ring: false
                        )
                        Text("@\(m.username)")
                            .font(.caption.weight(.bold))
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                selected.removeAll { $0.user_id == m.user_id }
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                    .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Add people", text: $query)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
    }

    private var pool: [WhisperUserRow] {
        var seen = Set<String>()
        var out: [WhisperUserRow] = []
        for u in candidates + searchResults {
            if seen.insert(u.user_id).inserted { out.append(u) }
        }
        guard !trimmedQuery.isEmpty else { return out }
        let q = trimmedQuery.lowercased()
        return out.filter { WhisperUserSearch.matches(q, username: $0.username, displayName: $0.display_name) }
    }

    private var userList: some View {
        VStack(spacing: 0) {
            ForEach(Array(pool.enumerated()), id: \.element.id) { idx, u in
                row(u)
                if idx < pool.count - 1 {
                    Divider().background(WhisperTheme.hairline(colorScheme)).padding(.leading, 60)
                }
            }
        }
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func row(_ u: WhisperUserRow) -> some View {
        let isOn = selected.contains(where: { $0.user_id == u.user_id })
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.25)) {
                if isOn {
                    selected.removeAll { $0.user_id == u.user_id }
                } else {
                    selected.append(WhisperGroupMember(
                        user_id: u.user_id,
                        username: u.username,
                        profile_image_url: u.profile_image_url
                    ))
                }
            }
        } label: {
            HStack(spacing: 12) {
                WhisperAvatar(
                    username: u.username,
                    size: 40,
                    imageURL: u.profile_image_url.flatMap(URL.init(string:)),
                    ring: false
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(u.display_name.flatMap { $0.isEmpty ? nil : $0 } ?? u.username)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("@\(u.username)").font(.caption).foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? WhisperTheme.coachAccent : WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func runSearch(_ raw: String) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { searchResults = []; return }
        searchResults = await users.search(q, limit: 20)
    }

    private func create() {
        guard !creating else { return }
        creating = true; creationError = nil
        Task {
            defer { creating = false }
            do {
                let g = try await groups.createGroup(name: name, members: selected)
                Haptics.success()
                onCreated(g)
                dismiss()
            } catch {
                creationError = "Couldn't create the group. Check your connection and try again."
                Haptics.error()
            }
        }
    }
}

// MARK: - Group details sheet

/// The info sheet — roster with the owner chip, owner tools (rename · add
/// people · remove), everyone's tools (mute · video call · leave), and the
/// owner's delete. Honest about the registry when it hasn't been migrated.
struct WhisperGroupDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Binding var group: WhisperGroup
    var messages: [WhisperMessageRow] = []
    let onSearch: () -> Void
    @State private var detailRoute: String?
    @State private var memberProfile: WhisperUserRow?
    @State private var profileRequestID: String?
    @State private var profileError: String?
    /// Called after leave/delete so the thread closes too.
    var onGone: () -> Void

    @State private var groups = WhisperGroupChatService.shared
    @State private var users = WhisperUserService.shared
    @State private var photoItem: PhotosPickerItem?
    @State private var photoError: String?
    @State private var renaming: Bool = false
    @State private var nameDraft: String = ""
    @State private var adding: Bool = false
    @State private var addQuery: String = ""
    @State private var addResults: [WhisperUserRow] = []
    @State private var addSearchError: String?
    @State private var addSearching: Bool = false
    @State private var addSearchRetry: Int = 0
    @State private var showGroupPhoto: Bool = false
    @State private var busy: Bool = false
    @State private var actionMenu: WhisperActionMenuModel? = nil

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var isOwner: Bool { groups.isOwner(group) }
    private var currentUID: String { AccountStorage.currentUserID.lowercased() }
    private var meName: String {
        LeaderboardService.shared.savedUsername ?? AuthenticationService.shared.currentUser.username ?? "you"
    }

    var body: some View {
        Group {
            ZStack {
                WhisperConversationDetailsBackdrop()
                ScrollView {
                    VStack(spacing: 24) {
                        identity
                        quickActions
                        attachmentsCard
                        if let message = photoError ?? groups.lastError {
                            Text(message).font(.footnote).foregroundStyle(.red)
                        }
                        detailsRows
                        if !groups.registryAvailable && groups.registryChecked {
                            Text("Couldn't confirm the current group details. Refresh before changing the roster.")
                                .font(.caption2)
                                .foregroundStyle(muted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .whisperNavigationBack(isEnabled: !busy && !renaming)
            .navigationDestination(item: $detailRoute) { route in
                if route == "Nicknames" {
                    WhisperChatNicknamesView(thread: group.id.uuidString, members: group.members)
                } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if let message = photoError ?? groups.lastError { Text(message).font(.footnote).foregroundStyle(.red) }
                        if route == "People" {
                            if adding { addPeopleCard }
                            rosterCard
                            if !isOwner { Text("The group owner can add more people.").font(.footnote).foregroundStyle(muted) }
                        } else if route == "Privacy & safety" {
                            Text("Your group controls").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                            toolsCard
                            Text("Muting and hiding apply to this device. Your group membership and message history stay unchanged unless the owner updates the roster.")
                                .font(.footnote).foregroundStyle(muted)
                        } else { identity }
                    }.padding(.horizontal, 16).padding(.vertical, 16)
                }
                .background(WhisperTheme.surface(colorScheme))
                .navigationTitle(route).navigationBarTitleDisplayMode(.inline)
                .whisperNavigationBack(isEnabled: !busy)
                }
            }
            .navigationDestination(item: $memberProfile) { WhisperUserProfileView(user: $0) }
            .task(id: profileRequestID) {
                guard let id = profileRequestID else { return }
                let epoch = AccountStorage.generation
                let found = await users.fetchByUserID(id)
                guard !Task.isCancelled, epoch == AccountStorage.generation, profileRequestID == id else { return }
                profileRequestID = nil
                if let found { memberProfile = found }
                else { profileError = "This profile couldn't be loaded. Tap the person to try again." }
            }
            .alert("Profile unavailable", isPresented: Binding(get: { profileError != nil }, set: { if !$0 { profileError = nil } })) {
                Button("OK") { profileError = nil }
            } message: { Text(profileError ?? "Please try again.") }
            .whisperActionMenu($actionMenu)
            .task(id: photoItem) {
                guard let item = photoItem else { return }
                busy = true; photoError = nil
                defer { busy = false; photoItem = nil }
                do {
                    try await groups.setPhoto(item, in: group)
                    if let fresh = groups.group(byID: group.id) { group = fresh }
                    Haptics.success()
                } catch {
                    guard !Task.isCancelled else { return }
                    photoError = (error as? WhisperGroupPhotoFailure)?.errorDescription ?? "This picture couldn't be opened. Choose it again and retry."
                    Haptics.error()
                }
            }
            .task(id: "\(addQuery)|\(adding)|\(addSearchRetry)") { if adding { await runAddSearch(addQuery) } }
            .fullScreenCover(isPresented: $showGroupPhoto) { WhisperGroupPhotoViewer(group: group) }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                addResults = []; addQuery = ""; showGroupPhoto = false; memberProfile = nil; profileRequestID = nil; dismiss()
            }
        }
        .interactiveDismissDisabled(busy || renaming)
    }

    private var quickActions: some View {
        HStack(spacing: 20) {
            if isOwner { compactAction("Add", icon: "person.badge.plus") { adding = true; detailRoute = "People" } }
            compactAction("Search", icon: "magnifyingglass", action: onSearch)
            compactAction(groups.isMuted(group) ? "Unmute" : "Mute", icon: groups.isMuted(group) ? "bell.slash" : "bell") { groups.toggleMute(group) }
            Menu {
                Button("Start audio call", systemImage: "phone") { Task { await WhisperCallService.shared.startGroupCall(group: group, mode: .audio) } }
                Button("Start video call", systemImage: "video") { Task { await WhisperCallService.shared.startGroupCall(group: group) } }
                if isOwner { Button("Delete group", role: .destructive) { confirmDelete() } }
                else { Button("Hide group", role: .destructive) { confirmLeave() } }
            } label: { VStack(spacing: 5) { Image(systemName: "ellipsis").font(.system(size: 22)); Text("Options").font(.caption2) }.frame(minWidth: 44, minHeight: 54) }
        }.foregroundStyle(ink).frame(maxWidth: .infinity).padding(.vertical, 12).disabled(busy)
    }

    private func compactAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) { Image(systemName: icon).font(.system(size: 21, weight: .regular)).frame(width: 56, height: 56).modifier(WhisperControlGlass(shape: Circle())); Text(title).font(.caption2) }
                .frame(minWidth: 44, minHeight: 54)
        }.buttonStyle(.plain)
    }

    private var attachmentsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Attachments").font(.headline)
                Spacer()
                Button("See all", action: onSearch).font(.subheadline)
            }
            let media = messages.reversed().filter {
                let body = WhisperChatReply.split($0.body).text
                return WhisperDMThreadView.imageURL(in: body) != nil || WhisperDMThreadView.videoURL(in: body) != nil
            }
            if media.isEmpty {
                Label("No shared photos or videos loaded", systemImage: "photo.on.rectangle")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(Array(media.prefix(6))) { message in
                        Button(action: onSearch) {
                            Color(uiColor: .secondarySystemBackground).aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    if let url = WhisperDMThreadView.imageURL(in: WhisperChatReply.split(message.body).text) {
                                        WhisperCachedAsyncImage(url: url) { phase in
                                            if case .success(let image) = phase { image.resizable().scaledToFill() }
                                        }
                                    } else { Image(systemName: "play.rectangle.fill").font(.title) }
                                }.clipShape(.rect(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityLabel("Browse shared attachments")
                    }
                }
            }
            Text("From messages currently loaded in this conversation.").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 20).modifier(WhisperConversationFrost())
    }

    private var detailsRows: some View {
        VStack(spacing: 0) {
            if isOwner {
                toolRow(icon: "person.badge.plus", title: "Add people", subtitle: "Bring someone into this group") { adding = true; detailRoute = "People" }
            }
            toolRow(icon: "person.2", title: "People", subtitle: group.members.map(\.username).joined(separator: ", ")) { detailRoute = "People" }
            toolRow(icon: "person.text.rectangle", title: "Nicknames", subtitle: "Personal names on this device") { detailRoute = "Nicknames" }
            toolRow(icon: "lock", title: "Privacy & safety", subtitle: "Manage this conversation") { detailRoute = "Privacy & safety" }
            toolRow(icon: "photo.on.rectangle", title: "Search & shared links", subtitle: "Find messages, photos, videos and links", action: onSearch)
        }.modifier(WhisperConversationFrost())
    }

    private var identity: some View {
        VStack(spacing: 8) {
            Button { showGroupPhoto = true } label: { WhisperGroupAvatarView(group: group, size: WhisperConversationPortraitSize.details) }
                .buttonStyle(.plain).accessibilityLabel("Enlarge group picture")
            if isOwner && renaming {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(busy ? "Saving…" : "Change group picture", systemImage: "camera")
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }
                .disabled(busy)
                if group.avatarPath != nil {
                    Button("Remove picture", role: .destructive) {
                        Task {
                            busy = true; photoError = nil
                            defer { busy = false }
                            do {
                                try await groups.removePhoto(in: group)
                                if let fresh = groups.group(byID: group.id) { group = fresh }
                            } catch { photoError = "Couldn't remove the picture. Try again." }
                        }
                    }.disabled(busy)
                }
            }
            if renaming {
                Button("Cancel changes") { nameDraft = group.name; renaming = false }.disabled(busy).frame(minHeight: 44)
                HStack(spacing: 8) {
                    TextField("Group name", text: $nameDraft)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(WhisperTheme.card(colorScheme), in: Capsule())
                        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75) }
                    Button {
                        Haptics.tap()
                        Task { await commitRename() }
                    } label: {
                        Text("Save")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.surface(colorScheme))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || nameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Text(group.name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
            }
            Text("\(group.members.count + 1) members\(isOwner ? " · You created this group" : "")")
                .font(.caption)
                .foregroundStyle(muted)
            if isOwner && !renaming {
                Button {
                    Haptics.tap()
                    nameDraft = group.name
                    withAnimation(WhisperChatStyle.spring) { renaming = true }
                } label: {
                    Text("Change name and image")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(WhisperTheme.card(colorScheme), in: Capsule())
                        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75) }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Members")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(muted)
                Spacer()
                if isOwner {
                    Button {
                        Haptics.tap()
                        withAnimation(WhisperChatStyle.spring) { adding.toggle() }
                    } label: {
                        Label(adding ? "Done" : "Add people", systemImage: adding ? "checkmark" : "person.badge.plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            memberRow(username: meName, imageURL: nil, subtitle: isOwner ? "You · Owner" : "You", isMe: true, member: nil)
            ForEach(group.members.filter { $0.user_id.lowercased() != currentUID }) { m in
                Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(height: 0.5).padding(.leading, 62)
                memberRow(
                    username: m.username,
                    imageURL: m.profile_image_url.flatMap(URL.init(string:)),
                    subtitle: m.user_id.lowercased() == group.ownerID ? "Owner" : "Member",
                    isMe: false,
                    member: m
                )
            }
        }
        .background(WhisperTheme.card(colorScheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private func memberRow(username: String, imageURL: URL?, subtitle: String, isMe: Bool, member: WhisperGroupMember?) -> some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                profileRequestID = isMe ? currentUID : member?.user_id
            } label: {
                HStack(spacing: 12) {
                    WhisperAvatar(username: username, size: 38, imageURL: imageURL, ring: false)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("@\(username)").font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                        Text(subtitle).font(.caption).foregroundStyle(muted)
                    }
                    Spacer()
                    if profileRequestID == (isMe ? currentUID : member?.user_id) { ProgressView() }
                    else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(muted) }
                }.frame(minHeight: 44).contentShape(.rect)
            }.buttonStyle(.plain).accessibilityLabel("View @\(username)'s profile")
            if let member, isOwner, member.user_id.lowercased() != group.ownerID {
                Button {
                    Haptics.tap()
                    confirmRemove(member)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove @\(member.username)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var addPeopleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(muted)
                TextField("Search people to add", text: $addQuery)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(12)
            .background(WhisperTheme.surface(colorScheme), in: Capsule())
            .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75) }
            Text("People added here will receive new messages, not the group's earlier history or old Meet invitations. Re-adding someone does not restore invitations revoked by their removal.")
                .font(.caption).foregroundStyle(muted)
            if addSearching { ProgressView().frame(maxWidth: .infinity) }
            if let addSearchError {
                Text(addSearchError).font(.caption).foregroundStyle(.red)
                Button("Retry search") { addSearchRetry += 1 }.frame(minHeight: 44)
            } else if !addSearching && addResults.isEmpty {
                Text(addQuery.count < 2 ? "Search a name or username to add someone." : "No matching people.")
                    .font(.footnote).foregroundStyle(muted)
            }
            ForEach(addResults.prefix(12)) { u in
                let already = group.members.contains { $0.user_id.lowercased() == u.user_id.lowercased() }
                Button {
                    guard !already, !busy else { return }
                    Haptics.tap()
                    busy = true
                    let epoch = AccountStorage.generation
                    Task {
                        let updated = await groups.addMembers(group, [WhisperGroupMember(user_id: u.user_id, username: u.username, profile_image_url: u.profile_image_url)])
                        guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                        group = updated; busy = false
                        if groups.lastError == nil { Haptics.success() }
                    }
                } label: {
                    HStack(spacing: 12) {
                        WhisperAvatar(username: u.username, size: 34, imageURL: u.profile_image_url.flatMap(URL.init(string:)), ring: false)
                        Text("@\(u.username)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                        Spacer()
                        Image(systemName: already ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(already ? muted : ink)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .disabled(already || busy)
            }
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var toolsCard: some View {
        VStack(spacing: 0) {
            toolRow(icon: groups.isMuted(group) ? "bell" : "bell.slash", title: groups.isMuted(group) ? "Unmute group" : "Mute group", subtitle: "No haptics or inbox emphasis on this phone") {
                groups.toggleMute(group)
            }
            Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(height: 0.5).padding(.leading, 56)
            toolRow(icon: "video", title: "Start a video call", subtitle: "Rings everyone in the group") {
                Task { await WhisperCallService.shared.startGroupCall(group: group) }
            }
            Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(height: 0.5).padding(.leading, 56)
            if isOwner {
                toolRow(icon: "trash", title: "Delete group", subtitle: "Everyone keeps the messages they already have", destructive: true) {
                    confirmDelete()
                }
            } else {
                toolRow(icon: "rectangle.portrait.and.arrow.right", title: "Hide group", subtitle: "Hides it on this device; ask the owner to remove you", destructive: true) {
                    confirmLeave()
                }
            }
        }
        .background(WhisperTheme.card(colorScheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private func toolRow(icon: String, title: String, subtitle: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(destructive ? Color(red: 0.90, green: 0.35, blue: 0.35) : ink)
                    .frame(width: 26, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(destructive ? Color(red: 0.90, green: 0.35, blue: 0.35) : ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: Actions

    private func runAddSearch(_ raw: String) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        addSearchError = nil; addResults = []; addSearching = false
        guard q.count >= 2 else { return }
        let generation = AccountStorage.generation
        addSearching = true
        do {
            try await Task.sleep(for: .milliseconds(220))
            let results = try await users.mentionSuggestions(q, limit: 20, matchingNames: true)
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            addResults = results.filter { $0.user_id.lowercased() != currentUID }
            addSearching = false
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            addSearching = false; addSearchError = "Couldn't search people. Try again."
        }
    }

    private func commitRename() async {
        busy = true
        group = await groups.rename(group, to: nameDraft)
        busy = false
        if groups.lastError == nil {
            withAnimation(WhisperChatStyle.spring) { renaming = false }
            Haptics.success()
        }
    }

    private func confirmRemove(_ member: WhisperGroupMember) {
        actionMenu = WhisperActionMenuModel(
            title: "Remove @\(member.username)?",
            subtitle: "They'll stop receiving new messages. Removing them from the server roster permanently revokes every Meet invitation that includes them, for everyone. Re-adding them won't restore those invitations. Other message history stays.",
            actions: [
                WhisperMenuAction(icon: "minus.circle", title: "Remove", isDestructive: true) {
                    guard !busy else { return }
                    busy = true
                    let epoch = AccountStorage.generation
                    Task {
                        guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                        let updated = await groups.removeMember(group, member)
                        guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                        group = updated; busy = false
                    }
                }
            ],
            isConfirmStyle: true
        )
    }

    private func confirmLeave() {
        actionMenu = WhisperActionMenuModel(
            title: "Hide \(group.name)?",
            subtitle: "Hidden on this device only. This doesn't change membership or revoke Meet invitations. Ask the owner to remove you from the server roster.",
            actions: [
                WhisperMenuAction(icon: "rectangle.portrait.and.arrow.right", title: "Hide group", isDestructive: true) {
                    Task {
                        busy = true
                        await groups.leave(group)
                        busy = false
                        dismiss()
                        onGone()
                    }
                }
            ],
            isConfirmStyle: true
        )
    }

    private func confirmDelete() {
        actionMenu = WhisperActionMenuModel(
            title: "Delete \(group.name)?",
            subtitle: "After server confirmation, this group is deleted and its Meet invitations are permanently revoked for everyone. Other messages already sent stay in each person's history.",
            actions: [
                WhisperMenuAction(icon: "trash", title: "Delete group", isDestructive: true) {
                    guard !busy else { return }
                    busy = true
                    let epoch = AccountStorage.generation
                    Task {
                        guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                        let deleted = await groups.deleteGroup(group.id)
                        guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                        busy = false
                        if deleted { dismiss(); onGone() }
                    }
                }
            ],
            isConfirmStyle: true
        )
    }
}
