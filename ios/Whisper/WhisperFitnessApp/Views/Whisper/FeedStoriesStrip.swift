import SwiftUI

/// Horizontal stories strip (live bubbles + your bubble + friends' latest
/// stories) for the feed. Extracted from `WhisperFeedView` so realtime story
/// updates only recompose this strip rather than the entire scroll view.
///
/// Live rooms merge into this row Instagram-style: red-ringed bubbles with a
/// LIVE pill lead the strip, group lives show interlocked stacked avatars,
/// and tapping opens the live instantly. Rooms stream in via Supabase
/// Realtime so bubbles appear/disappear the moment friends go live.
struct FeedStoriesStrip: View {
    let storyService: WhisperStoryService
    let onCreateStory: () -> Void
    let onOpenStory: (WhisperStoryRow) -> Void
    let onOpenMyStories: () -> Void
    var onOpenRoom: (WhisperLiveRoom) -> Void = { _ in }
    @Environment(\.colorScheme) private var colorScheme

    /// Brand blue used for the "your story" ring so it stands out from the
    /// neutral ink rings used for everyone else.
    private let ownRingTint = Color(red: 0.20, green: 0.55, blue: 1.0)
    /// Match the inbox story portraits on the shared recessed rail.
    private let bubbleSize: CGFloat = 84
    private let liveRed = Color(red: 0.95, green: 0.15, blue: 0.35)

    // Live rooms state
    @State private var liveRooms: [WhisperLiveRoom] = []
    @State private var speakersByRoom: [String: [WhisperLiveSpeaker]] = [:]
    @State private var liveProfiles: [String: WhisperBackendService.WhisperPublicProfile] = [:]
    @State private var invitedRoomIDs: Set<String> = []

    @State private var favorites = WhisperStoryFavorites.shared
    /// One-shot pop when a story finishes uploading.
    @State private var landedPop: Bool = false

    /// Everyone else's stories — your FAVORITES first, then the usual order.
    private var otherGroups: [(username: String, userID: String, latest: WhisperStoryRow, all: [WhisperStoryRow])] {
        let list = storyService.storiesByUser().filter { $0.userID.lowercased() != AccountStorage.currentUserID.lowercased() }
        return favorites.sorted(list, userID: { $0.userID })
    }

