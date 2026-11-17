import SwiftUI
import PhotosUI
import AVKit
import Supabase

nonisolated struct WhisperDisappearingItem: Codable, Identifiable, Sendable {
    let id: String
    let sender_id: String
    let recipient_id: String
    let mime: String
    let created_at: Date
    let expires_at: Date
    let opened_at: Date?
    let username: String?
    let display_name: String?
    @MainActor var otherID: String { sender_id.lowercased() == AccountStorage.currentUserID.lowercased() ? recipient_id : sender_id }

    enum CodingKeys: String, CodingKey { case id, sender_id, recipient_id, mime, created_at, expires_at, opened_at, username, display_name }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sender_id = try c.decode(String.self, forKey: .sender_id)
        recipient_id = try c.decode(String.self, forKey: .recipient_id)
        mime = try c.decode(String.self, forKey: .mime)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        display_name = try c.decodeIfPresent(String.self, forKey: .display_name)
        func date(_ key: CodingKeys) throws -> Date? {
            guard let raw = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let value = formatter.date(from: raw) { return value }
            formatter.formatOptions = [.withInternetDateTime]
            guard let value = formatter.date(from: raw) else { throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Invalid timestamp") }
            return value
        }
        guard let created = try date(.created_at), let expiry = try date(.expires_at) else { throw DecodingError.dataCorruptedError(forKey: .created_at, in: c, debugDescription: "Missing timestamp") }
        created_at = created; expires_at = expiry; opened_at = try date(.opened_at)
    }
}

nonisolated private struct DisappearingRequest: Encodable, Sendable {
    let action: String
    var id: String? = nil
    var recipient: String? = nil
    var mime: String? = nil
    var media: String? = nil
}
nonisolated private struct DisappearingList: Decodable, Sendable { let items: [WhisperDisappearingItem] }
nonisolated private struct DisappearingOK: Decodable, Sendable { let ok: Bool }
nonisolated private struct DisappearingBytes: Decodable, Sendable { let mime: String; let media: String }

@Observable final class WhisperDisappearingService {
    static let shared = WhisperDisappearingService()
    private(set) var items: [WhisperDisappearingItem] = []
    private(set) var loading = false
    var error: String?
    private var operation = UUID()
    private var owner = ""
    private var refreshedAt: Date?
    private let client = SupabaseService.shared.client

    private init() {
        // A terminated process cannot run onDisappear; remove only this viewer's residual files.
        if let files = try? FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("whisper-once-") { try? FileManager.default.removeItem(at: file) }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("WhisperMeetingAccountWillChange"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.clear() }
        }
    }
    func clear() { operation = UUID(); owner = ""; items = []; loading = false; error = nil; refreshedAt = nil }
    func refreshIfStale() async {
        guard owner != AccountStorage.currentUserID || refreshedAt == nil || Date().timeIntervalSince(refreshedAt!) > 15 else { return }
        await refresh()
    }
    func refresh() async {
        let account = AccountStorage.currentUserID
        let generation = AccountStorage.generation
        if owner != account { clear(); owner = account }
        guard UUID(uuidString: account) != nil, !loading else { return }
        let request = UUID(); operation = request; loading = true; error = nil
        defer { if operation == request { loading = false } }
        do {
            let result: DisappearingList = try await client.functions.invoke("whisper-disappearing", options: .init(body: DisappearingRequest(action: "list")))
            guard !Task.isCancelled, generation == AccountStorage.generation, operation == request else { return }
            items = result.items; refreshedAt = Date()
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation, operation == request else { return }
            self.error = "Couldn't refresh Flicks. Please try again."
        }
    }
    private func invalidateListRead() {
        // A list captured before a send/open must never restore stale receipt state.
        operation = UUID(); loading = false; refreshedAt = nil
    }
    func send(data: Data, mime: String, to recipient: String, attemptID: String) async throws {
        let epoch = AccountStorage.generation
        guard UUID(uuidString: recipient) != nil,
              recipient.lowercased() != AccountStorage.currentUserID.lowercased(),
              !WhisperBlockService.shared.isBlocked(userID: recipient) else { throw URLError(.noPermissionsToReadFile) }
        guard data.count <= 12_000_000, !data.isEmpty else { throw URLError(.dataLengthExceedsMaximum) }
        let media = await WhisperFlickPreparation.shared.base64(data)
        guard epoch == AccountStorage.generation, !Task.isCancelled,
              !WhisperBlockService.shared.isBlocked(userID: recipient) else { throw CancellationError() }
        let result: DisappearingOK = try await client.functions.invoke("whisper-disappearing", options: .init(body: DisappearingRequest(action: "send", id: attemptID, recipient: recipient, mime: mime, media: media)))
        guard epoch == AccountStorage.generation, !Task.isCancelled, result.ok else { throw CancellationError() }
        // Delivery is already confirmed; do not hold the composer open for a second request.
        invalidateListRead()
        Task { await self.refresh() }
    }
    func open(_ item: WhisperDisappearingItem) async throws -> (Data, String) {
        let epoch = AccountStorage.generation
        guard item.recipient_id.lowercased() == AccountStorage.currentUserID.lowercased(),
              item.opened_at == nil, item.expires_at > Date(),
              !WhisperBlockService.shared.isBlocked(userID: item.sender_id) else { throw URLError(.noPermissionsToReadFile) }
        let result: DisappearingBytes = try await client.functions.invoke("whisper-disappearing", options: .init(body: DisappearingRequest(action: "open", id: item.id)))
        guard epoch == AccountStorage.generation, !Task.isCancelled,
              !WhisperBlockService.shared.isBlocked(userID: item.sender_id),
              ["image/jpeg", "video/mp4", "video/quicktime"].contains(result.mime),
              let data = Data(base64Encoded: result.media), !data.isEmpty, data.count <= 12_000_000 else { throw CancellationError() }
        // Remove the unopened affordance immediately; no replay path retains these bytes.
        invalidateListRead()
        items.removeAll { $0.id == item.id }
        return (data, result.mime)
    }
}

private let disappearingBlue = LinearGradient(colors: [Color(red: 0.42, green: 0.62, blue: 0.92), Color(red: 0.55, green: 0.82, blue: 0.96)], startPoint: .topLeading, endPoint: .bottomTrailing)
private let flickAccent = Color(red: 0.42, green: 0.62, blue: 0.92)

