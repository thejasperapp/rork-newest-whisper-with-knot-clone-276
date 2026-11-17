import AVFoundation
import Network
import ReplayKit
import UIKit
import WebRTC
import Supabase
import Auth

/// Pushes ReplayKit screen frames into a WebRTC video source. Runs on the
/// ReplayKit capture queue — deliberately `nonisolated` and `@unchecked
/// Sendable` so frames flow without hopping to the main actor.
nonisolated private final class WhisperScreenFrameCapturer: RTCVideoCapturer, @unchecked Sendable {
    func push(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let timeStampNs = Int64(seconds * 1_000_000_000)
        let rtcBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let frame = RTCVideoFrame(buffer: rtcBuffer, rotation: ._0, timeStampNs: timeStampNs)
        delegate?.capturer(self, didCapture: frame)
    }
}

/// Mesh WebRTC live room transport for iOS — no LiveKit server needed.
///
/// Signaling runs over Supabase Realtime broadcast channels. ICE servers
/// (STUN/TURN) come from the Rork toolkit endpoint. Media flows peer-to-peer
/// via RTCPeerConnection.
///
/// Topology: selective mesh.
/// - Speakers connect to all other peers and publish audio + video.
/// - Listeners connect only to speakers and receive media.
/// - When a listener is promoted to speaker, new connections are created
///   and existing ones are renegotiated to carry the new media tracks.
@MainActor
final class WhisperLiveRTCService: NSObject {
    static let shared = WhisperLiveRTCService()

    // ─── Callbacks ───────────────────────────────────────────────────────────

    var onConnectionStateChanged: ((Bool) -> Void)?
    var onConnectionFailed: (() -> Void)?
    /// Called when the user denied camera or microphone access — the UI
    /// should show an alert directing them to Settings (mirrors the web's
    /// getUserMedia rejection flow).
    var onPermissionDenied: (() -> Void)?
    /// Called when a specific peer's video track arrives or is removed.
    var onRemoteVideoTrackForPeer: ((String, RTCVideoTrack?) -> Void)?
    var onParticipantsChanged: (() -> Void)?
    /// Called with an emoji whenever anyone in the room sends a floating
    /// reaction (including yourself, locally, for zero-latency feedback).
    var onReaction: ((String) -> Void)?
    /// App-level events (client presenting, shared Jasper answers, deck
    /// walkthroughs, …) that ride the same signaling channel as WebRTC —
    /// shared with the web client. Delivers (event, data, fromPeerId).
    var onAppEvent: ((String, [String: Any], String) -> Void)?

    // ─── State ───────────────────────────────────────────────────────────────

    private(set) var localVideoTrack: RTCVideoTrack?
    /// Remote video tracks keyed by peerId — supports multiple simultaneous speakers.
    private(set) var remoteVideoTracks: [String: RTCVideoTrack] = [:]
    private(set) var micOn: Bool = false
    private(set) var cameraOn: Bool = false
    private(set) var connected: Bool = false {
        didSet { WhisperCameraCallMonitor.shared.setAppMediaInUse(isInUse) }
    }
    /// True while my video track carries the screen instead of the camera.
    private(set) var isScreenSharing: Bool = false
    /// Remote peers currently sharing their screen — their tile gets the
    /// large slot in the split layout.
    private(set) var screenSharingPeerIds: Set<String> = []

    private var peerConnections: [String: RTCPeerConnection] = [:]
    private var knownPeers: [String: KnownPeer] = [:]
    private var retiredPeerIDs: Set<String> = []
    /// Track which peerId each PC delegate corresponds to.
    private var peerConnectionIds: [ObjectIdentifier: String] = [:]
    /// ICE candidates that arrived before the PC or remote description was ready.
    private var pendingIceCandidates: [String: [RTCIceCandidate]] = [:]
    /// Per-peer mic state from mic-toggle / track-update signals — mirrors the
    /// web client so mute badges reflect reality instead of hardcoded true.
    private var peerMicOn: [String: Bool] = [:]
    /// Per-peer camera state from track-update signals. A disabled remote
    /// camera keeps its WebRTC track alive but sends black frames — without
    /// this flag, camera-off peers rendered as black rectangles instead of
    /// their avatar backdrop (self already handled it locally).
    private var peerVideoOn: [String: Bool] = [:]
    /// Reconnect grace: peers in transient `.disconnected` get a timer before
    /// removal so brief network blips don't kick them from the room.
    private var disconnectGraceTasks: [String: Task<Void, Never>] = [:]
    /// Serial signaling queue — processes messages one at a time in order.
    private var signalContinuation: AsyncStream<[String: Any]>.Continuation?
    private var myPeerId: String = ""
    /// Stable local peerId for UI identification (e.g. placing the self-view in PIP).
    var localPeerId: String { myPeerId }
    private var userId: String = ""
    private var name: String = ""
    private var roomId: String = ""
    private var isSpeakerRole: Bool = false
    private var iceServers: [RTCIceServer] = []
    /// TURN credentials are short-lived — track freshness so ICE restarts
    /// and rebuilds always gather with valid relay credentials.
    private var iceFetchedAt: Date = .distantPast
    private var iceTtlSeconds: TimeInterval = 300
    /// OS-level network path watcher — restarts ICE the moment wifi/cellular
    /// switches instead of waiting for WebRTC's failure timers.
    private var pathMonitor: NWPathMonitor?
    private var lastPathKey: String = ""
    private var lastNetworkRestartAt: Date = .distantPast
    /// Factory MUST be built with explicit video encoder/decoder factories —
    /// the bare `RTCPeerConnectionFactory()` init ships with NO video codecs,
    /// so offers carry an empty video m-line, negotiation fails, and neither
    /// audio nor video ever flows. This mirrors what the browser gives the
    /// web client for free.
    private let factory: RTCPeerConnectionFactory = {
        _ = RTCInitializeSSL()
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
    }()
    private var localStream: RTCMediaStream?
    private var audioTrack: RTCAudioTrack?
    private var videoTrack: RTCVideoTrack?
    private var videoCapturer: RTCCameraVideoCapturer?
    private var videoSource: RTCVideoSource?
    private var screenCapturer: WhisperScreenFrameCapturer?
    private var cameraPosition: AVCaptureDevice.Position = .front
    private var didConfigureAudio = false
    /// Social calls opt into receiver-first; meetings retain their speaker default.
    private var defaultsToSpeaker: Bool = true
    private var explicitReceiverSelection: Bool = false
    var onAudioRouteChanged: (() -> Void)?

    var actualAudioRoute: WhisperAudioRoute {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        if outputs.contains(where: { $0.portType == .builtInSpeaker }) { return .speaker }
        if outputs.contains(where: { WhisperAudioRoute.bluetoothPortTypes.contains($0.portType) }) { return .bluetooth }
        return .receiver
    }

