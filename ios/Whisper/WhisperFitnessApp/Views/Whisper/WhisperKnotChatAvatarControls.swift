import SwiftUI

/// Only consent and explicit whole-set restoration belong beside the photo picker.
/// Persona verification, providers, jobs and state ledgers are never display text.
struct WhisperKnotChatAvatarControls: View {
    let snapshot: KnotPersonaSnapshot
    let conversationID: UUID
    let messageID: UUID
    let enabled: Bool
    @State private var store = WhisperKnotPersonaStore.shared
    @State private var busy = false
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let pending = snapshot.pendingAvatar,
               pending.source?.matches(conversationID: conversationID, messageID: messageID) == true,
               let pendingID = pending.id {
                Text("Allow sharing your avatar description and media with Google for creation and checks?")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Allow & create") {
                    let generation = AccountStorage.generation
                    perform {
                        try await store.change("consent", fields: ["allowed": true, "scope": "google_avatar_media_quality_v2"])
                        guard generation == AccountStorage.generation else { throw CancellationError() }
                        try await store.change("candidates", fields: ["pendingID": pendingID, "jobID": UUID().uuidString.lowercased(), "prompt": pending.prompt, "count": pending.count, "edit": pending.edit])
                    }
                }.buttonStyle(.borderedProminent).disabled(!enabled || busy)
            }
            if snapshot.restoreRequested == true, snapshot.restoreSource?.matches(conversationID: conversationID, messageID: messageID) == true {
                ForEach(snapshot.sets.reversed()) { set in
                    Button {
                        perform { try await store.change("revert", fields: ["setID": set.id]) }
                    } label: {
                        HStack(spacing: 12) {
                            if let image = store.images[set.masterMediaID] {
                                Image(uiImage: image).resizable().scaledToFit().frame(width: 52, height: 52).background(.white, in: .rect(cornerRadius: 12))
                            }
                            Text(set.id == snapshot.masterID ? "Current avatar" : "Restore avatar from \(Date(timeIntervalSince1970: set.createdAt / 1000).formatted(date: .abbreviated, time: .omitted))")
                        }
                    }.disabled(!enabled || busy || set.id == snapshot.masterID)
                        .task(id: set.masterMediaID) { await store.loadImage(set.masterMediaID) }
                }
                Button("Use original Knot") { perform { try await store.change("revert", fields: ["setID": NSNull()]) } }.disabled(!enabled || busy)
            }
            if busy { ProgressView().accessibilityLabel("Updating avatar") }
            if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in notice = nil }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; notice = nil
        let generation = AccountStorage.generation
        Task { @MainActor in
            defer { if generation == AccountStorage.generation { busy = false } }
            guard generation == AccountStorage.generation else { return }
            do { try await action() }
            catch {
                guard generation == AccountStorage.generation else { return }
                notice = error.localizedDescription
                try? await store.refresh(force: true)
            }
        }
    }
}

/// Withdrawal stays in Privacy & context, never in the creation conversation.
struct WhisperKnotAvatarSharingSettings: View {
    @State private var store = WhisperKnotPersonaStore.shared
    @State private var busy = false
    @State private var notice: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Avatar sharing").font(.headline)
            Text("Avatar descriptions, reference images and generated media go through Whisper, Rork AI Cloud and Vercel AI Gateway to Google for creation and separate quality checks. No profile, memory or other chat is attached.")
                .font(.subheadline).foregroundStyle(.secondary)
            if store.snapshot?.consent == true {
                Button("Withdraw avatar sharing", role: .destructive) { withdraw() }.disabled(busy)
            }
            Text("Withdrawal stops future sharing and discards late results; it cannot retract data already sent. Your saved avatar stays available.")
                .font(.caption).foregroundStyle(.secondary)
            Link("Google privacy", destination: URL(string: "https://policies.google.com/privacy")!).font(.caption)
            if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
        }
        .task { try? await store.refresh(force: true) }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in notice = nil }
    }
    private func withdraw() {
        guard !busy else { return }; busy = true; notice = nil
        let generation = AccountStorage.generation
        Task { @MainActor in
            defer { if generation == AccountStorage.generation { busy = false } }
            do {
                try await store.change("consent", fields: ["allowed": false])
                guard generation == AccountStorage.generation else { return }
                notice = "Avatar sharing withdrawn."
            } catch {
                guard generation == AccountStorage.generation else { return }
                notice = "Withdrawal wasn’t confirmed. Try again when connected."
                try? await store.refresh(force: true)
            }
        }
    }
}
