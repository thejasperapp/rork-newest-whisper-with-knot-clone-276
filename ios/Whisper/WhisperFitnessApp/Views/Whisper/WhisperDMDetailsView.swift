import SwiftUI

struct WhisperDMDetailsView: View {
    let user: WhisperUserRow
    let messages: [WhisperMessageRow]
    var conversationKey: String? = nil
    var isFlicks = false
    var onAudioCall: (() -> Void)? = nil
    var onVideoCall: (() -> Void)? = nil
    let onMessage: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var showSearch: Bool = false
    @State private var libraryScope = "Media"
    @State private var showReport: Bool = false
    @State private var route: String?
    @State private var profile: WhisperUserRow?
    @State private var blocks = WhisperBlockService.shared
    @State private var confirmBlock: Bool = false
    @State private var changingBlock: Bool = false
    @State private var blockError: String?
    private var isBlocked: Bool { blocks.isBlocked(userID: user.user_id) }

    private var member: WhisperGroupMember { .init(user_id: user.user_id, username: user.username, profile_image_url: user.profile_image_url) }
    private var media: [WhisperMessageRow] {
        messages.reversed().filter { WhisperDMThreadView.imageURL(in: WhisperChatReply.split($0.body).text) != nil || WhisperDMThreadView.videoURL(in: WhisperChatReply.split($0.body).text) != nil }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    WhisperAvatar(username: user.username, size: WhisperConversationPortraitSize.details, imageURL: user.profile_image_url.flatMap(URL.init(string:)), ring: false)
                    Text(user.display_name ?? user.username).font(.largeTitle.bold())
                    Text("@\(user.username)").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 16)
                HStack(spacing: 28) {
                    if let onAudioCall { action("Audio", icon: "phone.fill", action: onAudioCall) }
                    if let onVideoCall { action("Video", icon: "video.fill", action: onVideoCall) }
                    action("Profile", icon: "person.crop.circle") { profile = user }
                    Menu {
                        Button("View profile", systemImage: "person") { profile = user }
                        if !isFlicks { Button("Search conversation", systemImage: "magnifyingglass") { libraryScope = "Messages"; showSearch = true } }
                        Button("Report", systemImage: "flag", role: .destructive) { showReport = true }
                        Button(isBlocked ? "Unblock" : "Block", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
                    } label: { VStack(spacing: 6) { Image(systemName: "ellipsis").font(.system(size: 21)); Text("Options").font(.caption2) }.frame(minWidth: 44, minHeight: 54) }
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Attachments").font(.headline)
                        Spacer()
                        if !isFlicks { Button("See all") { libraryScope = "Media"; showSearch = true }.font(.subheadline) }
                    }
                    if media.isEmpty {
                        Label(isFlicks ? "Flicks are view once and aren’t saved here" : "No shared photos or videos loaded", systemImage: isFlicks ? "eye.slash" : "photo.on.rectangle")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    ForEach(media.prefix(36)) { message in
                        Button { onMessage(message.id) } label: {
                            Color(.secondarySystemBackground).aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    if let image = WhisperDMThreadView.imageURL(in: WhisperChatReply.split(message.body).text) {
                                        WhisperCachedAsyncImage(url: image) { phase in
                                            if case .success(let image) = phase { image.resizable().scaledToFill() }
                                        }.allowsHitTesting(false)
                                    } else { Image(systemName: "play.rectangle.fill").font(.title) }
                                }.clipped()
                        }.buttonStyle(.plain).accessibilityLabel("Open shared media in conversation")
                    }
                }
                    Text(isFlicks ? "Unopened Flicks stay in the inbox until opened or expired. This menu never opens them." : "From messages currently loaded in this conversation.").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 18).modifier(WhisperConversationFrost())
                if !isFlicks { VStack(spacing: 0) {
                    row("Shared links", icon: "link") { libraryScope = "Links"; showSearch = true }
                    Divider()
                    row("Search conversation", icon: "magnifyingglass") { libraryScope = "Messages"; showSearch = true }
                }.modifier(WhisperConversationFrost()) }
                VStack(spacing: 0) {
                    row("Nicknames", icon: "person.text.rectangle") { route = "Nicknames" }
                    Divider()
                    row("Privacy & safety", icon: "lock") { route = "Privacy & safety" }
                }.modifier(WhisperConversationFrost())
                VStack(spacing: 0) {
                    WhisperConversationMenuRow(title: "Report conversation", icon: "flag", destructive: true) { showReport = true }
                    Divider()
                    WhisperConversationMenuRow(title: isBlocked ? "Unblock contact" : "Block contact", icon: "hand.raised", destructive: true) { confirmBlock = true }
                        .disabled(changingBlock)
                }.modifier(WhisperConversationFrost())
            }.padding(.horizontal, 20).padding(.bottom, 32)
        }
        .background { WhisperConversationDetailsBackdrop() }
        .foregroundStyle(WhisperTheme.ink(scheme))
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .whisperNavigationBack()
        .navigationDestination(item: $profile) { WhisperUserProfileView(user: $0) }
        .navigationDestination(item: $route) { route in
            if route == "Nicknames" { WhisperChatNicknamesView(thread: conversationKey ?? user.user_id, members: [member]) }
            else {
                List {
                    Section("Actions you can take") {
                        Button("Report conversation", systemImage: "flag", role: .destructive) { showReport = true }
                        Button(isBlocked ? "Unblock this person" : "Block this person", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }.disabled(changingBlock)
                        NavigationLink("Blocked accounts", value: "Blocked accounts")
                    }
                    Section { Text("Report a message from its long-press menu, or manage blocked accounts below. Jasper's personal answers stay private until you share them.").font(.footnote).foregroundStyle(.secondary) }
                }.listStyle(.plain).navigationTitle("Privacy & safety").whisperNavigationBack()
                    .navigationDestination(for: String.self) { _ in WhisperBlockedAccountsView().whisperNavigationBack() }
            }
        }
        .confirmationDialog(isBlocked ? "Unblock @\(user.username)?" : "Block @\(user.username)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button(isBlocked ? "Unblock" : "Block", role: .destructive) { Task { await changeBlock() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Blocking hides their messages and stories. You can change this later in Settings.") }
        .alert("Couldn't update blocking", isPresented: Binding(get: { blockError != nil }, set: { if !$0 { blockError = nil } })) {
            Button("OK") { blockError = nil }
        } message: { Text(blockError ?? "Please try again.") }
        .sheet(isPresented: $showSearch) { WhisperChatLibraryView(messages: messages, onSelect: onMessage, initialScope: libraryScope) }
        .sheet(isPresented: $showReport) { WhisperReportSheet(kind: .dm, targetID: nil, targetUserID: user.user_id, targetUsername: user.username) }
    }

    private func changeBlock() async {
        guard !changingBlock else { return }
        changingBlock = true
        let epoch = AccountStorage.generation
        let success = isBlocked
            ? await blocks.unblock(userID: user.user_id, username: user.username)
            : await blocks.block(userID: user.user_id, username: user.username)
        guard epoch == AccountStorage.generation else { return }
        changingBlock = false
        if !success { blockError = "Your change couldn't be saved. Check your connection and try again."; await blocks.refresh() }
    }

    private func action(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { VStack(spacing: 6) { Image(systemName: icon).font(.system(size: 21)).frame(width: 58, height: 58).modifier(WhisperControlGlass(shape: Circle())); Text(title).font(.caption2) }.frame(minWidth: 44, minHeight: 54) }.buttonStyle(.plain)
    }
    private func row(_ title: String, subtitle: String? = nil, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline); if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) } }
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.frame(minHeight: 52).contentShape(.rect)
        }.buttonStyle(.plain)
    }
}
