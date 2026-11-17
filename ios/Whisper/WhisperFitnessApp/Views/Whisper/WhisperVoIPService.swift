import Foundation
import UIKit
import PushKit
import CallKit
import AVFoundation
import WebRTC
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_voip_tokens (
//   token text primary key,
//   user_id uuid not null references auth.users(id) on delete cascade,
//   bundle_id text,
//   environment text not null default 'sandbox',
//   created_at timestamptz not null default now(),
//   updated_at timestamptz not null default now()
// );
// create index if not exists whisper_voip_tokens_user_idx
//   on public.whisper_voip_tokens (user_id);
// alter table public.whisper_voip_tokens enable row level security;
// create policy "wvt upsert own" on public.whisper_voip_tokens
//   for insert with check (auth.uid() = user_id);
// create policy "wvt update own" on public.whisper_voip_tokens
//   for update using (auth.uid() = user_id);
// create policy "wvt delete own" on public.whisper_voip_tokens
//   for delete using (auth.uid() = user_id);
// create policy "wvt read own"   on public.whisper_voip_tokens
//   for select using (auth.uid() = user_id);

extension Notification.Name {
    /// Posted when the user ends a Whisper call/meeting from the SYSTEM
    /// call UI (lock screen, Dynamic Island) rather than in-app — screens
    /// hosting the media (meeting room) listen and close themselves.
    static let whisperCallKitEndedExternally = Notification.Name("WhisperCallKitEndedExternally")
}

nonisolated struct WhisperVoIPTokenUpsert: Codable, Sendable {
    let token: String
    let user_id: String
    let bundle_id: String?
    let environment: String
}

nonisolated struct WhisperVoIPTokenClaim: Codable, Sendable {
    let p_token: String
    let p_bundle_id: String?
    let p_environment: String
}

/// Registers the device for VoIP PushKit pushes (the only legal way to wake
/// the app from a terminated state for an inbound call on modern iOS) and
/// bridges incoming pushes to CallKit + the existing `WhisperCallService`.
///
/// The PushKit token is uploaded to `whisper_voip_tokens`. The push-fanout
/// edge function reads that table when it sees a call `invite` signal and
/// posts to APNs with `apns-push-type: voip` and topic `<bundleID>.voip`.
///
/// When iOS delivers the push we MUST call
/// `CXProvider.reportNewIncomingCall` synchronously inside
/// `pushRegistry(_:didReceiveIncomingPushWith:for:completion:)` — otherwise
/// iOS will terminate the app. We then inject the invite into
/// `WhisperCallService` so the existing SwiftUI + WebRTC pipeline picks it
/// up exactly like a foreground realtime invite.
@MainActor
final class WhisperVoIPService: NSObject {
    static let shared = WhisperVoIPService()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var pushRegistry: PKPushRegistry?
    private let client = SupabaseService.shared.client
    private var lastUploadedToken: String?

    /// Maps CallKit's per-call UUID to the WhisperCallService string id so
    /// we can translate CXEnd/CXAnswer actions back into call-service calls.
    private var uuidToCallID: [UUID: String] = [:]
    private var callIDToUUID: [String: UUID] = [:]

    /// True if a call we're tracking has reached CallKit. The call service
    /// uses this to suppress its in-app synthetic ringtone so we don't
    /// double-ring on top of CallKit's system ringer.
    func isHandlingCall(id: String) -> Bool {
        callIDToUUID[id] != nil
    }

    /// Tracks call_ids we've already surfaced to CallKit so retransmitted
    /// VoIP pushes (the caller fires the same invite multiple times for
    /// delivery reliability) don't show 7 separate incoming-call UIs.
    /// Kept for a few minutes so a brand-new call after a hangup with the
    /// same id (shouldn't happen, but defensively) can still ring.
    private var recentlyHandledCallIDs: [String: Date] = [:]
    private let dedupeWindow: TimeInterval = 120

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    override private init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = true
        if let logo = UIImage(named: "WhisperLogo") {
            let format = UIGraphicsImageRendererFormat()
            format.opaque = false
            format.scale = 2
            let template = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40), format: format).image { _ in
                let height = 36 * logo.size.height / max(1, logo.size.width)
                logo.draw(in: CGRect(x: 2, y: (40 - height) / 2, width: 36, height: height))
            }
            config.iconTemplateImageData = template.pngData()
        }
        self.provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    /// Call once at launch, after AuthenticationService is wired up.
    func start() {
        guard pushRegistry == nil else { return }
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        pushRegistry = registry
    }

    /// Re-uploads the cached VoIP token (if any) for the currently signed-in
    /// user. Safe to call after sign-in.
    func registerIfNeeded() async {
        guard isRemote else { return }
        guard let token = UserDefaults.standard.string(forKey: "whisper.voipToken"),
              !token.isEmpty else { return }
        await upload(token: token)
    }

    /// Detach this device's VoIP token on sign-out.
    func unregister() async {
        guard isRemote,
              let token = UserDefaults.standard.string(forKey: "whisper.voipToken"),
              !token.isEmpty else { return }
        do {
            try await client.from("whisper_voip_tokens")
                .delete()
                .eq("token", value: token)
                .eq("user_id", value: currentUID)
                .execute()
            lastUploadedToken = nil
        } catch {
            print("[Whisper] voip token unregister failed: \(error)")
        }
    }

    private var lastUploadedUID: String?

    private func upload(token: String) async {
        guard isRemote else { return }
        let uid = currentUID
        if lastUploadedToken == token && lastUploadedUID == uid { return }
        // Environment comes from the provisioning profile, NOT #if DEBUG —
        // Release-config dev-signed installs still get SANDBOX VoIP tokens.
        let environment = WhisperPushService.apnsEnvironmentIsSandbox() ? "sandbox" : "production"
        let bundleID = Bundle.main.bundleIdentifier

        // Claim the token for the CURRENT account (a previous sign-in on
        // this device may own the row; RLS blocks a plain upsert from
        // reassigning it, which would ring the wrong account).
        do {
            try await client.rpc(
                "whisper_claim_voip_token",
                params: WhisperVoIPTokenClaim(
                    p_token: token,
                    p_bundle_id: bundleID,
                    p_environment: environment
                )
            ).execute()
            lastUploadedToken = token
            lastUploadedUID = uid
            return
        } catch {
            print("[Whisper] voip claim rpc unavailable, falling back to upsert: \(error)")
        }

        let payload = WhisperVoIPTokenUpsert(
            token: token,
            user_id: uid,
            bundle_id: bundleID,
            environment: environment
        )
        do {
            try await client.from("whisper_voip_tokens")
                .upsert(payload, onConflict: "token")
                .execute()
            lastUploadedToken = token
            lastUploadedUID = uid
        } catch {
            print("[Whisper] voip token upload failed: \(error)")
        }
    }

    // MARK: - CallKit bridging

    /// Reports a hang-up to CallKit when the call ends through the in-app
    /// UI (so the system call screen / Recents stay in sync). Safe to call
    /// for calls we never surfaced through CallKit — it just no-ops.
    func reportEnded(callID: String, reason: CXCallEndedReason = .remoteEnded) {
        guard let uuid = callIDToUUID[callID] else { return }
        provider.reportCall(with: uuid, endedAt: nil, reason: reason)
        callIDToUUID.removeValue(forKey: callID)
        uuidToCallID.removeValue(forKey: uuid)
        // Keep the dedupe entry so late-arriving retransmits don't re-ring.
    }

    private func prunePushDedupe() {
        let cutoff = Date().addingTimeInterval(-dedupeWindow)
        recentlyHandledCallIDs = recentlyHandledCallIDs.filter { $0.value > cutoff }
    }

    /// Reports a connected state to CallKit so the call timer starts.
    func reportConnected(callID: String) {
        guard let uuid = callIDToUUID[callID] else { return }
        provider.reportOutgoingCall(with: uuid, connectedAt: nil)
    }

    /// Call ids (meetings) that should flip straight to connected the moment
    /// CallKit performs the start action — they have no ring phase.
    private var autoConnectCallIDs: Set<String> = []

    /// True while a CXAnswerCallAction is being performed, so the in-app
    /// answer path doesn't request a second (looping) answer transaction.
    private(set) var performingCallKitAnswer = false

    /// Registers an OUTGOING call (or a live meeting) with CallKit so iOS
    /// keeps the mic, audio, and networking alive when the app backgrounds
    /// mid-call — and the system shows the green call indicator. Without
    /// this, iOS suspends the app seconds after backgrounding and the call
    /// audio dies.
    func startOutgoingCall(
        callID: String,
        displayName: String,
        video: Bool,
        connectedImmediately: Bool = false
    ) {
        guard callIDToUUID[callID] == nil else { return }
        let uuid = UUID()
        uuidToCallID[uuid] = callID
        callIDToUUID[callID] = uuid
        recentlyHandledCallIDs[callID] = Date()
        if connectedImmediately { autoConnectCallIDs.insert(callID) }
        let action = CXStartCallAction(call: uuid, handle: CXHandle(type: .generic, value: displayName))
        action.isVideo = video
        callController.request(CXTransaction(action: action)) { [weak self] error in
            guard let error else { return }
            print("[Whisper] CXStartCallAction failed: \(error)")
            Task { @MainActor in
                guard let self else { return }
                self.uuidToCallID.removeValue(forKey: uuid)
                self.callIDToUUID.removeValue(forKey: callID)
                self.autoConnectCallIDs.remove(callID)
            }
        }
    }

    /// The user answered through the in-app ring UI while CallKit was also
    /// showing this call (VoIP push path) — flip the system call screen to
    /// connected instead of letting it keep ringing.
    func syncAnswerToCallKit(callID: String) {
        guard !performingCallKitAnswer, let uuid = callIDToUUID[callID] else { return }
        callController.request(CXTransaction(action: CXAnswerCallAction(call: uuid))) { error in
            if let error {
                print("[Whisper] CXAnswerCallAction sync failed: \(error)")
            }
        }
    }
}

