import SwiftUI

nonisolated struct WhisperKnotWelcomeInvitation: Decodable, Sendable {
    let id: String
    let expiresAt: Double
    let version: String
}
/// This value is created only by an informed Answer, never by appearance or a
/// stored general sharing flag. It grants this one call, not future contact.
nonisolated struct WhisperKnotWelcomeAnswer: Sendable {
    let invitationID: String
    let deviceID: String
    let answerID: String
    let displayName: String
    let expiresAt: Double
    let consentVersion = "knot_welcome_rork_voice_v2"
}
@MainActor final class WhisperKnotWelcomeService {
    static let shared = WhisperKnotWelcomeService()
    private var attemptedOwners = Set<String>()
    let deviceID: String
    private nonisolated struct Offer: Encodable { let deviceID: String; let platform = "ios" }
    private nonisolated struct Listing: Decodable, Sendable { let invitation: WhisperKnotWelcomeInvitation? }
    private nonisolated struct Change: Encodable {
        let invitationID: String; let deviceID: String; let answerID: String?
        let consentVersion = "knot_welcome_rork_voice_v2"
    }
    private nonisolated struct Acknowledged: Decodable, Sendable { let ok: Bool; let expiresAt: Double? }
    private init() {
        let key = "knot_welcome_device_v1"
        if let saved = UserDefaults.standard.string(forKey: key), UUID(uuidString: saved) != nil { deviceID = saved.lowercased() }
        else { let id = UUID().uuidString.lowercased(); deviceID = id; UserDefaults.standard.set(id, forKey: key) }
    }
    static var audioBusy: Bool {
        WhisperCallService.shared.active != nil || WhisperCameraCallMonitor.shared.callOwnsAudio
        || WhisperLiveRTCService.shared.isInUse || WhisperKnotVoiceSession.isBusy
    }
    func offer() async {
        let owner = AccountStorage.currentUserID, generation = AccountStorage.generation
        guard owner != "guest", !attemptedOwners.contains(owner), !Self.audioBusy,
              WhisperKnotContactService.shared.presentation == nil else { return }
        attemptedOwners.insert(owner)
        do {
            let response: Listing = try await WhisperKnotBackgroundService.shared.contactRequest("/welcome", method: "POST", body: JSONEncoder().encode(Offer(deviceID: deviceID)))
            try Task.checkCancellation()
            guard generation == AccountStorage.generation, owner == AccountStorage.currentUserID, !Self.audioBusy,
                  WhisperKnotContactService.shared.presentation == nil, let invitation = response.invitation,
                  invitation.version == "knot_welcome_2026_11_10", UUID(uuidString: invitation.id) != nil,
                  invitation.expiresAt > Date().timeIntervalSince1970 * 1000 else { return }
            WhisperKnotContactService.shared.presentation = .init(bot: .main, conversationID: UUID(), invitation: nil, welcome: invitation)
        } catch { /* Unknown offers are never retried or manufactured locally. */ }
    }
    func answer(_ invitation: WhisperKnotWelcomeInvitation) async throws -> WhisperKnotWelcomeAnswer {
        guard !Self.audioBusy, invitation.expiresAt > Date().timeIntervalSince1970 * 1000 else { throw CancellationError() }
        let owner = AccountStorage.currentUserID, generation = AccountStorage.generation
        let answerID = UUID().uuidString.lowercased()
        // Only the current member's display name, never email, username,
        // preferences, private profile, history or another Knot's context.
        let me = WhisperUserService.shared.me
        let name = me?.user_id.lowercased() == owner.lowercased() ? String((me?.display_name ?? "").split(whereSeparator: \.isWhitespace).first?.prefix(80) ?? "") : ""
        let response: Acknowledged = try await WhisperKnotBackgroundService.shared.contactRequest("/welcome/answer", method: "POST", body: JSONEncoder().encode(Change(invitationID: invitation.id, deviceID: deviceID, answerID: answerID)))
        try Task.checkCancellation()
        guard generation == AccountStorage.generation, owner == AccountStorage.currentUserID, !Self.audioBusy,
              response.ok, let expiresAt = response.expiresAt, expiresAt > Date().timeIntervalSince1970 * 1000 else { throw CancellationError() }
        return .init(invitationID: invitation.id, deviceID: deviceID, answerID: answerID, displayName: name, expiresAt: expiresAt)
    }
    func decline(_ invitation: WhisperKnotWelcomeInvitation) {
        let generation = AccountStorage.generation
        Task { @MainActor in
            guard generation == AccountStorage.generation else { return }
            let _: Acknowledged? = try? await WhisperKnotBackgroundService.shared.contactRequest("/welcome/decline", method: "POST", body: JSONEncoder().encode(Change(invitationID: invitation.id, deviceID: deviceID, answerID: nil)))
        }
    }
}
/// Lives behind the authoritative root/onboarding gate, not the global sync
/// loop. The server owns cross-device deduplication, including missed offers.
struct WhisperKnotWelcomeAgent: View {
    let ready: Bool
    @Environment(\.scenePhase) private var scenePhase
    private var available: Bool { ready && scenePhase == .active && !WhisperKnotWelcomeService.audioBusy && WhisperKnotContactService.shared.presentation == nil }
    var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            .task(id: "\(available)-\(AccountStorage.generation)") {
                guard available else { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard available, !Task.isCancelled else { return }
                await WhisperKnotWelcomeService.shared.offer()
            }
            .onChange(of: ready) { _, ready in if !ready { dismissWelcome() } }
            .onChange(of: scenePhase) { _, phase in if phase == .background { dismissWelcome() } }
    }
    private func dismissWelcome() {
        if WhisperKnotContactService.shared.presentation?.welcome != nil { WhisperKnotContactService.shared.presentation = nil }
    }
}
struct WhisperKnotWelcomeDestination: View {
    let invitation: WhisperKnotWelcomeInvitation
    let close: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var answered: WhisperKnotWelcomeAnswer?
    @State private var operation: Task<Void, Never>?
    @State private var attempted = false
    @State private var busy = false
    @State private var failure = false
    @State private var generation = AccountStorage.generation
    var body: some View {
        Group {
            if let answered {
                WhisperEmberVoiceScreen(knotBot: .main, welcome: answered, onExternalClose: close)
            } else {
                WhisperKnotAudioCallLayout(bot: .main) {
                    Text(failure ? "Couldn’t connect this call" : busy ? "Confirming your answer…" : "Incoming welcome call")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.8)).padding(.top, 10)
                        .accessibilityAddTraits(.updatesFrequently)
                    if failure {
                        Text("Find Knot in Messages. We won’t call again automatically.")
                            .font(.caption).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center).padding(.top, 12)
                    }
                } detail: {
                    if !attempted {
                        Text("By answering, you agree to share your first name and live audio with ElevenLabs for this call only. Transcripts and answers pass through Whisper and Rork AI Cloud, via Vercel AI Gateway to OpenAI, using the same answering model as chat. No profile or chat history is shared. Recording is off; provider history is limited to one day. A transcript is saved separately on this device. You can end the call at any time.")
                            .font(.caption).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                        Text("No microphone before Answer. No permission for future calls.")
                            .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                            .padding(.top, 10).padding(.bottom, 24)
                    }
                } controls: {
                    if !attempted {
                        HStack(alignment: .top, spacing: 80) {
                            control("Decline", icon: "phone.down.fill", color: .red, action: decline)
                            control("Answer", icon: "phone.fill", color: .green, action: answer)
                        }
                    } else {
                        VStack(spacing: 20) {
                            if busy { ProgressView().tint(.white).accessibilityLabel("Confirming your answer") }
                            control(failure ? "Done" : "Cancel", icon: "phone.down.fill", color: .red, action: decline)
                        }
                    }
                }
            }
        }
        .task {
            let seconds = max(0, invitation.expiresAt / 1000 - Date().timeIntervalSince1970)
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            if !attempted { close() }
        }
        .onDisappear { operation?.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { operation?.cancel(); close() } }
        .onChange(of: WhisperKnotWelcomeService.audioBusy) { _, busy in if busy && answered == nil { operation?.cancel(); close() } }
        .accessibilityAction(.escape) { decline() }
    }
    private func control(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Button(action: action) { Image(systemName: icon).font(.system(size: 24, weight: .medium)).frame(width: 64, height: 64).background(color, in: Circle()) }.buttonStyle(.plain).accessibilityLabel(title)
            Text(title).font(.caption)
        }
    }
    private func decline() { operation?.cancel(); WhisperKnotWelcomeService.shared.decline(invitation); close() }
    private func answer() {
        guard !attempted, scenePhase == .active, generation == AccountStorage.generation, !WhisperKnotWelcomeService.audioBusy else { return }
        attempted = true; busy = true; Haptics.tap()
        operation = Task { @MainActor in
            do {
                let result = try await WhisperKnotWelcomeService.shared.answer(invitation)
                guard !Task.isCancelled, generation == AccountStorage.generation, scenePhase == .active else { return }
                busy = false; answered = result
            } catch {
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                busy = false; failure = true
            }
        }
    }
}
