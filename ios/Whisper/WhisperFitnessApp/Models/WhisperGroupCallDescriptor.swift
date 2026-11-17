import Foundation

/// Versioned call identity stored on the existing room, not inferred from a meeting title.
nonisolated struct WhisperGroupCallDescriptor: Codable, Equatable, Sendable {
    let callID: String
    let roomID: String
    let groupID: String
    let groupName: String
    let mode: WhisperCallSignal.Mode
    static let prefix = "::whisper-group-call-v1::"

    var encoded: String? {
        guard let data = try? JSONEncoder().encode(self), let json = String(data: data, encoding: .utf8) else { return nil }
        return Self.prefix + json
    }
    static func decode(_ value: String?) -> Self? {
        guard let value, value.hasPrefix(prefix), value.utf8.count < 4096,
              let data = String(value.dropFirst(prefix.count)).data(using: .utf8),
              let result = try? JSONDecoder().decode(Self.self, from: data),
              UUID(uuidString: result.callID) != nil, UUID(uuidString: result.roomID) != nil,
              UUID(uuidString: result.groupID) != nil, !result.groupName.isEmpty, result.groupName.count <= 160 else { return nil }
        return result
    }
}