// MARK: - PKPushRegistryDelegate

extension WhisperVoIPService: PKPushRegistryDelegate {
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let token = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
        Task { @MainActor in
            UserDefaults.standard.set(token, forKey: "whisper.voipToken")
            await self.upload(token: token)
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        Task { @MainActor in
            UserDefaults.standard.removeObject(forKey: "whisper.voipToken")
        }
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else { completion(); return }
        let dict = payload.dictionaryPayload
        let callID = (dict["call_id"] as? String) ?? UUID().uuidString
        let fromUserID = (dict["from_user_id"] as? String) ?? ""
        let fromUsername = (dict["from_username"] as? String) ?? "Unknown"
        let modeRaw = (dict["mode"] as? String) ?? "audio"
        let isVideo = modeRaw == "video"
        // Caller avatar rides in the VoIP payload so the in-app ring screen
        // can paint the photo + blurred backdrop IMMEDIATELY on a cold
        // launch — the profile fetch fallback needs network + session and
        // lags several seconds behind first render.
        let avatarURLString = (dict["sender_avatar_url"] as? String) ?? ""
        var metadata: [String: String] = [:]
        for key in ["call_id", "from_user_id", "from_username", "mode", "meeting_id", "group_id", "group_name", "recipient_user_id", "at"] {
            if let value = dict[key] as? String { metadata[key] = value }
            else if let number = dict[key] as? NSNumber { metadata[key] = number.stringValue }
        }

        // CRITICAL: must call reportNewIncomingCall synchronously on the
        // same runloop tick as the push delivery, or iOS will terminate
        // the app. PKPushRegistry is initialised with `queue: .main`, so
        // this delegate already runs on main — assume that isolation and
        // surface synchronously rather than hopping through a Task.
        MainActor.assumeIsolated {
            self.surfaceIncoming(
                callID: callID,
                fromUserID: fromUserID,
                fromUsername: fromUsername,
                modeRaw: modeRaw,
                isVideo: isVideo,
                avatarURLString: avatarURLString,
                metadata: metadata,
                completion: completion
            )
        }
    }

