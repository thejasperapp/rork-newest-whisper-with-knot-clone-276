import Foundation
import AVFoundation
import Combine
import ElevenLabs
import struct ElevenLabs.Message
import LiveKit
import Supabase
import OSLog

/// The maintained SDK owns capture, playback and transport. This adapter owns
/// consent/account leases, a single audio owner and a separate bounded transcript.
@MainActor @Observable final class WhisperKnotVoiceSession {
    enum Phase { case idle, connecting, active, ended, unavailable }
    private(set) var phase: Phase = .idle
    private(set) var status = "Connecting…"
    private(set) var avatarMotion: String?
    private(set) var muted = false
    private(set) var muteBusy = false
    private(set) var connectedAt: Date?
    private(set) var audioRoute: WhisperAudioRoute = .speaker
    private(set) var needsSettings = false
    private(set) var record: WhisperKnotCallRecord?
    let history = WhisperKnotCallHistory()

    private static weak var audioOwner: WhisperKnotVoiceSession?
    static var isBusy: Bool { audioOwner != nil }
    @ObservationIgnored private var welcome: WhisperKnotWelcomeAnswer?
    @ObservationIgnored private var incoming: WhisperKnotIncomingAnswer?
    @ObservationIgnored private var invitationMonitor: Task<Void, Never>?
    @ObservationIgnored private var invitationEnded = false
    @ObservationIgnored private var conversation: Conversation?
    @ObservationIgnored private var voiceLease: (id: String, token: String)?
    // Separate player: never start or stop the human-call ringtone singleton.
    @ObservationIgnored private let ringback = WhisperCallRingtone()
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()
    @ObservationIgnored private var startup: Task<Void, Never>?
    @ObservationIgnored private var durationLimit: Task<Void, Never>?
    @ObservationIgnored private var muteOperation: Task<Void, Never>?
    @ObservationIgnored private var relay: (@MainActor (String) async -> String)?
    @ObservationIgnored private var stopWork: (() -> Void)?
    @ObservationIgnored private var relayTask: Task<Void, Never>?
    @ObservationIgnored private var relayOperation = UUID()
    @ObservationIgnored private var handledToolIDs = Set<String>()
    @ObservationIgnored private var handledUtterances = Set<Int>()
    @ObservationIgnored private var finalizedUtterance: (id: Int, text: String)?
    @ObservationIgnored private var relayCallID: String?
    @ObservationIgnored private var openingWatchdog: Task<Void, Never>?
    @ObservationIgnored private var receivedAgentResponse = false
    @ObservationIgnored private var receivedAgentAudio = false
    @ObservationIgnored private var initiationAccepted = false
    // A deliberate outgoing Call tap authorizes only this voice session. It
    // never silently enables saved chat-tool or incoming-call permissions.
    @ObservationIgnored private var directOutgoing = false
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private let generation = AccountStorage.generation
    @ObservationIgnored private let revision = WhisperKnotContextPermission.revision
    @ObservationIgnored private var oldAvailability: AudioEngineAvailability?
    @ObservationIgnored private var oldSpeakerPreference = true

    private var leaseValid: Bool {
        !stopped && generation == AccountStorage.generation && revision == WhisperKnotContextPermission.revision
        && (welcome != nil || directOutgoing || (WhisperKnotVoicePreferences.allowed && WhisperKnotContextPermission.allowed))
        && (relay == nil || WhisperKnotContextPermission.allowed && WhisperKnotVoicePreferences.chatToolsAllowed)
        && (welcome == nil || phase == .active || (welcome?.expiresAt ?? 0) > Date().timeIntervalSince1970 * 1000)
        && !WhisperCameraCallMonitor.shared.callOwnsAudio
        && (welcome == nil || (WhisperCallService.shared.active == nil && !WhisperLiveRTCService.shared.isInUse))
        && AccountStorage.currentUserID != "guest"
    }

