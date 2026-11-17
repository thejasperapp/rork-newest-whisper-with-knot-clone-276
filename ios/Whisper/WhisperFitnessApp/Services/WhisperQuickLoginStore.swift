import Foundation
import Security
import CryptoKit
import LocalAuthentication

/// Snapshot of the last email account that signed in on this device — enough
/// to render a "Continue as @user" card on the auth sheet without any network.
nonisolated struct WhisperSavedAccount: Codable, Equatable {
    let userID: String
    let email: String
    let displayName: String
    let username: String?
    let avatarURL: String?
    let savedAt: Date
}

/// One-tap login + local security for Whisper.
///
/// - The last email login is remembered (profile snapshot in UserDefaults,
///   password in the Keychain, device-only, never synced to iCloud) so the
///   auth sheet can offer "Continue as @user" after a sign-out.
/// - An optional 4–6 digit PIN (salted SHA-256, Keychain) and/or Face ID
///   gate that one-tap login.
///
/// Everything here is wiped when the user deletes their account or taps
/// "Remove saved login" in Security settings.
@Observable
final class WhisperQuickLoginStore {
    static let shared = WhisperQuickLoginStore()

    private(set) var savedAccount: WhisperSavedAccount?
    private(set) var hasPIN: Bool = false

    /// Require Face ID / Touch ID before the one-tap login fires. Defaults
    /// to false — biometrics are opt-in, not armed silently on every fresh
    /// install. Toggling it on in Security & login is the only path that
    /// arms it, so a user who never visits that screen never gets a
    /// biometric prompt (and we never touch LAContext on launch).
    var faceIDEnabled: Bool {
        didSet { UserDefaults.standard.set(faceIDEnabled, forKey: Self.faceIDKey) }
    }

    private static let accountKey = "whisper.quicklogin.account"
    private static let faceIDKey = "whisper.quicklogin.faceid"
    private static let passwordItem = "quicklogin.password"
    private static let pinHashItem = "quicklogin.pin.hash"
    private static let pinSaltItem = "quicklogin.pin.salt"

    private init() {
        // Opt-in: default to false so a fresh install (or a user who never
        // opens Security & login) never has biometrics armed. Only an
        // explicit toggle in that screen flips this to true.
        faceIDEnabled = (UserDefaults.standard.object(forKey: Self.faceIDKey) as? Bool) ?? false
        if let data = UserDefaults.standard.data(forKey: Self.accountKey),
           let account = try? JSONDecoder().decode(WhisperSavedAccount.self, from: data) {
            savedAccount = account
        }
        hasPIN = KeychainBox.read(Self.pinHashItem) != nil
    }

    // MARK: - Saved login

    /// Remember a successful email login for one-tap sign-in later.
    func rememberLogin(
        userID: String,
        email: String,
        password: String,
        displayName: String,
        username: String?,
        avatarURL: String?
    ) {
        let account = WhisperSavedAccount(
            userID: userID,
            email: email,
            displayName: displayName,
            username: username,
            avatarURL: avatarURL,
            savedAt: Date()
        )
        if let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: Self.accountKey)
        }
        if let pw = password.data(using: .utf8) {
            KeychainBox.write(pw, item: Self.passwordItem)
        }
        savedAccount = account
    }

    /// Refresh the display bits (name / username / avatar) after profile
    /// hydration so the card never shows a stale identity.
    func refreshProfileSnapshot(displayName: String, username: String?, avatarURL: String?) {
        guard let current = savedAccount else { return }
        let updated = WhisperSavedAccount(
            userID: current.userID,
            email: current.email,
            displayName: displayName,
            username: username ?? current.username,
            avatarURL: avatarURL ?? current.avatarURL,
            savedAt: current.savedAt
        )
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: Self.accountKey)
        }
        savedAccount = updated
    }

    /// The stored password for the saved account, or nil when nothing is saved.
    func storedPassword() -> String? {
        guard let data = KeychainBox.read(Self.passwordItem) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Forget the saved login entirely (profile card + Keychain password).
    func clearSavedLogin() {
        UserDefaults.standard.removeObject(forKey: Self.accountKey)
        KeychainBox.delete(Self.passwordItem)
        savedAccount = nil
    }

    /// Full wipe — saved login AND PIN. Used on account deletion.
    func wipeEverything() {
        clearSavedLogin()
        removePIN()
    }

    // MARK: - PIN

    /// Store a new PIN (salted SHA-256; the raw PIN never touches disk).
    func setPIN(_ pin: String) {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let hash = Self.hashPIN(pin, salt: salt)
        KeychainBox.write(salt, item: Self.pinSaltItem)
        KeychainBox.write(hash, item: Self.pinHashItem)
        hasPIN = true
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let salt = KeychainBox.read(Self.pinSaltItem),
              let stored = KeychainBox.read(Self.pinHashItem) else { return false }
        return Self.hashPIN(pin, salt: salt) == stored
    }

    func removePIN() {
        KeychainBox.delete(Self.pinHashItem)
        KeychainBox.delete(Self.pinSaltItem)
        hasPIN = false
    }

    private nonisolated static func hashPIN(_ pin: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(pin.utf8))
        return Data(SHA256.hash(data: input))
    }

    // MARK: - Biometrics

    /// True when the device can evaluate Face ID / Touch ID (or passcode).
    /// Computed lazily and only ever read from the Security & login screen
    /// or the auth sheet's quick-login card — never on app launch.
    var biometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        let ok = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        if !ok, let error {
            print("[QuickLogin] Biometrics unavailable: \(error.localizedDescription)")
        }
        return ok
    }

    /// Prompt Face ID / Touch ID (with device-passcode fallback). Returns
    /// true when the user authenticated.
    func unlockWithBiometrics(reason: String = "Confirm it's you to sign in") async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            print("[QuickLogin] Biometric auth failed: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Keychain

/// Minimal generic-password Keychain wrapper. Items are device-only
/// (`AfterFirstUnlockThisDeviceOnly`) so credentials never leave the phone.
private nonisolated enum KeychainBox {
    private static let service = "app.jasper.whisper.quicklogin"

    static func write(_ data: Data, item: String) {
        delete(item)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[QuickLogin] Keychain write failed (\(status)) for \(item)")
        }
    }

    static func read(_ item: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(_ item: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
