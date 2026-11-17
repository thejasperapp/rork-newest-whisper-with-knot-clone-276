import Foundation

/// Persists the user's DM privacy preference plus per-user approval state
/// for message requests. When `isPrivate` is on, DMs from anyone who is
/// neither following the user nor being followed by the user land in
/// "Requests" instead of the main inbox. The user can then Approve or
/// Deny each request.
@MainActor
@Observable
final class WhisperDMPrivacyService {
    static let shared = WhisperDMPrivacyService()

    private let privateKey = "whisper.dm.private.v1"
    private let approvedKey = "whisper.dm.approved.v1"
    private let deniedKey = "whisper.dm.denied.v1"

    private var reloading: Bool = false

    var isPrivate: Bool {
        didSet { if !reloading { AccountStorage.set(isPrivate, forKey: privateKey); WhisperPushPreferenceSync.shared.refresh() } }
    }

    /// Lowercased user IDs the local user has explicitly approved to DM them.
    var approved: Set<String> {
        didSet {
            if !reloading { AccountStorage.set(Array(approved), forKey: approvedKey); WhisperPushPreferenceSync.shared.refresh() }
        }
    }

    /// Lowercased user IDs the local user has denied. We hide their thread
    /// from the inbox until they're explicitly approved.
    var denied: Set<String> {
        didSet {
            if !reloading { AccountStorage.set(Array(denied), forKey: deniedKey); WhisperPushPreferenceSync.shared.refresh() }
        }
    }

    private init() {
        let d = UserDefaults.standard
        self.isPrivate = (AccountStorage.object(forKey: privateKey) as? Bool) ?? d.bool(forKey: privateKey)
        self.approved = Set((AccountStorage.object(forKey: approvedKey) as? [String] ?? []).map { $0.lowercased() })
        self.denied = Set(((AccountStorage.object(forKey: deniedKey) as? [String]) ?? (d.array(forKey: deniedKey) as? [String]) ?? []).map { $0.lowercased() })
    }

    /// Preserve legacy restrictions conservatively; never assign unowned approvals to a new account.
    func reloadForCurrentAccount() {
        reloading = true
        defer { reloading = false }
        isPrivate = (AccountStorage.object(forKey: privateKey) as? Bool) ?? UserDefaults.standard.bool(forKey: privateKey)
        approved = Set((AccountStorage.object(forKey: approvedKey) as? [String] ?? []).map { $0.lowercased() })
        denied = Set(((AccountStorage.object(forKey: deniedKey) as? [String]) ?? (UserDefaults.standard.array(forKey: deniedKey) as? [String]) ?? []).map { $0.lowercased() })
    }

    func approve(_ userID: String) {
        let id = userID.lowercased()
        denied.remove(id)
        approved.insert(id)
    }

    func deny(_ userID: String) {
        let id = userID.lowercased()
        approved.remove(id)
        denied.insert(id)
    }

    func reset(_ userID: String) {
        let id = userID.lowercased()
        approved.remove(id)
        denied.remove(id)
    }

    func isApproved(_ userID: String) -> Bool {
        approved.contains(userID.lowercased())
    }

    func isDenied(_ userID: String) -> Bool {
        denied.contains(userID.lowercased())
    }
}
