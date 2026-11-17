import Foundation
import AVFoundation
import Supabase

/// Jasper's TRUE speech-to-speech voice — an OpenAI Realtime session in the
/// `echo` voice over WebSocket. The microphone streams straight to the
/// model, semantic turn detection handles turn-taking and barge-in (talk
/// over Jasper to interrupt), and Jasper's PCM audio plays back while it
/// generates. No robotic on-device TTS anywhere.
///
/// Credentials: a short-lived Realtime client secret minted by the project
/// backend (`/ai/realtime-token`, signed-in users only) — the OpenAI key
/// never ships inside the app.
@Observable
@MainActor
final class WhisperEmberRealtimeVoice {
    enum Phase: Equatable {
        case connecting
        /// Live — mic hot, Jasper listening.
        case listening
        /// Live, but the user muted the mic.
        case idle
        case thinking
        case speaking
        case unavailable
    }

    private(set) var phase: Phase = .connecting
    /// Live (partial) transcript of what the user is saying.
    private(set) var transcript: String = ""
    /// Jasper's reply transcript, streaming while it talks.
    private(set) var replyText: String = ""
    /// Smoothed mic level 0…1 for the waveform.
    private(set) var level: CGFloat = 0
    private(set) var statusMessage: String?
    private(set) var micMuted: Bool = false
    private(set) var connectedAt: Date?

