import Foundation

/// Conversation context is carried by the stored thread identity, never inferred from message text or a local label.
nonisolated enum WhisperConversationKind: String, Codable, CaseIterable, Sendable {
    case direct
    case dating

    func threadID(_ first: String, _ second: String) -> String {
        if self == .direct { return WhisperBackendService.deterministicThreadID(first, second) }
        return WhisperBackendService.deterministicThreadID("dating-v1:" + first.lowercased(), "dating-v1:" + second.lowercased())
    }

    func localKey(peer: String) -> String {
        self == .direct ? peer.lowercased() : "dating:" + peer.lowercased()
    }

    static func resolve(threadID: String?, first: String, second: String) -> Self {
        guard let threadID else { return .direct }
        return threadID.lowercased() == Self.dating.threadID(first, second) ? .dating : .direct
    }
}
