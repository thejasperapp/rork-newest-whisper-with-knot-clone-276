import SwiftUI
import Supabase

/// Browse, schedule, and join Whisper lives. Live rooms show interlocked
/// broadcaster avatars and a pulsing LIVE badge; scheduled lives show a
/// real-time countdown. Hosts can delete their lives — ended lives are
/// auto-removed, so only live + upcoming rooms ever appear here.
struct WhisperLiveRoomsListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var rooms: [WhisperLiveRoom] = []
    @State private var speakersByRoom: [String: [WhisperLiveSpeaker]] = [:]
    @State private var profiles: [String: WhisperBackendService.WhisperPublicProfile] = [:]
    @State private var invitedRoomIDs: Set<String> = []
    @State private var loading: Bool = false
    @State private var error: String? = nil
    @State private var showCreate: Bool = false
    @State private var createdRoom: WhisperLiveRoom? = nil
    @State private var selectedRoom: WhisperLiveRoom? = nil
    @State private var refreshing: Bool = false
    @State private var confirmDelete: WhisperLiveRoom? = nil
    @State private var active = false
    @State private var lifecycle = UUID()
    @State private var refreshTask: Task<Void, Never>?
    @State private var refreshPending = false

    private let liveRed = Color(red: 0.95, green: 0.15, blue: 0.35)

    private var liveNow: [WhisperLiveRoom] { rooms.filter { $0.is_live } }
    private var upcoming: [WhisperLiveRoom] { rooms.filter { $0.isUpcoming } }

    private var myUserID: String {
        SupabaseService.shared.client.auth.currentUser?.id.uuidString ?? ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        createButton
                        if let error {
                            HStack(spacing: 12) {
                                Text(error).font(.callout).foregroundStyle(WhisperTheme.ink(colorScheme))
                                Spacer(minLength: 0)
                                Button("Try again") { Task { await refresh() } }.disabled(refreshing).frame(minHeight: 44)
                            }.padding(16).background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
                        }

                        if loading && rooms.isEmpty {
                            ProgressView()
                                .tint(WhisperTheme.ink(colorScheme))
                                .padding(.top, 40)
                        } else if rooms.isEmpty && error == nil {
                            emptyState
                        } else {
                            if !liveNow.isEmpty {
                                sectionHeader("Live now", icon: "dot.radiowaves.left.and.right", tint: liveRed)
                                ForEach(liveNow) { room in
                                    liveCard(room)
                                }
                            }
                            if !upcoming.isEmpty {
                                sectionHeader("Upcoming", icon: "calendar", tint: .orange)
                                ForEach(upcoming) { room in
                                    upcomingCard(room)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .disabled(refreshing)
                }
            }
        }
        .onAppear {
            active = true
            lifecycle = UUID()
            Task { await refresh() }
            WhisperLiveRoomService.shared.subscribeToRoomsList(key: "live-hub") {
                Task { await refresh() }
            }
        }
        .onDisappear {
            active = false; lifecycle = UUID()
            refreshTask?.cancel(); refreshTask = nil
            refreshPending = false; refreshing = false; loading = false
            WhisperLiveRoomService.shared.unsubscribeFromRoomsList(key: "live-hub")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, active {
                WhisperLiveRoomService.shared.subscribeToRoomsList(key: "live-hub") { Task { await refresh() } }
                Task { await refresh() }
            } else if phase != .active {
                lifecycle = UUID(); refreshTask?.cancel(); refreshTask = nil
                refreshPending = false; refreshing = false; loading = false
                WhisperLiveRoomService.shared.unsubscribeFromRoomsList(key: "live-hub")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in
            active = false; lifecycle = UUID()
            refreshTask?.cancel(); refreshTask = nil; refreshPending = false
            WhisperLiveRoomService.shared.unsubscribeFromRoomsList(key: "live-hub")
            rooms = []; speakersByRoom = [:]; profiles = [:]; invitedRoomIDs = []
            dismiss()
        }
        .sheet(isPresented: $showCreate) {
            CreateLiveRoomSheet { room in
                createdRoom = room.is_live ? room : nil
                showCreate = false
                Task { await refresh() }
            }
        }
        .fullScreenCover(item: $createdRoom) { room in
            WhisperLiveRoomView(room: room, isHost: true)
        }
        .fullScreenCover(item: $selectedRoom) { room in
            WhisperLiveRoomView(room: room, isHost: isCurrentHost(room))
        }
        .confirmationDialog(
            "Delete this live?",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let room = confirmDelete {
                    Task {
                        try? await WhisperLiveRoomService.shared.deleteRoom(id: room.id)
                        confirmDelete = nil
                        await refresh()
                    }
                }
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("This removes the live for everyone. This can't be undone.")
        }
    }

    // MARK: - Sections

    private func sectionHeader(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.weight(.black))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer()
        }
    }

    private var createButton: some View {
        Button {
            Haptics.tap()
            showCreate = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: "video.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Go Live")
                        .font(.subheadline.weight(.black))
                    Text("Solo or with up to 3 friends")
                        .font(.caption2)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [liveRed, Color(red: 1.0, green: 0.45, blue: 0.25)],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 20)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            WhisperMeetDoodle(symbol: "dot.radiowaves.left.and.right", height: 144)
            Text("No lives right now")
                .font(.headline.weight(.bold))
            Text("Go live now or schedule one for later — invite friends to broadcast together.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    // MARK: - Cards

    private func liveCard(_ room: WhisperLiveRoom) -> some View {
        let speakers = speakersByRoom[room.id] ?? []
        let cohostCount = max(0, speakers.count - 1)
        return Button {
            Haptics.tap()
            selectedRoom = room
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    WhisperLiveRing(size: 66, lineWidth: 2.5)
                    WhisperAvatar(
                        username: profiles[room.host_id]?.username ?? "host",
                        size: 56,
                        imageURL: profiles[room.host_id]?.profile_image_url.flatMap { URL(string: $0) }
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Circle().fill(.white).frame(width: 5, height: 5)
                            Text("LIVE")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(liveRed, in: Capsule())

                        if cohostCount > 0 {
                            Text("+\(cohostCount) live together")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(liveRed)
                        }

                        if invitedRoomIDs.contains(room.id) {
                            Text("Invited")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(room.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("@\(profiles[room.host_id]?.username ?? "host")")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        HStack(spacing: 3) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 9))
                            Text("\(room.listener_count)")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(14)
            .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .contextMenu {
            ShareLink(item: room.shareURL) {
                Label("Share live link", systemImage: "square.and.arrow.up")
            }
            if isCurrentHost(room) {
                Button(role: .destructive) {
                    confirmDelete = room
                } label: {
                    Label("Delete live", systemImage: "trash")
                }
            }
        }
    }

    private func upcomingCard(_ room: WhisperLiveRoom) -> some View {
        let speakers = speakersByRoom[room.id] ?? []
        let isMine = isCurrentHost(room)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    WhisperLiveRing(size: 62, lineWidth: 2.5, isUpcoming: true)
                    WhisperAvatar(
                        username: profiles[room.host_id]?.username ?? "host",
                        size: 52,
                        imageURL: profiles[room.host_id]?.profile_image_url.flatMap { URL(string: $0) }
                    )
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("SCHEDULED")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.orange, in: Capsule())
                        if invitedRoomIDs.contains(room.id) {
                            Text("You're invited")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(room.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    Text("@\(profiles[room.host_id]?.username ?? "host")")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
            }

            // Live countdown, ticking every second.
            if let date = room.scheduledDate {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = date.timeIntervalSince(context.date)
                    HStack(spacing: 10) {
                        Image(systemName: "timer")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                        Text(remaining > 0 ? countdownText(remaining) : "Starting now")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.orange)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Spacer()
                        if isMine {
                            Button {
                                Haptics.tap()
                                Task { await startScheduled(room) }
                            } label: {
                                Text(remaining <= 0 ? "Start now" : "Go live early")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        remaining <= 0 ? liveRed : Color.orange,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }
            }

            HStack(spacing: 10) {
                ShareLink(item: room.shareURL) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(WhisperTheme.surface(colorScheme), in: Capsule())
                    .overlay(Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1))
                }
                if isMine {
                    Button {
                        Haptics.tap()
                        confirmDelete = room
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 20))
    }

    private func countdownText(_ remaining: TimeInterval) -> String {
        let total = Int(remaining)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Actions

    private func startScheduled(_ room: WhisperLiveRoom) async {
        if let live = try? await WhisperLiveRoomService.shared.goLive(id: room.id) {
            createdRoom = live
        }
        await refresh()
    }

    private func refresh() async {
        guard active, scenePhase == .active, !Task.isCancelled else { return }
        refreshPending = true
        if let refreshTask { await refreshTask.value; return }
        let token = lifecycle
        let generation = AccountStorage.generation
        refreshing = true
        loading = rooms.isEmpty
        let worker = Task { @MainActor in
            while refreshPending && active && scenePhase == .active && lifecycle == token && generation == AccountStorage.generation && !Task.isCancelled {
                refreshPending = false
                do {
                    let fetched = try await WhisperLiveRoomService.shared.fetchRooms()
                    guard active, scenePhase == .active, lifecycle == token, generation == AccountStorage.generation, !Task.isCancelled else { return }
                    rooms = fetched; loading = false; error = nil
                    let roomIDs = Set(fetched.map { $0.id })
                    speakersByRoom = speakersByRoom.filter { roomIDs.contains($0.key) }
                    invitedRoomIDs.formIntersection(roomIDs)
                    // Invitations only decorate room rows; room entry keeps its existing permission checks.
                    async let invitations = WhisperLiveRoomService.shared.myInvitedRoomIDs()
                    let map = await WhisperLiveRoomService.shared.fetchSpeakersForRooms(roomIDs: Array(roomIDs))
                    guard active, scenePhase == .active, lifecycle == token, generation == AccountStorage.generation, !Task.isCancelled else { return }
                    var ids = fetched.map { $0.host_id }
                    ids.append(contentsOf: map.values.flatMap { $0.map { $0.user_id } })
                    let nextProfiles = await WhisperLiveRoomService.shared.hydrateProfiles(userIDs: ids)
                    let invites = await invitations
                    guard active, scenePhase == .active, lifecycle == token, generation == AccountStorage.generation, !Task.isCancelled else { return }
                    speakersByRoom = map
                    profiles = nextProfiles; invitedRoomIDs = invites
                    error = nil
                } catch {
                    guard active, lifecycle == token, generation == AccountStorage.generation, !Task.isCancelled else { return }
                    self.error = "Lives couldn’t refresh just now. Please try again."
                }
            }
        }
        refreshTask = worker
        await worker.value
        if refreshTask == worker {
            refreshTask = nil
            loading = false; refreshing = false
        }
    }

    private func isCurrentHost(_ room: WhisperLiveRoom) -> Bool {
        guard !myUserID.isEmpty else { return false }
        return room.host_id.lowercased() == myUserID.lowercased()
    }
}

// MARK: - Create / schedule live sheet

/// Cinematic "Go Live" sheet — name + topic pills, optional co-host invites
/// (group lives up to 4), and optional scheduling with a date picker.
struct CreateLiveRoomSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let onCreated: (WhisperLiveRoom) -> Void

    @State private var name: String = ""
    @State private var topic: String = ""
    @State private var description: String = ""
    @State private var busy: Bool = false
    @State private var scheduleEnabled: Bool = false
    @State private var scheduledDate: Date = Date().addingTimeInterval(3600)
    @State private var showInvitePicker: Bool = false
    @State private var invited: [WhisperUserRow] = []
    @State private var errorText: String? = nil
    @State private var creationTask: Task<Void, Never>?
    @State private var closed: Bool = false
    @State private var generation: UUID = AccountStorage.generation

    private let liveRed = Color(red: 0.95, green: 0.15, blue: 0.35)

    private let topicPills: [(emoji: String, label: String)] = [
        ("💬", "Chat"), ("🏋️", "Training"), ("🎯", "Recruiting"),
        ("🎥", "Behind the scenes"), ("❓", "Q&A"), ("🎵", "Music"),
        ("🍳", "Cooking"), ("🎮", "Gaming")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        // Hero
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [liveRed, Color(red: 1.0, green: 0.45, blue: 0.25)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 56, height: 56)
                                Image(systemName: "video.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Go Live")
                                    .font(.title3.weight(.black))
                                Text("Broadcast solo or with up to 3 friends")
                                    .font(.subheadline)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        WhisperTextField(label: "Live title", text: $name, placeholder: "e.g. Friday night Q&A")

                        // Topic pills
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Topic")
                                .font(.subheadline.weight(.semibold))
                            FlowLayout(spacing: 8) {
                                ForEach(topicPills, id: \.label) { pill in
                                    Button {
                                        Haptics.tap()
                                        topic = topic == pill.label ? "" : pill.label
                                    } label: {
                                        Text("\(pill.emoji) \(pill.label)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(topic == pill.label ? .white : WhisperTheme.ink(colorScheme))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                topic == pill.label ? AnyShapeStyle(liveRed) : AnyShapeStyle(WhisperTheme.card(colorScheme)),
                                                in: Capsule()
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        WhisperTextField(label: "Description", text: $description, placeholder: "What's this live about?", axis: .vertical)

                        // Group live — invite co-hosts.
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Go live together", systemImage: "person.2.fill")
                                    .font(.subheadline.weight(.bold))
                                Spacer()
                                Button {
                                    Haptics.tap()
                                    showInvitePicker = true
                                } label: {
                                    Text(invited.isEmpty ? "Invite friends" : "Edit")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(liveRed)
                                }
                                .buttonStyle(.plain)
                            }
                            if invited.isEmpty {
                                Text("Invited friends join your broadcast grid the moment they open the live.")
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            } else {
                                HStack(spacing: -10) {
                                    ForEach(invited.prefix(3)) { user in
                                        WhisperAvatar(
                                            username: user.username,
                                            size: 36,
                                            imageURL: user.profile_image_url.flatMap { URL(string: $0) }
                                        )
                                        .overlay(Circle().strokeBorder(WhisperTheme.card(colorScheme), lineWidth: 2))
                                    }
                                    Text("  \(invited.map { "@" + $0.username }.joined(separator: ", "))")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(14)
                        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16))

                        // Schedule
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $scheduleEnabled.animation(.spring(response: 0.35, dampingFraction: 0.8))) {
                                Label("Schedule for later", systemImage: "calendar.badge.clock")
                                    .font(.subheadline.weight(.bold))
                            }
                            .tint(.orange)
                            if scheduleEnabled {
                                DatePicker(
                                    "Starts",
                                    selection: $scheduledDate,
                                    in: Date().addingTimeInterval(300)...,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .datePickerStyle(.compact)
                                Text("Your live stays visible with a countdown until it starts — it won't be deleted.")
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                        .padding(14)
                        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16))

                        if let errorText {
                            Text(errorText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }

                        Button {
                            guard !busy, !closed else { return }
                            creationTask = Task { await create() }
                        } label: {
                            HStack {
                                if busy { ProgressView().tint(.white) }
                                Image(systemName: scheduleEnabled ? "calendar.badge.clock" : "dot.radiowaves.left.and.right")
                                Text(scheduleEnabled ? "Schedule live" : "Go live now")
                                    .font(.subheadline.weight(.black))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                name.isEmpty
                                    ? AnyShapeStyle(Color.gray.opacity(0.5))
                                    : AnyShapeStyle(LinearGradient(
                                        colors: scheduleEnabled
                                            ? [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)]
                                            : [liveRed, Color(red: 1.0, green: 0.45, blue: 0.25)],
                                        startPoint: .leading, endPoint: .trailing
                                    )),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(name.isEmpty || busy)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("New Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { closed = true; dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme)).disabled(busy)
                }
            }
        }
        .interactiveDismissDisabled(busy)
        .onDisappear { if !showInvitePicker { closed = true; creationTask?.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            closed = true; creationTask?.cancel(); dismiss()
        }
        .sheet(isPresented: $showInvitePicker) {
            WhisperLiveInviteSheet(
                maxSelectable: WhisperLiveRoomService.maxBroadcasters - 1,
                onInvite: { chosen in
                    invited = chosen
                }
            )
        }
    }

    private func create() async {
        guard !busy, !closed, generation == AccountStorage.generation else { return }
        busy = true
        defer { busy = false }
        errorText = nil
        do {
            let room = try await WhisperLiveRoomService.shared.createRoom(
                name: name,
                description: description,
                topic: topic,
                scheduledAt: scheduleEnabled ? scheduledDate : nil
            )
            guard !closed, !Task.isCancelled, generation == AccountStorage.generation else { return }
            if !invited.isEmpty {
                await WhisperLiveRoomService.shared.invite(
                    roomID: room.id,
                    inviteeIDs: invited.map { $0.user_id }
                )
            }
            guard !closed, !Task.isCancelled, generation == AccountStorage.generation else { return }
            onCreated(room)
        } catch {
            guard !closed, !Task.isCancelled, generation == AccountStorage.generation else { return }
            errorText = "Couldn't create the live. Please try again."
        }
    }
}

struct WhisperTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(axis == .vertical ? 6 : 1)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
