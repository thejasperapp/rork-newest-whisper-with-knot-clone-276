import Foundation
import SwiftUI
import UIKit
import CallKit
import WebRTC

/// App-wide call state. Drives the in-app call UI mounted at the root so
/// incoming calls surface no matter which screen the recipient is on.
///
/// Media rides the SAME mesh WebRTC engine as meetings and lives
/// (`WhisperLiveRTCService`), joined on the shared `meeting:{roomID}`
/// signaling channel — so an iOS caller and a web callee land in one room
/// and everything that already works for meetings (TURN, reconnects,
/// screen share, app events) works for calls too.
///
/// The `whisper_messages` signal layer only carries call lifecycle:
///   1. Ring the recipient(s) (`.invite` — also rings the web client),
///   2. Tell the caller their invite was accepted/declined,
///   3. Tell either side the other hung up before/after connect.
/// Room presence doubles as an accept: the moment anyone else appears in
/// the mesh room, a ringing call flips to connected.
@MainActor
@Observable
final class WhisperCallService {
    static let shared = WhisperCallService()

    enum Direction: Equatable { case outgoing, incoming }
    enum CallState: Equatable { case ringing, connected, ended }

    /// Why the call ended — drives the final "ringing → missed / declined /
    /// ended" frame of the call UI.
    enum EndReason: Equatable {
        case completed   // connected, then hung up
        case missed      // rang out with no answer
        case declined    // explicitly declined
        case cancelled   // caller cancelled before pickup
    }

    struct ActiveCall: Identifiable, Equatable {
        let id: String              // shared call/signal id
        let roomID: String          // mesh room (meeting id) carrying media
        let direction: Direction
        var state: CallState
        let otherUserID: String     // 1:1 peer, or the inviter for group rings
        let otherUsername: String
        var avatarURL: URL?
        let mode: WhisperCallSignal.Mode
        var startedAt: Date?        // set when state → connected
        var isGroup: Bool
        var groupID: String?
        /// "@username" for 1:1, the group name for group calls.
        var title: String
        /// Set when state → .ended so the closing frame reads correctly.
        var endReason: EndReason?
    }

    /// Currently presented call (if any). The dedicated call window
    /// (`WhisperCallWindowManager`) presents/dismisses itself off this —
    /// floating above every sheet and cover, so the caller stays right in
    /// the chat while the call rings, connects, and runs.
    var active: ActiveCall? {
        didSet {
            if active != nil {
                WhisperCallWindowManager.shared.show()
            } else if oldValue != nil {
                WhisperCallWindowManager.shared.hide()
            }
        }
    }

    /// Transient banner message for failures.
    var lastErrorMessage: String?

    /// Set by the DM thread / Group chat while they are on screen so the
    /// root view doesn't double-present the call cover.
    var chatIsHandlingCallUI: Bool = false

    /// Bumped whenever mesh participants / video tracks change so the call
    /// UI re-renders (the RTC service isn't observable itself).
    var rtcTick: Int = 0

    /// Peer a class host spotlighted for everyone (nil = automatic layout).
    var spotlightPeerID: String?
    /// Coach-led "class mode" — surfaces a class banner for everyone.
    var classModeOn: Bool = false
    var classHostName: String?
    /// Set whenever a coach remotely muted me — the UI shows a toast.
    var mutedByCoachAt: Date?

    // ── Fun layer & class tools ────────────────────────────────────

    /// A floating emoji reaction raining over the call stage.
    struct CallReaction: Identifiable, Equatable {
        let id: UUID
        let emoji: String
        let fromName: String
        let at: Date
    }

    /// Recent reactions (pruned by the call UI as they finish floating).
    var callReactions: [CallReaction] = []

    /// userID (lowercased) → display name of everyone with a hand up.
    var raisedHands: [String: String] = [:]

    /// Coach-broadcast interval timer (work / rest) everyone can see.
    struct ClassTimer: Equatable {
        let label: String
        let endsAt: Date
        let totalSeconds: Int
        let isRest: Bool
    }
    var classTimer: ClassTimer?

    /// Coach-broadcast "now doing" exercise card shown to the whole call.
    var classExercise: String?

    private(set) var isStarting: Bool = false
    private var startOperation: UUID = UUID()
    private var incomingJoinTask: Task<Void, Never>?
    private var ownsRTC: Bool = false
    private var ringTimeoutTask: Task<Void, Never>?
    private var remoteDepartureTask: Task<Void, Never>?
    private var incomingRingTimeoutTask: Task<Void, Never>?
    private var pendingIncomingCallID: String?

    private init() {
        NotificationCenter.default.addObserver(forName: Notification.Name("WhisperMeetingAccountWillChange"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.ownsRTC { WhisperLiveRTCService.shared.suspendMediaForExit() }
                self.endLocal(reason: .cancelled)
                self.active = nil
                self.resetCallExtras()
            }
        }
    }

