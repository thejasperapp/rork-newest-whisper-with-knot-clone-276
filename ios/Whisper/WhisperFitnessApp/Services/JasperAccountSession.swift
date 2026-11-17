import Foundation
import Supabase

/// Captures account identity before asynchronous partner work, including A → B → A switches.
struct JasperAccountSession {
    let ownerID: String
    let generation: UUID
    let jwt: String

    static func current() async throws -> JasperAccountSession {
        let generation = AccountStorage.generation
        let owner = AccountStorage.currentUserID.lowercased()
        guard UUID(uuidString: owner) != nil else { throw JasperConnectError.notSignedIn }
        let session = try await SupabaseService.shared.client.auth.session
        let context = JasperAccountSession(ownerID: owner, generation: generation, jwt: session.accessToken)
        try context.check()
        guard session.user.id.uuidString.lowercased() == owner else { throw JasperConnectError.notSignedIn }
        return context
    }

    func check() throws {
        try Task.checkCancellation()
        guard AccountStorage.generation == generation,
              AccountStorage.currentUserID.lowercased() == ownerID,
              AuthenticationService.shared.isSignedIn,
              AuthenticationService.shared.currentUser.userID.lowercased() == ownerID else { throw CancellationError() }
    }
}
