import Foundation
import AVFoundation
import LiveKit
import Supabase
import Auth

/// Real in-app voice / video transport for Whisper calls, backed by
/// LiveKit Cloud. Replaces the previous WhisperWebRTCService + bespoke
/// SDP-over-DM signaling. LiveKit handles SDP, ICE, TURN, reconnection
/// and adaptive bitrate for us — the call service only needs to ring
/// the other peer and tell them what room to join.
///
/// Lifecycle:
/// 1. Both peers call `join(roomName:identity:isVideo:)` with the
///    shared call id as the room name. The service mints a LiveKit
///    token via `whisper-livekit-token` Edge Function and connects.
/// 2. Microphone (and camera, for video calls) is published immediately
///    on connect. Mute / camera-off / camera-flip / speaker run through
///    `setMuted`, `setCameraEnabled`, `switchCamera`, `setSpeaker`.
/// 3. Remote video tracks are exposed via `remoteVideoTrack` for the
///    SwiftUI renderer; observers are notified through
///    `onRemoteVideoTrackChanged` and `onConnectionStateChanged`.
/// 4. `leave()` disconnects the room and releases the audio session.
@MainActor
final class WhisperLiveKitService: NSObject {
    static let shared = WhisperLiveKitService()

    /// Emitted when the room connection state changes. UI can flip
    /// "Connecting…" → "Connected" off this.
    var onConnectionStateChanged: ((ConnectionState) -> Void)?
    /// Emitted when ICE / signaling fails permanently — surfaces a
    /// "Couldn't connect" banner via WhisperCallService.
    var onConnectionFailed: (() -> Void)?
    /// Emitted when the remote participant's camera track becomes
    /// available (or goes away). The SwiftUI renderer attaches to the
    /// returned track.
    var onRemoteVideoTrackChanged: ((VideoTrack?) -> Void)?
    /// Emitted when the remote participant joins / leaves the room.
    /// `true` once they've actually arrived — used to flip outgoing
    /// state from "Ringing" → "Connected" without needing a custom
    /// `.accept` signal.
    var onRemoteParticipantPresenceChanged: ((Bool) -> Void)?

    /// The currently active local video track (camera). Exposed for
    /// the SwiftUI local-preview tile.
    private(set) var localVideoTrack: VideoTrack?
    /// The remote participant's published camera track, if any.
    private(set) var remoteVideoTrack: VideoTrack?

    private var room: Room?
    private var currentRoomName: String?
    private var isVideoCall: Bool = false
    private var didConfigureAudio = false
    private var currentCameraPosition: AVCaptureDevice.Position = .front

    private override init() { super.init() }

    /// Returns the first published camera VideoTrack for a participant
    /// without using the SDK's `internal` `getTrackPublication(source:)`.
    private static func firstCameraTrack(for participant: Participant) -> VideoTrack? {
        for pub in participant.trackPublications.values where pub.source == .camera {
            if let track = pub.track as? VideoTrack { return track }
        }
        return nil
    }

    // MARK: - Public API

    /// Connects to the LiveKit room named `roomName` as `identity`,
    /// publishing microphone (and camera for video calls). Returns when
    /// the underlying connect call completes (or throws).
    func join(roomName: String, identity: String, isVideo: Bool) async {
        // If we're already in this room, no-op.
        if let r = room, currentRoomName == roomName, r.connectionState != .disconnected {
            return
        }
        // Tear down any stale room from a prior call.
        if room != nil { await leave() }

        isVideoCall = isVideo
        configureAudioSession(video: isVideo)

        let url = Config.allValues["EXPO_PUBLIC_LIVEKIT_URL"] ?? "wss://whisper-xgk6npj8.livekit.cloud"
        guard !url.isEmpty else {
            onConnectionFailed?()
            return
        }
        guard let token = await mintToken(roomName: roomName, identity: identity) else {
            onConnectionFailed?()
            return
        }

        let r = Room(delegate: self)
        room = r
        currentRoomName = roomName

        let connectOptions = ConnectOptions(enableMicrophone: true)
        let roomOptions = RoomOptions(
            defaultCameraCaptureOptions: CameraCaptureOptions(
                position: .front,
                dimensions: .h720_169,
                fps: 30
            ),
            adaptiveStream: true,
            suspendLocalVideoTracksInBackground: true
        )
        do {
            try await r.connect(
                url: url,
                token: token,
                connectOptions: connectOptions,
                roomOptions: roomOptions
            )
            if isVideo {
                _ = try? await r.localParticipant.setCamera(enabled: true)
                localVideoTrack = Self.firstCameraTrack(for: r.localParticipant)
                // Video calls belong on the loudspeaker — LiveKit's audio
                // engine can re-route to the earpiece when it (re)configures
                // the session during connect, which made calls sound quiet.
                setSpeaker(true)
            }
        } catch {
            print("[Whisper] LiveKit connect failed: \(error)")
            onConnectionFailed?()
        }
    }