    private var myUserID: String { AccountStorage.currentUserID }
    private var myUsername: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "someone"
    }

    /// True when `userID` is one of my accepted coaching clients — unlocks
    /// class-host controls (spotlight, mute) inside calls.
    func isMyClient(userID: String) -> Bool {
        guard !userID.isEmpty else { return false }
        return WhisperCoachRequestService.shared.myClients.contains {
            $0.client_user_id.lowercased() == userID.lowercased()
        }
    }

    // MARK: - Outgoing

    /// Called by the DM thread's video button. Creates the meeting row that
    /// carries the media (so web recipients can answer at /meet/{id}),
    /// rings the recipient, and joins the mesh room immediately so media is
    /// ready the moment they answer.
    func startOutgoing(
        otherUserID: String,
        otherUsername: String,
        avatarURL: URL?,
        mode: WhisperCallSignal.Mode
    ) async {
        guard !otherUserID.isEmpty, canStartCall() else { return }
        let operation = UUID(); startOperation = operation
        isStarting = true
        defer { if startOperation == operation { isStarting = false } }
        let generation = AccountStorage.generation
        let roomID = await makeCallRoom(
            title: mode == .video
                ? "Video call with @\(otherUsername)"
                : "Audio call with @\(otherUsername)"
        )
        guard !Task.isCancelled, generation == AccountStorage.generation, active == nil,
              !WhisperMeetingWindow.shared.isPresenting, !WhisperLiveRTCService.shared.isInUse else { return }
        active = ActiveCall(
            id: roomID,
            roomID: roomID,
            direction: .outgoing,
            state: .ringing,
            otherUserID: otherUserID,
            otherUsername: otherUsername,
            avatarURL: avatarURL,
            mode: mode,
            startedAt: nil,
            isGroup: false,
            groupID: nil,
            title: "@\(otherUsername)",
            endReason: nil
        )
        WhisperCallRingtone.shared.start(style: .ringback)
        // CallKit keeps the outgoing call alive (mic + audio + networking)
        // if the caller backgrounds the app while ringing or mid-call.
        WhisperVoIPService.shared.startOutgoingCall(
            callID: roomID,
            displayName: "@\(otherUsername)",
            video: mode == .video
        )
        sendInvite(
            callID: roomID, roomID: roomID, mode: mode,
            toUserID: otherUserID, toUsername: otherUsername,
            groupID: nil, groupName: nil
        )
        attachRTCCallbacks()
        await WhisperLiveRTCService.shared.join(
            roomId: "meeting:\(roomID)",
            userId: myUserID,
            name: myUsername,
            asListener: false,
            withVideo: mode == .video,
            defaultToSpeaker: false,
            shouldContinue: { [weak self] in
                self?.active?.id == roomID && self?.active?.state != .ended && generation == AccountStorage.generation
            }
        )
        guard active?.id == roomID, active?.state == .ringing else { return }
        startRingTimeout(callID: roomID, seconds: 32)
    }

    /// Rings every member of a group and opens one shared room — the class
    /// / group-call flow. A join link is also posted into the group thread
    /// so members who miss the ring (or are on web) can hop in.
    func startGroupCall(group: WhisperGroup, mode: WhisperCallSignal.Mode = .video) async {
        guard !group.members.isEmpty, canStartCall() else { return }
        let operation = UUID(); startOperation = operation
        isStarting = true
        defer { if startOperation == operation { isStarting = false } }
        let generation = AccountStorage.generation
        let roomID = UUID().uuidString.lowercased()
        let descriptor = WhisperGroupCallDescriptor(callID: roomID, roomID: roomID, groupID: group.id.uuidString.lowercased(), groupName: group.name, mode: mode)
        active = ActiveCall(
            id: roomID,
            roomID: roomID,
            direction: .outgoing,
            state: .ringing,
            otherUserID: "",
            otherUsername: group.name,
            avatarURL: nil,
            mode: mode,
            startedAt: nil,
            isGroup: true,
            groupID: group.id.uuidString,
            title: group.name,
            endReason: nil
        )
        await WhisperGroupChatService.shared.syncRegistry(force: true)
        guard !Task.isCancelled, generation == AccountStorage.generation, active?.id == roomID, active?.state != .ended else { return }
        guard WhisperGroupChatService.shared.activeRegistryIDs.contains(group.id), WhisperGroupChatService.shared.lastError == nil else {
            lastErrorMessage = "Couldn't verify your group membership. Please try again."
            endLocal(reason: .cancelled); return
        }
        do {
            _ = try await WhisperMeetingService.shared.create(title: "Group call · \(group.name)", id: roomID, callDescriptor: descriptor)
        } catch {
            guard generation == AccountStorage.generation, active?.id == roomID, active?.state != .ended else { return }
            lastErrorMessage = "Couldn't start the group call. Check your connection and try again."
            endLocal(reason: .cancelled)
            return
        }
        guard !Task.isCancelled, generation == AccountStorage.generation, active?.id == roomID, active?.state == .ringing,
              !WhisperMeetingWindow.shared.isPresenting, !WhisperLiveRTCService.shared.isInUse else { return }
        WhisperCallRingtone.shared.start(style: .ringback)
        WhisperVoIPService.shared.startOutgoingCall(
            callID: roomID,
            displayName: group.name,
            video: mode == .video
        )
        for member in group.members where member.user_id.lowercased() != myUserID.lowercased() {
            sendInvite(
                callID: roomID, roomID: roomID, mode: mode,
                toUserID: member.user_id, toUsername: member.username,
                groupID: group.id.uuidString, groupName: group.name
            )
        }
        Task {
            guard generation == AccountStorage.generation, active?.id == roomID, active?.state != .ended else { return }
            _ = await WhisperGroupChatService.shared.sendMessage(
                toGroup: group,
                body: "Started a group \(mode == .audio ? "audio" : "video") call — join here: \(WhisperMeetingService.socialCallLink(for: roomID))"
            )
        }
        attachRTCCallbacks()
        await WhisperLiveRTCService.shared.join(
            roomId: "meeting:\(roomID)",
            userId: myUserID,
            name: myUsername,
            asListener: false,
            withVideo: mode == .video,
            defaultToSpeaker: false,
            shouldContinue: { [weak self] in
                self?.active?.id == roomID && self?.active?.state != .ended && generation == AccountStorage.generation
            }
        )
        guard active?.id == roomID, active?.state == .ringing else { return }
        startRingTimeout(callID: roomID, seconds: 45)
    }

    /// Join an existing group room without a meeting lobby, new room, or another ring blast.
    func joinGroupCall(room: WhisperMeetingRow, groupHint: WhisperGroup? = nil, modeHint: WhisperCallSignal.Mode? = nil) {
        if let current = active {
            if current.roomID.lowercased() == room.id.lowercased() {
                WhisperCallWindowManager.shared.restore()
                if current.direction == .incoming, current.state == .ringing { answerIncoming() }
            } else { lastErrorMessage = "Leave this call before joining another." }
            return
        }
        guard !room.isEnded, canStartCall() else { return }
        let descriptor = room.groupCall
        let knownGroup = groupHint ?? WhisperGroupChatService.shared.visibleGroups.first {
            $0.id.uuidString.lowercased() == descriptor?.groupID.lowercased()
                || "Group call · \($0.name)" == room.title
        }
        let groupID = descriptor?.groupID ?? knownGroup?.id.uuidString.lowercased()
        let title = descriptor?.groupName ?? knownGroup?.name ?? "Group call"
        let mode = descriptor?.mode ?? modeHint ?? .audio
        let callID = descriptor?.callID ?? room.id
        let generation = AccountStorage.generation
        let operation = UUID(); startOperation = operation
        isStarting = true
        active = ActiveCall(id: callID, roomID: room.id, direction: .incoming, state: .connected,
            otherUserID: room.host_id, otherUsername: room.host_username, avatarURL: nil, mode: mode,
            startedAt: nil, isGroup: true, groupID: groupID, title: title, endReason: nil)
        incomingJoinTask?.cancel()
        incomingJoinTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.startOperation == operation { self.isStarting = false } }
            await WhisperGroupChatService.shared.syncRegistry(force: true)
            guard !Task.isCancelled, generation == AccountStorage.generation, self.active?.id == callID, self.active?.state != .ended else { return }
            let resolvedID = groupID ?? WhisperGroupChatService.shared.visibleGroups.first { "Group call · \($0.name)" == room.title }?.id.uuidString
            guard let resolvedID, let uuid = UUID(uuidString: resolvedID),
                  WhisperGroupChatService.shared.activeRegistryIDs.contains(uuid), WhisperGroupChatService.shared.lastError == nil else {
                self.lastErrorMessage = "This group call isn't available to this account. Open it from your group chat."
                self.endLocal(reason: .cancelled)
                return
            }
            guard !WhisperLiveRTCService.shared.isInUse, !WhisperMeetingWindow.shared.isPresenting else {
                self.lastErrorMessage = "Leave your current room before joining this call."
                self.endLocal(reason: .cancelled)
                return
            }
            self.active?.groupID = resolvedID
            WhisperVoIPService.shared.startOutgoingCall(callID: callID, displayName: title, video: mode == .video, connectedImmediately: true)
            self.attachRTCCallbacks()
            await WhisperLiveRTCService.shared.join(roomId: "meeting:\(room.id)", userId: self.myUserID, name: self.myUsername,
                asListener: false, withVideo: mode == .video, defaultToSpeaker: false, shouldContinue: { [weak self] in
                    self?.active?.id == callID && self?.active?.state != .ended && generation == AccountStorage.generation
                })
            guard !Task.isCancelled, generation == AccountStorage.generation, self.active?.id == callID, self.active?.state != .ended else { return }
            guard WhisperLiveRTCService.shared.connected else {
                self.lastErrorMessage = "Couldn't connect to the group call. Please try again."
                self.endLocal(reason: .cancelled)
                return
            }
            self.active?.startedAt = Date()
            self.rtcTick &+= 1
        }
    }

    private func canStartCall() -> Bool {
        guard active == nil, !isStarting else {
            if active != nil { WhisperCallWindowManager.shared.restore() }
            return false
        }
        guard !WhisperMeetingWindow.shared.isPresenting, !WhisperLiveRTCService.shared.isInUse else {
            lastErrorMessage = "Leave your current meeting or live room before starting a call."
            return false
        }
        lastErrorMessage = nil
        return true
    }

    /// Creates the meeting row backing a call so web users can join the
    /// same room; falls back to a bare UUID when offline (iOS↔iOS still
    /// connects via the mesh room).
    private func makeCallRoom(title: String) async -> String {
        if let meeting = try? await WhisperMeetingService.shared.create(title: title) {
            return meeting.id
        }
        return UUID().uuidString.lowercased()
    }

    /// Caller cancels before the other side picks up.
    func cancelOutgoing() {
        guard let call = active, call.direction == .outgoing else { return }
        if call.state == .ringing {
            if call.isGroup {
                sendGroupCancel(call)
            } else {
                sendControl(kind: .cancel, call: call)
                postCallEndedSystemMessage(call, connected: false)
            }
        }
        endLocal(reason: .cancelled)
    }

    // MARK: - Incoming

    /// Recipient taps Answer. Sends `.accept`, joins the mesh room, flips
    /// to connected (media streams in as peers negotiate).
    func answerIncoming() {
        guard var call = active, call.direction == .incoming, call.state == .ringing else { return }
        guard !WhisperMeetingWindow.shared.isPresenting, !WhisperLiveRTCService.shared.isInUse else {
            lastErrorMessage = "Leave your current meeting before answering this call."
            return
        }
        WhisperCallRingtone.shared.stop()
        WhisperNotificationService.shared.clearIncomingCallBanner(callID: call.id)
        // If CallKit is also showing this call (VoIP push path), flip the
        // system UI to connected — guarded internally against loops when
        // the answer CAME from CallKit.
        WhisperVoIPService.shared.syncAnswerToCallKit(callID: call.id)
        let roomID = call.roomID
        let identity = myUserID
        let name = myUsername
        let wantsVideo = call.mode == .video
        let callID = call.id
        let generation = AccountStorage.generation
        let operation = UUID(); startOperation = operation; isStarting = true
        incomingJoinTask?.cancel()
        incomingJoinTask = Task {
            defer { if self.startOperation == operation { self.isStarting = false } }
            if let groupID = call.groupID, let uuid = UUID(uuidString: groupID) {
                await WhisperGroupChatService.shared.syncRegistry(force: true)
                guard !Task.isCancelled, generation == AccountStorage.generation, self.active?.id == callID, self.active?.state != .ended else { return }
                guard WhisperGroupChatService.shared.activeRegistryIDs.contains(uuid), WhisperGroupChatService.shared.lastError == nil else {
                    self.lastErrorMessage = "Couldn't verify access to this group call."
                    self.endLocal(reason: .cancelled); return
                }
            }
            guard !Task.isCancelled, generation == AccountStorage.generation, self.active?.id == callID, self.active?.state != .ended else { return }
            self.sendControl(kind: .accept, call: call)
            self.attachRTCCallbacks()
            await WhisperLiveRTCService.shared.join(
                roomId: "meeting:\(roomID)",
                userId: identity,
                name: name,
                asListener: false,
                withVideo: wantsVideo,
                defaultToSpeaker: false,
                shouldContinue: { [weak self] in
                    self?.active?.id == callID && self?.active?.state != .ended && generation == AccountStorage.generation
                }
            )
        }
        call.state = .connected
        call.startedAt = Date()
        active = call
        pendingIncomingCallID = nil
    }

    /// Recipient taps Decline.
    func declineIncoming() {
        guard let call = active, call.direction == .incoming else { return }
        WhisperNotificationService.shared.clearIncomingCallBanner(callID: call.id)
        sendControl(kind: .decline, call: call)
        endLocal(reason: .declined)
    }

    // MARK: - Either side

    func endCall() {
        guard let call = active else { return }
        if !call.isGroup {
            sendControl(kind: .end, call: call)
            postCallEndedSystemMessage(call, connected: call.state == .connected)
        } else if call.direction == .outgoing, call.state == .ringing {
            sendGroupCancel(call)
        }
        endLocal(reason: call.state == .connected ? .completed : .cancelled)
    }

    /// Dismisses the call UI without sending another signal. Used when
    /// the remote side sends us `cancel`, `decline`, or `end`.
    func endLocal(reason: EndReason = .completed) {
        remoteDepartureTask?.cancel()
        remoteDepartureTask = nil
        startOperation = UUID(); isStarting = false
        guard var call = active, call.state != .ended else { return }
        incomingJoinTask?.cancel(); incomingJoinTask = nil
        call.state = .ended
        call.endReason = reason
        active = call
        pendingIncomingCallID = nil
        ringTimeoutTask?.cancel()
        ringTimeoutTask = nil
        incomingRingTimeoutTask?.cancel()
        incomingRingTimeoutTask = nil
        WhisperCallRingtone.shared.stop()
        let shouldLeaveRTC = ownsRTC
        if ownsRTC { detachRTCCallbacks() }
        ownsRTC = false
        spotlightPeerID = nil
        classModeOn = false
        classHostName = nil
        mutedByCoachAt = nil
        if shouldLeaveRTC { Task { await WhisperLiveRTCService.shared.leave() } }
        WhisperNotificationService.shared.clearIncomingCallBanner(callID: call.id)
        let ckReason: CXCallEndedReason
        switch reason {
        case .missed:   ckReason = .unanswered
        case .declined: ckReason = .declinedElsewhere
        default:        ckReason = .remoteEnded
        }
        WhisperVoIPService.shared.reportEnded(callID: call.id, reason: ckReason)
        // Hold the closing frame ("Missed" / "Declined" / "Call ended")
        // long enough to actually read before the window fades out.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reason == .completed ? 800 : 1300))
            if self.active?.id == call.id { self.active = nil }
        }
    }

    // MARK: - Mesh room callbacks

    /// The call service owns the RTC callbacks while a call is active —
    /// meetings and lives set their own when those screens join.
    private func attachRTCCallbacks() {
        ownsRTC = true
        let rtc = WhisperLiveRTCService.shared
        rtc.onAudioRouteChanged = { [weak self] in self?.rtcTick &+= 1 }
        rtc.onParticipantsChanged = { [weak self] in
            guard let self else { return }
            self.rtcTick &+= 1
            self.remotePresenceCheck()
        }
        rtc.onRemoteVideoTrackForPeer = { [weak self] _, _ in
            self?.rtcTick &+= 1
        }
        rtc.onAppEvent = { [weak self] event, data, fromPeerId in
            self?.handleCallAppEvent(event, data: data, fromPeerId: fromPeerId)
        }
        rtc.onPermissionDenied = { [weak self] in
            self?.lastErrorMessage = "Calls need camera & microphone access \u{2014} enable both in Settings."
            self?.endCall()
        }
    }

    private func detachRTCCallbacks() {
        let rtc = WhisperLiveRTCService.shared
        rtc.onAudioRouteChanged = nil
        rtc.onParticipantsChanged = nil
        rtc.onRemoteVideoTrackForPeer = nil
        rtc.onAppEvent = nil
        rtc.onPermissionDenied = nil
    }

    /// Someone appeared in the mesh room. Joining the room IS the accept —
    /// the most reliable signal there is (works even when the `.accept`
    /// realtime row is delayed, and it's how web answers).
    private func remotePresenceCheck() {
        guard var call = active, call.state != .ended else { return }
        let rtc = WhisperLiveRTCService.shared
        let others = rtc.participants.filter { $0.peerId != rtc.localPeerId }
        if !others.isEmpty {
            remoteDepartureTask?.cancel()
            remoteDepartureTask = nil
        } else if call.state == .connected, !call.isGroup, remoteDepartureTask == nil {
            let generation = AccountStorage.generation
            let callID = call.id
            remoteDepartureTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard let self, generation == AccountStorage.generation,
                      self.active?.id == callID, self.active?.state == .connected,
                      !WhisperLiveRTCService.shared.participants.contains(where: { $0.peerId != WhisperLiveRTCService.shared.localPeerId }) else { return }
                self.endLocal(reason: .completed)
            }
        }
        guard call.state == .ringing, !others.isEmpty else { return }
        ringTimeoutTask?.cancel()
        ringTimeoutTask = nil
        WhisperCallRingtone.shared.stop()
        call.state = .connected
        call.startedAt = Date()
        active = call
        WhisperVoIPService.shared.reportConnected(callID: call.id)
        Haptics.success()
    }

    // MARK: - Class (coach) controls

    func classMute(userID: String) {
        WhisperLiveRTCService.shared.sendAppEvent("call-mute", data: ["targetUserId": userID.lowercased()])
    }

    func classMuteAll() {
        WhisperLiveRTCService.shared.sendAppEvent("call-mute-all", data: ["byName": myUsername])
    }

    func classSpotlight(peerID: String?) {
        WhisperLiveRTCService.shared.sendAppEvent("call-spotlight", data: ["peerId": peerID ?? ""])
        spotlightPeerID = peerID
    }

    func setClassMode(_ on: Bool) {
        WhisperLiveRTCService.shared.sendAppEvent("call-class-mode", data: ["on": on, "host": myUsername])
        classModeOn = on
        classHostName = on ? myUsername : nil
    }

    // ── Reactions / hands / class extras (broadcast + local echo — app
    //    events never loop back to their sender) ──────────────────────

    /// Anyone on the call can throw a floating emoji reaction.
    func sendReaction(_ emoji: String) {
        WhisperLiveRTCService.shared.sendAppEvent(
            "call-react",
            data: ["emoji": emoji, "byName": myUsername]
        )
        pushReaction(emoji: emoji, fromName: myUsername)
    }

    var isMyHandRaised: Bool { raisedHands[myUserID.lowercased()] != nil }

    func setHandRaised(_ up: Bool) {
        WhisperLiveRTCService.shared.sendAppEvent(
            "call-hand",
            data: ["up": up, "userId": myUserID.lowercased(), "byName": myUsername]
        )
        applyHand(up: up, userID: myUserID, name: myUsername)
    }

    /// Coach: broadcast a work/rest countdown to everyone on the call.
    func classStartTimer(seconds: Int, label: String, isRest: Bool) {
        let endsAt = Date().addingTimeInterval(TimeInterval(seconds))
        WhisperLiveRTCService.shared.sendAppEvent("call-timer", data: [
            "action": "start",
            "endsAtMs": endsAt.timeIntervalSince1970 * 1000,
            "seconds": seconds,
            "label": label,
            "rest": isRest
        ])
        classTimer = ClassTimer(label: label, endsAt: endsAt, totalSeconds: max(seconds, 1), isRest: isRest)
        Haptics.success()
    }

    func classStopTimer() {
        WhisperLiveRTCService.shared.sendAppEvent("call-timer", data: ["action": "stop"])
        classTimer = nil
    }

    /// Coach: broadcast (or clear) the "now doing" exercise card.
    func classSetExercise(_ text: String?) {
        WhisperLiveRTCService.shared.sendAppEvent("call-exercise", data: ["text": text ?? ""])
        classExercise = (text?.isEmpty == false) ? text : nil
    }

    /// Clears the transient fun/class layer (called when a call connects).
    func resetCallExtras() {
        callReactions = []
        raisedHands = [:]
        classTimer = nil
        classExercise = nil
    }

    private func pushReaction(emoji: String, fromName: String) {
        callReactions.append(CallReaction(id: UUID(), emoji: emoji, fromName: fromName, at: Date()))
        if callReactions.count > 40 {
            callReactions.removeFirst(callReactions.count - 40)
        }
    }

    private func applyHand(up: Bool, userID: String, name: String) {
        if up {
            raisedHands[userID.lowercased()] = name
        } else {
            raisedHands.removeValue(forKey: userID.lowercased())
        }
    }

    private func handleCallAppEvent(_ event: String, data: [String: Any], fromPeerId: String) {
        // This call surface has no verified meeting-host identity or consent UI.
        // Fail closed rather than allowing a meeting recorder to assume approval.
        if ["recording-request-v1", "recording-state-v1", "recording-request-v2", "recording-state-v2"].contains(event) {
            if let id = data["requestId"] as? String, UUID(uuidString: id) != nil,
               WhisperLiveRTCService.shared.participants.contains(where: { $0.peerId == fromPeerId }) {
                WhisperLiveRTCService.shared.sendAppEvent(event.hasSuffix("-v2") ? "recording-reply-v2" : "recording-reply-v1", data: ["requestId": id, "accepted": false])
            }
            return
        }
        switch event {
        case "call-mute":
            guard let target = data["targetUserId"] as? String,
                  target.lowercased() == myUserID.lowercased() else { return }
            WhisperLiveRTCService.shared.setMuted(true)
            mutedByCoachAt = Date()
            rtcTick &+= 1
        case "call-mute-all":
            WhisperLiveRTCService.shared.setMuted(true)
            mutedByCoachAt = Date()
            rtcTick &+= 1
        case "call-spotlight":
            let peer = (data["peerId"] as? String) ?? ""
            spotlightPeerID = peer.isEmpty ? nil : peer
        case "call-class-mode":
            classModeOn = (data["on"] as? Bool) ?? false
            classHostName = data["host"] as? String
        case "call-react":
            let emoji = (data["emoji"] as? String) ?? "\u{2764}\u{FE0F}"
            let name = (data["byName"] as? String) ?? "someone"
            pushReaction(emoji: emoji, fromName: name)
        case "call-hand":
            let up = (data["up"] as? Bool) ?? false
            let uid = (data["userId"] as? String) ?? ""
            let name = (data["byName"] as? String) ?? "someone"
            if !uid.isEmpty {
                applyHand(up: up, userID: uid, name: name)
            }
        case "call-timer":
            if (data["action"] as? String) == "start" {
                let secs = (data["seconds"] as? Int)
                    ?? (data["seconds"] as? Double).map(Int.init)
                    ?? 30
                let label = (data["label"] as? String) ?? "Timer"
                let rest = (data["rest"] as? Bool) ?? false
                let endsAt: Date
                if let ms = data["endsAtMs"] as? Double {
                    endsAt = Date(timeIntervalSince1970: ms / 1000)
                } else {
                    endsAt = Date().addingTimeInterval(TimeInterval(secs))
                }
                classTimer = ClassTimer(label: label, endsAt: endsAt, totalSeconds: max(secs, 1), isRest: rest)
            } else {
                classTimer = nil
            }
        case "call-exercise":
            let text = (data["text"] as? String) ?? ""
            classExercise = text.isEmpty ? nil : text
        default:
            break
        }
    }

    // MARK: - Incoming signal routing

    /// `avatarURL` is passed by the VoIP push path (the payload carries
    /// `sender_avatar_url`) so a cold-launched ring screen paints the
    /// caller's photo + blurred backdrop on first frame. Realtime signal
    /// callers leave it nil and the async profile fetch below fills it.
    func handleSignal(
        _ payload: WhisperCallSignal.Payload,
        fromUserID: String,
        fromUsername: String,
        currentUID: String,
        avatarURL: URL? = nil
    ) {
        let me = currentUID.lowercased()
        guard !me.isEmpty, me == myUserID.lowercased() else { return }
        let from = fromUserID.lowercased()
        if from == me { return }
        if let recipient = payload.toUserId, recipient.lowercased() != me { return }

        switch payload.kind {
        case .invite:
            if WhisperCallSignal.isStaleInvite(payload) { return }
            if var existing = active, existing.id == payload.id {
                if existing.otherUserID.lowercased() == from, existing.state != .ended,
                   let groupID = payload.groupId, UUID(uuidString: groupID) != nil {
                    existing.isGroup = true; existing.groupID = groupID
                    existing.title = payload.groupName ?? "Group call"
                    active = existing
                }
                return
            }
            if active != nil || isStarting || WhisperMeetingWindow.shared.isPresenting || WhisperLiveRTCService.shared.isInUse {
                // Busy — auto-decline the new ring.
                var decline = WhisperCallSignal.Payload(id: payload.id, kind: .decline, mode: payload.mode)
                decline.groupId = payload.groupId
                send(decline, toUserID: fromUserID, toUsername: fromUsername)
                return
            }
            pendingIncomingCallID = payload.id
            if !WhisperVoIPService.shared.isHandlingCall(id: payload.id) {
                WhisperCallRingtone.shared.start(style: .incoming)
            }
            let isGroup = (payload.groupId?.isEmpty == false)
            let callerName = payload.fromUsername ?? fromUsername
            active = ActiveCall(
                id: payload.id,
                roomID: payload.roomID,
                direction: .incoming,
                state: .ringing,
                otherUserID: fromUserID,
                otherUsername: callerName,
                avatarURL: avatarURL,
                mode: payload.mode,
                startedAt: nil,
                isGroup: isGroup,
                groupID: payload.groupId,
                title: isGroup ? (payload.groupName ?? "Group call") : "@\(callerName)",
                endReason: nil
            )
            // Incoming rings expire on their own — if the caller vanishes
            // (network drop, force-quit) the ring must not hang forever.
            startIncomingRingTimeout(callID: payload.id, seconds: 45)
            // Realtime beat the push while the app is backgrounded (or the
            // push never arrived) — surface a proper call banner with
            // Answer/Decline actions so the ring isn't silent. When the
            // VoIP push won the race, CallKit already owns the screen.
            if UIApplication.shared.applicationState != .active,
               !WhisperVoIPService.shared.isHandlingCall(id: payload.id) {
                WhisperNotificationService.shared.notifyIncomingCall(
                    callID: payload.id,
                    fromUID: fromUserID,
                    fromUsername: callerName,
                    isVideo: payload.mode == .video,
                    avatarURL: avatarURL,
                    invite: payload
                )
            }
            Task { [weak self] in
                guard let self else { return }
                let profile = await WhisperBackendService.shared.fetchPublicProfile(userID: fromUserID)
                let url = profile?.profile_image_url.flatMap(URL.init(string:))
                if var c = self.active, c.id == payload.id, c.avatarURL == nil {
                    c.avatarURL = url
                    self.active = c
                }
            }

        case .accept:
            guard var call = active, call.id == payload.id, call.direction == .outgoing, call.state == .ringing else { return }
            ringTimeoutTask?.cancel()
            ringTimeoutTask = nil
            WhisperCallRingtone.shared.stop()
            // Room presence will also flip us — belt-and-suspenders for
            // slow mesh joins.
            call.state = .connected
            if call.startedAt == nil { call.startedAt = Date() }
            active = call
            WhisperVoIPService.shared.reportConnected(callID: call.id)

        case .decline, .cancel:
            guard let call = active, call.id == payload.id else { return }
            // A single decline never ends a group ring — other members may
            // still pick up.
            if call.isGroup {
                guard payload.kind == .cancel, call.state == .ringing,
                      call.direction == .incoming, from == call.otherUserID.lowercased() else { return }
            }
            if call.direction == .outgoing && call.state == .ringing && !call.isGroup {
                postCallEndedSystemMessage(call, connected: false)
            }
            // Caller cancelled while we were still ringing → that's a
            // missed call on this side. Surface it like Instagram: banner
            // notification that deep-links back into the thread.
            if call.direction == .incoming, call.state == .ringing, payload.kind == .cancel {
                WhisperNotificationService.shared.notifyMissedCall(
                    callID: call.id,
                    fromUID: call.otherUserID,
                    fromUsername: call.otherUsername,
                    isVideo: call.mode == .video,
                    avatarURL: call.avatarURL,
                    groupID: call.groupID, groupName: call.isGroup ? call.title : nil
                )
                endLocal(reason: .missed)
            } else if call.direction == .outgoing, call.state == .ringing {
                endLocal(reason: payload.kind == .decline ? .declined : .missed)
            } else {
                endLocal(reason: call.state == .connected ? .completed : .cancelled)
            }

        case .end:
            guard let call = active, call.id == payload.id else { return }
            // Connected group calls end when the ROOM empties, not when one
            // member hangs up.
            if call.isGroup, call.state == .connected { return }
            endLocal(reason: call.state == .connected ? .completed : .cancelled)

        case .ice:
            // Legacy WebRTC signaling — the mesh handles ICE internally.
            return
        }
    }

    // MARK: - Media control passthrough

    func setMuted(_ muted: Bool) { WhisperLiveRTCService.shared.setMuted(muted) }

    /// Routes through the RTC service's speaker preference so the route
    /// enforcement (which re-asserts the speaker whenever WebRTC's audio
    /// unit re-activates the session) respects the user's choice.
    func setSpeaker(_ on: Bool) {
        WhisperLiveRTCService.shared.setSpeakerPreferred(on)
    }

    /// Three-way output routing: speaker, ear receiver, or Bluetooth.
    func setAudioRoute(_ route: WhisperAudioRoute) {
        WhisperLiveRTCService.shared.setAudioRoute(route)
    }

    var audioRoute: WhisperAudioRoute { WhisperLiveRTCService.shared.audioRoute }

    func setCameraEnabled(_ enabled: Bool) { WhisperLiveRTCService.shared.setCameraEnabled(enabled) }
    func switchCamera() { WhisperLiveRTCService.shared.switchCamera() }

    // MARK: - Send

    /// Invites carry the web-parity fields (`meetingId`, `fromUserId`, …)
    /// so the web client's IncomingCallWatcher rings too. Control signals
    /// stay lean — the web treats any payload with those fields as a ring,
    /// so accept/decline/end must NOT include them.
    private func sendInvite(
        callID: String,
        roomID: String,
        mode: WhisperCallSignal.Mode,
        toUserID: String,
        toUsername: String,
        groupID: String?,
        groupName: String?
    ) {
        var payload = WhisperCallSignal.Payload(id: callID, kind: .invite, mode: mode)
        payload.meetingId = roomID
        payload.fromUserId = myUserID.lowercased()
        payload.fromUsername = myUsername
        payload.toUserId = toUserID.lowercased()
        payload.at = Date().timeIntervalSince1970 * 1000
        payload.groupId = groupID
        payload.groupName = groupName
        send(payload, toUserID: toUserID, toUsername: toUsername)
    }

    private func sendControl(kind: WhisperCallSignal.Kind, call: ActiveCall) {
        guard !call.otherUserID.isEmpty else { return }
        var payload = WhisperCallSignal.Payload(id: call.id, kind: kind, mode: call.mode)
        payload.groupId = call.groupID
        send(payload, toUserID: call.otherUserID, toUsername: call.otherUsername)
    }

    private func sendGroupCancel(_ call: ActiveCall) {
        guard let gid = call.groupID.flatMap(UUID.init(uuidString:)),
              let group = WhisperGroupChatService.shared.group(byID: gid) else { return }
        for member in group.members {
            var payload = WhisperCallSignal.Payload(id: call.id, kind: .cancel, mode: call.mode)
            payload.groupId = call.groupID
            send(payload, toUserID: member.user_id, toUsername: member.username)
        }
    }

    private func send(
        _ payload: WhisperCallSignal.Payload,
        toUserID: String,
        toUsername: String
    ) {
        let body = WhisperCallSignal.encode(payload)
        let generation = AccountStorage.generation
        let owner = myUserID.lowercased()
        guard !body.isEmpty else { return }
        Task {
            guard generation == AccountStorage.generation, owner == myUserID.lowercased() else { return }
            _ = await WhisperBackendService.shared.sendMessage(
                toUserID: toUserID,
                toUsername: toUsername,
                body: body
            )
        }
    }

    private func startRingTimeout(callID: String, seconds: Double) {
        ringTimeoutTask?.cancel()
        ringTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            guard let self,
                  let call = self.active,
                  call.id == callID,
                  call.state == .ringing,
                  call.direction == .outgoing
            else { return }
            if call.isGroup {
                self.sendGroupCancel(call)
            } else {
                self.sendControl(kind: .cancel, call: call)
                self.postCallEndedSystemMessage(call, connected: false)
            }
            self.endLocal(reason: .missed)
        }
    }

    /// Incoming rings auto-expire: if nobody answers and no cancel arrives
    /// (caller offline / crashed), the ring dies on its own and lands in
    /// missed-call state — never a zombie ring screen.
    private func startIncomingRingTimeout(callID: String, seconds: Double) {
        incomingRingTimeoutTask?.cancel()
        incomingRingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            guard let self,
                  let call = self.active,
                  call.id == callID,
                  call.state == .ringing,
                  call.direction == .incoming
            else { return }
            WhisperNotificationService.shared.notifyMissedCall(
                callID: call.id,
                fromUID: call.otherUserID,
                fromUsername: call.otherUsername,
                isVideo: call.mode == .video,
                avatarURL: call.avatarURL,
                groupID: call.groupID, groupName: call.isGroup ? call.title : nil
            )
            self.endLocal(reason: .missed)
        }
    }

    private func postCallEndedSystemMessage(_ call: ActiveCall, connected: Bool) {
        guard !call.isGroup, !call.otherUserID.isEmpty else { return }
        let secs: Int
        if let started = call.startedAt {
            secs = max(0, Int(Date().timeIntervalSince(started)))
        } else {
            secs = 0
        }
        let payload = WhisperCallSummaryEmbed.Payload(
            id: UUID().uuidString,
            mode: call.mode.rawValue,
            durationSeconds: secs,
            connected: connected
        )
        let body = WhisperCallSummaryEmbed.encode(payload)
        guard !body.isEmpty else { return }
        Task {
            _ = await WhisperBackendService.shared.sendMessage(
                toUserID: call.otherUserID,
                toUsername: call.otherUsername,
                body: body
            )
        }
    }
}