struct WhisperDisappearingInbox: View {
    let query: String
    let active: Bool
    var composeRequest: Int = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @State private var service = WhisperDisappearingService.shared
    @State private var blocks = WhisperBlockService.shared
    @State private var composer = false
    @State private var recipient: String?
    @State private var recipientName: String?
    @State private var viewing: WhisperDisappearingItem?
    @State private var reporting: WhisperDisappearingItem?
    @State private var actionError: String?
    @State private var showsPrivacy = false
    @State private var contactDetails: WhisperDisappearingItem?
    @Namespace private var contactTransition

    private var threads: [[WhisperDisappearingItem]] {
        let available = service.items.filter { $0.expires_at > Date() && !blocks.isBlocked(userID: $0.otherID) }
        return Dictionary(grouping: available, by: \.otherID).values.filter { group in
            guard let first = group.first else { return false }
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return term.isEmpty || (first.username ?? "").localizedCaseInsensitiveContains(term) || (first.display_name ?? "").localizedCaseInsensitiveContains(term)
        }.sorted { ($0.first?.created_at ?? .distantPast) > ($1.first?.created_at ?? .distantPast) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("View once", systemImage: "square.stack.3d.up.fill")
                    .font(.subheadline.bold()).foregroundStyle(disappearingBlue)
                Spacer()
                Button { showsPrivacy = true } label: {
                    Image(systemName: "info.circle").font(.body.weight(.medium))
                        .foregroundStyle(WhisperTheme.ink(scheme)).frame(width: 44, height: 44)
                }.accessibilityLabel("Flicks privacy")
            }.padding(.horizontal, 20)
            if let error = service.error {
                HStack { Text(error).font(.caption); Spacer(); Button("Retry") { Task { await service.refresh() } }.disabled(service.loading) }
                    .padding(16)
            }
            if service.loading && service.items.isEmpty {
                ProgressView().tint(WhisperTheme.ink(scheme)).padding(12).accessibilityLabel("Refreshing Flicks")
            }
            if threads.isEmpty && !service.loading && service.error == nil {
                VStack(spacing: 24) {
                    Image(systemName: query.isEmpty ? "camera.fill" : "magnifyingglass")
                        .font(.system(size: 36, weight: .medium)).foregroundStyle(disappearingBlue)
                        .frame(width: 92, height: 92)
                        .background(flickAccent.opacity(0.09), in: .rect(cornerRadius: 32))
                        .rotationEffect(.degrees(query.isEmpty ? -8 : 0))
                    Text(query.isEmpty ? "Make it a moment." : "No matching chats")
                        .font(.title2.bold()).foregroundStyle(WhisperTheme.ink(scheme))
                    if query.isEmpty {
                        Button { Haptics.tap(); recipient = nil; recipientName = nil; composer = true } label: {
                            Label("Open camera", systemImage: "plus").font(.headline)
                                .foregroundStyle(WhisperTheme.surface(scheme)).padding(.horizontal, 22).padding(.vertical, 14)
                                .background(WhisperTheme.ink(scheme), in: Capsule())
                        }.buttonStyle(WhisperMomentPressStyle())
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 48)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(threads.compactMap { $0.first }) { latest in
                        threadRow(latest, items: service.items.filter { $0.otherID == latest.otherID && $0.expires_at > Date() })
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .top)
        .background(WhisperTheme.surface(scheme))
        .task(id: "\(active)|\(scenePhase)|\(AccountStorage.generation)") {
            guard active, scenePhase == .active else { return }
            while !Task.isCancelled {
                await service.refreshIfStale()
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
            }
        }
        .onChange(of: composeRequest) { _, _ in
            guard active else { return }
            recipient = nil; recipientName = nil; composer = true
        }
        .fullScreenCover(isPresented: $composer) {
            WhisperDisappearingComposer(initialRecipient: recipient, initialName: recipientName)
        }
        .fullScreenCover(item: $viewing, onDismiss: { Task { await service.refresh() } }) { item in
            WhisperDisappearingViewer(item: item)
        }
        .sheet(isPresented: $showsPrivacy) { WhisperMomentPrivacySheet() }
        .sheet(item: $contactDetails) { item in
            NavigationStack {
                WhisperDMDetailsView(user: WhisperUserRow(user_id: item.otherID, username: item.username ?? "Whisper member", display_name: item.display_name, bio: nil, interests: nil, profile_image_url: nil, onboarded_at: nil, is_private: nil), messages: [], conversationKey: "flicks:\(item.otherID)", isFlicks: true) { _ in }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { contactDetails = nil } } }
            }
            .presentationDetents([.large]).presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
            .modifier(WhisperPortraitDestination(sourceID: item.otherID, namespace: contactTransition))
        }
        .sheet(item: $reporting) { item in
            WhisperReportSheet(kind: .dm, targetID: item.id, targetUserID: item.otherID, targetUsername: item.username ?? "")
        }
        .alert("Couldn't block this person", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) { Button("OK") { actionError = nil } } message: { Text(actionError ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            composer = false; viewing = nil; reporting = nil; contactDetails = nil; showsPrivacy = false; recipient = nil; recipientName = nil; actionError = nil
        }
    }
    private func threadRow(_ latest: WhisperDisappearingItem, items: [WhisperDisappearingItem]) -> some View {
        let incoming = items.filter { $0.recipient_id.lowercased() == AccountStorage.currentUserID.lowercased() && $0.opened_at == nil }.sorted { $0.created_at < $1.created_at }
        let outgoing = latest.sender_id.lowercased() == AccountStorage.currentUserID.lowercased()
        let status = !incoming.isEmpty ? (incoming.first?.mime == "image/jpeg" ? "New photo" : "New video") : latest.opened_at != nil ? "Opened" : outgoing ? "Delivered" : "Received"
        return HStack(spacing: 12) {
            Button { Haptics.tap(); contactDetails = latest } label: {
                WhisperFlickAvatar(username: latest.username ?? "", size: WhisperConversationPortraitSize.inbox, opensStories: false)
                    .matchedTransitionSource(id: latest.otherID, in: contactTransition)
            }.buttonStyle(WhisperPortraitPressStyle())
                .accessibilityLabel("\(latest.username ?? "Whisper member"), Flicks conversation details")
            Button {
                if let next = incoming.first { viewing = next }
                else { recipient = latest.otherID; recipientName = latest.username; composer = true }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(latest.display_name?.isEmpty == false ? latest.display_name! : latest.username ?? "Whisper member")
                            .font(.body.weight(incoming.isEmpty ? .medium : .bold)).foregroundStyle(WhisperTheme.ink(scheme)).lineLimit(1)
                        HStack(spacing: 5) {
                            Image(systemName: !incoming.isEmpty ? "square.fill" : outgoing ? "paperplane" : "square")
                                .foregroundStyle(disappearingBlue)
                            Text(incoming.count > 1 ? "\(incoming.count) new Flicks" : status).fontWeight(incoming.isEmpty ? .regular : .semibold)
                            Text("·")
                            Text(latest.created_at, style: .relative)
                        }.font(.caption).foregroundStyle(incoming.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(disappearingBlue)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 14).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(latest.display_name?.isEmpty == false ? latest.display_name! : latest.username ?? "Whisper member"), \(incoming.count > 1 ? "\(incoming.count) new Flicks" : status)")
                .accessibilityHint(incoming.isEmpty ? "Opens the camera to reply" : "Opens the oldest unopened Flick once")
            Button { recipient = latest.otherID; recipientName = latest.username; composer = true } label: {
                Image(systemName: "camera").font(.title3).foregroundStyle(.secondary).frame(width: 44, height: 44)
            }.accessibilityLabel("Send to \(latest.username ?? "this person")")
        }.padding(.horizontal, 16)
            .overlay(alignment: .bottom) { Divider().padding(.leading, 64) }
            .contextMenu {
                Button("Report", systemImage: "flag") { reporting = latest }
                Button("Block", systemImage: "hand.raised", role: .destructive) {
                    Task {
                        let epoch = AccountStorage.generation
                        let ok = await blocks.block(userID: latest.otherID, username: latest.username ?? "")
                        guard epoch == AccountStorage.generation else { return }
                        if !ok { actionError = "Please try again in a moment." }
                        await service.refresh()
                    }
                }
            }
    }
}

private struct WhisperDisappearingComposer: View {
    let initialRecipient: String?
    let initialName: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var cameraHolder = SnapCameraHolder()
    private var camera: SnapCameraSession { cameraHolder.session }
    @State private var follows = WhisperFollowService.shared
    @State private var followedProfiles: [WhisperUserRow] = []
    @State private var loadingPeople = false
    @State private var peopleLoadedAt: Date?
    @State private var textLayer = WaveTextOverlay()
    @State private var editingText = false
    @State private var mediaAspect: CGFloat = 9 / 16
    @State private var previewHeight: CGFloat = 1
    @State private var previewWidth: CGFloat = 1
    @FocusState private var textFocused: Bool
    @State private var recipient: String?
    @State private var recipientName: String?
    @State private var recipientQuery = ""
    @State private var results: [WhisperUserRow] = []
    @State private var searching = false
    @State private var picker: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var movie: URL?
    @State private var recording = false
    @State private var busy = false
    @State private var sending = false
    @State private var preparedMedia: (data: Data, mime: String)?
    @State private var problem: String?
    @State private var captureRevision = UUID()
    @State private var sendID = UUID().uuidString.lowercased()
    @State private var recordLimit: Task<Void, Never>?
    @State private var work: Task<Void, Never>?
    @State private var closed = false
    @State private var choosingRecipient = false
    @State private var videoMode = false
    @State private var recordingStarted = Date()
    @State private var showsPrivacy = false
    @State private var sent = false
    @State private var confirmsDiscard = false
    @State private var retaking = false
    @State private var searchRetry = 0
    @State private var searchFailed = false
    @State private var searchOperation = UUID()
    @State private var peopleOperation = UUID()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool

    private var hasMedia: Bool { photo != nil || movie != nil }
    private var captureDisabled: Bool { busy || !camera.isAvailable || camera.isDenied || camera.isRestricted }
    private var followedPeople: [WhisperUserRow] {
        let hydrated = Dictionary(followedProfiles.map { ($0.user_id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        return follows.following.sorted().compactMap { id in
            guard !WhisperBlockService.shared.isBlocked(userID: id), id.lowercased() != AccountStorage.currentUserID.lowercased() else { return nil }
            if let row = hydrated[id.lowercased()] { return row }
            guard let name = follows.followingUsernames[id] else { return nil }
            return WhisperUserRow(user_id: id, username: name, display_name: nil, bio: nil, interests: nil, profile_image_url: nil, onboarded_at: nil, is_private: nil)
        }.sorted { ($0.display_name ?? $0.username).localizedStandardCompare($1.display_name ?? $1.username) == .orderedAscending }
    }
    private var recentPeople: [WhisperDisappearingItem] {
        var seen = Set<String>()
        return WhisperDisappearingService.shared.items.filter {
            $0.expires_at > Date() && $0.otherID.lowercased() != AccountStorage.currentUserID.lowercased()
                && !WhisperBlockService.shared.isBlocked(userID: $0.otherID)
                && seen.insert($0.otherID.lowercased()).inserted
        }.prefix(8).map { $0 }
    }

    var body: some View {
        NavigationStack {
            cameraScreen
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showsPrivacy) { WhisperMomentPrivacySheet() }
                .sheet(isPresented: $choosingRecipient, onDismiss: {
                    searchFocused = false
                    if !closed, !hasMedia, !showsPrivacy { camera.configure() }
                }) {
                    NavigationStack {
                        recipientPicker
                            .navigationTitle("Send to")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { choosingRecipient = false }
                                }
                            }
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
        }
        .onAppear { recipient = initialRecipient; recipientName = initialName; camera.configure() }
        .task(id: choosingRecipient) {
            guard choosingRecipient else { return }
            let epoch = AccountStorage.generation, operation = UUID()
            peopleOperation = operation; loadingPeople = true
            defer { if epoch == AccountStorage.generation, peopleOperation == operation { loadingPeople = false } }
            await follows.refreshIfStale()
            guard !closed, !Task.isCancelled, epoch == AccountStorage.generation else { return }
            if let peopleLoadedAt, Date().timeIntervalSince(peopleLoadedAt) < 60 { return }
            let profiles = await follows.followingProfiles(limit: 100)
            guard !closed, !Task.isCancelled, epoch == AccountStorage.generation, peopleOperation == operation else { return }
            followedProfiles = profiles
            peopleLoadedAt = Date()
        }
        .confirmationDialog(retaking ? "Retake this Flick?" : "Discard this Flick?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button(retaking ? "Retake" : "Discard", role: .destructive) {
                if retaking { clearMedia(); camera.configure() } else { close() }
            }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("Your photo or video and text will not be saved.")
        }
        .sheet(isPresented: $editingText) { textEditor }
        .task(id: movie) {
            guard let movie else { return }
            let epoch = AccountStorage.generation
            if let poster = await WhisperStoryPoster.firstFrame(of: movie, maxSize: CGSize(width: 320, height: 560)),
               !closed, !Task.isCancelled, epoch == AccountStorage.generation, self.movie == movie {
                mediaAspect = poster.size.width / max(1, poster.size.height)
            }
        }
        .onChange(of: textLayer) { _, _ in sendID = UUID().uuidString.lowercased(); preparedMedia = nil }
        .onDisappear { closed = true; captureRevision = UUID(); work?.cancel(); recordLimit?.cancel(); camera.cancelRecording(); camera.stop(); clearMedia() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { close() }
            // System camera/microphone permission alerts temporarily make the scene inactive.
            // Preserve capture intent through those alerts; resume after returning from Settings.
            else if phase == .active, !closed, !choosingRecipient, !hasMedia, !showsPrivacy { camera.configure() }
        }
        .onChange(of: picker) { _, item in
            if let item {
                work?.cancel(); captureRevision = UUID()
                work = Task { await importMedia(item) }
            }
        }
        .onChange(of: showsPrivacy) { _, showing in
            if showing { camera.stop() }
            else if !choosingRecipient, !hasMedia, !closed { camera.configure() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in close() }
    }

    private var recipientPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "1.circle.fill").foregroundStyle(flickAccent)
                Text("Choose one person. They can open your Flick once.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical, 20)
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.body.weight(.semibold)).foregroundStyle(disappearingBlue)
                TextField("Search people", text: $recipientQuery)
                    .font(.body).textInputAutocapitalization(.never).autocorrectionDisabled().focused($searchFocused)
                    .submitLabel(.search)
                if !recipientQuery.isEmpty {
                    Button { recipientQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(WhisperTheme.muted(scheme)) }
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(16).modifier(WhisperControlGlass(shape: RoundedRectangle(cornerRadius: 24)))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(searchFocused ? flickAccent.opacity(0.6) : Color.clear, lineWidth: 1.5).allowsHitTesting(false) }
            .padding(.bottom, 20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if recipientQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if !followedPeople.isEmpty {
                            Text("Following").font(.headline).foregroundStyle(WhisperTheme.ink(scheme)).padding(.vertical, 10)
                            ForEach(followedPeople) { person in
                                personRow(id: person.user_id, username: person.username, name: person.display_name, imageURL: person.profile_image_url.flatMap(URL.init(string:)))
                            }
                        }
                        if !recentPeople.isEmpty {
                            Text("Recent").font(.headline).foregroundStyle(WhisperTheme.ink(scheme)).padding(.vertical, 10)
                            ForEach(recentPeople) { person in
                                personRow(id: person.otherID, username: person.username ?? "", name: person.display_name)
                            }
                        } else if followedPeople.isEmpty && !loadingPeople {
                            Button { searchFocused = true } label: {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 54, weight: .light)).foregroundStyle(disappearingBlue)
                                    .frame(maxWidth: .infinity).padding(.vertical, 64)
                            }.accessibilityLabel("Search for someone to send to")
                        }
                        if loadingPeople && followedPeople.isEmpty { ProgressView().tint(WhisperTheme.ink(scheme)).padding(24) }
                    } else {
                        if searching { ProgressView().tint(flickAccent).frame(maxWidth: .infinity).padding(24) }
                        ForEach(results) { user in
                            personRow(id: user.user_id, username: user.username, name: user.display_name, imageURL: user.profile_image_url.flatMap(URL.init(string:)))
                        }
                    }
                    if let problem {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(problem, systemImage: searchFailed ? "exclamationmark.circle" : "magnifyingglass")
                                .font(.callout.weight(.medium))
                            if searchFailed { Button("Try again") { searchRetry += 1 }.frame(minHeight: 44) }
                        }.foregroundStyle(WhisperTheme.ink(scheme)).padding(.vertical, 18)
                            .accessibilityElement(children: .contain)
                    }
                }
            }.scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        .background(WhisperTheme.surface(scheme).ignoresSafeArea())
        .buttonStyle(WhisperMomentPressStyle())
        .task(id: "\(recipientQuery)|\(searchRetry)") {
            let operation = UUID(); searchOperation = operation
            results = []; problem = nil; searching = false; searchFailed = false
            let term = recipientQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return }
            let epoch = AccountStorage.generation
            searching = true
            defer { if searchOperation == operation { searching = false } }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            do {
                // This picker owns its failure state; another screen's search cannot overwrite it.
                let found = try await WhisperUserService.shared.mentionSuggestions(term, limit: 30, matchingNames: true)
                guard !Task.isCancelled, !closed, epoch == AccountStorage.generation, choosingRecipient,
                      searchOperation == operation, term == recipientQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                results = found.filter { $0.user_id.lowercased() != AccountStorage.currentUserID.lowercased() && !WhisperBlockService.shared.isBlocked(userID: $0.user_id) }
                if results.isEmpty { problem = "No people found. Try a name or username." }
            } catch {
                guard !Task.isCancelled, !closed, epoch == AccountStorage.generation, choosingRecipient,
                      searchOperation == operation, term == recipientQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                searchFailed = true; problem = "People couldn’t load. Check your connection and try again."
            }
        }
    }

    private func personRow(id: String, username: String, name: String?, imageURL: URL? = nil) -> some View {
        Button {
            guard !WhisperBlockService.shared.isBlocked(userID: id) else { return }
            Haptics.tap(); searchFocused = false
            if recipient?.lowercased() != id.lowercased() { sendID = UUID().uuidString.lowercased() }
            results = []; problem = nil
            recipient = id; recipientName = username; choosingRecipient = false
        } label: {
            HStack(spacing: 14) {
                WhisperFlickAvatar(username: username, size: 48, imageURL: imageURL, opensStories: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name?.isEmpty == false ? name! : username).font(.headline).foregroundStyle(WhisperTheme.ink(scheme)).lineLimit(1)
                    if name?.isEmpty == false { Text("@\(username)").font(.subheadline).foregroundStyle(WhisperTheme.muted(scheme)).lineLimit(1) }
                }
                Spacer(minLength: 8)
                Image(systemName: recipient?.lowercased() == id.lowercased() ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(recipient?.lowercased() == id.lowercased() ? flickAccent : WhisperTheme.muted(scheme).opacity(0.4))
                    .frame(width: 44, height: 44)
            }.padding(.vertical, 12).contentShape(Rectangle())
        }.accessibilityLabel("Choose \(name?.isEmpty == false ? name! : username)")
            .accessibilityHint(hasMedia ? "Returns to your preview. Nothing is sent yet." : "Returns to the camera")
            .accessibilityAddTraits(recipient?.lowercased() == id.lowercased() ? .isSelected : [])
    }

    private var cameraScreen: some View {
        ZStack {
            cameraStage.ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.4), .clear, .clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 12) {
                cameraHeader
                Spacer(minLength: 12)
                if recording { recordingProgress }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.circle.fill")
                        .font(.callout.weight(.medium)).foregroundStyle(.white)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(WhisperControlGlass(shape: RoundedRectangle(cornerRadius: 22)))
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if hasMedia { sendControls } else { captureControls }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
            .frame(maxWidth: 680)
            .allowsHitTesting(!sent)
            if sent {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark").font(.system(size: 36, weight: .bold))
                        .frame(width: 80, height: 80).background(disappearingBlue, in: Circle())
                    Text("Sent").font(.title2.bold())
                }.foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.55)).ignoresSafeArea().transition(.opacity)
                    .accessibilityLabel("Flick sent")
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .buttonStyle(WhisperMomentPressStyle())
    }

    private var cameraHeader: some View {
            HStack(spacing: 10) {
                Button {
                    Haptics.tap(); camera.stop(); problem = nil
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .whisperSmooth) { choosingRecipient = true }
                } label: {
                    HStack(spacing: 8) {
                        if let recipientName, !recipientName.isEmpty { WhisperFlickAvatar(username: recipientName, size: 32, opensStories: false) }
                        else { Image(systemName: "person.crop.circle.badge.plus").font(.title3).foregroundStyle(disappearingBlue) }
                        Text(recipientName?.isEmpty == false ? "@\(recipientName!)" : "Send to")
                            .font(.subheadline.bold()).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2.bold())
                    }.foregroundStyle(.white).padding(.horizontal, 14).frame(minHeight: 48)
                        .modifier(WhisperControlGlass(shape: Capsule()))
                }.disabled(recording || sending || busy).accessibilityLabel(recipient == nil ? "Choose recipient" : "Change recipient")
                Spacer(minLength: 0)
                Button { showsPrivacy = true } label: { cameraIcon("info") }
                    .disabled(recording || busy || sending).accessibilityLabel("Privacy details")
                Button {
                    if hasMedia && !sent { retaking = false; confirmsDiscard = true }
                    else { close() }
                } label: { cameraIcon("xmark") }.disabled(sending || busy || recording).accessibilityLabel("Close camera")
            }
    }

    private var cameraStage: some View {
            ZStack {
                Color(white: 0.07)
                captureArea
                if hasMedia {
                    GeometryReader { proxy in
                        let frame = fittedMedia(in: proxy.size)
                        WhisperFlickTextPreview(text: textLayer, aspect: mediaAspect).equatable()
                            .frame(width: frame.width, height: frame.height)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }.allowsHitTesting(false)
                }
                if busy && !hasMedia { ProgressView().tint(.white).padding(20).background(.black.opacity(0.5), in: Circle()) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { if hasMedia && !sending && !busy { editingText = true } }
            .gesture(DragGesture(minimumDistance: 10).onChanged { value in
                guard hasMedia, !sending, !busy, !textLayer.text.isEmpty else { return }
                let mediaHeight = min(previewHeight, previewWidth / max(0.1, mediaAspect))
                let topInset = (previewHeight - mediaHeight) / 2
                textLayer.y = min(0.8, max(0.2, Double((value.location.y - topInset) / max(1, mediaHeight))))
            })
            .onGeometryChange(for: CGSize.self) { $0.size } action: { previewHeight = $0.height; previewWidth = $0.width }
            .clipped()
    }

    private var recordingProgress: some View {
                    TimelineView(.periodic(from: recordingStarted, by: 0.1)) { context in
                        let elapsed = min(15, max(0, context.date.timeIntervalSince(recordingStarted)))
                        VStack(spacing: 10) {
                            ProgressView(value: elapsed, total: 15).tint(flickAccent)
                            HStack(spacing: 6) {
                                Circle().fill(flickAccent).frame(width: 7, height: 7)
                                Text(String(format: "0:%02d / 0:15", Int(elapsed))).monospacedDigit().font(.subheadline.bold())
                            }.foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.black.opacity(0.6), in: Capsule())
                        }.padding(18)
                    }.allowsHitTesting(false)
    }

    private func cameraIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .modifier(WhisperControlGlass(shape: Circle()))
    }

    private var captureControls: some View {
        VStack(spacing: 20) {
            HStack(spacing: 6) {
                ForEach([false, true], id: \.self) { video in
                    Button { Haptics.tap(); withAnimation(reduceMotion ? nil : .whisperSnappy) { videoMode = video } } label: {
                        Text(video ? "Video · 15s" : "Photo").font(.subheadline.bold())
                            .foregroundStyle(videoMode == video ? Color.black : Color.white)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background { if videoMode == video { Capsule().fill(.white) } }
                    }.disabled(recording || busy).accessibilityAddTraits(videoMode == video ? .isSelected : [])
                }
            }.padding(4).modifier(WhisperControlGlass(shape: Capsule()))
            HStack {
                PhotosPicker(selection: $picker, matching: .any(of: [.images, .videos])) {
                    cameraIcon("photo.on.rectangle")
                }.disabled(recording || busy).accessibilityLabel("Choose from library")
                Spacer()
                Button {
                    Haptics.tap()
                    if recording { stopRecording() }
                    else if videoMode { startRecording() }
                    else { takePhoto() }
                } label: {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 3).frame(width: 76, height: 76)
                        RoundedRectangle(cornerRadius: recording ? 8 : 34)
                            .fill(recording ? Color.red : Color.white)
                            .frame(width: recording ? 26 : 60, height: recording ? 26 : 60)
                        if busy { ProgressView().tint(.black) }
                    }.frame(width: 88, height: 88)
                        .modifier(WhisperControlGlass(shape: Circle())).contentShape(Circle())
                        .animation(reduceMotion ? nil : .whisperSnappy, value: recording)
                }.disabled(captureDisabled)
                    .accessibilityLabel(recording ? "Stop recording" : videoMode ? "Record video" : "Take photo")
                Spacer()
                Button { Haptics.tap(); camera.flipCamera() } label: { cameraIcon("arrow.triangle.2.circlepath.camera") }
                    .disabled(recording || busy || !camera.isAvailable || camera.isDenied || camera.isRestricted).accessibilityLabel("Flip camera")
            }.padding(.horizontal, 12)
        }.padding(.top, 4).padding(.bottom, 8)
    }

    private var sendControls: some View {
        HStack(spacing: 14) {
            Button { Haptics.tap(); retaking = true; confirmsDiscard = true } label: {
                cameraIcon("arrow.counterclockwise")
            }.disabled(sending || busy).accessibilityLabel("Retake")
            Button { editingText = true } label: { cameraIcon("textformat") }
                .disabled(sending || busy).accessibilityLabel("Add or edit text")
            Button {
                Haptics.tap()
                if recipient == nil {
                    problem = nil
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .whisperSmooth) { choosingRecipient = true }
                } else { work = Task { await send() } }
            } label: {
                HStack(spacing: 12) {
                    if sending && !sent { ProgressView().tint(Color(red: 0.04, green: 0.14, blue: 0.22)) }
                    Text(sent ? "Sent" : sending ? "Sending…" : recipient == nil ? "Send to" : "Send once").font(.headline)
                        .contentTransition(.identity)
                    Image(systemName: sent ? "checkmark" : "arrow.up.right").font(.body.weight(.semibold))
                }.foregroundStyle(Color(red: 0.04, green: 0.14, blue: 0.22)).padding(.horizontal, 18).frame(minHeight: 52)
                    .frame(maxWidth: .infinity)
                    .modifier(WhisperFlickSendGlass())
            }.disabled(sending || busy || sent)
                .accessibilityLabel(sent ? "Flick sent" : sending ? "Sending Flick" : recipientName.map { "Send once to @\($0)" } ?? "Choose who to send to")
                .accessibilityHint("The recipient can open this photo or video once")
        }.padding(.vertical, 12)
    }

    private func fittedMedia(in size: CGSize) -> CGSize {
        let width = min(size.width, size.height * mediaAspect)
        return CGSize(width: width, height: width / max(0.1, mediaAspect))
    }

    private var textEditor: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 24) {
                TextField("Say something…", text: $textLayer.text, axis: .vertical)
                    .font(textLayer.font.swiftUIFont(size: 28)).multilineTextAlignment(.center)
                    .lineLimit(2...6).focused($textFocused).padding(24)
                    .foregroundStyle(WhisperTheme.ink(scheme))
                    .onChange(of: textLayer.text) { _, value in
                        if value.count > 160 { textLayer.text = String(value.prefix(160)) }
                    }
                Text("\(textLayer.text.count) / 160")
                    .font(.caption.monospacedDigit()).foregroundStyle(WhisperTheme.muted(scheme))
                    .accessibilityLabel("\(textLayer.text.count) of 160 characters")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(WaveTextFont.allCases) { font in
                            Button { textLayer.font = font } label: {
                                Text(font.rawValue.capitalized).font(font.swiftUIFont(size: 16))
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                    .foregroundStyle(textLayer.font == font ? WhisperTheme.surface(scheme) : WhisperTheme.ink(scheme))
                                    .background(textLayer.font == font ? WhisperTheme.ink(scheme) : WhisperTheme.card(scheme), in: Capsule())
                            }.accessibilityAddTraits(textLayer.font == font ? .isSelected : [])
                        }
                    }.padding(.horizontal, 24)
                }
                HStack(spacing: 12) {
                    ForEach(["FFFFFF", "0C1014", "FFC94D", "FF4D8D", "9BE8C4"], id: \.self) { hex in
                        Button { textLayer.colorHex = hex } label: {
                            Circle().fill(WaveTextPalette.color(hex)).frame(width: 28, height: 28)
                                .padding(5).overlay { Circle().strokeBorder(textLayer.colorHex == hex ? WhisperTheme.ink(scheme) : WhisperTheme.hairline(scheme), lineWidth: 2) }
                        }.frame(minWidth: 44, minHeight: 44)
                            .accessibilityAddTraits(textLayer.colorHex == hex ? .isSelected : [])
                            .accessibilityLabel(hex == "FFFFFF" ? "White text" : hex == "0C1014" ? "Black text" : hex == "FFC94D" ? "Gold text" : hex == "FF4D8D" ? "Pink text" : "Mint text")
                    }
                }
                HStack {
                    Button { textLayer.style = (textLayer.style + 1) % 3 } label: {
                        Image(systemName: "a.square").font(.title2).frame(width: 44, height: 44)
                    }.accessibilityLabel("Change text background")
                        .accessibilityValue(textLayer.style == 0 ? "None" : textLayer.style == 1 ? "Style one" : "Style two")
                    Slider(value: $textLayer.scale, in: 0.7...1.6).tint(WhisperTheme.ink(scheme)).accessibilityLabel("Text size")
                    Button { textLayer.text = ""; editingText = false } label: {
                        Image(systemName: "trash").frame(width: 44, height: 44)
                    }.accessibilityLabel("Remove text")
                }.padding(.horizontal, 24)
                HStack {
                    Text("Position").font(.subheadline)
                    Slider(value: $textLayer.y, in: 0.2...0.8).tint(WhisperTheme.ink(scheme))
                        .accessibilityLabel("Text vertical position")
                        .accessibilityValue("\(Int(textLayer.y * 100)) percent from the top")
                }.padding(.horizontal, 24)
            }.padding(.vertical, 20)
            }.scrollDismissesKeyboard(.interactively)
            .background(WhisperTheme.surface(scheme))
            .navigationTitle("Text").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { textFocused = false; editingText = false }.tint(WhisperTheme.ink(scheme)) } }
            .onAppear { textFocused = true }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }

    @ViewBuilder private var captureArea: some View {
        if let movie { WhisperStoryVideoStage(url: movie, muted: true).frame(maxWidth: .infinity, maxHeight: .infinity) }
        else if let photo { Image(uiImage: photo).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
        else if camera.isDenied || camera.isRestricted {
            ContentUnavailableView { Label("Camera access is off", systemImage: "camera") } actions: {
                if !camera.isRestricted { Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.tint(flickAccent) }
            }
        } else if !camera.isAvailable {
            ContentUnavailableView { Label("No camera available", systemImage: "camera") } actions: {
                PhotosPicker(selection: $picker, matching: .any(of: [.images, .videos])) { Text("Choose from library") }.tint(flickAccent)
            }
        } else { SnapCameraPreview(session: camera.session) }
    }
    private func close() { closed = true; editingText = false; showsPrivacy = false; textFocused = false; searchFocused = false; captureRevision = UUID(); work?.cancel(); recordLimit?.cancel(); camera.cancelRecording(); camera.stop(); clearMedia(); dismiss() }
    private func clearMedia() { preparedMedia = nil; textLayer = WaveTextOverlay(); sendID = UUID().uuidString.lowercased(); if let movie { try? FileManager.default.removeItem(at: movie) }; movie = nil; photo = nil; picker = nil; problem = nil }
    private func takePhoto() {
        guard !busy, !closed else { return }
        busy = true; let revision = captureRevision; let epoch = AccountStorage.generation
        camera.capturePhoto(filter: .none, mirrored: camera.position == .front) { image in
            guard !closed, revision == captureRevision, epoch == AccountStorage.generation else { return }
            busy = false
            if let image { photo = image; mediaAspect = image.size.width / max(1, image.size.height); camera.stop() } else { problem = "Couldn't take that photo. Please try again." }
        }
    }
    private func startRecording() {
        guard !recording, !busy, !closed else { return }
        busy = true; let revision = captureRevision; let epoch = AccountStorage.generation
        work = Task {
            await camera.prepareRecordingAudio()
            guard !closed, !Task.isCancelled, revision == captureRevision, epoch == AccountStorage.generation else { return }
            busy = false; recordingStarted = Date(); recording = true
            camera.startRecording { url in
                guard !closed, revision == captureRevision, epoch == AccountStorage.generation else { if let url { try? FileManager.default.removeItem(at: url) }; return }
                recording = false; busy = false
                guard let url else { problem = "Couldn't record that video. Please try again."; return }
                movie = url; camera.stop()
            }
            recordLimit = Task { do { try await Task.sleep(for: .seconds(15)) } catch { return }; if recording { stopRecording() } }
        }
    }
    private func stopRecording() { recordLimit?.cancel(); recording = false; busy = true; camera.stopRecording() }
    private func importMedia(_ item: PhotosPickerItem) async {
        let epoch = AccountStorage.generation, revision = captureRevision; busy = true; problem = nil; preparedMedia = nil
        defer { if epoch == AccountStorage.generation, revision == captureRevision { busy = false; picker = nil } }
        do {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                guard let imported = try await item.loadTransferable(type: WhisperPickedMovie.self) else { throw URLError(.cannotDecodeContentData) }
                guard !closed, !Task.isCancelled, epoch == AccountStorage.generation, revision == captureRevision else { try? FileManager.default.removeItem(at: imported.url); return }
                let duration = await WhisperStoryPoster.duration(of: imported.url)
                guard !closed, !Task.isCancelled, epoch == AccountStorage.generation, revision == captureRevision else { try? FileManager.default.removeItem(at: imported.url); return }
                guard duration > 0, duration <= 15 else { try? FileManager.default.removeItem(at: imported.url); problem = "Choose a video up to 15 seconds long."; return }
                movie = imported.url; photo = nil
            } else {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                guard !closed, !Task.isCancelled, epoch == AccountStorage.generation, revision == captureRevision else { return }
                photo = image; mediaAspect = image.size.width / max(1, image.size.height)
            }
            // A failed import keeps the previous draft's retry identity intact.
            sendID = UUID().uuidString.lowercased()
            camera.stop()
        } catch { if !closed, !Task.isCancelled, epoch == AccountStorage.generation, revision == captureRevision { problem = "Couldn't open that media. Please choose another." } }
    }
    private func send() async {
        guard !sending, !closed, let recipient else { return }
        let epoch = AccountStorage.generation; sending = true; problem = nil
        defer { if epoch == AccountStorage.generation { sending = false } }
        do {
            let data: Data; let mime: String
            if let preparedMedia {
                data = preparedMedia.data; mime = preparedMedia.mime
            } else if let movie {
                let duration = await WhisperStoryPoster.duration(of: movie)
                guard duration > 0, duration <= 15.5 else { problem = "Choose a video up to 15 seconds long."; return }
                var delivered = movie
                if !textLayer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    guard let edited = await WhisperWaveStudio.bake(url: movie, trimStart: 0, trimEnd: duration, totalDuration: duration, muteOriginal: false, musicURL: nil, musicVolume: 0, texts: [textLayer]) else {
                        problem = "Couldn't finish the text edit. Your video is still here. Please try again."; return
                    }
                    delivered = edited
                }
                defer { if delivered != movie { try? FileManager.default.removeItem(at: delivered) } }
                guard !closed, !Task.isCancelled, epoch == AccountStorage.generation else { return }
                data = try await WhisperFlickPreparation.shared.fileData(delivered); mime = delivered.pathExtension.lowercased() == "mp4" ? "video/mp4" : "video/quicktime"
            } else if let photo {
                // Apply the same bounded, orientation-normalized canvas with or without a caption.
                guard let jpeg = await WhisperFlickCanvas.photoData(photo, text: textLayer) else { problem = "Couldn’t prepare your photo. Your draft is still here."; return }
                data = jpeg; mime = "image/jpeg"
            }
            else { return }
            guard data.count <= 12_000_000 else { problem = "This file is too large. Choose a photo or video smaller than 12 MB."; return }
            guard !closed, !Task.isCancelled, epoch == AccountStorage.generation else { return }
            // Only an unchanged outgoing draft is reused, in memory, for an explicit retry.
            preparedMedia = (data, mime)
            try await WhisperDisappearingService.shared.send(data: data, mime: mime, to: recipient, attemptID: sendID)
            guard !closed, epoch == AccountStorage.generation, !Task.isCancelled else { return }
            Haptics.tap()
            withAnimation(reduceMotion ? nil : .whisperSnappy) { sent = true }
            try await Task.sleep(for: .milliseconds(650))
            guard !closed, epoch == AccountStorage.generation, !Task.isCancelled else { return }
            close()
        } catch {
            guard !closed, epoch == AccountStorage.generation, !Task.isCancelled else { return }
            if (error as? URLError)?.code == .dataLengthExceedsMaximum {
                problem = "This file is too large. Choose a photo or video smaller than 12 MB."
            } else {
                problem = "Delivery isn’t confirmed. Your draft is still here. Check your connection and try Send once again; an unchanged retry won’t send a duplicate."
            }
        }
    }
}

