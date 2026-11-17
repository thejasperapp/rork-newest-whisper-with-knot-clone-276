import Foundation
import Observation

/// Participant-only consent for a web-host recording. This never captures iPhone call audio.
@MainActor @Observable
final class WhisperRecordingConsentService {
    static let shared = WhisperRecordingConsentService()
    private(set) var requestID: String?
    private(set) var recorderPeerID: String?
    private(set) var recorderName: String = "The host"
    private(set) var includesVideo: Bool = false
    private(set) var includesCloudAI: Bool = false
    private(set) var includesCloudArchive: Bool = false
    private(set) var accepted: Bool?
    private(set) var isRecording: Bool = false
    private(set) var notice: String?
    var showPrompt: Bool = false
    @ObservationIgnored private var lastHeard: Date = .distantPast
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var accountGeneration: UUID = AccountStorage.generation

    var hasStatus: Bool { requestID != nil || notice != nil }

    func reset() {
        reply(false)
        watchdog?.cancel(); watchdog = nil
        requestID = nil; recorderPeerID = nil; accepted = nil; isRecording = false; notice = nil; showPrompt = false
        includesVideo = false; includesCloudAI = false; includesCloudArchive = false
        accountGeneration = AccountStorage.generation
    }

    func reconcile(hostID: String) {
        guard let peerID = recorderPeerID else { return }
        let present = WhisperLiveRTCService.shared.participants.contains { $0.peerId == peerID && $0.userId.lowercased() == hostID.lowercased() }
        if !present || accountGeneration != AccountStorage.generation { reset() }
    }

    @discardableResult func receive(_ event: String, data: [String: Any], from peerID: String, hostID: String) -> Bool {
        guard event.hasPrefix("recording-") else { return false }
        guard accountGeneration == AccountStorage.generation,
              let sender = WhisperLiveRTCService.shared.participants.first(where: { $0.peerId == peerID }),
              sender.userId.lowercased() == hostID.lowercased(),
              let id = data["requestId"] as? String, UUID(uuidString: id) != nil else { return true }
        if event == "recording-request-v1" || event == "recording-state-v1" {
            WhisperLiveRTCService.shared.sendAppEvent("recording-reply-v1", data: ["requestId": id, "accepted": false])
            return true
        }
        if event == "recording-request-v2" {
            guard let video = data["video"] as? Bool, let cloud = data["transcribe"] as? Bool, let archive = data["archive"] as? Bool else { return true }
            if requestID == id, recorderPeerID == peerID {
                lastHeard = Date()
                if includesVideo != video || includesCloudAI != cloud || includesCloudArchive != archive { reply(false); return true }
                if let accepted { sendReply(id: id, accepted: accepted) }
                return true
            }
            reset()
            requestID = id; recorderPeerID = peerID; recorderName = String(sender.name.prefix(100))
            includesVideo = video; includesCloudAI = cloud; includesCloudArchive = archive; lastHeard = Date(); showPrompt = true
            WhisperMeetingWindow.shared.restore()
            watchdog = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                    guard let self, requestID != nil else { return }
                    if accountGeneration != AccountStorage.generation { reset(); return }
                    if Date().timeIntervalSince(lastHeard) > 15 {
                        reset()
                        notice = "Recording status connection lost. Permission withdrawn; check with the host before continuing."
                        return
                    }
                }
            }
        } else if event == "recording-state-v2" {
            guard let active = data["active"] as? Bool else { return true }
            guard requestID == id, recorderPeerID == peerID else {
                if active {
                    sendReply(id: id, accepted: false)
                    notice = "The host announced recording without your permission. A stop request was sent; leave if it continues."
                    WhisperMeetingWindow.shared.restore()
                }
                return true
            }
            if !active { reset() }
            else {
                guard let video = data["video"] as? Bool, let cloud = data["transcribe"] as? Bool,
                      let archive = data["archive"] as? Bool,
                      video == includesVideo, cloud == includesCloudAI, archive == includesCloudArchive else {
                    reply(false)
                    notice = "Recording scope changed. Permission withdrawn; ask the host for a new request."
                    return true
                }
                isRecording = true; lastHeard = Date(); sendReply(id: id, accepted: accepted == true)
            }
        }
        return true
    }

    func reply(_ allow: Bool) {
        guard let id = requestID else { return }
        let value = allow && accountGeneration == AccountStorage.generation && Date().timeIntervalSince(lastHeard) <= 15
        accepted = value; showPrompt = false
        sendReply(id: id, accepted: value)
    }

    func withdrawForBackground() {
        guard requestID != nil else { return }
        reply(false)
        notice = "Recording permission withdrawn while Whisper is in the background. Ask the host to request it again when you return."
    }

    private func sendReply(id: String, accepted: Bool) {
        WhisperLiveRTCService.shared.sendAppEvent("recording-reply-v2", data: ["requestId": id, "accepted": accepted])
    }
}