    @MainActor
    private func surfaceIncoming(
        callID: String,
        fromUserID: String,
        fromUsername: String,
        modeRaw: String,
        isVideo: Bool,
        avatarURLString: String = "",
        metadata: [String: String] = [:],
        completion: @escaping () -> Void
    ) {
        // iOS TERMINATES apps that receive a VoIP push without posting an
        // incoming call — EVERY push must report to CallKit, including the
        // caller's delivery-reliability retransmits. Duplicates are
        // re-reported benignly instead of silently completed.
        prunePushDedupe()
        if let existingUUID = callIDToUUID[callID] {
            // Same call still live: re-reporting the same UUID fails with
            // .callUUIDAlreadyExists — no second ring, requirement met.
            let update = CXCallUpdate()
            update.remoteHandle = CXHandle(type: .generic, value: "@\(fromUsername)")
            update.localizedCallerName = metadata["group_name"] ?? "@\(fromUsername)"
            update.hasVideo = isVideo
            provider.reportNewIncomingCall(with: existingUUID, update: update) { _ in
                completion()
            }
            return
        }
        if recentlyHandledCallIDs[callID] != nil {
            // Call already answered/ended: report a throwaway call and end
            // it immediately so the requirement is met without ringing.
            let ghost = UUID()
            let update = CXCallUpdate()
            update.remoteHandle = CXHandle(type: .generic, value: "@\(fromUsername)")
            update.localizedCallerName = metadata["group_name"] ?? "@\(fromUsername)"
            provider.reportNewIncomingCall(with: ghost, update: update) { [weak self] _ in
                self?.provider.reportCall(with: ghost, endedAt: nil, reason: .answeredElsewhere)
                completion()
            }
            return
        }
        let uuid = UUID()
        uuidToCallID[uuid] = callID
        callIDToUUID[callID] = uuid
        recentlyHandledCallIDs[callID] = Date()
        // CallKit's system ringer takes over from here — if the realtime
        // signal beat this push and started the in-app ringtone, stop it
        // so the phone doesn't ring twice at once.
        WhisperCallRingtone.shared.stop()

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: "@\(fromUsername)")
        update.localizedCallerName = metadata["group_name"] ?? "@\(fromUsername)"
        update.hasVideo = isVideo
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        // Inject into the existing call service FIRST so the in-app
        // SwiftUI cover lights up immediately — if we wait until after
        // reportNewIncomingCall's completion, the in-app answer sheet
        // can race the CallKit UI and never appear when the app is
        // already foregrounded.
        let mode: WhisperCallSignal.Mode = isVideo ? .video : .audio
        let signalPayload = WhisperCallSignal.pushInvite(metadata)
            ?? WhisperCallSignal.Payload(id: callID, kind: .invite, mode: mode)
        WhisperCallService.shared.handleSignal(
            signalPayload,
            fromUserID: fromUserID,
            fromUsername: fromUsername,
            currentUID: AccountStorage.currentUserID,
            avatarURL: avatarURLString.isEmpty ? nil : URL(string: avatarURLString)
        )
        let admitted = WhisperCallService.shared.active?.id == callID && WhisperCallService.shared.active?.state != .ended
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if error != nil || !admitted {
                if error == nil { self?.provider.reportCall(with: uuid, endedAt: nil, reason: .failed) }
                self?.uuidToCallID.removeValue(forKey: uuid)
                self?.callIDToUUID.removeValue(forKey: callID)
                if error != nil { self?.recentlyHandledCallIDs.removeValue(forKey: callID) }
            }
            completion()
        }
    }
}

