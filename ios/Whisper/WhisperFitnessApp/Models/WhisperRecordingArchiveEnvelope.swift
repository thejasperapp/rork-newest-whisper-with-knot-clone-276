import Foundation

/// Database identity remains pageable even when an older snapshot needs repair.
nonisolated struct WhisperRecordingArchiveEnvelope: Decodable, Sendable {
    let id: String
    let created_at: String
    let archive: WhisperRecordingArchive?
    private enum CodingKeys: String, CodingKey { case id, created_at }
    init(from decoder: Decoder) throws {
        let identity = try decoder.container(keyedBy: CodingKeys.self)
        id = try identity.decode(String.self, forKey: .id)
        created_at = try identity.decode(String.self, forKey: .created_at)
        archive = try? WhisperRecordingArchive(from: decoder)
    }
}
