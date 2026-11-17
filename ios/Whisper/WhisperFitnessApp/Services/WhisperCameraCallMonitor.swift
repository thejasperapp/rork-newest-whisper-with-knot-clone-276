import AVFoundation
import CallKit
import Observation

/// Observe system and in-app calls without activating or reconfiguring their audio session.
@MainActor @Observable
final class WhisperCameraCallMonitor: NSObject, CXCallObserverDelegate {
    static let shared = WhisperCameraCallMonitor()
    static let changed = Notification.Name("WhisperCameraCallOwnershipChanged")
    private(set) var hasSystemCall: Bool = false
    private var appMediaInUse: Bool = false
    private let observer = CXCallObserver()

    var callOwnsAudio: Bool { hasSystemCall || appMediaInUse }

    private override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
        hasSystemCall = observer.calls.contains { !$0.hasEnded }
    }

    func setAppMediaInUse(_ inUse: Bool) {
        guard appMediaInUse != inUse else { return }
        appMediaInUse = inUse
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let active = self.observer.calls.contains { !$0.hasEnded }
            guard self.hasSystemCall != active else { return }
            self.hasSystemCall = active
            NotificationCenter.default.post(name: Self.changed, object: nil)
        }
    }
}