    func start(bot: WhisperKnotBot, recentConversation: String, incoming: WhisperKnotIncomingAnswer? = nil, welcome: WhisperKnotWelcomeAnswer? = nil,
               directOutgoing: Bool = false, relay: (@MainActor (String) async -> String)? = nil, stopWork: (() -> Void)? = nil) {
        guard phase == .idle else { return }
        guard incoming == nil || welcome == nil else { phase = .unavailable; status = "This invitation is unavailable."; return }
        self.welcome = welcome
        self.directOutgoing = directOutgoing && incoming == nil && welcome == nil
        guard leaseValid else { phase = .unavailable; status = "Calls need your sharing permission."; return }
        guard Self.audioOwner == nil else { phase = .unavailable; status = "Your previous call is still ending. Please try again in a moment."; return }
        self.incoming = incoming
        if incoming == nil && welcome == nil && WhisperKnotContextPermission.allowed && WhisperKnotVoicePreferences.chatToolsAllowed {
            self.relay = relay; self.stopWork = stopWork
        }
        Self.audioOwner = self
        phase = .connecting
        startup = Task { await connect(bot: welcome == nil ? bot : .main, recentConversation: welcome == nil ? recentConversation : "") }
    }

    private func checkLease() throws {
        try Task.checkCancellation()
        guard leaseValid else { throw CancellationError() }
    }