    /// Rooms surfaced as bubbles: everything live, plus upcoming rooms I host
    /// or was invited to (with a countdown pill instead of LIVE).
    private var visibleRooms: [WhisperLiveRoom] {
        let me = AccountStorage.currentUserID.lowercased()
        return liveRooms.filter { room in
            if room.is_live { return true }
            guard room.isUpcoming else { return false }
            return room.host_id.lowercased() == me || invitedRoomIDs.contains(room.id)
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                // Your story composer is ALWAYS first — never pushed back by lives.
                yourBubble
                // Live bubbles follow, Instagram-style.
                ForEach(visibleRooms) { room in
                    liveBubble(room)
                        .transition(.scale.combined(with: .opacity))
                }
                // Exclude my own group from the friends list — my stories
                // live in the dedicated "Your story" bubble at the start.
                ForEach(otherGroups, id: \.userID) { item in
                    let unseen = storyService.hasUnseenStories(userID: item.userID)
                    storyBubble(username: item.username, story: item.latest, all: item.all, viewed: !unseen)
                }
            }
            .padding(.vertical, 4)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: visibleRooms.map { $0.id })
        }
        .contentMargins(.horizontal, 14, for: .scrollContent)
        .task { await loadLive() }
        .onAppear {
            WhisperLiveRoomService.shared.subscribeToRoomsList(key: "feed-strip") {
                Task { await loadLive() }
            }
        }
        .onDisappear {
            WhisperLiveRoomService.shared.unsubscribeFromRoomsList(key: "feed-strip")
        }
    }

    // MARK: - Live bubbles

    private func liveBubble(_ room: WhisperLiveRoom) -> some View {
        let speakers = speakersByRoom[room.id] ?? []
        let hostName = liveProfiles[room.host_id]?.username ?? room.name
        let isUpcoming = room.isUpcoming
        let cohostCount = max(0, speakers.count - 1)

        return VStack(spacing: 5) {
            ZStack {
                WhisperLiveRing(size: bubbleSize + 8, lineWidth: 2.5, isUpcoming: isUpcoming)

                // Single host avatar — group lives use "username +n" text
                // below instead of interlocking photos.
                WhisperAvatar(
                    username: hostName,
                    size: bubbleSize - 4,
                    imageURL: liveProfiles[room.host_id]?.profile_image_url.flatMap { URL(string: $0) }
                )

                // LIVE / SOON pill overlapping the bottom edge.
                VStack {
                    Spacer()
                    Text(isUpcoming ? "SOON" : "LIVE")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(isUpcoming ? Color.orange : liveRed, in: Capsule())
                        .overlay(Capsule().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 1.5))
                        .offset(y: 4)
                }
                .frame(height: bubbleSize + 8)
            }
            .contentShape(Circle())
            .onTapGesture {
                Haptics.tap()
                onOpenRoom(room)
            }

            // "username" for solo, "username +n" for group lives.
            Text(cohostCount > 0 ? "\(hostName) +\(cohostCount)" : hostName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.8))
                .lineLimit(1)
                .frame(maxWidth: bubbleSize + 14)
        }
    }

    private func loadLive() async {
        do {
            let rooms = try await WhisperLiveRoomService.shared.fetchRooms()
            let map = await WhisperLiveRoomService.shared.fetchSpeakersForRooms(roomIDs: rooms.map { $0.id })
            var ids = rooms.map { $0.host_id }
            ids.append(contentsOf: map.values.flatMap { $0.map { $0.user_id } })
            let profileMap = await WhisperLiveRoomService.shared.hydrateProfiles(userIDs: ids)
            let invites = await WhisperLiveRoomService.shared.myInvitedRoomIDs()
            liveRooms = rooms
            speakersByRoom = map
            liveProfiles = profileMap
            invitedRoomIDs = invites
        } catch {
            liveRooms = []
        }
    }

    // MARK: - Story bubbles

    private var yourBubble: some View {
        let me = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
        let hasStory = storyService.meHasActiveStory
        let upload = storyService.uploading
        // Tapping the avatar opens my own story viewer when I have stories;
        // the `+` corner always opens the composer so I can post a new one.
        return VStack(spacing: 5) {
            ZStack {
                WhisperAvatarChrome(
                    username: me,
                    size: bubbleSize,
                    storyRing: hasStory,
                    ringTint: hasStory ? ownRingTint : nil,
                    gradientRing: hasStory && storyService.hasUnseenStories(userID: AccountStorage.currentUserID),
                    plusButton: upload == nil,
                    plusSymbol: "plus",
                    onPlusTap: onCreateStory
                )
                .opacity(upload == nil ? 1 : 0.35)

                // THE UPLOAD MOMENT — the new picture sits in the bubble under
                // a brand-gradient ring that fills as it uploads, then the
                // bubble pops when the story lands.
                if let upload {
                    WhisperStoryUploadBubble(state: upload, size: bubbleSize)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .scaleEffect(landedPop ? 1.14 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: landedPop)
            .animation(.easeOut(duration: 0.2), value: upload == nil)
            .onChange(of: upload == nil) { wasUploading, idle in
                // nil → uploading → nil: pop once when it lands.
                guard idle, !wasUploading else { return }
                Haptics.success()
                landedPop = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { landedPop = false }
            }
            .onTapGesture {
                guard upload == nil else { return }
                Haptics.tap()
                if hasStory {
                    onOpenMyStories()
                } else {
                    onCreateStory()
                }
            }
            HStack(spacing: 3) {
                Text(upload != nil ? (upload?.failed == true ? "Didn't post" : "Posting…") : (hasStory ? "Your story" : "Add story"))
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                VerifiedBadge(
                    badge: UserVerificationService.shared.badge(forUsername: me),
                    size: 10,
                    username: me,
                    userID: AccountStorage.currentUserID,
                    maxChips: 0
                )
            }
            .frame(maxWidth: bubbleSize + 10)
        }
    }

    private func storyBubble(username: String, story: WhisperStoryRow, all: [WhisperStoryRow], viewed: Bool) -> some View {
        let isFavorite = favorites.isFavorite(story.user_id)
        // The viewer's order is oldest → newest; the service hands newest first.
        let group: [WhisperStoryRow] = Array(all.reversed())
        return VStack(spacing: 5) {
            WhisperAvatarChrome(
                username: username,
                size: bubbleSize,
                imageURL: URL(string: story.image_url),
                // Instagram-exact: the conic gradient ring while unseen,
                // neutral gray hairline once every story was opened.
                storyRing: true,
                ringTint: nil,
                gradientRing: !viewed,
                plusButton: false
            )
            .overlay(alignment: .bottomTrailing) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(WhisperBrandGradient.diagonal, in: Circle())
                        .overlay { Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 2) }
                        .offset(x: 2, y: 2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Circle())
            .onTapGesture {
                Haptics.tap()
                onOpenStory(story)
            }
            // Press and hold to PEEK — the story lifts into the preview card
            // without recording a view; Favorite lives in its menu.
            .onLongPressGesture(minimumDuration: 0.32, maximumDistance: 12) {
                WhisperPeekCenter.shared.present(.story(group.isEmpty ? [story] : group))
            }
            HStack(spacing: 3) {
                Text(username)
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
                    .lineLimit(1)
                VerifiedBadge(
                    badge: UserVerificationService.shared.badge(forUsername: username),
                    size: 10,
                    username: username,
                    userID: story.user_id,
                    maxChips: 0
                )
            }
            .frame(maxWidth: bubbleSize + 10)
            .contentShape(.rect)
            .onTapGesture {
                Haptics.tap()
                onOpenStory(story)
            }
        }
    }
}

/// "Your story" WHILE a story posts — the new picture sits in the bubble
/// under a brand-gradient ring that fills with the upload (and keeps turning
/// so it always reads alive), then the strip pops it when the story lands.
struct WhisperStoryUploadBubble: View {
    let state: WhisperStoryService.UploadState
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var spin: Double = 0

    var body: some View {
        ZStack {
            if let preview = state.preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size - 6, height: size - 6)
                    .clipShape(Circle())
                    .opacity(state.failed ? 0.4 : 0.9)
            } else {
                Circle()
                    .fill(WhisperTheme.card(colorScheme))
                    .frame(width: size - 6, height: size - 6)
            }

            Circle()
                .stroke(WhisperTheme.hairline(colorScheme), lineWidth: 3)
                .frame(width: size + 6, height: size + 6)

            Circle()
                .trim(from: 0, to: max(0.06, min(1, state.progress)))
                .stroke(
                    state.failed ? AnyShapeStyle(Color(red: 0.93, green: 0.22, blue: 0.22)) : AnyShapeStyle(WhisperBrandGradient.angular),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: size + 6, height: size + 6)
                .rotationEffect(.degrees(-90 + (state.progress < 1 ? spin : 0)))
                .animation(.easeOut(duration: 0.4), value: state.progress)

            if state.failed {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3)
            } else if state.progress >= 1 {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: size + 8, height: size + 8)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { spin = 360 }
        }
        .accessibilityLabel(state.failed ? "Story didn't post" : "Posting your story")
    }
}
