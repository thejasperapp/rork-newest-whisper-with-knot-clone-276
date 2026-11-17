import Foundation

/// A bounded display cache, never evidence of server permissions or account readiness.
nonisolated struct WhisperLocalDisplaySnapshot<Value: Codable & Sendable>: Codable, Sendable {
    let version: Int
    let owner: String
    let savedAt: Date
    let value: Value

    func isValid(for account: String, now: Date = Date(), maxAge: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(savedAt)
        return version == 1 && owner == account.lowercased() && UUID(uuidString: owner) != nil
            && age >= 0 && age < maxAge
    }
}