    private func connect(bot: WhisperKnotBot, recentConversation: String) async {
        defer {
            ringback.stop()
            startup = nil
            if conversation == nil { revokeVoiceLease(); releaseAudioOwnership(); endIncomingInvitation() }
        }
        do {
            try checkLease()
            // Request before creating a token or SDK session. Denied is distinct
            // from connectivity/configuration failure and links to iOS Settings.
            let permitted: Bool
            switch AVAudioApplication.shared.recordPermission {
            case .granted: permitted = true
            case .denied: permitted = false
            default: permitted = await AVAudioApplication.requestRecordPermission()
            }
            try checkLease()
            guard permitted else {
                needsSettings = true; phase = .unavailable
                status = "Allow microphone access in Settings to call Knot."
                return
            }
            // Ring only after microphone permission and the account/consent
            // lease are confirmed; token + SDK connection can take a moment.
            ringback.start(style: .ringback, defaultToSpeaker: true)
            let chosenVoice = WhisperKnotVoicePreferences.voice
            let response = try await fetchToken(bot: bot, voice: chosenVoice, recentConversation: recentConversation)
            try checkLease()
            record = WhisperKnotCallRecord(bot: bot, voice: chosenVoice, startedAt: Date(), invitationID: incoming?.invitation.id)
            oldAvailability = AudioManager.shared.engineAvailability
            oldSpeakerPreference = AudioManager.shared.isSpeakerOutputPreferred
            AudioManager.shared.isSpeakerOutputPreferred = true
            try AudioManager.shared.setEngineAvailability(.default)
            ElevenLabs.configure(.init(logLevel: .error, debugMode: false))
            guard relay == nil || response.relayVersion == WhisperKnotVoicePreferences.relayConsentVersion else {
                throw VoiceFailure(message: "Couldn’t confirm chat tools for this call. No work was started.")
            }
            // Stop our isolated ring before the SDK takes ownership of playback.
            ringback.stop()
            Self.connectionLog.info("Voice token accepted; SDK startup beginning")
            let config = ConversationConfig(
                agentOverrides: AgentOverrides(prompt: response.prompt, firstMessage: response.firstMessage),
                ttsOverrides: TTSOverrides(voiceId: response.voiceID),
                onAgentReady: { Self.connectionLog.info("Voice remote participant joined; awaiting initiation acknowledgement") },
                onDisconnect: { [weak self] reason in
                    Task { @MainActor [weak self] in
                        guard let self, !self.stopped else { return }
                        let code: String
                        switch reason { case .agent: code = "agent"; case .user: code = "user"; case .error: code = "error" }
                        Self.connectionLog.info("Voice disconnected: reason=\(code, privacy: .public), initiationAccepted=\(self.initiationAccepted, privacy: .public)")
                        self.stop(message: self.initiationAccepted ? "Call ended" : "Knot’s call service ended the connection before it was ready. Please try again later.")
                    }
                },
                startupConfiguration: .init(agentReadyTimeout: 20),
                audioConfiguration: .init(recordingAlwaysPrepared: false, useSoftwareMute: false),
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self, !self.stopped else { return }
                        let code = Self.errorCode(error)
                        Self.connectionLog.error("Voice SDK failure: \(code, privacy: .public)")
                        self.stop(message: self.initiationAccepted ? "The call was interrupted. You can call again when you’re ready." : "Knot’s call service couldn’t start this conversation. Please try again later.")
                    }
                },
                onAgentResponse: { [weak self] _, _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.leaseValid else { return }
                        self.receivedAgentResponse = true
                        self.initiationAccepted = true
                        self.activateIfReady()
                    }
                },
                onUserTranscript: { [weak self] text, eventID in
                    Task { @MainActor [weak self] in
                        guard let self, self.leaseValid else { return }
                        self.finalizedUtterance = (eventID, text)
                    }
                },
                onConversationMetadata: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.leaseValid else { return }
                        self.initiationAccepted = true
                        Self.connectionLog.info("Voice initiation acknowledged by provider")
                        self.activateIfReady()
                    }
                },
                onInterruption: { [weak self] _ in
                    Task { @MainActor [weak self] in self?.cancelRelay() }
                },
                onUnhandledClientToolCall: { _ in
                    // Observed through pendingToolCalls after SDK ownership is set.
                    // Never dispatch from two callbacks or tear down a healthy call.
                }
            )
            // v3.4.0's token convenience overload replaces config callbacks with
            // nil defaults. The full factory preserves our lifecycle callbacks.
            let active = try await ElevenLabs.startConversation(
                auth: .conversationToken(response.token), config: config
            )
            // A late SDK connection never gets to outlive end, withdrawal,
            // backgrounding, account switching or another call taking audio.
            guard leaseValid, !Task.isCancelled else {
                try? await active.setMuted(true)
                await active.endConversation()
                return
            }
            ringback.stop()
            conversation = active
            // A room + participant is not proof the provider accepted initiation.
            // Do not start the timer or label the call Listening until it does.
            status = "Waiting for Knot…"
            initiationAccepted = initiationAccepted || active.conversationMetadata != nil
            activateIfReady()
            muted = active.isMuted
            observe(active)
            refreshRoute()
            watchOpening(active)
            if let record { history.save(record) }
            monitorIncomingInvitation()
            durationLimit = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(1200)) } catch { return }
                self?.stop(message: "This call reached its 20-minute limit.")
            }
        } catch {
            if !stopped, generation == AccountStorage.generation {
                if let sdkError = error as? ConversationError {
                    let code = Self.errorCode(sdkError)
                    Self.connectionLog.error("Voice startup failed: \(code, privacy: .public)")
                }
                phase = .unavailable
                status = (error as? VoiceFailure)?.message ?? "Couldn’t connect this call. You can try calling again."
            }
        }
    }

    private func activateIfReady() {
        guard initiationAccepted, conversation != nil, leaseValid, phase == .connecting else { return }
        connectedAt = Date(); record?.connectedAt = connectedAt
        phase = .active; status = "Listening"
        if let record { history.save(record) }
    }

    private static func errorCode(_ error: ConversationError) -> String {
        // Associated provider/network descriptions may contain private data.
        switch error {
        case .notConnected: return "not_connected"
        case .alreadyActive: return "already_active"
        case .connectionFailed: return "connection_failed"
        case .authenticationFailed: return "authentication_failed"
        case .agentTimeout: return "agent_timeout"
        case .microphoneToggleFailed: return "microphone_failed"
        case .localNetworkPermissionRequired: return "local_network_permission"
        case .noSoftwareMuteHandlerConfigured: return "mute_configuration"
        case .serverError: return "provider_rejected"
        }
    }

    private func observe(_ active: Conversation) {
        active.$messages.sink { [weak self] messages in
            self?.reconcile(messages)
        }.store(in: &subscriptions)
        active.$isMuted.sink { [weak self] value in self?.muted = value }.store(in: &subscriptions)
        active.$pendingToolCalls.sink { [weak self, weak active] calls in
            guard let self, let active else { return }
            for call in calls { self.handle(call, in: active) }
        }.store(in: &subscriptions)
        active.$agentState.sink { [weak self, weak active] state in
            guard let self, self.leaseValid, self.phase == .active else { return }
            switch state {
            case .listening: self.status = "Listening"; self.avatarMotion = "call-listening"
            case .speaking:
                self.status = "Speaking"; self.avatarMotion = "call-speaking"
                if active?.agentAudioTrack != nil { self.receivedAgentAudio = true }
            case .thinking: self.status = "Thinking…"; self.avatarMotion = nil
            }
        }.store(in: &subscriptions)
    }

    private func watchOpening(_ active: Conversation) {
        openingWatchdog = Task { @MainActor [weak self, weak active] in
            do { try await Task.sleep(for: .seconds(25)) } catch { return }
            guard let self, let active, self.leaseValid, self.phase == .active || self.phase == .connecting else { return }
            let hasResponse = self.receivedAgentResponse || active.messages.contains { $0.role != .user && !$0.content.isEmpty }
            let hasAudio = self.receivedAgentAudio
            Self.connectionLog.info("Opening observed: response=\(hasResponse, privacy: .public), remoteSpeaking=\(hasAudio, privacy: .public)")
            if !self.initiationAccepted {
                self.stop(message: "Knot’s call service did not finish connecting. Please try again later.")
            } else if !hasResponse && !hasAudio {
                self.stop(message: "Knot connected but did not send an opening response. Please try a new call when you’re ready.")
            }
        }
    }

    private func handle(_ call: ClientToolCallEvent, in active: Conversation) {
        guard leaseValid, phase == .active, handledToolIDs.insert(call.toolCallId).inserted else { return }
        guard call.toolName == "ask_knot", let relay,
              WhisperKnotVoicePreferences.chatToolsAllowed, call.parametersData.count <= 256,
              let parameters = try? call.getParameters(), parameters.isEmpty,
              let utterance = finalizedUtterance,
              !utterance.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              utterance.text.count <= 16000,
              relayTask == nil, handledUtterances.insert(utterance.id).inserted else {
            Task { try? await active.sendToolResult(for: call.toolCallId, result: "This request was not dispatched. Do not retry or claim any execution. Ask the member to use chat if they need to clarify.", isError: true) }
            return
        }
        let operation = UUID(); relayOperation = operation; relayCallID = call.toolCallId
        status = "Working in your chat…"
        relayTask = Task { @MainActor [weak self, weak active] in
            let answer = await relay(utterance.text)
            guard let self, let active, self.leaseValid, !Task.isCancelled, self.relayOperation == operation else { return }
            self.relayTask = nil; self.relayCallID = nil
            do { try await active.sendToolResult(for: call.toolCallId, result: String(answer.prefix(12000))) }
            catch { self.stop(message: "The spoken result could not be confirmed. Check your chat before trying again.") }
        }
    }

    private func cancelRelay() {
        guard relayTask != nil else { return }
        relayOperation = UUID(); relayTask?.cancel(); relayTask = nil
        stopWork?()
        if !stopped, let conversation, let callID = relayCallID {
            Task { try? await conversation.sendToolResult(for: callID, result: "Work was interrupted. Check the recorded receipts in chat. Do not retry or claim completion.", isError: true) }
        }
        relayCallID = nil
    }

    private func reconcile(_ messages: [Message]) {
        guard leaseValid, var call = record else { return }
        var remaining = 120_000
        var lines: [WhisperKnotCallRecord.Line] = []
        var truncated = messages.count > 300
        for message in messages.prefix(300) {
            let value = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let text = String(value.prefix(min(12_000, remaining)))
            if text.count < value.count { truncated = true }
            guard !text.isEmpty else { truncated = true; break }
            remaining -= text.count
            lines.append(.init(id: message.id, isUser: message.role == .user, text: text, timestamp: message.timestamp))
        }
        // Replace the SDK's snapshot: corrections keep the same message ID,
        // rather than duplicating each transcript/response callback as a turn.
        call.messages = lines; call.truncated = truncated
        record = call; history.save(call)
    }

    func toggleMute() {
        guard phase == .active, leaseValid, !muteBusy, let conversation else { return }
        muteBusy = true
        let shouldMute = !muted
        muteOperation = Task {
            defer { muteBusy = false; muteOperation = nil }
            do { try await conversation.setMuted(shouldMute) }
            catch { if leaseValid { stop(message: "Microphone control was interrupted. Please call again.") } }
        }
    }

    func refreshRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        if outputs.contains(where: { $0.portType == .builtInSpeaker }) { audioRoute = .speaker }
        else if outputs.contains(where: { WhisperAudioRoute.bluetoothPortTypes.contains($0.portType) }) { audioRoute = .bluetooth }
        else { audioRoute = .receiver }
    }

    func route(to route: WhisperAudioRoute) {
        guard phase == .active, leaseValid else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            AudioManager.shared.isSpeakerOutputPreferred = route == .speaker
            switch route {
            case .speaker: try session.setPreferredInput(nil); try session.overrideOutputAudioPort(.speaker)
            case .receiver:
                try session.overrideOutputAudioPort(.none)
                try session.setPreferredInput(session.availableInputs?.first { $0.portType == .builtInMic })
            case .bluetooth:
                guard let input = WhisperAudioRoute.bluetoothInput() else { refreshRoute(); return }
                try session.overrideOutputAudioPort(.none); try session.setPreferredInput(input)
            }
            refreshRoute()
        } catch { refreshRoute() }
    }

    /// Synchronous stop closes the audio-engine gate even while the SDK factory
    /// is still connecting. Restore it only after that operation has torn down.
    func stop(message: String = "Call ended") {
        guard !stopped else { return }
        ringback.stop()
        if let conversation { reconcile(conversation.messages) }
        stopped = true
        revokeVoiceLease()
        cancelRelay()
        openingWatchdog?.cancel(); openingWatchdog = nil
        invitationMonitor?.cancel(); invitationMonitor = nil; endIncomingInvitation()
        durationLimit?.cancel(); durationLimit = nil
        startup?.cancel()
        if Self.audioOwner === self, oldAvailability != nil {
            try? AudioManager.shared.setEngineAvailability(.none)
        }
        record?.endedAt = Date()
        if let record { history.save(record) }
        phase = .ended; status = message
        subscriptions.removeAll()
        if let active = conversation {
            conversation = nil
            let pendingMute = muteOperation
            pendingMute?.cancel()
            Task {
                // Keep the engine closed until any already-started unmute has
                // finished, then tear down before restoring shared availability.
                await pendingMute?.value
                try? await active.setMuted(true)
                await active.endConversation()
                releaseAudioOwnership()
            }
        } else if startup == nil { releaseAudioOwnership() }
    }

    private func monitorIncomingInvitation() {
        guard let incoming else { return }
        invitationMonitor = Task { @MainActor [weak self] in
            do {
                _ = try await WhisperKnotContactService.shared.change(incoming.invitation, action: "connected", answerID: incoming.answerID)
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(10))
                    let current = try await WhisperKnotContactService.shared.read(incoming.invitation)
                    guard let self, self.leaseValid else { return }
                    if current.state != "answered" { self.stop(message: "This invitation ended."); return }
                }
            } catch {
                guard let self, !Task.isCancelled, self.leaseValid else { return }
                self.stop(message: "Couldn’t confirm this invitation. The call has ended.")
            }
        }
    }
    private func endIncomingInvitation() {
        guard let incoming, !invitationEnded else { return }; invitationEnded = true
        let lease = generation
        Task { @MainActor in
            guard lease == AccountStorage.generation else { return }
            _ = try? await WhisperKnotContactService.shared.change(incoming.invitation, action: "end", answerID: incoming.answerID)
        }
    }
    private func revokeVoiceLease() {
        guard let lease = voiceLease else { return }
        voiceLease = nil
        // Revoke only this exact owned call with its original account token.
        // Best effort; no refresh, reconnect, replay or new call authorization.
        Task { @MainActor in
            guard let url = URL(string: WhisperKnotBackend.origin + "/knot/voice/end") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"; request.timeoutInterval = 5
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(lease.token)", forHTTPHeaderField: "X-Whisper-Authorization")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["sessionID": lease.id])
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil; configuration.timeoutIntervalForResource = 5
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            _ = try? await session.data(for: request)
        }
    }

    private func releaseAudioOwnership() {
        guard Self.audioOwner === self else { return }
        if let oldAvailability {
            AudioManager.shared.isSpeakerOutputPreferred = oldSpeakerPreference
            try? AudioManager.shared.setEngineAvailability(oldAvailability)
            self.oldAvailability = nil
        }
        Self.audioOwner = nil
    }

    private nonisolated struct TokenBody: Encodable {
        let consentVersion = "knot_rork_elevenlabs_voice_consent_v2"
        let bot: String
        let voice: String
        let preferences: String
        let profile: String
        let recentConversation: String
        let invitationID: String?
        let answerID: String?
        let welcomeID: String?
        let deviceID: String?
        let welcomeConsentVersion: String?
        let displayName: String?
        let relayConsentVersion: String?
    }
    private nonisolated struct TokenResponse: Decodable {
        let token: String
        let prompt: String
        let voiceID: String
        let firstMessage: String?
        let relayVersion: String?
        let routingVersion: String
        let provider: String
        let sessionID: String
    }
    private nonisolated struct VoiceFailure: Error {
        let message: String
    }
    private nonisolated struct TokenError: Decodable { let error: String }
    private static let connectionLog = Logger(subsystem: "Whisper", category: "KnotVoiceConnection")

    private func fetchToken(bot: WhisperKnotBot, voice: WhisperKnotCallVoice, recentConversation: String) async throws -> TokenResponse {
        try checkLease()
        let token = try await SupabaseService.shared.client.auth.session.accessToken
        try checkLease()
        guard let url = URL(string: WhisperKnotBackend.origin + "/knot/voice/token") else { throw CancellationError() }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 28
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "X-Whisper-Authorization")
        request.httpBody = try JSONEncoder().encode(TokenBody(
            bot: bot.rawValue, voice: voice.rawValue,
            preferences: welcome == nil ? String(WhisperJasperTuningStore.load().promptInstruction.prefix(8000)) : "",
            profile: incoming == nil && welcome == nil && WhisperKnotContextPermission.allowed ? String(WhisperKnotContextPermission.profileBlock().prefix(8000)) : "",
            recentConversation: incoming == nil && welcome == nil && WhisperKnotContextPermission.allowed ? String(recentConversation.suffix(24_000)) : "",
            invitationID: incoming?.invitation.id, answerID: welcome?.answerID ?? incoming?.answerID,
            welcomeID: welcome?.invitationID, deviceID: welcome?.deviceID,
            welcomeConsentVersion: welcome?.consentVersion, displayName: welcome?.displayName,
            relayConsentVersion: relay == nil ? nil : WhisperKnotVoicePreferences.relayConsentVersion
        ))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 220_000 else { throw VoiceFailure(message: "Couldn’t connect this call.") }
        if http.statusCode != 200 { try checkLease() }
        if http.statusCode == 503 {
            let code = (try? JSONDecoder().decode(TokenError.self, from: data))?.error ?? "voice_unavailable"
            // Only fixed allowlisted codes enter logs; no token/body/context.
            let known = ["voice_not_configured", "server_not_configured", "voice_auth_unavailable", "voice_admission_unavailable", "voice_policy_fetch_unavailable", "voice_policy_unavailable", "voice_token_unavailable", "voice_connection_timeout", "voice_unavailable"]
            let safeCode = known.contains(code) ? code : "voice_unavailable"
            Self.connectionLog.error("Connection failed: \(safeCode, privacy: .public)")
            let message: String
            switch safeCode {
            case "voice_not_configured", "server_not_configured": message = "Knot’s call service is unavailable right now. You can keep chatting by text."
            case "voice_auth_unavailable": message = "Couldn’t verify your sign-in for this call. Please try again in a moment."
            case "voice_policy_unavailable": message = "Calls are paused while Knot’s privacy settings are checked. Text chat is still available."
            case "voice_connection_timeout": message = "The call connection took too long. Please try again when your connection is stable."
            default: message = "Couldn’t connect to Knot’s call service. Please try again in a moment."
            }
            throw VoiceFailure(message: message)
        }
        if http.statusCode == 409 { throw VoiceFailure(message: "This invitation ended or was already answered. No call was started.") }
        if http.statusCode == 429 { throw VoiceFailure(message: "You’ve made several calls recently. Please wait a few minutes.") }
        if http.statusCode == 401 || http.statusCode == 403 { throw VoiceFailure(message: "Please sign in again before calling Knot.") }
        guard http.statusCode == 200 else { throw VoiceFailure(message: "Couldn’t connect this call. Please try again later.") }
        let result = try JSONDecoder().decode(TokenResponse.self, from: data)
        // Capture only this response's valid call identity before the final lease
        // check, so Stop can revoke a late result without ever starting its SDK.
        if UUID(uuidString: result.sessionID) != nil { voiceLease = (result.sessionID, token) }
        try checkLease()
        guard result.routingVersion == "knot_rork_voice_v2", result.provider == "rork", voiceLease != nil,
              result.prompt.count <= 180_000, result.prompt.hasPrefix("[KNOT_VOICE_V2.") else {
            throw VoiceFailure(message: "Couldn’t confirm Knot’s shared AI connection. No call was started.")
        }
        return result
    }
}
