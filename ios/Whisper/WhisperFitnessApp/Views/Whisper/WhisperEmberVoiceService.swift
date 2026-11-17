import Foundation
import AVFoundation
import Speech
import Supabase

/// Voice pipeline for the talk-to-Jasper screen: speech-to-text via
/// `SFSpeechRecognizer` + `AVAudioEngine`, and spoken replies via the
/// OpenAI GPT voice (`gpt-4o-mini-tts`) — the same natural voice the web
/// client uses — with `AVSpeechSynthesizer` only as an offline fallback.
///
/// The cloud simulator has no microphone, so listening will simply fail to
/// start there — the screen detects that and degrades to typed chat rather
/// than breaking. On a real device the full hands-free loop works.
@Observable
@MainActor
final class WhisperEmberVoiceService: NSObject {
    enum Phase: Equatable { case idle, listening, thinking, speaking, unavailable }

    private(set) var phase: Phase = .idle
    /// Live (partial) transcript while the user speaks.
    private(set) var transcript: String = ""
    /// Smoothed input level 0…1 for the listening visualization.
    private(set) var level: CGFloat = 0
    private(set) var statusMessage: String?

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// GPT-voice playback — the natural OpenAI voice, not the robot one.
    private var player: AVAudioPlayer?
    private var ttsTask: Task<Void, Never>?

    private var onFinalTranscript: ((String) -> Void)?
    private var onSpeechFinished: (() -> Void)?
    private var silenceTimer: Timer?
    private var lastTranscriptChange: Date = .distantPast
    private var captureID: UUID?
    private var isShutDown: Bool = false

    override init() {
        super.init()
        synthesizer.delegate = self
        recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
    }

    // MARK: - Permissions

    /// Requests speech + mic permission. Returns false (and sets a message) if
    /// either is denied or unsupported on this build/device.
    func requestAuthorization() async -> Bool {
        guard !isShutDown else { return false }
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard !isShutDown else { return false }
        guard speechOK else {
            statusMessage = "Enable Speech Recognition in Settings to talk to Knot."
            phase = .unavailable
            return false
        }
        let micOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard !isShutDown else { return false }
        guard micOK else {
            statusMessage = "Enable Microphone access in Settings to talk to Knot."
            phase = .unavailable
            return false
        }
        return true
    }

    // MARK: - Listening