    private var routingOptions: AVAudioSession.CategoryOptions {
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP]
        if audioRoute == .speaker { options.insert(.defaultToSpeaker) }
        return options
    }

    private var routingMode: AVAudioSession.Mode {
        // videoChat implicitly enables speaker. Camera capture is independent
        // of audio mode, so receiver-first calls use voiceChat even with video.
        defaultsToSpeaker && audioRoute == .speaker && audioSessionVideoMode ? .videoChat : .voiceChat
    }
    /// The output route the user chose for this call (speaker / ear
    /// receiver / Bluetooth). Route enforcement re-asserts it whenever
    /// WebRTC's audio unit re-activates the session.
    private(set) var audioRoute: WhisperAudioRoute = .speaker
    private var routeChangeObserver: NSObjectProtocol?
    /// Lifecycle watchers that rebuild WebRTC's audio unit after iOS tears
    /// it down (backgrounding, Siri, phone calls, lock screen, PiP trips).
    /// Without this, audio IO restarts on a stale sample rate and the
    /// speaker sounds garbled to everyone after coming back.
    private var audioRecoveryObservers: [NSObjectProtocol] = []
    /// Mode the session was configured with — re-asserted on recovery.
    private var audioSessionVideoMode = false
    /// Debounce so stacked notifications don't thrash the audio unit.
    private var lastAudioRecoveryAt = Date.distantPast
    private var realtimeChannel: RealtimeChannelV2?
    /// CRITICAL: `onBroadcast` returns a subscription token that CANCELS the
    /// observation when deallocated. It must be retained for the lifetime of
    /// the channel — discarding it leaves this client able to SEND but never
    /// RECEIVE (peers see us join while our own room stays empty).
    private var broadcastSubscription: RealtimeSubscription?
    /// Watches channel status — Supabase silently re-joins after socket
    /// reconnects and anything broadcast while offline is gone forever, so
    /// presence is re-announced on every re-subscribe (web-client parity).
    private var channelStatusTask: Task<Void, Never>?
    private var signalingTask: Task<Void, Never>?
    /// Throttled remote-audio sampling drives the active-speaker focus frame.
    private var speakerMonitorTask: Task<Void, Never>?
    private var speakingUntil: [String: Date] = [:]
    private var speakingPeerIDs: Set<String> = []

    struct KnownPeer {
        var peerId: String
        var userId: String
        var name: String
        var isSpeaker: Bool
    }

    /// Participant info for the UI.
    struct ParticipantInfo: Equatable {
        let peerId: String
        let userId: String
        let name: String
        let isSpeaker: Bool
        let hasVideo: Bool
        let hasAudio: Bool
        let micOn: Bool
        let isScreenSharing: Bool
        /// True briefly after WebRTC reports meaningful inbound audio energy.
        let isSpeaking: Bool
    }

    /// Current participant list (including self) for the UI.
    var participants: [ParticipantInfo] {
        var list: [ParticipantInfo] = []
        for (peerId, known) in knownPeers.sorted(by: { $0.key < $1.key }) {
            // Video shows only when a track exists AND the peer's camera is
            // actually on (or they're screen sharing) — disabled tracks
            // stream black frames.
            let camOn = peerVideoOn[peerId] ?? true
            let hasVideo = remoteVideoTracks[peerId] != nil
                && (camOn || screenSharingPeerIds.contains(peerId))
            list.append(ParticipantInfo(
                peerId: peerId,
                userId: known.userId,
                name: known.name,
                isSpeaker: known.isSpeaker,
                hasVideo: hasVideo,
                hasAudio: peerConnections[peerId] != nil,
                micOn: peerMicOn[peerId] ?? true,
                isScreenSharing: screenSharingPeerIds.contains(peerId),
                isSpeaking: speakingPeerIDs.contains(peerId)
            ))
        }
        // Add self
        list.insert(ParticipantInfo(
            peerId: myPeerId,
            userId: userId,
            name: "You",
            isSpeaker: isSpeakerRole,
            hasVideo: cameraOn || isScreenSharing,
            hasAudio: micOn,
            micOn: micOn,
            isScreenSharing: isScreenSharing,
            isSpeaking: false
        ), at: 0)
        return list
    }

    private override init() { super.init() }

    // ─── Public API ──────────────────────────────────────────────────────────

    private var isJoining: Bool = false {
        didSet { WhisperCameraCallMonitor.shared.setAppMediaInUse(isInUse) }
    }
    private var isLeaving: Bool = false {
        didSet { WhisperCameraCallMonitor.shared.setAppMediaInUse(isInUse) }
    }
    var isInUse: Bool { isJoining || isLeaving || connected }

    func join(roomId: String, userId: String, name: String, asListener: Bool, withVideo: Bool = true, initiallyMuted: Bool = false, defaultToSpeaker: Bool = true, shouldContinue: () -> Bool = { true }) async {
        guard !isInUse, shouldContinue(), !Task.isCancelled else { return }
        isJoining = true
        defer { isJoining = false }
        self.roomId = roomId
        self.userId = userId
        self.name = name
        self.isSpeakerRole = !asListener
        self.retiredPeerIDs.removeAll()
        self.myPeerId = UUID().uuidString
        self.defaultsToSpeaker = defaultToSpeaker
        self.explicitReceiverSelection = false
        self.audioRoute = actualAudioRoute == .bluetooth ? .bluetooth : (defaultToSpeaker ? .speaker : .receiver)
        startRouteEnforcement()

        // 1. Fetch ICE servers from the Rork toolkit.
        await fetchIceServers()
        guard shouldContinue(), !Task.isCancelled else { return }

        // 2. Acquire media BEFORE announcing the join — mirrors the web
        //    client, which runs prepareLocalMedia() on the Join tap. Every
        //    offer/answer we negotiate then carries our tracks from the very
        //    first SDP round. The old announce-first flow answered the web's
        //    offer with ZERO tracks (media still behind the permission
        //    dialog); when the web side was the designated offerer (smaller
        //    peerId) nobody ever renegotiated, so iOS audio/video never
        //    reached the room even though the roster showed us present —
        //    the exact "in the meeting but no voice/video" bug.
        var mediaReady = false
        if !asListener {
            mediaReady = await requestMediaPermissions(needsVideo: withVideo)
            guard shouldContinue(), !Task.isCancelled else { return }
            if mediaReady {
                configureAudioSession(video: withVideo)
                createLocalMediaStream(captureVideo: withVideo, initiallyMuted: initiallyMuted)
                micOn = !initiallyMuted
                cameraOn = withVideo
            }
        }

        // 3. Set up the signaling channel. Even when media failed
        //    (permission denied, no camera on simulator), the peer still
        //    joins the channel so others see them in the room — recvonly
        //    transceivers keep the SDP valid without local tracks.
        let (stream, continuation) = AsyncStream.makeStream(of: [String: Any].self)
        signalContinuation = continuation
        signalingTask = Task { [weak self] in
            for await msg in stream {
                guard let self else { return }
                await self.handleSignal(msg)
            }
        }

        let client = SupabaseService.shared.client
        let channel = client.realtimeV2.channel("live-signal:\(roomId)") {
            $0.broadcast.receiveOwnBroadcasts = false
        }
        realtimeChannel = channel

        // Register broadcast callback before subscribing. The returned token
        // MUST be retained: it deregisters the callback the moment it is
        // deallocated, which makes this client deaf to every signal — the
        // "web sees iOS join, iOS sees an empty room" bug.
        broadcastSubscription = channel.onBroadcast(event: "signal") { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleBroadcastMessage(message)
            }
        }

        await channel.subscribe()
        guard shouldContinue(), !Task.isCancelled else { await leave(); return }
        print("[WhisperLiveRTC] signaling channel status: \(channel.status)")

        // Supabase auto-rejoins the channel after network blips; signaling
        // sent while we were offline is gone forever. Re-announce presence on
        // every re-subscribe so peers who missed our join still discover us —
        // parity with the web client's re-SUBSCRIBED handler.
        channelStatusTask = Task { [weak self, weak channel] in
            guard let channel else { return }
            var sawFirstSubscribe = false
            for await status in channel.statusChange {
                if Task.isCancelled { return }
                guard status == .subscribed else { continue }
                if !sawFirstSubscribe {
                    sawFirstSubscribe = true
                    continue
                }
                guard let self, self.connected else { continue }
                print("[WhisperLiveRTC] channel re-subscribed — re-announcing presence")
                await self.reannouncePresence()
            }
        }

        // 4. Announce join so existing peers can create offers.
        await broadcast([
            "type": "join",
            "peerId": myPeerId,
            "userId": userId,
            "name": name,
            "isSpeaker": isSpeakerRole
        ])

        guard shouldContinue(), !Task.isCancelled else { await leave(); return }

        // Audio-only joins (DM voice calls) keep a video track for later
        // upgrades but the camera stays off — tell the room immediately so
        // remote tiles render the avatar backdrop instead of black frames
        // (peers default unknown camera state to ON).
        if isSpeakerRole && mediaReady && (!cameraOn || !micOn) {
            await broadcast([
                "type": "track-update",
                "from": myPeerId,
                "hasAudio": micOn,
                "hasVideo": cameraOn || isScreenSharing
            ])
        }

        guard shouldContinue(), !Task.isCancelled, !isLeaving, realtimeChannel === channel else { return }
        connected = true
        onConnectionStateChanged?(true)
        startSpeakerMonitoring()
        startPathMonitoring()
        applyAudioRoute()

        if !asListener {
            if mediaReady {
                onParticipantsChanged?()
                onRemoteVideoTrackForPeer?(myPeerId, localVideoTrack)
            } else {
                micOn = false
                cameraOn = false
                onPermissionDenied?()
            }
        } else {
            // Listeners still need the audio session for playback.
            configureAudioSession(video: false)
        }
    }

    /// Publish freshly acquired local tracks into EVERY existing peer
    /// connection — reusing idle transceivers where possible — then
    /// renegotiate. Either side may renegotiate: glare is resolved by the
    /// rollback rule in handleOffer (identical to the web client's
    /// publishTrack convention). This must never be gated on peerId order —
    /// that gate is exactly what stranded iOS media in the announce-first
    /// era.
    private func publishLocalTracksToAllPeers() async {
        for (peerId, pc) in peerConnections {
            var needsOffer = false
            if let audio = audioTrack {
                needsOffer = attach(track: audio, to: pc) || needsOffer
            }
            if let video = videoTrack {
                needsOffer = attach(track: video, to: pc) || needsOffer
            }
            if needsOffer && pc.signalingState == .stable {
                await createOffer(peerId: peerId)
            }
        }
        await broadcast([
            "type": "track-update",
            "from": myPeerId,
            "hasAudio": micOn,
            "hasVideo": cameraOn || isScreenSharing
        ])
    }

    /// Wire a local track into a peer connection. Reuses the live sender when
    /// one exists; otherwise addTrack takes over — per the WebRTC spec it
    /// fills an idle transceiver of the same kind (flipping recvonly →
    /// sendrecv) before creating a new m-line. Returns true when the SDP
    /// changed and renegotiation is required.
    private func attach(track: RTCMediaStreamTrack, to pc: RTCPeerConnection) -> Bool {
        if let sender = pc.senders.first(where: { $0.track?.kind == track.kind }) {
            if sender.track !== track { sender.track = track }
            return false
        }
        _ = pc.add(track, streamIds: [track.kind])
        return true
    }

    func setMuted(_ muted: Bool) {
        micOn = !muted
        audioTrack?.isEnabled = !muted
        Task {
            await broadcast([
                "type": "mic-toggle",
                "from": myPeerId,
                "isOn": !muted
            ])
        }
        onParticipantsChanged?()
    }

    func setCameraEnabled(_ enabled: Bool) {
        cameraOn = enabled
        if enabled {
            startCameraCapture()
        } else {
            if let capturer = videoCapturer {
                Task { await capturer.stopCapture() }
            }
        }
        videoTrack?.isEnabled = enabled
        Task {
            await broadcast([
                "type": "track-update",
                "from": myPeerId,
                "hasAudio": micOn,
                "hasVideo": enabled
            ])
        }
        onParticipantsChanged?()
    }

    func becomeSpeaker() async {
        guard !isSpeakerRole else { return }
        isSpeakerRole = true

        // Same permission gate as join — promotion to speaker needs cam + mic.
        let granted = await requestMediaPermissions()
        guard granted else {
            micOn = false
            cameraOn = false
            onPermissionDenied?()
            return
        }

        // Reconfigure audio session for video chat mode now that we publish.
        configureAudioSession(video: true)
        createLocalMediaStream()
        micOn = true
        cameraOn = true
        onParticipantsChanged?()
        onRemoteVideoTrackForPeer?(myPeerId, localVideoTrack)

        // Publish tracks into existing PCs — either side may renegotiate;
        // the glare rollback in handleOffer keeps simultaneous offers safe.
        await publishLocalTracksToAllPeers()

        // Broadcast promotion so other peers can create new PCs with us.
        await broadcast([
            "type": "became-speaker",
            "peerId": myPeerId,
            "userId": userId,
            "name": name
        ])

        // Create offers to known peers we don't have a PC with yet.
        for (peerId, known) in knownPeers {
            if peerConnections[peerId] != nil { continue }
            if known.isSpeaker && myPeerId > peerId { continue }
            _ = createPeerConnection(peerId: peerId)
            if myPeerId < peerId {
                await createOffer(peerId: peerId)
            }
        }

        onParticipantsChanged?()
    }

    /// Flip between the front and back camera (Instagram-style).
    /// The running capture session MUST be stopped before starting a new one
    /// with a different device — restarting while active crashes inside the
    /// capturer's session queue.
    func switchCamera() {
        cameraPosition = cameraPosition == .front ? .back : .front
        guard cameraOn, !isScreenSharing else { return }
        guard let capturer = videoCapturer else { return }
        Task {
            await capturer.stopCapture()
            startCameraCapture()
        }
    }

    /// True when the local camera should be mirrored in the preview tile.
    var isFrontCamera: Bool { cameraPosition == .front }

    /// Send a floating emoji reaction to everyone in the room.
    func sendReaction(_ emoji: String) {
        onReaction?(emoji)
        Task {
            await broadcast(["type": "reaction", "from": myPeerId, "emoji": emoji])
        }
    }

    /// Broadcast an app-level event (JSON-serializable data) to everyone in
    /// the room. Mirrors the web client's `sendAppEvent`, so payloads like
    /// "present-client" and "ember-share" work across iOS and web.
    func sendAppEvent(_ event: String, data: [String: Any]) {
        Task {
            await broadcast([
                "type": "app-event",
                "from": myPeerId,
                "event": event,
                "data": data,
            ])
        }
    }

    // ─── Screen share ────────────────────────────────────────────────────────

    /// Start sharing the app screen into the live via ReplayKit. The screen
    /// frames replace the camera feed on the existing video track so no
    /// renegotiation is needed — remote peers just see the screen.
    ///
    /// CRITICAL: Do NOT stop the camera capturer until AFTER startCapture
    /// succeeds. Stopping first then failing leaves the user with no video
    /// at all (the "camera looks funky" bug). The system shows a permission
    /// prompt for screen recording — if the user denies or dismisses it,
    /// startCapture throws and we cleanly restore the camera.
    @discardableResult
    func startScreenShare() async -> Bool {
        guard isSpeakerRole, let source = videoSource, !isScreenSharing else { return false }
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            print("[WhisperLiveRTC] RPScreenRecorder not available")
            return false
        }

        let forwarder = WhisperScreenFrameCapturer(delegate: source)
        recorder.isMicrophoneEnabled = false

        do {
            try await recorder.startCapture { sampleBuffer, bufferType, error in
                guard error == nil else { return }
                guard bufferType == .video else { return }
                forwarder.push(sampleBuffer)
            }
        } catch {
            print("[WhisperLiveRTC] Screen share startCapture failed: \(error)")
            return false
        }

        // Screen share started successfully — NOW stop the camera and swap.
        if let capturer = videoCapturer {
            await capturer.stopCapture()
        }
        screenCapturer = forwarder
        isScreenSharing = true
        videoTrack?.isEnabled = true
        await broadcast(["type": "screen-share", "from": myPeerId, "isOn": true])
        onParticipantsChanged?()
        return true
    }

    /// Stop screen sharing and hand the video track back to the camera.
    func stopScreenShare() async {
        guard isScreenSharing else { return }
        isScreenSharing = false
        screenCapturer = nil
        let recorder = RPScreenRecorder.shared()
        if recorder.isRecording {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                recorder.stopCapture { _ in cont.resume() }
            }
        }
        if cameraOn { startCameraCapture() }
        videoTrack?.isEnabled = cameraOn
        await broadcast(["type": "screen-share", "from": myPeerId, "isOn": false])
        onParticipantsChanged?()
    }

    /// Silence media synchronously; transcript uploads or signaling may be slow.
    func suspendMediaForExit() {
        audioTrack?.isEnabled = false
        videoTrack?.isEnabled = false
        for connection in peerConnections.values {
            for receiver in connection.receivers { receiver.track?.isEnabled = false }
        }
    }

    func leave() async {
        guard !isLeaving else { return }
        isLeaving = true
        defer { isLeaving = false }
        suspendMediaForExit()
        for task in disconnectGraceTasks.values { task.cancel() }
        disconnectGraceTasks.removeAll()
        peerMicOn.removeAll()
        peerVideoOn.removeAll()
        stopSpeakerMonitoring()
        await broadcast(["type": "leave", "peerId": myPeerId])

        if isScreenSharing {
            isScreenSharing = false
            screenCapturer = nil
            let recorder = RPScreenRecorder.shared()
            if recorder.isRecording {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    recorder.stopCapture { _ in cont.resume() }
                }
            }
        }
        screenSharingPeerIds.removeAll()

        // Stop the serial signaling queue.
        signalContinuation?.finish()
        signalContinuation = nil
        signalingTask?.cancel()
        signalingTask = nil
        pendingIceCandidates.removeAll()

        for pc in peerConnections.values {
            pc.close()
        }
        peerConnections.removeAll()
        peerConnectionIds.removeAll()
        knownPeers.removeAll()

        if let capturer = videoCapturer {
            await capturer.stopCapture()
        }
        videoCapturer = nil
        localVideoTrack = nil
        remoteVideoTracks.removeAll()
        audioTrack = nil
        videoTrack = nil
        localStream = nil

        channelStatusTask?.cancel()
        channelStatusTask = nil
        broadcastSubscription?.cancel()
        broadcastSubscription = nil
        if let channel = realtimeChannel {
            Task { await channel.unsubscribe() }
            realtimeChannel = nil
        }

        stopPathMonitoring()
        stopRouteEnforcement()
        defaultsToSpeaker = true
        explicitReceiverSelection = false
        audioRoute = .speaker
        connected = false
        micOn = false
        cameraOn = false
        onConnectionStateChanged?(false)
        releaseAudioSession()
    }

    // ─── Speaker routing ───────────────────────────────────────────

    /// User-facing speaker toggle (audio calls). Kept for existing call
    /// sites — maps onto the richer three-way routing below.
    func setSpeakerPreferred(_ on: Bool) {
        setAudioRoute(on ? .speaker : .receiver)
    }

    /// Full three-way output routing: speaker, ear receiver, or a connected
    /// Bluetooth device. The choice sticks for the rest of the call; route
    /// enforcement keeps WebRTC's audio unit from silently undoing it.
    func setAudioRoute(_ route: WhisperAudioRoute) {
        audioRoute = route
        explicitReceiverSelection = route == .receiver
        applyAudioRoute()
    }

    private func applyAudioRoute() {
        let rtcSession = RTCAudioSession.sharedInstance()
        updateRoutingTemplate()
        rtcSession.lockForConfiguration()
        do {
            try rtcSession.setCategory(.playAndRecord, mode: routingMode, options: routingOptions)
            try rtcSession.overrideOutputAudioPort(audioRoute == .speaker ? .speaker : .none)
        } catch {
            print("[WhisperLiveRTC] audio route override failed: \(error)")
        }
        rtcSession.unlockForConfiguration()
        // The preferred INPUT steers the rest of the route once the speaker
        // override is lifted: built-in mic → ear receiver, Bluetooth mic →
        // the headset (HFP pairs input + output).
        let session = AVAudioSession.sharedInstance()
        switch audioRoute {
        case .speaker:
            // Clear any Bluetooth input preference so the override sticks.
            try? session.setPreferredInput(nil)
        case .receiver:
            if explicitReceiverSelection, let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtIn)
            } else {
                try? session.setPreferredInput(nil)
            }
        case .bluetooth:
            if let bluetooth = WhisperAudioRoute.bluetoothInput() {
                try? session.setPreferredInput(bluetooth)
            }
        }
        onAudioRouteChanged?()
    }

    /// WebRTC's audio unit re-activates the session mid-call (first peer
    /// connect, ICE restarts) which silently re-routes audio to the ear
    /// receiver on some devices. Watch route changes and shove the route
    /// back to what the user chose — but never fight wired headphones or
    /// CarPlay they plugged in themselves.
    private func updateRoutingTemplate() {
        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.categoryOptions = routingOptions
        configuration.mode = routingMode.rawValue
        RTCAudioSessionConfiguration.setWebRTC(configuration)
    }

    private func startRouteEnforcement() {
        stopRouteEnforcement()
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let previous = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let hadAccessory = previous?.outputs.contains { $0.portType != .builtInReceiver && $0.portType != .builtInSpeaker } ?? false
            Task { @MainActor in
                WhisperLiveRTCService.shared.handleAudioRouteChange(reason: reason, hadAccessory: hadAccessory)
            }
        }
    }

    private func stopRouteEnforcement() {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
    }

    private func handleAudioRouteChange(reason: UInt, hadAccessory: Bool) {
        guard connected || isJoining else { return }
        defer { onAudioRouteChanged?() }
        let reason = AVAudioSession.RouteChangeReason(rawValue: reason)
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let hasAccessory = outputs.contains { $0.portType != .builtInReceiver && $0.portType != .builtInSpeaker }
        if hasAccessory || reason == .override || reason == .newDeviceAvailable {
            let observed = actualAudioRoute
            // A matching output acknowledges our own override; preserve the
            // explicit iPhone input choice through subsequent recovery.
            guard observed != audioRoute else { return }
            audioRoute = observed
            explicitReceiverSelection = observed == .receiver && !hasAccessory
            updateRoutingTemplate()
            if didConfigureAudio, !hasAccessory { applyAudioRoute() }
            return
        }
        if reason == .oldDeviceUnavailable {
            guard hadAccessory, audioRoute != .speaker, !explicitReceiverSelection else { return }
            audioRoute = defaultsToSpeaker ? .speaker : .receiver
            explicitReceiverSelection = false
            updateRoutingTemplate()
            if didConfigureAudio { applyAudioRoute() }
        } else if reason == .categoryChange {
            if audioRoute == .speaker, actualAudioRoute == .receiver {
                applyAudioRoute()
            } else if audioRoute == .receiver, actualAudioRoute == .speaker,
                      UIDevice.current.userInterfaceIdiom == .phone {
                applyAudioRoute()
            }
        }
    }

    // ─── Network path monitoring ─────────────────────────────────────────

    /// Watch OS-level network switches (wifi→cellular, VPN toggles). When the
    /// path changes we refresh TURN credentials and restart ICE on every pair
    /// immediately — WebRTC's own timers take seconds to notice a dead path.
    private func startPathMonitoring() {
        stopPathMonitoring()
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let key = path.availableInterfaces
                .map { "\($0.type)" }
                .sorted()
                .joined(separator: ",")
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let previous = self.lastPathKey
                self.lastPathKey = key
                guard satisfied, !previous.isEmpty, previous != key else { return }
                await self.handleNetworkSwitch(from: previous, to: key)
            }
        }
        monitor.start(queue: DispatchQueue(label: "whisper.rtc.path"))
    }

    private func stopPathMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
        lastPathKey = ""
    }

    private func handleNetworkSwitch(from previous: String, to current: String) async {
        guard connected else { return }
        guard Date().timeIntervalSince(lastNetworkRestartAt) >= 4 else { return }
        lastNetworkRestartAt = Date()
        print("[WhisperLiveRTC] network path changed (\(previous) → \(current)) — restarting ICE on \(peerConnections.count) pair(s)")
        await refreshIceServersIfStale(maxAge: 0)
        for peerId in Array(peerConnections.keys) {
            let theirIsSpeaker = knownPeers[peerId]?.isSpeaker ?? true
            let iAmOfferer = (isSpeakerRole && theirIsSpeaker) ? (myPeerId < peerId) : isSpeakerRole
            if iAmOfferer {
                await createOffer(peerId: peerId, iceRestart: true)
            } else {
                // The offerer must mint the ICE-restart offer — ask for one.
                await broadcast(["type": "reneg", "from": myPeerId, "to": peerId])
            }
        }
    }

    // ─── ICE servers ─────────────────────────────────────────────────────────

    private func fetchIceServers() async {
        let toolkitUrl = Config.allValues["EXPO_PUBLIC_TOOLKIT_URL"] ?? ""
        let secretKey = Config.allValues["EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY"] ?? ""
        guard !toolkitUrl.isEmpty, !secretKey.isEmpty,
              let url = URL(string: "\(toolkitUrl)/v2/webrtc/ice-servers") else {
            applyStunOnlyFallback()
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Bearer \(secretKey)", forHTTPHeaderField: "Authorization")

        // Short-lived TURN creds are critical for NAT traversal — retry once
        // with a hard timeout before degrading to STUN-only (which can't relay).
        for attempt in 1...2 {
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if let httpResp = response as? HTTPURLResponse {
                    print("[WhisperLiveRTC] ICE servers HTTP \(httpResp.statusCode) (attempt \(attempt))")
                }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let servers = json["iceServers"] as? [[String: Any]] {
                    let parsed: [RTCIceServer] = servers.compactMap { server in
                        guard let urls = server["urls"] as? [String] else { return nil }
                        let username = server["username"] as? String ?? ""
                        let credential = server["credential"] as? String ?? ""
                        return RTCIceServer(
                            urlStrings: urls,
                            username: username,
                            credential: credential
                        )
                    }
                    if !parsed.isEmpty {
                        iceServers = parsed
                        if let ttl = json["ttlSeconds"] as? Double, ttl > 0 {
                            iceTtlSeconds = min(max(ttl, 60), 1800)
                        } else {
                            iceTtlSeconds = 300
                        }
                        iceFetchedAt = Date()
                        print("[WhisperLiveRTC] Got \(iceServers.count) ICE servers, ttl \(Int(iceTtlSeconds))s")
                        return
                    }
                }
            } catch {
                print("[WhisperLiveRTC] ICE fetch attempt \(attempt) failed: \(error)")
            }
            if attempt == 1 {
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
        applyStunOnlyFallback()
    }

    /// STUN-only fallback with a SHORT ttl — the refresh logic retries the
    /// toolkit soon and upgrades live connections back to TURN. Keeps any
    /// previous TURN list (its creds may still be valid) over downgrading.
    private func applyStunOnlyFallback() {
        if iceServers.isEmpty {
            iceServers = [RTCIceServer(urlStrings: ["stun:stun.cloudflare.com:3478"])]
        }
        iceTtlSeconds = 45
        iceFetchedAt = Date()
        print("[WhisperLiveRTC] Using STUN-only/previous ICE list — retrying toolkit soon")
    }

    /// Refresh short-lived TURN credentials and push them into every LIVE
    /// connection. Without setConfiguration, existing peer connections keep
    /// the credentials they were created with — an ICE restart minutes into
    /// a call would gather with EXPIRED relay creds and never reconnect on
    /// hostile networks.
    private func refreshIceServersIfStale(maxAge: TimeInterval? = nil) async {
        let limit = maxAge ?? min(iceTtlSeconds * 0.75, 600)
        guard Date().timeIntervalSince(iceFetchedAt) >= limit else { return }
        await fetchIceServers()
        for pc in peerConnections.values {
            _ = pc.setConfiguration(makeRTCConfiguration())
        }
    }

    // ─── Local media ─────────────────────────────────────────────────────────

    private func createLocalMediaStream(captureVideo: Bool = true, initiallyMuted: Bool = false) {
        let stream = factory.mediaStream(withStreamId: UUID().uuidString)
        localStream = stream

        // Audio track
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = factory.audioSource(with: audioConstraints)
        let audio = factory.audioTrack(with: audioSource, trackId: "audio-\(myPeerId)")
        audio.isEnabled = !initiallyMuted
        audioTrack = audio
        stream.addAudioTrack(audio)

        // Video track — camera frames route through the effects engine
        // (background blur / virtual backdrops) before reaching the source.
        // With effects off it's a zero-copy passthrough.
        let videoSource = factory.videoSource()
        self.videoSource = videoSource
        WhisperVideoEffects.shared.attach(to: videoSource)
        let capturer = RTCCameraVideoCapturer(delegate: WhisperVideoEffects.shared)
        videoCapturer = capturer
        let video = factory.videoTrack(with: videoSource, trackId: "video-\(myPeerId)")
        video.isEnabled = captureVideo
        videoTrack = video
        localVideoTrack = video
        stream.addVideoTrack(video)

        if captureVideo {
            startCameraCapture()
        }
    }

    /// Request camera + microphone access, prompting the user when the
    /// status is not yet determined. Video surfaces need BOTH; audio-only
    /// calls need just the microphone (no camera prompt at all).
    private func requestMediaPermissions(needsVideo: Bool = true) async -> Bool {
        var micOK: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micOK = true
        case .notDetermined:
            micOK = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            micOK = false
        }
        guard needsVideo else { return micOK }

        var cameraOK: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraOK = true
        case .notDetermined:
            cameraOK = await AVCaptureDevice.requestAccess(for: .video)
        default:
            cameraOK = false
        }

        return cameraOK && micOK
    }

    private func startCameraCapture() {
        guard let capturer = videoCapturer else { return }
        // Never start a capture session without authorization — the session
        // silently produces black frames instead of prompting.
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }

        // Include .external so the cloud simulator's injected webcam is found.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        let camera = discovery.devices.first(where: { $0.position == cameraPosition })
            ?? discovery.devices.first
        guard let camera else {
            print("[WhisperLiveRTC] No camera device available")
            return
        }

        // Pick the format closest to 720p — blindly taking formats.last can
        // select a format whose max frame rate is below the requested fps,
        // which throws NSInvalidArgumentException inside the capturer (the
        // camera-flip crash). Clamp fps to what the chosen format supports.
        let formats = RTCCameraVideoCapturer.supportedFormats(for: camera)
        guard !formats.isEmpty else { return }
        let targetPixels = 1280 * 720
        let format = formats.min(by: { a, b in
            let dimsA = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let dimsB = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            let diffA = abs(Int(dimsA.width) * Int(dimsA.height) - targetPixels)
            let diffB = abs(Int(dimsB.width) * Int(dimsB.height) - targetPixels)
            return diffA < diffB
        }) ?? formats[0]
        let maxSupportedFps = format.videoSupportedFrameRateRanges
            .map { $0.maxFrameRate }
            .max() ?? 30
        let fps = max(1, Int(min(30, maxSupportedFps.rounded(.down))))

        capturer.startCapture(with: camera, format: format, fps: fps) { error in
            if let error = error {
                print("[WhisperLiveRTC] Camera capture error: \(error)")
            }
        }
    }

    // ─── Signaling ───────────────────────────────────────────────────────────

    /// Convert a `[String: Any]` dictionary to `[String: AnyJSON]` for Supabase broadcast.
    private func toJSON(_ dict: [String: Any]) -> [String: AnyJSON] {
        var result: [String: AnyJSON] = [:]
        for (key, value) in dict {
            result[key] = anyToJSON(value)
        }
        return result
    }

    private func anyToJSON(_ value: Any) -> AnyJSON {
        if let s = value as? String { return .string(s) }
        if let n = value as? NSNumber {
            // CFBoolean check FIRST — a bare `as? Bool` also matches NSNumber
            // 0/1 (JSONSerialization emits NSNumbers), which used to turn
            // numeric fields into booleans on the wire. Receivers' decoders
            // then dropped the WHOLE payload (creator cards never appeared).
            if CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            let type = String(cString: n.objCType)
            if type == "d" || type == "f" { return .double(n.doubleValue) }
            return .integer(n.intValue)
        }
        if let dict = value as? [String: Any] {
            var obj: [String: AnyJSON] = [:]
            for (k, v) in dict { obj[k] = anyToJSON(v) }
            return .object(obj)
        }
        // Arrays used to fall through to `.null`, silently deleting every
        // array field (top posts, photos, media URLs) from broadcasts.
        if let arr = value as? [Any] {
            return .array(arr.map { anyToJSON($0) })
        }
        return .null
    }

    /// Convert an `AnyJSON` value back to a plain `Any` for downstream handling.
    private func jsonToAny(_ json: AnyJSON) -> Any {
        switch json {
        case .null: return NSNull()
        case .bool(let b): return b
        case .integer(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .object(let obj):
            var dict: [String: Any] = [:]
            for (k, v) in obj { dict[k] = jsonToAny(v) }
            return dict
        case .array(let arr):
            return arr.map { jsonToAny($0) }
        }
    }

    private func broadcast(_ message: [String: Any]) async {
        guard let channel = realtimeChannel else { return }
        let jsonMessage = toJSON(message)
        await channel.broadcast(event: "signal", message: jsonMessage)
    }

    /// Handle incoming broadcast messages from Supabase Realtime.
    /// Enqueues the payload onto the serial signaling queue so messages
    /// are processed one at a time, in arrival order.
    private func handleBroadcastMessage(_ message: [String: AnyJSON]) {
        // Supabase wraps broadcast payloads in a "payload" key.
        let payload: [String: Any]
        if let p = message["payload"], case .object(let obj) = p {
            var dict: [String: Any] = [:]
            for (k, v) in obj { dict[k] = jsonToAny(v) }
            payload = dict
        } else {
            var dict: [String: Any] = [:]
            for (k, v) in message { dict[k] = jsonToAny(v) }
            payload = dict
        }
        signalContinuation?.yield(payload)
    }

    /// Re-broadcast presence — receivers treat duplicate joins idempotently.
    private func reannouncePresence() async {
        await broadcast([
            "type": "join",
            "peerId": myPeerId,
            "userId": userId,
            "name": name,
            "isSpeaker": isSpeakerRole
        ])
    }

    private func handleSignal(_ msg: [String: Any]) async {
        guard let type = msg["type"] as? String else { return }

        // Drop messages not addressed to me (to-field) or from myself.
        if let to = msg["to"] as? String, to != myPeerId { return }
        if let from = msg["from"] as? String, from == myPeerId { return }
        let senderID = (msg["from"] as? String) ?? (msg["peerId"] as? String) ?? ""
        guard !retiredPeerIDs.contains(senderID) else { return }

        if type != "ice" {
            let sender = (msg["from"] as? String) ?? (msg["peerId"] as? String) ?? "?"
            print("[WhisperLiveRTC] signal ← \(type) from \(sender.prefix(8))")
        }

        switch type {
        case "join":
            let peerId = msg["peerId"] as? String ?? ""
            let peerUserId = msg["userId"] as? String ?? ""
            let peerName = msg["name"] as? String ?? ""
            let peerIsSpeaker = msg["isSpeaker"] as? Bool ?? false
            guard !peerId.isEmpty, peerId != myPeerId else { return }

            evictStaleSessions(userID: peerUserId, keeping: peerId)
            knownPeers[peerId] = KnownPeer(peerId: peerId, userId: peerUserId, name: peerName, isSpeaker: peerIsSpeaker)

            // Respond with my presence so the new peer knows about me.
            await broadcast([
                "type": "peer-presence",
                "peerId": myPeerId,
                "userId": userId,
                "name": name,
                "isSpeaker": isSpeakerRole,
                "targetPeerId": peerId
            ])

            // A newcomer assumes everyone's camera + mic are ON until told
            // otherwise — if mine are off (audio call, muted, camera off),
            // tell the room again so the late joiner renders my avatar tile
            // instead of black frames.
            await broadcastMediaState(to: peerId)
            if isSpeakerRole && (!cameraOn || !micOn) {
                await broadcast([
                    "type": "track-update",
                    "from": myPeerId,
                    "hasAudio": micOn,
                    "hasVideo": cameraOn || isScreenSharing
                ])
            }

            // Duplicate-safe: peers re-announce their join after reconnects
            // and shortly after joining (the web client re-sends at +2s). A
            // live pair must never be clobbered by a repeat announcement.
            if peerConnections[peerId] != nil {
                onParticipantsChanged?()
                return
            }

            // If I'm a speaker, create a PC to the new peer. CRITICAL: when
            // the new peer is ALSO a speaker (meetings — everyone publishes),
            // both sides would create offers simultaneously (glare) and
            // negotiation deadlocks — the "black screen / no audio" bug.
            // The offerer is always the smaller peerId.
            if isSpeakerRole && peerIsSpeaker {
                _ = createPeerConnection(peerId: peerId)
                if myPeerId < peerId {
                    await createOffer(peerId: peerId)
                }
            } else if isSpeakerRole {
                _ = createPeerConnection(peerId: peerId)
                await createOffer(peerId: peerId)
            } else if peerIsSpeaker {
                // New peer is a speaker, I'm a listener — create PC as answerer,
                // wait for their offer.
                _ = createPeerConnection(peerId: peerId)
            }
            onParticipantsChanged?()

        case "peer-presence":
            guard let target = msg["targetPeerId"] as? String, target == myPeerId else { return }
            let peerId = msg["peerId"] as? String ?? ""
            let peerUserId = msg["userId"] as? String ?? ""
            let peerName = msg["name"] as? String ?? ""
            let peerIsSpeaker = msg["isSpeaker"] as? Bool ?? false
            guard !peerId.isEmpty, peerId != myPeerId else { return }

            evictStaleSessions(userID: peerUserId, keeping: peerId)
            knownPeers[peerId] = KnownPeer(peerId: peerId, userId: peerUserId, name: peerName, isSpeaker: peerIsSpeaker)

            await broadcastMediaState(to: peerId)

            // If both are speakers, offerer = smaller peerId.
            if isSpeakerRole && peerIsSpeaker && peerConnections[peerId] == nil {
                _ = createPeerConnection(peerId: peerId)
                if myPeerId < peerId {
                    await createOffer(peerId: peerId)
                }
            } else if isSpeakerRole && !peerIsSpeaker && peerConnections[peerId] == nil {
                // I'm a speaker, they're a listener — I must create a PC and send
                // an offer so they can receive my audio/video.
                _ = createPeerConnection(peerId: peerId)
                await createOffer(peerId: peerId)
            } else if !isSpeakerRole && peerIsSpeaker && peerConnections[peerId] == nil {
                // I'm a listener, they're a speaker — create a PC as answerer.
                // The speaker's 'join' handler may have already sent an offer,
                // but if we missed it (race), we still need the PC to receive it.
                // We also re-announce ourselves so the speaker creates a PC + offer.
                _ = createPeerConnection(peerId: peerId)
                await broadcast([
                    "type": "peer-presence",
                    "peerId": myPeerId,
                    "userId": userId,
                    "name": name,
                    "isSpeaker": isSpeakerRole,
                    "targetPeerId": peerId
                ])
            }
            onParticipantsChanged?()

        case "offer":
            guard let from = msg["from"] as? String else { return }
            guard let sdp = msg["sdp"] as? [String: Any] else { return }
            await handleOffer(from: from, sdp: sdp)

        case "answer":
            guard let from = msg["from"] as? String else { return }
            guard let sdp = msg["sdp"] as? [String: Any] else { return }
            await handleAnswer(from: from, sdp: sdp)

        case "ice":
            guard let from = msg["from"] as? String else { return }
            guard let candidate = msg["candidate"] as? [String: Any] else { return }
            // Web sends candidate.toJSON() whose sdpMLineIndex is a JSON
            // number that can decode as Double — `as? Int` silently fails
            // and defaults to m-line 0, which breaks video ICE from web
            // peers. Accept Int, Double, and numeric strings.
            let mLineIndex: Int32
            if let i = candidate["sdpMLineIndex"] as? Int {
                mLineIndex = Int32(i)
            } else if let d = candidate["sdpMLineIndex"] as? Double {
                mLineIndex = Int32(d)
            } else if let s = candidate["sdpMLineIndex"] as? String, let i = Int(s) {
                mLineIndex = Int32(i)
            } else {
                mLineIndex = 0
            }
            // Web may send sdpMid as null for end-of-candidates markers.
            let mid = (candidate["sdpMid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let iceCandidate = RTCIceCandidate(
                sdp: candidate["candidate"] as? String ?? "",
                sdpMLineIndex: mLineIndex,
                sdpMid: mid
            )
            await handleIceCandidate(from: from, candidate: iceCandidate)

        case "leave":
            let peerId = msg["peerId"] as? String ?? ""
            guard !peerId.isEmpty else { return }
            forgetParticipant(peerId)

        case "became-speaker":
            let peerId = msg["peerId"] as? String ?? ""
            let peerUserId = msg["userId"] as? String ?? ""
            let peerName = msg["name"] as? String ?? ""
            guard !peerId.isEmpty else { return }

            if var known = knownPeers[peerId] {
                known.isSpeaker = true
                knownPeers[peerId] = known
            } else {
                knownPeers[peerId] = KnownPeer(peerId: peerId, userId: peerUserId, name: peerName, isSpeaker: true)
            }

            if peerConnections[peerId] != nil {
                // Existing PC — renegotiate. The offerer creates the new offer.
                if myPeerId < peerId {
                    await createOffer(peerId: peerId)
                }
            } else if isSpeakerRole {
                // I'm a speaker, no PC yet — create one (offerer = smaller peerId).
                _ = createPeerConnection(peerId: peerId)
                if myPeerId < peerId {
                    await createOffer(peerId: peerId)
                }
            } else {
                // I'm a listener, no PC yet — create one as answerer, wait for offer.
                _ = createPeerConnection(peerId: peerId)
            }

        case "track-update":
            if let from = msg["from"] as? String, let hasAudio = msg["hasAudio"] as? Bool {
                peerMicOn[from] = hasAudio
                if !hasAudio {
                    speakingUntil.removeValue(forKey: from)
                    speakingPeerIDs.remove(from)
                }
            }
            if let from = msg["from"] as? String, let hasVideo = msg["hasVideo"] as? Bool {
                peerVideoOn[from] = hasVideo
            }
            onParticipantsChanged?()

        case "mic-toggle":
            if let from = msg["from"] as? String, let isOn = msg["isOn"] as? Bool {
                peerMicOn[from] = isOn
                if !isOn {
                    speakingUntil.removeValue(forKey: from)
                    speakingPeerIDs.remove(from)
                }
            }
            onParticipantsChanged?()

        case "screen-share":
            let from = msg["from"] as? String ?? ""
            let isOn = msg["isOn"] as? Bool ?? false
            guard !from.isEmpty else { return }
            if isOn {
                screenSharingPeerIds.insert(from)
            } else {
                screenSharingPeerIds.remove(from)
            }
            onParticipantsChanged?()

        case "reaction":
            let emoji = msg["emoji"] as? String ?? "\u{2764}\u{FE0F}"
            onReaction?(emoji)

        case "app-event":
            if let event = msg["event"] as? String, !event.isEmpty {
                onAppEvent?(
                    event,
                    msg["data"] as? [String: Any] ?? [:],
                    msg["from"] as? String ?? ""
                )
            }

        case "reneg":
            // A peer's negotiation stalled and it asked for a fresh offer.
            // Re-offer with an ICE restart; glare protection in handleOffer
            // keeps simultaneous offers safe.
            guard let from = msg["from"] as? String, !from.isEmpty else { return }
            await refreshIceServersIfStale(maxAge: 45)
            if peerConnections[from] != nil {
                await createOffer(peerId: from, iceRestart: true)
            } else if let known = knownPeers[from], isSpeakerRole || known.isSpeaker {
                _ = createPeerConnection(peerId: from)
                await createOffer(peerId: from)
            }

        case "reset":
            // The other side rebuilt our pair from scratch — mirror it so
            // both ends restart negotiation cleanly.
            guard let from = msg["from"] as? String, !from.isEmpty else { return }
            let resetPeerIsSpeaker = knownPeers[from]?.isSpeaker ?? true
            removePeer(from)
            guard isSpeakerRole || resetPeerIsSpeaker else { return }
            await refreshIceServersIfStale(maxAge: 45)
            _ = createPeerConnection(peerId: from)
            if isSpeakerRole && resetPeerIsSpeaker {
                if myPeerId < from {
                    await createOffer(peerId: from)
                }
            } else if isSpeakerRole {
                await createOffer(peerId: from)
            }
            onParticipantsChanged?()

        default:
            break
        }
    }

    // ─── Peer connection management ──────────────────────────────────────────

    /// Single source of truth for peer-connection config — used at creation
    /// AND pushed into live connections when TURN credentials rotate.
    private func makeRTCConfiguration() -> RTCConfiguration {
        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.iceCandidatePoolSize = 10
        config.continualGatheringPolicy = .gatherContinually
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        return config
    }

    @discardableResult
    private func createPeerConnection(peerId: String) -> RTCPeerConnection? {
        // Never clobber a live pair — duplicate join/presence announcements
        // (re-announced after reconnects) must not orphan a mid-negotiation
        // PC. Rebuild paths call removePeer(_:) first, so they pass through.
        if let existing = peerConnections[peerId] {
            return existing
        }
        let config = makeRTCConfiguration()

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        guard let pc = factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        ) else {
            print("[WhisperLiveRTC] Failed to create peer connection for peer \(peerId)")
            return nil
        }

        // Add local tracks if we're a speaker. Any kind we can't send yet
        // (device blocked, media still acquiring) becomes a recvonly
        // transceiver so the SDP ALWAYS carries both m-lines — offers with
        // missing media sections deadlock cross-platform negotiation.
        if isSpeakerRole {
            if let audio = audioTrack {
                _ = pc.add(audio, streamIds: ["audio"])
            } else {
                let audioInit = RTCRtpTransceiverInit()
                audioInit.direction = .recvOnly
                _ = pc.addTransceiver(of: .audio, init: audioInit)
            }
            if let video = videoTrack {
                _ = pc.add(video, streamIds: ["video"])
            } else {
                let videoInit = RTCRtpTransceiverInit()
                videoInit.direction = .recvOnly
                _ = pc.addTransceiver(of: .video, init: videoInit)
            }
        } else {
            // Listeners: add recvonly transceivers so the SDP negotiation
            // includes audio + video media sections even though we have no
            // local tracks to send. Without this, the answer we create has
            // no media m-lines and no media flows from speaker to listener.
            let audioInit = RTCRtpTransceiverInit()
            audioInit.direction = .recvOnly
            _ = pc.addTransceiver(of: .audio, init: audioInit)
            let videoInit = RTCRtpTransceiverInit()
            videoInit.direction = .recvOnly
            _ = pc.addTransceiver(of: .video, init: videoInit)
        }

        peerConnections[peerId] = pc
        peerConnectionIds[ObjectIdentifier(pc)] = peerId

        // Flush any ICE candidates that were buffered before the PC existed.
        Task { await flushPendingIce(for: peerId) }

        onParticipantsChanged?()
        return pc
    }

    private func createOffer(peerId: String, iceRestart: Bool = false) async {
        guard let pc = peerConnections[peerId] else { return }
        // No OfferToReceive constraints — addTransceiver (added in
        // createPeerConnection) handles recvonly direction for listeners.
        // Legacy OfferToReceiveAudio/Video creates extra m-lines that conflict
        // with the transceivers and break SDP negotiation on some browsers.
        // IceRestart mints fresh ICE credentials when a peer asks us to heal
        // a stuck connection ("reneg" signal).
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: iceRestart ? ["IceRestart": "true"] : nil,
            optionalConstraints: nil
        )
        do {
            let offer = try await pc.offer(for: constraints)
            try await pc.setLocalDescription(offer)
            await broadcast([
                "type": "offer",
                "from": myPeerId,
                "to": peerId,
                "sdp": ["type": "offer", "sdp": offer.sdp]
            ])
        } catch {
            print("[WhisperLiveRTC] Create offer error: \(error)")
        }
    }

    private func handleOffer(from peerId: String, sdp: [String: Any]) async {
        if peerConnections[peerId] == nil {
            // Create a minimal PC WITHOUT pre-adding recvonly transceivers.
            // The offer's m-lines define the transceivers; pre-adding extra
            // ones before setRemoteDescription creates duplicate m-sections
            // that break SDP negotiation with the web client (cross-platform
            // black-screen bug). This mirrors the web's handleOffer approach.
            let config = RTCConfiguration()
            config.iceServers = iceServers
            config.sdpSemantics = .unifiedPlan
            config.iceCandidatePoolSize = 10
            config.continualGatheringPolicy = .gatherContinually
            config.bundlePolicy = .maxBundle
            config.rtcpMuxPolicy = .require
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
            )
            guard let pc = factory.peerConnection(
                with: config,
                constraints: constraints,
                delegate: self
            ) else {
                print("[WhisperLiveRTC] Failed to create PC for offer from \(peerId)")
                return
            }
            // Add local tracks if we're a speaker (for meetings, we always are).
            if isSpeakerRole {
                if let audio = audioTrack { _ = pc.add(audio, streamIds: ["audio"]) }
                if let video = videoTrack { _ = pc.add(video, streamIds: ["video"]) }
            }
            peerConnections[peerId] = pc
            peerConnectionIds[ObjectIdentifier(pc)] = peerId
            Task { await flushPendingIce(for: peerId) }
            onParticipantsChanged?()
        }
        guard let pc = peerConnections[peerId] else { return }

        let typeStr = sdp["type"] as? String ?? "offer"
        let sdpStr = sdp["sdp"] as? String ?? ""
        let sessionDesc = RTCSessionDescription(type: sdpType(from: typeStr), sdp: sdpStr)

        do {
            // Glare protection (perfect negotiation): if we already sent our
            // own offer, the rightful offerer is the smaller peerId. The
            // rightful offerer IGNORES the incoming offer (the peer will
            // answer ours); the polite side ROLLS BACK and answers instead.
            if pc.signalingState == .haveLocalOffer {
                if myPeerId < peerId {
                    return // impolite — our offer wins, drop theirs
                }
                try await pc.setLocalDescription(RTCSessionDescription(type: .rollback, sdp: ""))
            }
            try await pc.setRemoteDescription(sessionDesc)
            // Flush any ICE candidates that were buffered before remote description was set.
            await flushPendingIce(for: peerId)
            // No OfferToReceive constraints — transceivers are already set
            // by setRemoteDescription. Legacy constraints create extra m-lines.
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: nil
            )
            let answer = try await pc.answer(for: constraints)
            try await pc.setLocalDescription(answer)
            await broadcast([
                "type": "answer",
                "from": myPeerId,
                "to": peerId,
                "sdp": ["type": "answer", "sdp": answer.sdp]
            ])
        } catch {
            print("[WhisperLiveRTC] Handle offer error: \(error)")
        }
    }

    private func handleAnswer(from peerId: String, sdp: [String: Any]) async {
        guard let pc = peerConnections[peerId] else { return }
        let typeStr = sdp["type"] as? String ?? "answer"
        let sdpStr = sdp["sdp"] as? String ?? ""
        let sessionDesc = RTCSessionDescription(type: sdpType(from: typeStr), sdp: sdpStr)
        do {
            try await pc.setRemoteDescription(sessionDesc)
            // Flush any ICE candidates that were buffered before remote description was set.
            await flushPendingIce(for: peerId)
        } catch {
            print("[WhisperLiveRTC] Handle answer error: \(error)")
        }
    }

    /// Buffered ICE candidate handler. Candidates that arrive before the PC
    /// exists or before setRemoteDescription are queued and flushed later.
    private func handleIceCandidate(from peerId: String, candidate: RTCIceCandidate) async {
        guard let pc = peerConnections[peerId] else {
            // PC doesn't exist yet — buffer the candidate.
            pendingIceCandidates[peerId, default: []].append(candidate)
            return
        }
        // If remote description isn't set yet, buffer.
        if pc.remoteDescription == nil {
            pendingIceCandidates[peerId, default: []].append(candidate)
            return
        }
        do {
            try await pc.add(candidate)
        } catch {
            // ICE errors are common during teardown — ignore.
        }
    }

    /// Flush buffered ICE candidates for a peer after setRemoteDescription.
    private func flushPendingIce(for peerId: String) async {
        guard let candidates = pendingIceCandidates[peerId], !candidates.isEmpty else { return }
        pendingIceCandidates.removeValue(forKey: peerId)
        guard let pc = peerConnections[peerId] else { return }
        for candidate in candidates {
            do {
                try await pc.add(candidate)
            } catch {
                // Ignore — stale or duplicate.
            }
        }
    }

    /// Map a string SDP type to `RTCSdpType`.
    private func sdpType(from str: String) -> RTCSdpType {
        switch str {
        case "offer": return .offer
        case "answer": return .answer
        default: return .offer
        }
    }

    /// Removes membership as well as media. Renegotiation uses removePeer instead.
    func forgetParticipant(_ peerId: String, retire: Bool = true) {
        guard peerId != myPeerId, !peerId.isEmpty else { return }
        if retire { retiredPeerIDs.insert(peerId) }
        knownPeers.removeValue(forKey: peerId)
        screenSharingPeerIds.remove(peerId)
        removePeer(peerId)
    }

    private func evictStaleSessions(userID: String, keeping peerID: String) {
        guard !userID.isEmpty else { return }
        let stale = knownPeers.values.filter {
            $0.peerId != peerID && $0.userId.lowercased() == userID.lowercased()
        }.map(\.peerId)
        for id in stale { forgetParticipant(id) }
    }

    private func broadcastMediaState(to peerID: String) async {
        await broadcast(["type": "screen-share", "from": myPeerId, "to": peerID, "isOn": isScreenSharing])
        await broadcast(["type": "track-update", "from": myPeerId, "to": peerID,
                         "hasAudio": micOn, "hasVideo": cameraOn || isScreenSharing])
    }

    private func removePeer(_ peerId: String) {
        disconnectGraceTasks[peerId]?.cancel()
        disconnectGraceTasks.removeValue(forKey: peerId)
        peerMicOn.removeValue(forKey: peerId)
        peerVideoOn.removeValue(forKey: peerId)
        speakingUntil.removeValue(forKey: peerId)
        speakingPeerIDs.remove(peerId)
        pendingIceCandidates.removeValue(forKey: peerId)
        if let pc = peerConnections[peerId] {
            peerConnectionIds.removeValue(forKey: ObjectIdentifier(pc))
            pc.close()
            peerConnections.removeValue(forKey: peerId)
        }
        // Clean up remote video track for this peer
        if remoteVideoTracks.removeValue(forKey: peerId) != nil {
            onRemoteVideoTrackForPeer?(peerId, nil)
        }
        onParticipantsChanged?()
    }

    // ─── Active speaker detection ────────────────────────────────────────────

    private func startSpeakerMonitoring() {
        stopSpeakerMonitoring()
        speakerMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.pollRemoteAudioLevels()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func stopSpeakerMonitoring() {
        speakerMonitorTask?.cancel()
        speakerMonitorTask = nil
        speakingUntil.removeAll()
        speakingPeerIDs.removeAll()
    }

    /// Read remote inbound RTP stats without touching the media renderers.
    private func pollRemoteAudioLevels() {
        for (peerId, connection) in peerConnections {
            connection.statistics { [weak self] report in
                let level = Self.inboundAudioLevel(in: report)
                Task { @MainActor [weak self] in
                    self?.applyAudioLevel(level, for: peerId)
                }
            }
        }
    }

    private func applyAudioLevel(_ level: Double, for peerId: String) {
        guard peerConnections[peerId] != nil else { return }
        let now = Date()
        let wasSpeaking = speakingPeerIDs.contains(peerId)
        if (peerMicOn[peerId] ?? true) && level >= 0.018 {
            speakingUntil[peerId] = now.addingTimeInterval(0.9)
        }
        let isSpeaking = isPeerSpeaking(peerId, now: now)
        if isSpeaking {
            speakingPeerIDs.insert(peerId)
        } else {
            speakingPeerIDs.remove(peerId)
        }
        if wasSpeaking != isSpeaking {
            onParticipantsChanged?()
        }
    }

    private func isPeerSpeaking(_ peerId: String, now: Date) -> Bool {
        guard peerMicOn[peerId] ?? true else { return false }
        return (speakingUntil[peerId] ?? .distantPast) > now
    }

    nonisolated private static func inboundAudioLevel(in report: RTCStatisticsReport) -> Double {
        var peak: Double = 0
        for statistic in report.statistics.values where statistic.type == "inbound-rtp" {
            let kind = (statistic.values["kind"] as? String) ?? (statistic.values["mediaType"] as? String)
            guard kind == "audio" else { continue }
            if let number = statistic.values["audioLevel"] as? NSNumber {
                peak = max(peak, number.doubleValue)
            } else if let value = statistic.values["audioLevel"] as? Double {
                peak = max(peak, value)
            }
        }
        return peak
    }

    // ─── Audio session ───────────────────────────────────────────────────────

    /// Configure audio through WebRTC's RTCAudioSession wrapper — NOT the
    /// raw AVAudioSession. WebRTC owns the audio unit; configuring the raw
    /// session behind its back gets overridden the moment the first peer
    /// connection spins up its audio module, which is why audio was dead.
    private func configureAudioSession(video: Bool) {
        guard !didConfigureAudio else { return }
        didConfigureAudio = true
        audioSessionVideoMode = video
        let rtcSession = RTCAudioSession.sharedInstance()
        // useManualAudio = true so WebRTC doesn't auto-activate the AVAudioSession.
        // This allows AVAudioEngine (used by the meeting transcriber) to coexist
        // — both share the same audio session and audio unit instead of fighting
        // over it. Without this, engine.start() fails with a cryptic error because
        // WebRTC already grabbed the audio unit.
        rtcSession.useManualAudio = true

        // Teach WebRTC's OWN session template speaker-first routing — when
        // its audio module re-applies configuration mid-call it would
        // otherwise drop `.defaultToSpeaker` and flip audio to the ear
        // receiver.
        let webRTCConfig = RTCAudioSessionConfiguration.webRTC()
        webRTCConfig.category = AVAudioSession.Category.playAndRecord.rawValue
        webRTCConfig.categoryOptions = routingOptions
        webRTCConfig.mode = routingMode.rawValue
        RTCAudioSessionConfiguration.setWebRTC(webRTCConfig)

        rtcSession.lockForConfiguration()
        var audioReady = false
        do {
            try rtcSession.setCategory(
                .playAndRecord,
                mode: routingMode,
                options: routingOptions
            )
            try rtcSession.setActive(true)
            try rtcSession.overrideOutputAudioPort(audioRoute == .speaker ? .speaker : .none)
            audioReady = true
        } catch {
            print("[WhisperLiveRTC] Audio session config error: \(error)")
        }
        rtcSession.unlockForConfiguration()
        // Only enable WebRTC's audio module if the session activated successfully.
        // With useManualAudio = true, this starts the audio recording module
        // without trying to re-activate the session.
        if audioReady {
            rtcSession.isAudioEnabled = true
            startAudioRecoveryObservers()
        } else {
            didConfigureAudio = false
            print("[WhisperLiveRTC] Skipping isAudioEnabled — session activation failed")
        }
    }

    private func releaseAudioSession() {
        stopAudioRecoveryObservers()
        guard didConfigureAudio else { return }
        didConfigureAudio = false
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.isAudioEnabled = false
        rtcSession.lockForConfiguration()
        try? rtcSession.setActive(false)
        rtcSession.unlockForConfiguration()
    }

    /// Watch the audio/app lifecycle while a call is configured. Each of
    /// these events can leave WebRTC's audio unit running at a stale IO
    /// format: interruptions (Siri, phone calls, other apps grabbing the
    /// mic), media-server resets, and background → foreground trips —
    /// including returning to the room from the in-app PiP tile.
    private func startAudioRecoveryObservers() {
        stopAudioRecoveryObservers()
        let center = NotificationCenter.default
        audioRecoveryObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            Task { @MainActor in
                WhisperLiveRTCService.shared.recoverAudioSession(reason: "interruption-ended", force: true)
            }
        })
        audioRecoveryObservers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                WhisperLiveRTCService.shared.recoverAudioSession(reason: "media-services-reset", force: true)
            }
        })
        audioRecoveryObservers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                WhisperLiveRTCService.shared.recoverAudioSession(reason: "foreground")
            }
        })
    }

    private func stopAudioRecoveryObservers() {
        for observer in audioRecoveryObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        audioRecoveryObservers.removeAll()
    }

    /// Tear WebRTC's audio unit down and back up with a fresh session
    /// config. iOS quietly restarts audio IO at a different sample rate
    /// after interruptions and background trips while WebRTC keeps encoding
    /// at the old one — the exact "they sound garbled/robotic after coming
    /// back" bug. Rebuilding renegotiates the format and re-asserts the
    /// user's chosen output route.
    func recoverAudioSession(reason: String, force: Bool = false) {
        guard didConfigureAudio else { return }
        if !force, Date().timeIntervalSince(lastAudioRecoveryAt) < 1.5 { return }
        lastAudioRecoveryAt = Date()
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.isAudioEnabled = false
        rtcSession.lockForConfiguration()
        do {
            try rtcSession.setCategory(
                .playAndRecord,
                mode: routingMode,
                options: routingOptions
            )
            try rtcSession.setActive(true)
        } catch {
            print("[WhisperLiveRTC] audio recovery (\(reason)) failed: \(error)")
        }
        rtcSession.unlockForConfiguration()
        rtcSession.isAudioEnabled = true
        applyAudioRoute()
        print("[WhisperLiveRTC] audio unit rebuilt (\(reason))")
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WhisperLiveRTCService: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    // Unified Plan: tracks arrive via didAdd, not the legacy didAdd stream.
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        Task { @MainActor in
            guard let peerId = self.peerConnectionIds[ObjectIdentifier(peerConnection)] else { return }
            let track = rtpReceiver.track
            if let videoTrack = track as? RTCVideoTrack {
                self.remoteVideoTracks[peerId] = videoTrack
                self.onRemoteVideoTrackForPeer?(peerId, videoTrack)
            }
            self.onParticipantsChanged?()
        }
    }

    // Legacy Plan B callback — still required by the protocol, kept empty.
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        Task { @MainActor in
            guard let peerId = self.peerConnectionIds[ObjectIdentifier(peerConnection)] else { return }
            for videoTrack in stream.videoTracks {
                self.remoteVideoTracks[peerId] = videoTrack
                self.onRemoteVideoTrackForPeer?(peerId, videoTrack)
                break
            }
            self.onParticipantsChanged?()
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Task { @MainActor in
            guard let peerId = self.peerConnectionIds[ObjectIdentifier(peerConnection)] else { return }
            self.remoteVideoTracks.removeValue(forKey: peerId)
            self.onRemoteVideoTrackForPeer?(peerId, nil)
            self.onParticipantsChanged?()
        }
    }

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor in
            guard let peerId = self.peerConnectionIds[ObjectIdentifier(peerConnection)] else { return }
            switch newState {
            case .connected, .completed:
                // Recovered (or connected for the first time) — cancel any
                // pending grace-period removal.
                self.disconnectGraceTasks[peerId]?.cancel()
                self.disconnectGraceTasks.removeValue(forKey: peerId)
                self.onParticipantsChanged?()
            case .disconnected:
                // Transient blip — give the connection 8 seconds to recover
                // before dropping the peer (mirrors typical browser behavior).
                guard self.disconnectGraceTasks[peerId] == nil else { return }
                self.disconnectGraceTasks[peerId] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard let self else { return }
                        self.disconnectGraceTasks.removeValue(forKey: peerId)
                        guard self.peerConnections[peerId] === peerConnection else { return }
                        self.forgetParticipant(peerId, retire: false)
                    }
                }
            case .failed:
                self.onConnectionFailed?()
                self.forgetParticipant(peerId, retire: false)
            case .closed:
                self.forgetParticipant(peerId, retire: false)
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let candidateDict: [String: Any] = [
            "candidate": candidate.sdp,
            "sdpMLineIndex": Int(candidate.sdpMLineIndex),
            "sdpMid": candidate.sdpMid ?? ""
        ]
        Task { @MainActor in
            if let peerId = self.peerConnectionIds[ObjectIdentifier(peerConnection)] {
                await self.broadcast([
                    "type": "ice",
                    "from": self.myPeerId,
                    "to": peerId,
                    "candidate": candidateDict
                ])
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