    /// Disconnects the room and releases the audio session.
    func leave() async {
        if let r = room {
            await r.disconnect()
        }
        room = nil
        currentRoomName = nil
        localVideoTrack = nil
        if remoteVideoTrack != nil {
            remoteVideoTrack = nil
            onRemoteVideoTrackChanged?(nil)
        }
        isVideoCall = false
        releaseAudioSession()
    }

    func setMuted(_ muted: Bool) {
        guard let r = room else { return }
        Task { try? await r.localParticipant.setMicrophone(enabled: !muted) }
    }

    func setCameraEnabled(_ enabled: Bool) {
        guard let r = room else { return }
        Task {
            try? await r.localParticipant.setCamera(enabled: enabled)
            await MainActor.run {
                self.localVideoTrack = Self.firstCameraTrack(for: r.localParticipant)
            }
        }
    }

    func switchCamera() {
        guard let r = room,
              let track = Self.firstCameraTrack(for: r.localParticipant) as? LocalVideoTrack,
              let capturer = track.capturer as? CameraCapturer
        else { return }
        Task {
            try? await capturer.switchCameraPosition()
            await MainActor.run {
                self.currentCameraPosition =
                    self.currentCameraPosition == .front ? .back : .front
            }
        }
    }

    func setSpeaker(_ on: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.overrideOutputAudioPort(on ? .speaker : .none)
        } catch {
            // Best-effort.
        }
    }

    // MARK: - Token mint

    /// POSTs to the `whisper-livekit-token` Edge Function which signs a
    /// short-lived LiveKit JWT using the project's LIVEKIT_API_KEY /
    /// LIVEKIT_API_SECRET. The room name is the shared call id; the
    /// identity is the user's id (kept opaque to the recipient).
    private func mintToken(roomName: String, identity: String) async -> String? {
        let baseURL = WhisperBillingBackend.url
        guard let url = URL(string: "\(baseURL)/livekit/token") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Attach the Supabase auth token so the backend can verify identity.
        if let session = try? await SupabaseService.shared.client.auth.session {
            req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "room": roomName,
            "identity": identity
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("[Whisper] LiveKit token HTTP \(http.statusCode)")
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String, !token.isEmpty
            else { return nil }
            return token
        } catch {
            print("[Whisper] LiveKit token fetch failed: \(error)")
            return nil
        }
    }

    // MARK: - Audio session

    private func configureAudioSession(video: Bool) {
        guard !didConfigureAudio else { return }
        didConfigureAudio = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: video ? .videoChat : .voiceChat,
                options: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            // Non-fatal — LiveKit's internal audio engine will manage routing.
        }
    }

    private func releaseAudioSession() {
        guard didConfigureAudio else { return }
        didConfigureAudio = false
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

// MARK: - RoomDelegate

extension WhisperLiveKitService: RoomDelegate {
    nonisolated func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from _: ConnectionState) {
        Task { @MainActor in
            self.onConnectionStateChanged?(connectionState)
            switch connectionState {
            case .disconnected:
                // Only treat as failure if we still expected to be in a room.
                if self.currentRoomName != nil {
                    self.onConnectionFailed?()
                }
            default:
                break
            }
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in
            self.onRemoteParticipantPresenceChanged?(true)
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in
            self.onRemoteParticipantPresenceChanged?(false)
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        guard let track = publication.track as? VideoTrack else { return }
        Task { @MainActor in
            self.remoteVideoTrack = track
            self.onRemoteVideoTrackChanged?(track)
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        guard publication.track is VideoTrack else { return }
        Task { @MainActor in
            self.remoteVideoTrack = nil
            self.onRemoteVideoTrackChanged?(nil)
        }
    }
}
