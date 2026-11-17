import Foundation

nonisolated enum WhisperAccountTransitionPolicy {
    static func canReveal(expectedOwner: String, localOwner: String, sessionOwner: String?, profileOwner: String,
                          expectedGeneration: UUID, currentGeneration: UUID, destinationGeneration: UUID?,
                          active: Bool, signedIn: Bool) -> Bool {
        let owner = expectedOwner.lowercased()
        return !owner.isEmpty && owner != "guest" && signedIn && active
            && owner == localOwner.lowercased() && owner == sessionOwner?.lowercased()
            && owner == profileOwner.lowercased() && expectedGeneration == currentGeneration
            && expectedGeneration == destinationGeneration
    }
}