    var usesSpeaker: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
    }

    func toggleSpeaker() {
        guard managesAudioSession, connectedAt != nil, !isShutDown,
              !WhisperCameraCallMonitor.shared.callOwnsAudio else { return }
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(usesSpeaker ? .none : .speaker)
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    /// Gain stage after the player — WebRTC's voice-processing audio unit
    /// attenuates app-played audio during calls, which made Jasper's voice
    /// noticeably quiet in meetings. Boosted only while a call owns the
    /// audio session.
    @ObservationIgnored private let boost = AVAudioUnitEQ(numberOfBands: 0)
    @ObservationIgnored private let playFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!
    /// When false, the AVAudioSession belongs to someone else (the meeting's
    /// WebRTC engine) — never reconfigure or deactivate it from here.
    /// Deactivating the shared session behind WebRTC's back is what killed
    /// meeting audio after closing Jasper's voice line mid-call.
    @ObservationIgnored var managesAudioSession: Bool = true

    @ObservationIgnored private var ws: URLSessionWebSocketTask?
    @ObservationIgnored private var receiveTask: Task<Void, Never>?
    @ObservationIgnored private var handshakeTask: Task<Void, Never>?
    @ObservationIgnored private var onExchange: ((String, String) -> Void)?
    @ObservationIgnored private var pendingUser: String = ""
    @ObservationIgnored private var scheduledChunks: Int = 0
    @ObservationIgnored private var responseActive: Bool = false
    @ObservationIgnored private var isShutDown: Bool = false
    @ObservationIgnored private var hasInputTap: Bool = false
    @ObservationIgnored private var engineWired: Bool = false
    @ObservationIgnored private var sentSessionUpdate: Bool = false
    @ObservationIgnored private var lastInstructions: String = ""
    /// Read from the realtime audio tap thread — written only on the main actor.
    @ObservationIgnored nonisolated(unsafe) private var micEnabledFlag: Bool = true
    @ObservationIgnored nonisolated(unsafe) private var tapSocket: URLSessionWebSocketTask?
    /// In-meeting half-duplex gate. The meeting plays Jasper through the
    /// loudspeaker while WebRTC owns the audio session — WebRTC's echo
    /// cancellation does NOT cover our AVAudioEngine output, so the open
    /// mic fed Jasper's own voice straight back into the model: it barged
    /// in on itself, cut its own replies short, and answered itself in a
    /// loop. While Jasper is speaking (plus a short echo tail) mic frames
    /// are simply not sent. Standalone voice mode keeps the mic hot for
    /// natural barge-in — its `.voiceChat` session cancels the echo there.
    @ObservationIgnored nonisolated(unsafe) private var halfDuplex: Bool = false
    @ObservationIgnored nonisolated(unsafe) private var speakingFlag: Bool = false
    @ObservationIgnored nonisolated(unsafe) private var micHoldUntil: CFAbsoluteTime = 0

    private nonisolated struct TokenResponse: Codable, Sendable {
        let value: String
    }

    // MARK: - Permissions

    /// Mic permission only — transcription happens server-side, so Speech
    /// Recognition authorization is no longer involved at all.
    func requestAuthorization() async -> Bool {
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
        if !granted {
            statusMessage = "Enable Microphone access in Settings to talk to Knot."
            phase = .unavailable
        }
        return granted
    }

    // MARK: - Session lifecycle

    /// Opens the realtime line: mints an ephemeral secret from the backend,
    /// dials the OpenAI Realtime WebSocket, configures the session (echo
    /// voice, semantic turn detection, live input transcription), and starts
    /// streaming the microphone. `onExchange` fires after each spoken turn
    /// with (userText, replyText) so the chat transcript stays complete.
    func connect(
        instructions: String,
        onExchange: @escaping (String, String) -> Void
    ) async {
        guard !managesAudioSession || !WhisperCameraCallMonitor.shared.callOwnsAudio else {
            phase = .unavailable
            statusMessage = "Finish your call before starting Knot voice. You can still use text."
            return
        }
        // A fresh connect always reopens the line — a previous shutdown
        // (voice toggled off, screen closed) must NOT latch the instance
        // dead. This latch was why reopening Jasper's voice silently sat on
        // "connecting" forever.
        isShutDown = false
        sentSessionUpdate = false
        connectedAt = nil
        responseActive = false
        scheduledChunks = 0
        pendingUser = ""
        transcript = ""
        replyText = ""
        micEnabledFlag = false
        halfDuplex = !managesAudioSession
        speakingFlag = false
        micHoldUntil = 0
        self.onExchange = onExchange
        lastInstructions = instructions
        phase = .connecting
        statusMessage = nil
        do {
            let secret = try await mintSecret()
            guard !isShutDown, !Task.isCancelled else { return }
            guard !managesAudioSession || !WhisperCameraCallMonitor.shared.callOwnsAudio else {
                phase = .unavailable
                statusMessage = "Finish your call before starting Knot voice."
                return
            }
            guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            let socket = URLSession.shared.webSocketTask(with: request)
            ws = socket
            tapSocket = socket
            socket.resume()
            // Queued behind the handshake; re-sent on `session.created` too,
            // so a racey first send can never leave the session unconfigured.
            sendEvent(sessionUpdate(instructions: instructions))
            try startAudio()
            startReceiveLoop()
            guard !isShutDown else { return }
            // Remain connecting until the server acknowledges session configuration.
            handshakeTask?.cancel()
            handshakeTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                guard let self, !self.isShutDown, self.connectedAt == nil else { return }
                self.shutdown()
                self.statusMessage = "Knot's voice service didn't connect. Close and try again."
                self.phase = .unavailable
            }
        } catch {
            guard !isShutDown else { return }
            shutdown()
            if (error as? URLError)?.code == .userAuthenticationRequired {
                statusMessage = "Sign in to talk to Knot live — then try again."
            } else if (error as? URLError)?.code == .resourceUnavailable {
                statusMessage = "No microphone is available right now."
            } else {
                statusMessage = "Knot's live voice couldn't connect. Tap the mic to retry."
            }
            phase = .unavailable
        }
    }

    /// The user muted/unmuted the mic. The session stays warm either way.
    func toggleMute() {
        guard connectedAt != nil, !isShutDown else { return }
        micMuted.toggle()
        micEnabledFlag = !micMuted
        if micMuted {
            level = 0
            if phase == .listening { phase = .idle }
        } else if phase == .idle {
            phase = .listening
        }
    }

    /// Barge-in via the button: cancel the current answer and go back to
    /// listening immediately.
    func interruptSpeaking() {
        sendEvent(["type": "response.cancel"])
        stopPlayback()
        responseActive = false
        replyText = ""
        if phase == .speaking || phase == .thinking {
            phase = micMuted ? .idle : .listening
        }
    }

    /// Tears the whole line down. Safe to call repeatedly, and safe to
    /// `connect()` again afterwards — the line re-opens cleanly.
    func shutdown() {
        isShutDown = true
        connectedAt = nil
        micEnabledFlag = false
        handshakeTask?.cancel(); handshakeTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        tapSocket = nil
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
        if hasInputTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        player.stop()
        engine.stop()
        scheduledChunks = 0
        responseActive = false
        speakingFlag = false
        level = 0
        if managesAudioSession && !WhisperCameraCallMonitor.shared.callOwnsAudio {
            // Only release the session we activated ourselves. In meetings
            // the WebRTC engine owns it — deactivating would mute the call.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        onExchange = nil
    }

    // MARK: - Backend credential

    private func mintSecret() async throws -> String {
        let token = try await SupabaseService.shared.client.auth.session.accessToken
        var lastError: Error = URLError(.badServerResponse)
        // Walk every backend candidate — the configured deploy first, then
        // the known-good production host. A stale configured URL (missing
        // the newer /ai routes) must never kill Jasper's voice outright.
        for host in WhisperBillingBackend.hosts {
            guard let url = URL(string: "\(host)/ai/realtime-token") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 20
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                // Only a real auth rejection should tell the user to sign in —
                // backend hiccups (404/502/503) fall through to the next host.
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw URLError(.userAuthenticationRequired)
                }
                guard http.statusCode == 200 else {
                    print("[EmberVoice] token mint failed at \(host): HTTP \(http.statusCode)")
                    lastError = URLError(.badServerResponse)
                    continue
                }
                return try JSONDecoder().decode(TokenResponse.self, from: data).value
            } catch let urlError as URLError where urlError.code == .userAuthenticationRequired {
                throw urlError
            } catch {
                print("[EmberVoice] token mint error at \(host): \(error.localizedDescription)")
                lastError = error
                continue
            }
        }
        throw lastError
    }

    // MARK: - Audio pipeline

    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        if managesAudioSession {
            // `.voiceChat` enables echo cancellation so Jasper never hears
            // itself through the speaker and semantic VAD stays accurate.
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        }
        guard session.isInputAvailable else { throw URLError(.resourceUnavailable) }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw URLError(.resourceUnavailable)
        }

        // Attach/connect exactly once — reconnects reuse the wired graph.
        if !engineWired {
            engine.attach(player)
            engine.attach(boost)
            engine.connect(player, to: boost, format: playFormat)
            engine.connect(boost, to: engine.mainMixerNode, format: playFormat)
            engineWired = true
        }
        // In-meeting (WebRTC owns the session): +12 dB of clean gain counters
        // the voice-processing attenuation. Standalone voice screen: flat.
        boost.globalGain = managesAudioSession ? 0 : 12
        engine.mainMixerNode.outputVolume = 1

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, self.micEnabledFlag, let socket = self.tapSocket else { return }
            // Half-duplex (in-meeting): never stream the mic while Jasper's
            // own reply is coming out of the speaker right next to it.
            if self.halfDuplex,
               self.speakingFlag || CFAbsoluteTimeGetCurrent() < self.micHoldUntil {
                return
            }
            let (data, rms) = Self.pcm16Data(from: buffer, targetRate: 24_000)
            guard !data.isEmpty else { return }
            let payload: [String: Any] = [
                "type": "input_audio_buffer.append",
                "audio": data.base64EncodedString(),
            ]
            if let json = try? JSONSerialization.data(withJSONObject: payload),
               let text = String(data: json, encoding: .utf8) {
                socket.send(.string(text)) { _ in }
            }
            let clamped = CGFloat(min(1, rms * 14))
            Task { @MainActor [weak self] in
                guard let self, !self.micMuted else { return }
                self.level = self.level * 0.6 + clamped * 0.4
            }
        }
        hasInputTap = true
        engine.prepare()
        try engine.start()
        player.play()
    }

    /// Downsamples a mic buffer to 24kHz mono PCM16 with linear
    /// interpolation and reports its RMS level. Pure math — safe to run on
    /// the realtime audio thread.
    private nonisolated static func pcm16Data(
        from buffer: AVAudioPCMBuffer,
        targetRate: Double
    ) -> (Data, Float) {
        guard let channel = buffer.floatChannelData?[0] else { return (Data(), 0) }
        let frames = Int(buffer.frameLength)
        guard frames > 1 else { return (Data(), 0) }
        let sourceRate = buffer.format.sampleRate
        guard sourceRate > 0 else { return (Data(), 0) }
        let ratio = sourceRate / targetRate
        let outFrames = max(1, Int(Double(frames) / ratio))
        var data = Data(capacity: outFrames * 2)
        var sumSquares: Float = 0
        for index in 0..<outFrames {
            let src = Double(index) * ratio
            let base = Int(src)
            let frac = Float(src - Double(base))
            let a = channel[min(base, frames - 1)]
            let b = channel[min(base + 1, frames - 1)]
            let sample = a + (b - a) * frac
            sumSquares += sample * sample
            let clamped = max(-1, min(1, sample))
            var value = Int16(clamped * 32767)
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        let rms = sqrt(sumSquares / Float(outFrames))
        return (data, rms)
    }

    private func schedulePCM(_ data: Data) {
        let frames = data.count / 2
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: playFormat,
                frameCapacity: AVAudioFrameCount(frames)
              ),
              let dst = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for index in 0..<frames {
                dst[index] = Float(samples[index]) / 32768.0
            }
        }
        scheduledChunks += 1
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scheduledChunks = max(0, self.scheduledChunks - 1)
                self.maybeFinishSpeaking()
            }
        }
        if engine.isRunning && !player.isPlaying { player.play() }
        speakingFlag = true
        phase = .speaking
    }

    private func stopPlayback() {
        player.stop()
        scheduledChunks = 0
        speakingFlag = false
        micHoldUntil = CFAbsoluteTimeGetCurrent() + 0.45
        if engine.isRunning { player.play() }
    }

    private func maybeFinishSpeaking() {
        if scheduledChunks <= 0 && !responseActive && phase == .speaking {
            speakingFlag = false
            micHoldUntil = CFAbsoluteTimeGetCurrent() + 0.45
            if halfDuplex {
                // Drop any echo frames that slipped in around the boundary
                // so they can't be read back as a new question.
                sendEvent(["type": "input_audio_buffer.clear"])
            }
            phase = micMuted ? .idle : .listening
        }
    }

    // MARK: - Events

    private func sendEvent(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8)
        else { return }
        ws?.send(.string(text)) { _ in }
    }

    private func sessionUpdate(instructions: String) -> [String: Any] {
        [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "model": "gpt-realtime",
                "instructions": instructions,
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "transcription": ["model": "gpt-4o-mini-transcribe", "language": "en"],
                        "turn_detection": ["type": "semantic_vad"],
                    ],
                    "output": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "voice": "echo",
                    ],
                ],
            ],
        ]
    }

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let socket = self.ws else { return }
                do {
                    let message = try await socket.receive()
                    switch message {
                    case .string(let text):
                        self.handleEvent(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleEvent(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled && !self.isShutDown && self.ws === socket {
                        self.shutdown()
                        self.statusMessage =
                            "Knot's voice line dropped. Close and reopen voice mode to reconnect."
                        self.phase = .unavailable
                    }
                    return
                }
            }
        }
    }

    private func handleEvent(_ text: String) {
        guard !isShutDown else { return }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let event = object as? [String: Any],
              let type = event["type"] as? String
        else { return }

        switch type {
        case "session.created":
            // Re-assert the configuration in case the first update raced the
            // handshake — sending it twice is harmless.
            if !sentSessionUpdate {
                sentSessionUpdate = true
                sendEvent(sessionUpdate(instructions: lastInstructions))
            }

        case "session.updated":
            guard !isShutDown, engine.isRunning else { return }
            if connectedAt == nil {
                connectedAt = Date()
                handshakeTask?.cancel(); handshakeTask = nil
                micEnabledFlag = !micMuted
                phase = micMuted ? .idle : .listening
            }

        case "input_audio_buffer.speech_started":
            // Barge-in: the person talked over Jasper — cut playback instantly.
            stopPlayback()
            transcript = ""
            if phase == .speaking || phase == .thinking {
                phase = micMuted ? .idle : .listening
            }

        case "conversation.item.input_audio_transcription.delta":
            if let delta = event["delta"] as? String {
                transcript += delta
            }

        case "conversation.item.input_audio_transcription.completed":
            if let final = event["transcript"] as? String, !final.isEmpty {
                transcript = final
                pendingUser = final
            }

        case "response.created":
            responseActive = true
            replyText = ""
            if phase != .speaking { phase = .thinking }

        case "response.output_audio.delta", "response.audio.delta":
            if let base64 = event["delta"] as? String,
               let audio = Data(base64Encoded: base64) {
                transcript = ""
                schedulePCM(audio)
            }

        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            if let delta = event["delta"] as? String {
                replyText += delta
            }

        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            if let full = event["transcript"] as? String, !full.isEmpty {
                replyText = full
            }

        case "response.done":
            responseActive = false
            let userText = pendingUser
            let reply = replyText
            pendingUser = ""
            if !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onExchange?(userText, reply)
            }
            maybeFinishSpeaking()

        case "error":
            // "No active response" cancellation noise is expected mid-barge-in.
            let message =
                ((event["error"] as? [String: Any])?["message"] as? String) ?? ""
            if !message.localizedCaseInsensitiveContains("no active response")
                && !message.localizedCaseInsensitiveContains("cancellation") {
                // Non-fatal server complaints are logged, never fatal to the UI.
                print("[EmberVoice] realtime error: \(message)")
            }

        default:
            break
        }
    }
}
