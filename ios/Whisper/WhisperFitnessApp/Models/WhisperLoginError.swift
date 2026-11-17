import Foundation

nonisolated enum WhisperLoginError: LocalizedError {
    case invalidCredentials, unavailable, rateLimited, wrongAccount, invalidPhone

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "The sign-in details aren't correct. Check them and try again."
        case .unavailable: "Sign-in is temporarily unavailable. Please try again."
        case .rateLimited: "Too many sign-in attempts. Please wait a few minutes and try again."
        case .wrongAccount: "Those details belong to a different account. Enter the password for the account you selected."
        case .invalidPhone: "Use your verified sign-in number with its country code, for example +15551234567."
        }
    }
}
