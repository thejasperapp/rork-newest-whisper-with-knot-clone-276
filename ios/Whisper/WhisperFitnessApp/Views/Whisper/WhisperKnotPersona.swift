import SwiftUI
import Observation
import Supabase
import UIKit
import ImageIO

nonisolated struct KnotPersonaSnapshot: Decodable, Sendable {
    struct ChatSource: Decodable, Sendable {
        let bot: String; let conversationID: String; let sourceMessageID: String
        func matches(conversationID: UUID, messageID: UUID) -> Bool {
            bot == "main" && self.conversationID.lowercased() == conversationID.uuidString.lowercased() && sourceMessageID.lowercased() == messageID.uuidString.lowercased()
        }
    }
    struct Quality: Decodable, Sendable { let description: String; let eyesVisible: Bool; let mouthPresent: Bool }
    struct Media: Decodable, Identifiable, Sendable { let id: String; let kind: String; let status: String; let quality: Quality? }
    struct AvatarSet: Decodable, Identifiable, Sendable { let id: String; let masterMediaID: String; let createdAt: Double; let media: [Media]; let states: [String: String]?; let quality: Quality?; let source: ChatSource? }
    struct Candidate: Decodable, Identifiable, Sendable { let id: String; let mediaID: String; let source: ChatSource? }
    struct Job: Decodable, Identifiable, Sendable { let id: String; let kind: String; let status: String; let count: Int; let completed: Int; let error: String?; let source: ChatSource? }
    let epoch: String?
    let version: Int; let name: String; let vibe: String; let consent: Bool; let consentModel: String?
    let masterID: String?; let sets: [AvatarSet]; let candidates: [Candidate]; let jobs: [Job]
    struct PendingAvatar: Decodable, Sendable { let id: String?; let source: ChatSource?; let prompt: String; let count: Int; let edit: Bool }
    let pendingAvatar: PendingAvatar?
    let restoreRequested: Bool?
    let restoreSource: ChatSource?
    let consentScope: String?
    var master: AvatarSet? { sets.first { $0.id == masterID } }
}
/// Authorized snapshots and media never cross an account generation. No public URLs.
@MainActor @Observable final class WhisperKnotPersonaStore {
    static let shared = WhisperKnotPersonaStore()
    private var owner = ""
    private var value: KnotPersonaSnapshot?
    private(set) var images: [String: UIImage] = [:]
    private(set) var films: [String: URL] = [:]
    private var loading = Set<String>()
    private var mediaRevision = UUID()
    @ObservationIgnored private var sessions: [UUID: URLSession] = [:]
    private var refreshing = false
    private var refreshedAt = Date.distantPast
    private init() {
        // Clear private film remnants from any previously terminated process.
        for url in (try? FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: nil)) ?? [] where url.lastPathComponent.hasPrefix("knot-persona-") { try? FileManager.default.removeItem(at: url) }
    }
    var snapshot: KnotPersonaSnapshot? { owner == AccountStorage.currentUserID.lowercased() ? value : nil }
    var displayName: String { snapshot?.name ?? "Knot" }
    var masterImage: UIImage? { snapshot?.master.flatMap { images[$0.masterMediaID] } }
    var callPortrait: UIImage? { snapshot?.master?.media.last(where: { $0.kind == "call_portrait" && $0.status == "ready" }).flatMap { images[$0.id] } }
    private func mediaKind(_ kind: String) -> String {
        guard snapshot?.master?.states != nil else { return kind }
        switch kind {
        case "making-something": return "making_something"
        case "milestone": return "milestone_level_up"
        case "waking": return "connecting"
        default: return kind
        }
    }
    func film(kind: String) -> URL? { snapshot?.master?.media.last(where: { $0.kind == mediaKind(kind) && $0.status == "ready" }).flatMap { films[$0.id] } }
    func reset() {
        for session in sessions.values { session.invalidateAndCancel() }; sessions = [:]
        if !owner.isEmpty { WhisperKnotPersonaMediaCache.shared.clear(owner: owner) }
        mediaRevision = UUID()
        value = nil; owner = ""; images = [:]; loading = []; refreshing = false; refreshedAt = .distantPast
        films = [:]
    }
    private func request(_ action: String, body: [String: Any], long: Bool = false) async throws -> Data {
        let generation = AccountStorage.generation, account = AccountStorage.currentUserID.lowercased()
        guard account != "guest" else { throw CancellationError() }
        let auth = try await SupabaseService.shared.client.auth.session
        guard generation == AccountStorage.generation, auth.user.id.uuidString.lowercased() == account else { throw CancellationError() }
        var request = URLRequest(url: URL(string: WhisperKnotBackend.origin + "/knot/persona/" + action)!)
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = long ? 680 : 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "X-Whisper-Authorization")
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.timeoutIntervalForResource = long ? 700 : 30
        let session = URLSession(configuration: config), requestID = UUID(); sessions[requestID] = session
        defer { session.invalidateAndCancel(); sessions.removeValue(forKey: requestID) }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard generation == AccountStorage.generation, account == AccountStorage.currentUserID.lowercased() else { throw CancellationError() }
        guard data.count <= 12_500_000, let http = response as? HTTPURLResponse else { throw WhisperKnotLiveError.unavailable }
        guard (200..<300).contains(http.statusCode) else {
            let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
            throw PersonaError.message(Self.message(error?["error"], status: http.statusCode))
        }
        return data
    }
    private static func message(_ code: String?, status: Int) -> String {
        switch code {
        case "persona_changed": "This changed on another screen. Refresh and try again."
        case "generation_consent_required": "Allow avatar sharing in this chat before generating."
        case "avatar_history_full": "Your eight saved avatar sets are full. Reuse an existing set for now."
        case "generation_capacity": "A generation is still pending, or your private avatar storage is full."
        case "generation_already_consumed": "That generation was already submitted. Refresh to see its result; it will not restart."
        case "master_required": "Choose a master avatar first."
        case "candidate_quality_required": "This older candidate has no quality check. Ask Knot to create a new candidate; saved avatar sets can still be restored."
        default: status == 401 ? "Sign in again to manage your avatar." : "This change wasn’t confirmed. Refresh before trying again."
        }
    }
    enum PersonaError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let text) = self { text } else { nil } } }
    func refresh(force: Bool = false) async throws {
        guard AccountStorage.currentUserID != "guest" else { return }
        if refreshing || !force && snapshot != nil && Date().timeIntervalSince(refreshedAt) < 30 { return }
        let generation = AccountStorage.generation; refreshing = true
        defer { if generation == AccountStorage.generation { refreshing = false } }
        let data = try await request("read", body: [:])
        guard generation == AccountStorage.generation else { throw CancellationError() }
        try await apply(data)
        if generation == AccountStorage.generation { refreshedAt = Date() }
    }
    private func apply(_ data: Data) async throws {
        let next = try JSONDecoder().decode(KnotPersonaSnapshot.self, from: data)
        let account = AccountStorage.currentUserID.lowercased()
        if owner != account { reset(); owner = account }
        if let value, next.epoch == value.epoch, next.version < value.version { return }
        if value?.epoch != next.epoch || value?.version != next.version {
            mediaRevision = UUID(); loading = []
        }
        value = next
        images = images.filter { authorizedImage($0.key) }
        films = films.filter { authorizedFilm($0.key) }
        if let master = next.master {
            await loadImage(master.masterMediaID)
            if let portrait = master.media.last(where: { $0.kind == "call_portrait" && $0.status == "ready" }) { await loadImage(portrait.id) }
        }
    }
    func change(_ action: String, fields: [String: Any] = [:]) async throws {
        guard let snapshot else { throw PersonaError.message("Refresh your avatar settings first.") }
        let generation = AccountStorage.generation
        var body = fields; body["version"] = snapshot.version
        let data = try await request(action, body: body, long: ["candidates", "generate"].contains(action))
        guard generation == AccountStorage.generation else { throw CancellationError() }
        try await apply(data)
    }
    private func authorizedImage(_ id: String) -> Bool {
        snapshot?.candidates.contains(where: { $0.mediaID == id }) == true || snapshot?.sets.contains(where: { $0.masterMediaID == id || $0.media.contains(where: { $0.id == id && $0.kind == "call_portrait" && $0.status == "ready" }) }) == true
    }
    private func authorizedFilm(_ id: String) -> Bool {
        snapshot?.sets.contains(where: { $0.media.contains(where: { $0.id == id && $0.kind != "call_portrait" && ["ready", "review"].contains($0.status) }) }) == true
    }
    func loadImage(_ id: String) async {
        guard authorizedImage(id), images[id] == nil, !loading.contains(id) else { return }
        loading.insert(id); let generation = AccountStorage.generation, revision = mediaRevision, account = owner
        defer { if generation == AccountStorage.generation && revision == mediaRevision { loading.remove(id) } }
        do {
            let data: Data
            if let url = WhisperKnotPersonaMediaCache.shared.file(owner: account, id: id), let cached = try? Data(contentsOf: url) { data = cached }
            else { data = try await request("media", body: ["id": id]) }
            guard generation == AccountStorage.generation, revision == mediaRevision, authorizedImage(id),
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 640] as CFDictionary) else { return }
            _ = try? WhisperKnotPersonaMediaCache.shared.store(data, owner: account, id: id)
            images[id] = UIImage(cgImage: thumbnail)
        } catch { /* A missing private image never substitutes another identity. */ }
    }
    func loadFilm(kind: String) async {
        guard let id = snapshot?.master?.media.last(where: { $0.kind == mediaKind(kind) && $0.status == "ready" })?.id else { return }
        await loadFilm(id: id)
    }
    func loadFilm(id: String) async {
        guard authorizedFilm(id), films[id] == nil, !loading.contains(id) else { return }
        loading.insert(id); let generation = AccountStorage.generation, revision = mediaRevision, account = owner
        defer { if generation == AccountStorage.generation && revision == mediaRevision { loading.remove(id) } }
        do {
            if let url = WhisperKnotPersonaMediaCache.shared.file(owner: account, id: id) { films[id] = url; return }
            let data = try await request("media", body: ["id": id])
            guard generation == AccountStorage.generation, revision == mediaRevision, authorizedFilm(id) else { return }
            films[id] = try WhisperKnotPersonaMediaCache.shared.store(data, owner: account, id: id)
        } catch { /* The selected master still remains visible. */ }
    }
}