// MARK: - CXProviderDelegate

extension WhisperVoIPService: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in
            self.uuidToCallID.removeAll()
            self.callIDToUUID.removeAll()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        Task { @MainActor in
            let callID = self.uuidToCallID[action.callUUID]
            let isSocialCall = callID != nil && WhisperCallService.shared.active?.id == callID
            self.configureAudioSession(video: action.isVideo, receiverFirst: isSocialCall)
            provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
            if let cid = self.uuidToCallID[action.callUUID], self.autoConnectCallIDs.contains(cid) {
                self.autoConnectCallIDs.remove(cid)
                provider.reportOutgoingCall(with: action.callUUID, connectedAt: nil)
            }
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in
            // Configure the audio session BEFORE answering so WebRTC has a
            // session it can attach to. Use the video chat mode when the
            // current call carries video so the system picks the right
            // routing / echo cancellation profile.
            guard let callID = self.uuidToCallID[action.callUUID],
                  let call = WhisperCallService.shared.active, call.id == callID,
                  call.direction == .incoming, call.state != .ended else {
                action.fail()
                return
            }
            if call.state == .connected { action.fulfill(); return }
            guard !WhisperLiveRTCService.shared.isInUse, !WhisperMeetingWindow.shared.isPresenting else { action.fail(); return }
            let isVideo = call.mode == .video
            self.configureAudioSession(video: isVideo, receiverFirst: true)
            self.performingCallKitAnswer = true
            WhisperCallService.shared.answerIncoming()
            self.performingCallKitAnswer = false
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            // Drop the uuid mapping FIRST so the mirrored decline/end below
            // doesn't circle back through reportEnded for a call CallKit is
            // already tearing down via this very action.
            let uuid = action.callUUID
            let endedCallID = self.uuidToCallID.removeValue(forKey: uuid)
            if let endedCallID {
                self.callIDToUUID.removeValue(forKey: endedCallID)
                self.autoConnectCallIDs.remove(endedCallID)
            }
            // Mirror the system Decline/End into the app's call service.
            // For an incoming call that's still ringing this is semantically
            // a `decline` (so the caller sees a "Declined" bubble); for a
            // connected call (or our own outgoing) it's a regular hangup.
            if let call = WhisperCallService.shared.active,
               call.id == endedCallID {
                if call.direction == .incoming && call.state == .ringing {
                    WhisperCallService.shared.declineIncoming()
                } else {
                    WhisperCallService.shared.endCall()
                }
            } else if let endedCallID, let meeting = WhisperMeetingWindow.shared.meeting,
                      endedCallID == "meeting:\(meeting.id)", WhisperCallService.shared.active == nil {
                // A meeting ended from the system call UI (lock screen /
                // Dynamic Island) — leave the room and tell the meeting
                // screen to close itself.
                await WhisperLiveRTCService.shared.leave()
                NotificationCenter.default.post(
                    name: .whisperCallKitEndedExternally,
                    object: nil,
                    userInfo: ["callID": endedCallID]
                )
            }
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor in
            WhisperCallService.shared.setMuted(action.isMuted)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // Hand the CallKit-activated session to WebRTC (manual-audio mode)
        // so the audio unit spins up even for lock-screen answers, where
        // CallKit — not the app — owns session activation.
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
    }

    @MainActor
    private func configureAudioSession(video: Bool = false, receiverFirst: Bool = false) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: receiverFirst ? .voiceChat : (video ? .videoChat : .voiceChat),
                options: receiverFirst ? [.allowBluetoothHFP, .allowBluetoothA2DP] : [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true, options: [])
            if receiverFirst { try session.overrideOutputAudioPort(.none) }
        } catch {
            print("[Whisper] audio session config failed: \(error)")
        }
    }
}
