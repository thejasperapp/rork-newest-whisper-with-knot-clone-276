import SwiftUI
import Observation

/// Compatibility for existing presentation bindings. Decorative awards are retired;
/// stored awards and paid entitlements are not changed.
@Observable @MainActor
final class WhisperBadgeAwardService {
    static let shared = WhisperBadgeAwardService()
    var pendingAward: PendingAward?
    private init() {}
    struct PendingAward: Identifiable, Equatable {
        let kind: WhisperBadgeKind
        var id: String { kind.storageKey }
    }
    func hasSeen(_ kind: WhisperBadgeKind) -> Bool { true }
    func markSeen(_ kind: WhisperBadgeKind) { pendingAward = nil }
    func evaluate() { pendingAward = nil }
}
