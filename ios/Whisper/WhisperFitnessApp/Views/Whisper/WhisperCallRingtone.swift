import Foundation
import AVFoundation

/// Plays an audible ring while a Whisper call is in the `.ringing` state.
///
/// Both directions use warm bundled melodies generated for Whisper instead
/// of harsh synthesized telephone tones:
/// - **Incoming**: `whisper_call_ringtone.mp3` — a soft marimba/kalimba
///   motif, routed to the speaker so it's heard even face-down.
/// - **Ringback** (outgoing): `whisper_call_ringback.mp3` — two gentle
///   chime notes with a long rest, played quietly while the line rings.
///
/// If a bundle resource is ever missing, a soft synthesized fallback tone
/// keeps the ring audible (never silent, never scary).
@MainActor
final class WhisperCallRingtone {
    static let shared = WhisperCallRingtone()

    enum Style { case ringback, incoming }

    private var player: AVAudioPlayer?
    private var currentStyle: Style?

    // Synth fallback (only used when the bundled MP3s can't be loaded).
    private let engine = AVAudioEngine()
    private let toneNode = AVAudioPlayerNode()
    private var didAttach = false

    // Standalone AI calls own an isolated player; real calls keep using shared.
    init() {}

    func start(style: Style, defaultToSpeaker: Bool = false) {
        guard currentStyle != style else { return }
        stop()
        currentStyle = style
        ensureSession(style: style, defaultToSpeaker: defaultToSpeaker)

        let resource = style == .incoming ? "whisper_call_ringtone" : "whisper_call_ringback"
        if let url = Bundle.main.url(forResource: resource, withExtension: "mp3"),
           let mp3 = try? AVAudioPlayer(contentsOf: url) {
            mp3.numberOfLoops = -1
            mp3.volume = style == .incoming ? 0.95 : 0.42
            mp3.prepareToPlay()
            mp3.play()
            player = mp3
            return
        }

        startSynthFallback(style: style)
    }

    func stop() {
        currentStyle = nil
        player?.stop()
        player = nil
        if toneNode.isPlaying { toneNode.stop() }
        if engine.isRunning { engine.stop() }
    }

    // MARK: - Internals

    /// Best-effort audio session config. We don't fail the call if this throws
    /// — the WebRTC service owns the long-lived `.playAndRecord` session and
    /// will take over once the call connects. Incoming ringing stays audible;
    /// outgoing ringback follows the normal receiver/headset route.
    private func ensureSession(style: Style, defaultToSpeaker: Bool) {
        let session = AVAudioSession.sharedInstance()
        let useSpeaker = style == .incoming || defaultToSpeaker
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: useSpeaker
                    ? [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers]
                    : [.allowBluetoothHFP, .allowBluetoothA2DP, .mixWithOthers]
            )
            try session.setActive(true, options: [])
            // AI calls default to speaker like their connected SDK session,
            // but keep a connected headset/Bluetooth route when available.
            let hasExternalOutput = session.currentRoute.outputs.contains {
                $0.portType != .builtInSpeaker && $0.portType != .builtInReceiver
            }
            let forceSpeaker = style == .incoming || (defaultToSpeaker && !hasExternalOutput)
            try session.overrideOutputAudioPort(forceSpeaker ? .speaker : .none)
        } catch {
            // Non-fatal — call lifecycle still works without ringtone audio.
        }
    }

    // MARK: - Synth fallback

    private func startSynthFallback(style: Style) {
        ensureGraph()
        guard let buffer = makeBuffer(for: style) else { return }
        do {
            if engine.isRunning == false {
                try engine.start()
            }
        } catch {
            currentStyle = nil
            return
        }
        toneNode.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        toneNode.play()
    }

    private func ensureGraph() {
        guard !didAttach else { return }
        didAttach = true
        engine.attach(toneNode)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(toneNode, to: engine.mainMixerNode, format: format)
    }

    /// Builds a single-loop PCM buffer for the chosen ring style. Soft
    /// amplitudes + long rests keep even the fallback pleasant.
    private func makeBuffer(for style: Style) -> AVAudioPCMBuffer? {
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        let pattern: (onSeconds: Double, offSeconds: Double, f1: Double, f2: Double, amp: Float)
        switch style {
        case .ringback:
            pattern = (1.2, 3.8, 523.25, 659.25, 0.10)   // C5 + E5, gentle
        case .incoming:
            pattern = (1.4, 1.2, 523.25, 783.99, 0.22)   // C5 + G5, soft chime
        }
        let totalSeconds = pattern.onSeconds + pattern.offSeconds
        let frameCount = AVAudioFrameCount(totalSeconds * sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }
        buffer.frameLength = frameCount

        let channels = Int(format.channelCount)
        guard let channelData = buffer.floatChannelData else { return nil }
        let onFrames = Int(pattern.onSeconds * sampleRate)
        let twoPi = 2.0 * Double.pi
        // 40 ms cosine fade so each ring doesn't click on/off.
        let fadeFrames = max(1, Int(0.040 * sampleRate))

        for frame in 0..<Int(frameCount) {
            var sample: Float = 0
            if frame < onFrames {
                let t = Double(frame) / sampleRate
                let s1 = sin(twoPi * pattern.f1 * t)
                let s2 = sin(twoPi * pattern.f2 * t)
                var v = Float((s1 + s2) * 0.5) * pattern.amp
                if frame < fadeFrames {
                    v *= Float(frame) / Float(fadeFrames)
                } else if frame > onFrames - fadeFrames {
                    let remaining = max(0, onFrames - frame)
                    v *= Float(remaining) / Float(fadeFrames)
                }
                sample = v
            }
            for ch in 0..<channels {
                channelData[ch][frame] = sample
            }
        }
        return buffer
    }
}