    /// Starts capturing speech. `onFinal` fires once the user pauses (auto
    /// end-of-utterance) or `finishListening()` is called, with the transcript.
    func startListening(onFinal: @escaping (String) -> Void) {
        isShutDown = false
        guard !WhisperLiveRTCService.shared.connected else {
            statusMessage = "Voice mode is paused while you're in a live call. Keep typing to Knot instead."
            phase = .unavailable
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            statusMessage = "Voice isn't available right now. You can keep typing."
            phase = .unavailable
            return
        }
        stopSpeaking()
        teardownAudio()
        cancelRecognition()
        let captureID = UUID()
        self.captureID = captureID
        transcript = ""
        onFinalTranscript = onFinal

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            guard session.isInputAvailable else {
                statusMessage = "No microphone input is available. Keep typing instead."
                phase = .unavailable
                cancelRecognition()
                return
            }
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                statusMessage = "No microphone input is available. Keep typing instead."
                phase = .unavailable
                cancelRecognition()
                return
            }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, request] buffer, _ in
                request.append(buffer)
                let level = Self.bufferLevel(buffer)
                Task { @MainActor [weak self] in
                    guard let self, self.captureID == captureID, self.phase == .listening else { return }
                    self.updateLevel(level)
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            statusMessage = "Couldn't start the microphone. Keep typing instead."
            phase = .unavailable
            cancelRecognition()
            return
        }

        phase = .listening
        statusMessage = nil
        lastTranscriptChange = Date()
        startSilenceWatcher()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor [weak self] in
                guard let self, self.captureID == captureID, self.phase == .listening else { return }
                if let text, !text.isEmpty {
                    self.transcript = text
                    self.lastTranscriptChange = Date()
                }
                if isFinal || error != nil { self.finishListening() }
            }
        }
    }

    /// Ends capture and delivers whatever was transcribed.
    func finishListening() {
        guard phase == .listening else { return }
        captureID = nil
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        teardownAudio()
        silenceTimer?.invalidate(); silenceTimer = nil
        level = 0
        if text.isEmpty {
            phase = .idle
        } else {
            phase = .thinking
            onFinalTranscript?(text)
        }
    }

    func cancelListening() {
        captureID = nil
        teardownAudio()
        silenceTimer?.invalidate(); silenceTimer = nil
        level = 0
        if phase == .listening { phase = .idle }
    }

    // MARK: - Speaking

    /// Speaks Jasper's reply out loud with the OpenAI GPT voice, then calls
    /// `onFinished` so the screen can loop back to listening. Falls back to
    /// the on-device synthesizer only when the network call fails.
    func speak(_ text: String, onFinished: @escaping () -> Void) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { onFinished(); return }
        onSpeechFinished = onFinished
        do {
            let session = AVAudioSession.sharedInstance()
            // `.spokenAudio` plays TTS at full media volume — `.voicePrompt`
            // routes through the system prompt mixer, which is much quieter.
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch { /* best-effort; playback still attempts */ }

        phase = .speaking
        ttsTask?.cancel()
        ttsTask = Task { [weak self] in
            guard let self else { return }
            if let audio = await Self.fetchGPTVoice(for: clean) {
                guard !Task.isCancelled, self.phase == .speaking else { return }
                if self.playAudio(audio) { return }
            }
            guard !Task.isCancelled, self.phase == .speaking else { return }
            self.speakWithFallbackVoice(clean)
        }
    }

    /// OpenAI `gpt-4o-mini-tts` via the backend `/ai/speech` proxy — warm,
    /// natural, human-sounding, and the OpenAI key never ships in the app
    /// binary. Signed-in users only; returns nil on any failure (the system
    /// voice fallback below covers it).
    private nonisolated static func fetchGPTVoice(for text: String) async -> Data? {
        guard let token = try? await SupabaseService.shared.client.auth.session.accessToken,
              !token.isEmpty else { return nil }
        let hosts = await WhisperBillingBackend.hosts
        for host in hosts {
            guard let url = URL(string: "\(host)/ai/speech") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 20
            let body: [String: Any] = [
                "model": "gpt-4o-mini-tts",
                "voice": "alloy",
                "text": String(text.prefix(3000)),
                "format": "mp3",
                "instructions": "Speak warmly and conversationally, like a supportive friend. Natural pacing, light energy."
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            guard let (data, response) = try? await URLSession.shared.data(for: req),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  !data.isEmpty else { continue }
            return data
        }
        return nil
    }

    /// Plays fetched TTS audio. Returns false when playback couldn't start.
    private func playAudio(_ data: Data) -> Bool {
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.volume = 1
            self.player = player
            player.play()
            return true
        } catch {
            return false
        }
    }

    /// Offline fallback — the system voice, used only when the GPT voice
    /// can't be fetched.
    private func speakWithFallbackVoice(_ clean: String) {
        let utterance = AVSpeechUtterance(string: clean)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.prefersAssistiveTechnologySettings = false
        if let voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        ttsTask?.cancel()
        onSpeechFinished = nil
        ttsTask = nil
        if let player, player.isPlaying {
            player.stop()
        }
        player = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if phase == .speaking { phase = .idle }
    }

    /// Fully stops voice activity (used when the screen closes).
    func shutdown() {
        isShutDown = true
        captureID = nil
        cancelRecognition()
        teardownAudio()
        stopSpeaking()
        silenceTimer?.invalidate(); silenceTimer = nil
        onFinalTranscript = nil
        onSpeechFinished = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        phase = .idle
    }

    // MARK: - Internals

    private func updateLevel(_ raw: CGFloat) {
        level = level * 0.6 + raw * 0.4
    }

    private func startSilenceWatcher() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .listening else { return }
                // Auto-finish ~1.4s after the transcript stops growing.
                if !self.transcript.isEmpty, Date().timeIntervalSince(self.lastTranscriptChange) > 1.4 {
                    self.finishListening()
                }
            }
        }
    }

    private func teardownAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
    }

    private func cancelRecognition() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
    }

    private nonisolated static func bufferLevel(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frames { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(frames))
        // Map RMS to a lively 0…1 range.
        let scaled = min(1, max(0, CGFloat(rms) * 14))
        return scaled
    }
}

// MARK: - AVAudioPlayerDelegate (GPT voice)

extension WhisperEmberVoiceService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if phase == .speaking { phase = .idle }
            self.player = nil
            let cb = onSpeechFinished
            onSpeechFinished = nil
            cb?()
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate (fallback voice)

extension WhisperEmberVoiceService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if phase == .speaking { phase = .idle }
            let cb = onSpeechFinished
            onSpeechFinished = nil
            cb?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if phase == .speaking { phase = .idle }
            onSpeechFinished = nil
        }
    }
}