/// Real private candidates, read from the account actor, never model image URLs.
/// Choosing the master remains an explicit member action even in chat.
struct WhisperKnotChatAvatarChoices: View {
    let conversationID: UUID
    let messageID: UUID
    var working: Bool
    var enabled: Bool
    @State private var store = WhisperKnotPersonaStore.shared
    @State private var saving = false
    @State private var notice: String?
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                WhisperKnotChatAvatarControls(snapshot: snapshot, conversationID: conversationID, messageID: messageID, enabled: enabled && !working)
                let candidates = snapshot.candidates.filter { $0.source?.matches(conversationID: conversationID, messageID: messageID) == true }
                if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                                let selected = snapshot.master?.masterMediaID == candidate.mediaID
                                Button { choose(candidate.id) } label: {
                                    Group {
                                        if let image = store.images[candidate.mediaID] {
                                            Image(uiImage: image).resizable().scaledToFit()
                                        } else { ProgressView("Loading candidate") }
                                    }.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                                        .background(.white, in: .rect(cornerRadius: 20))
                                        .clipShape(.rect(cornerRadius: 20))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 3)
                                        }
                                        .overlay(alignment: .topTrailing) {
                                            if selected { Image(systemName: "checkmark.circle.fill").font(.title2).symbolRenderingMode(.palette).foregroundStyle(.white, Color.accentColor).padding(10) }
                                        }
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("Avatar candidate \(index + 1)")
                                    .accessibilityHint(selected ? "Your current avatar" : "Double-tap to use this photo as your avatar")
                                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                                    .disabled(saving || !enabled || working || selected || store.images[candidate.mediaID] == nil)
                                    .task(id: candidate.mediaID) { await store.loadImage(candidate.mediaID) }
                            }
                    }.padding(.vertical, 4)
                    if snapshot.master?.source?.matches(conversationID: conversationID, messageID: messageID) == true {
                        Text("Your avatar is updated.").font(.subheadline)
                    }
                    if saving { ProgressView().accessibilityLabel("Saving your choice") }
                    if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                }.padding(.vertical, 12)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in notice = nil }
    }
    private func choose(_ candidateID: String) {
        guard enabled, !working, phase == .active, !saving else { return }
        saving = true; notice = nil
        let generation = AccountStorage.generation
        Task {
            defer { if generation == AccountStorage.generation { saving = false } }
            guard generation == AccountStorage.generation else { return }
            do { try await store.change("pick", fields: ["candidateID": candidateID]) }
            catch {
                guard generation == AccountStorage.generation else { return }
                notice = error.localizedDescription
                try? await store.refresh(force: true)
            }
        }
    }
}

struct PersonaMotionPreview: View {
    let url: URL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var permitted: Bool { scenePhase == .active && !reduceMotion && !lowPower }
    var body: some View {
        VStack(spacing: 14) {
            Group {
                if playing && permitted {
                    KnotAvatarFilm(state: "idle", url: url, loops: true, completed: {}).id(url)
                } else {
                    ContentUnavailableView("Motion paused", systemImage: "pause.circle", description: Text(reduceMotion || lowPower ? "Motion pauses for Reduce Motion and Low Power Mode." : "Play to review this clip before approving it."))
                }
            }.aspectRatio(1, contentMode: .fit)
            Button(playing && permitted ? "Pause preview" : "Play preview", systemImage: playing && permitted ? "pause.fill" : "play.fill") { playing.toggle() }
                .buttonStyle(.bordered).disabled(!permitted)
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playing = false } }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled; if lowPower { playing = false } }
    }
}