private struct WhisperFlickSendGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let blue = Color(red: 0.65, green: 0.85, blue: 1)

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(blue, in: Capsule())
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(blue).interactive(), in: Capsule())
        } else {
            content.background(blue, in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1).allowsHitTesting(false) }
        }
    }
}

private struct WhisperMomentPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? nil : .whisperSnappy, value: configuration.isPressed)
    }
}

private struct WhisperMomentPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Here for a moment.").font(.largeTitle.bold())
                    privacyRow("1.circle", title: "One view", detail: "Photos and videos can be opened once. Closing the viewer ends that view.")
                    privacyRow("clock", title: "Seven days", detail: "Unopened photos and videos expire after seven days.")
                    privacyRow("viewfinder", title: "Screenshots are possible", detail: "People can still take screenshots or record what they see. Only share what you’re comfortable sending.")
                }.padding(24)
            }
            .foregroundStyle(WhisperTheme.ink(scheme)).background(WhisperTheme.surface(scheme))
            .navigationTitle("Flicks").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(WhisperTheme.ink(scheme)) } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    private func privacyRow(_ symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title2.weight(.medium)).foregroundStyle(disappearingBlue).frame(width: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.body).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct WhisperDisappearingViewer: View {
    let item: WhisperDisappearingItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var image: UIImage?
    @State private var url: URL?
    @State private var player = AVPlayer()
    @State private var muted = true
    @State private var ready = false
    @State private var failed = false
    @State private var closed = false
    @State private var remaining = 1.0
    @State private var viewingDuration = 10.0
    @State private var blocks = WhisperBlockService.shared
    @State private var report = false
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Flick photo") }
            else if url != nil { WhisperStoryStagePlayerLayer(player: player, gravity: .resizeAspect) }
            else if failed {
                ContentUnavailableView {
                    Label("No longer available", systemImage: "square.dashed")
                } description: {
                    Text("It may have been opened, expired, or interrupted while opening. A claimed Flick can’t be replayed.")
                } actions: {
                    Button("Back to Flicks") { close() }.buttonStyle(.bordered).tint(.white)
                }
            }
            else if !report { ProgressView("Opening once…").tint(.white).accessibilityLabel("Opening Flick once") }
            VStack {
                if ready {
                    ProgressView(value: remaining).tint(.white)
                        .accessibilityLabel("Viewing time remaining")
                        .accessibilityValue("\(Int(ceil(remaining * viewingDuration))) seconds")
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.username?.isEmpty == false ? "@\(item.username!)" : "Flick")
                            .font(.subheadline.bold()).lineLimit(1)
                        Text("View once").font(.caption).foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    if url != nil {
                        Button { muted.toggle(); player.isMuted = muted || WhisperCameraCallMonitor.shared.callOwnsAudio } label: { Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 44, height: 44) }.accessibilityLabel(muted ? "Enable video sound" : "Mute video")
                    }
                    Button { closed = true; closeMedia(); report = true } label: { Image(systemName: "flag").frame(width: 44, height: 44) }.accessibilityLabel("Report")
                    Button { close() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Close")
                }
                Spacer()
                if ready {
                    Text("Closes in \(Int(ceil(remaining * viewingDuration)))s")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.black.opacity(0.6), in: Capsule())
                        .accessibilityHidden(true)
                }
            }.padding(20).shadow(color: .black.opacity(0.7), radius: 4, y: 1)
        }.foregroundStyle(.white).preferredColorScheme(.dark)
            .task {
                let epoch = AccountStorage.generation
                guard scenePhase == .active, !closed, !blocks.isBlocked(userID: item.sender_id) else { close(); return }
                do {
                    let (data, mime) = try await WhisperDisappearingService.shared.open(item)
                    guard !Task.isCancelled, !closed, !report, epoch == AccountStorage.generation else { return }
                    var duration = 10.0
                    if mime == "image/jpeg" {
                        guard let decoded = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                        image = decoded
                    } else {
                        let file = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-once-\(UUID().uuidString).\(mime == "video/mp4" ? "mp4" : "mov")")
                        try data.write(to: file, options: [.atomic, .completeFileProtection])
                        url = file
                        player.isMuted = true
                        player.replaceCurrentItem(with: AVPlayerItem(url: file))
                        let seconds = await WhisperStoryPoster.duration(of: file)
                        guard !Task.isCancelled, !closed, epoch == AccountStorage.generation else { closeMedia(); return }
                        duration = min(16, max(1, seconds)); player.play()
                    }
                    viewingDuration = duration; ready = true
                    let start = Date()
                    while !Task.isCancelled, !closed, !report {
                        remaining = max(0, 1 - Date().timeIntervalSince(start) / duration)
                        if remaining <= 0 { close(); return }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                } catch { if !Task.isCancelled, !closed, epoch == AccountStorage.generation { failed = true; closeMedia() } }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { close() } }
            .onChange(of: WhisperCameraCallMonitor.shared.callOwnsAudio) { _, busy in player.isMuted = muted || busy }
            .onChange(of: blocks.blockedUserIDs) { _, _ in if blocks.isBlocked(userID: item.sender_id) { close() } }
            .onDisappear { closed = true; closeMedia() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in close() }
            .gesture(DragGesture(minimumDistance: 30).onEnded { if $0.translation.height > 70 { close() } })
            .sheet(isPresented: $report, onDismiss: { close() }) {
                WhisperReportSheet(kind: .dm, targetID: item.id, targetUserID: item.sender_id, targetUsername: item.username ?? "")
            }
    }
    private func closeMedia() { player.pause(); player.replaceCurrentItem(with: nil); image = nil; if let url { try? FileManager.default.removeItem(at: url) }; url = nil; ready = false }
    private func close() { closed = true; closeMedia(); dismiss() }
}
