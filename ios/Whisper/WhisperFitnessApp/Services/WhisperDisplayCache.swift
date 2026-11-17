import Foundation

/// Account-scoped local snapshots for the owner's profile. Encoding stays off the UI actor.
@MainActor
enum WhisperDisplayCache {
    static let profileKey = "whisper.display.profile.v1"
    static let ownPostsKey = "whisper.display.own-posts.v1"
    private static let maximumBytes = 512 * 1024
    private static var revisions: [String: UUID] = [:]

    static func invalidate(key: String) {
        revisions[AccountStorage.key(key)] = UUID()
        AccountStorage.removeObject(forKey: key)
    }

    private static func canUse(owner: String, generation: UUID) -> Bool {
        let auth = AuthenticationService.shared
        return generation == AccountStorage.generation && UUID(uuidString: owner) != nil
            && owner.lowercased() == AccountStorage.currentUserID.lowercased()
            && auth.isSignedIn && !auth.isRestoringSession
            && auth.currentUser.userID.lowercased() == owner.lowercased()
    }

    static func load<Value: Codable & Sendable>(_ type: Value.Type, key: String,
                                                maxAge: TimeInterval = 7 * 24 * 60 * 60) async -> Value? {
        let owner = AccountStorage.currentUserID
        let generation = AccountStorage.generation
        guard canUse(owner: owner, generation: generation),
              let data = AccountStorage.data(forKey: key), data.count <= maximumBytes else { return nil }
        let storageKey = AccountStorage.key(key)
        let revision = revisions[storageKey]
        let value = await Task.detached(priority: .userInitiated) {
            guard let snapshot = try? JSONDecoder().decode(WhisperLocalDisplaySnapshot<Value>.self, from: data),
                  snapshot.isValid(for: owner, maxAge: maxAge) else { return Optional<Value>.none }
            return snapshot.value
        }.value
        guard !Task.isCancelled, canUse(owner: owner, generation: generation),
              revisions[storageKey] == revision else { return nil }
        return value
    }

    static func save<Value: Codable & Sendable>(_ value: Value, key: String,
                                                owner: String, generation: UUID) async {
        guard !Task.isCancelled, canUse(owner: owner, generation: generation) else { return }
        let storageKey = AccountStorage.key(key)
        let revision = UUID(); revisions[storageKey] = revision
        let snapshot = WhisperLocalDisplaySnapshot(version: 1, owner: owner.lowercased(), savedAt: Date(), value: value)
        let data = await Task.detached(priority: .utility) { try? JSONEncoder().encode(snapshot) }.value
        guard !Task.isCancelled, canUse(owner: owner, generation: generation),
              revisions[storageKey] == revision, let data, data.count <= maximumBytes else { return }
        AccountStorage.set(data, forKey: key)
    }
}
