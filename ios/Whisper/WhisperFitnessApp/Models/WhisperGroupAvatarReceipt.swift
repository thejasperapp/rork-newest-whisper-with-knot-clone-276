import Foundation

/// A picture acknowledgment must not depend on unrelated roster fields decoding.
nonisolated struct WhisperGroupAvatarReceipt: Decodable, Sendable {
    let id: UUID
    let avatar_path: String?
}
