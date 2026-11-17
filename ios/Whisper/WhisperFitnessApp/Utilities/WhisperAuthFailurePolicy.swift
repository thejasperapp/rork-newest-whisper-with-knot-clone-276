import Foundation
import Auth

/// Only explicit credential/session failures ask for a password; outages preserve saved logins.
nonisolated enum WhisperAuthFailurePolicy {
    static func requiresSignIn(_ error: Error) -> Bool {
        guard let authError = error as? Auth.AuthError else { return false }
        return ["refresh_token_not_found", "refresh_token_already_used", "session_expired", "session_not_found"].contains(authError.errorCode.rawValue)
    }
}
