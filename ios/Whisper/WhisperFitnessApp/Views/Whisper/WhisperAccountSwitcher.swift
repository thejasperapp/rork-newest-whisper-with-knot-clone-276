import SwiftUI
import Supabase
import Security

/// One Whisper account this phone can switch into without re-typing a
/// password — the Supabase session pair lives in the Keychain (device-only).
nonisolated struct WhisperSwitchableAccount: Codable, Identifiable, Hashable, Sendable {
    let userID: String
    var username: String
    var displayName: String?
    var avatarURL: String?
    var email: String?
    var accessToken: String
    var refreshToken: String
    var lastActiveAt: Date
    var id: String { userID }
}

extension Notification.Name {
    /// Posted after a saved account has been adopted in place — every
    /// per-account service re-pulls for the new user (threads, stories,
    /// follows, flags, push registration) without a sign-in cycle.
    static let whisperAccountSwitched = Notification.Name("WhisperAccountSwitched")
}

private nonisolated enum WhisperAccountSwitchError: Error {
    case wrongAccount
}

/// MULTI-ACCOUNT — Instagram's "tap your username → switch account" grammar.
/// Every successful sign-in remembers its session here; switching adopts a
/// saved session in place (no password), "Add account" parks the current
/// session and opens the sign-in flow, and removal forgets the tokens.
/// Tokens never leave the Keychain; the list is capped at 5 accounts.
///
/// The one rule that makes this work: a parked login is NEVER signed out
/// server-side. Supabase's `signOut(scope: .local)` ends the session and
/// revokes its refresh token — which is exactly what made every switch-back
/// fail with "login expired" and then delete the account.
@MainActor
@Observable
final class WhisperAccountSwitcher {
    static let shared = WhisperAccountSwitcher()

    private(set) var accounts: [WhisperSwitchableAccount] = []
    var isSwitching: Bool = false
    var switchingTo: String? = nil
    var lastError: String? = nil
    /// The account whose parked login genuinely stopped working (revoked on
    /// another device, password changed). The row STAYS — the user signs back
    /// in with one tap instead of the entry silently vanishing.
    var needsSignIn: WhisperSwitchableAccount? = nil
    /// True between "Add account" and the next completed sign-in — the auth
    /// sheet is up because the user ASKED for a second account, not because
    /// they were signed out.
    var isAddingAccount: Bool = false

    private let client = SupabaseService.shared.client
    static let maxAccounts: Int = 5

    private var hasLoadedVault: Bool = false

    private init() {
        if let saved = WhisperAccountKeychain.load() {
            accounts = saved
            hasLoadedVault = true
        }
    }

    private func ensureVaultLoaded() -> Bool {
        if hasLoadedVault { return true }
        guard let saved = WhisperAccountKeychain.load() else {
            lastError = "Unlock your iPhone to access saved accounts, then try again."
            return false
        }
        accounts = saved
        hasLoadedVault = true
        return true
    }

    /// The account matching the signed-in user, if remembered.
    var current: WhisperSwitchableAccount? {
        let uid = AccountStorage.currentUserID.lowercased()
        return accounts.first { $0.userID.lowercased() == uid }
    }

    /// Everything except the active account, most recently used first.
    var others: [WhisperSwitchableAccount] {
        let uid = AccountStorage.currentUserID.lowercased()
        return accounts
            .filter { $0.userID.lowercased() != uid }
            .sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    // MARK: - Remember

    /// Captures the LIVE session for the signed-in account (refreshing if it
    /// expired) and upserts it into the list with the freshest profile bits.
    /// Cheap and idempotent — called after every sign-in and whenever the
    /// switcher sheet appears, so stored tokens stay current.
    func rememberCurrent() async {
        guard AuthenticationService.shared.isSignedIn, ensureVaultLoaded() else { return }
        let uid = AccountStorage.currentUserID
        let generation = AccountStorage.generation
        guard !uid.isEmpty, uid != "guest", !uid.hasPrefix("local_") else { return }
        guard let session = try? await client.auth.session else { return }
        guard generation == AccountStorage.generation, AuthenticationService.shared.isSignedIn,
              session.user.id.uuidString.caseInsensitiveCompare(uid) == .orderedSame,
              uid.caseInsensitiveCompare(AccountStorage.currentUserID) == .orderedSame else { return }

        let me = WhisperUserService.shared.me
        let auth = AuthenticationService.shared.currentUser
        let username = (me?.user_id.caseInsensitiveCompare(uid) == .orderedSame ? me?.username : nil)
            ?? auth.username
            ?? current?.username
            ?? (session.user.email?.components(separatedBy: "@").first ?? "you")
        let ownedMe = me?.user_id.caseInsensitiveCompare(uid) == .orderedSame ? me : nil
        let displayName = ownedMe?.display_name ?? auth.displayName ?? current?.displayName
        let avatar = ownedMe?.profile_image_url ?? auth.profileImageURL ?? current?.avatarURL

        let entry = WhisperSwitchableAccount(
            userID: session.user.id.uuidString,
            username: username,
            displayName: displayName,
            avatarURL: avatar,
            email: session.user.email,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            lastActiveAt: Date()
        )
        upsert(entry)
        isAddingAccount = false
    }

    private func upsert(_ entry: WhisperSwitchableAccount) {
        guard ensureVaultLoaded() else { return }
        var list = accounts.filter { $0.userID.lowercased() != entry.userID.lowercased() }
        list.insert(entry, at: 0)
        if list.count > Self.maxAccounts {
            list = Array(list.sorted { $0.lastActiveAt > $1.lastActiveAt }.prefix(Self.maxAccounts))
        }
        accounts = list
        WhisperAccountKeychain.save(list)
    }

    /// Rotation can occur while the app is parked on Add account. Update only
    /// an existing owner's token pair, never its identity, order or activation.
    func rememberRotatedSession(_ session: Session) {
        guard ensureVaultLoaded(), let index = accounts.firstIndex(where: { $0.userID.caseInsensitiveCompare(session.user.id.uuidString) == .orderedSame }),
              !accounts[index].refreshToken.isEmpty else { return }
        accounts[index].accessToken = session.accessToken
        accounts[index].refreshToken = session.refreshToken
        WhisperAccountKeychain.save(accounts)
    }

    // MARK: - Switch

    /// Adopts a saved account's session in place — one tap, no password.
    /// Returns true on success; on failure the CURRENT account stays signed
    /// in (the outgoing session is restored if the SDK dropped it) and
    /// `lastError` says why. Nothing is ever deleted by a failed switch.
    @discardableResult
    func switchTo(_ account: WhisperSwitchableAccount) async -> Bool {
        guard !isSwitching, !AuthenticationService.shared.isLoading, !WhisperAccountTransition.shared.isActive else { return false }
        await AuthenticationService.shared.waitForPendingSignOut()
        guard !isSwitching, !AuthenticationService.shared.isLoading else { return false }
        if account.refreshToken.isEmpty {
            await beginAddAccount(reauth: account)
            return false
        }
        if account.userID.lowercased() == AccountStorage.currentUserID.lowercased(),
           AuthenticationService.shared.isSignedIn,
           client.auth.currentSession?.user.id.uuidString.lowercased() == account.userID.lowercased() { return true }
        isSwitching = true
        switchingTo = account.username
        lastError = nil
        needsSignIn = nil
        defer {
            isSwitching = false
            switchingTo = nil
        }

        let transition = WhisperAccountTransition.shared
        guard let token = await transition.begin(owner: account.userID, username: account.username, avatarURL: account.avatarURL) else {
            lastError = "Please return to Whisper and try again."
            return false
        }
        // Install the opaque cover before replacing any session or account data.
        await rememberCurrent()
        let outgoing = current
        let outgoingUID = AccountStorage.currentUserID

        do {
            let session = try await client.auth.setSession(
                accessToken: account.accessToken,
                refreshToken: account.refreshToken
            )
            guard session.user.id.uuidString.caseInsensitiveCompare(account.userID) == .orderedSame else {
                throw WhisperAccountSwitchError.wrongAccount
            }
            guard await AuthenticationService.shared.adoptSession(session), transition.id == token else {
                throw WhisperAccountSwitchError.wrongAccount
            }
            transition.adopted(token: token, owner: account.userID, generation: AccountStorage.generation)
            // Store the (possibly rotated) tokens for the account we just entered.
            var refreshed = account
            refreshed.accessToken = session.accessToken
            refreshed.refreshToken = session.refreshToken
            refreshed.lastActiveAt = Date()
            refreshed.email = session.user.email ?? account.email
            upsert(refreshed)
            isAddingAccount = false
            NotificationCenter.default.post(name: .whisperAccountSwitched, object: nil)
            await rememberCurrent()
            return true
        } catch {
            // Reconcile the actual SDK identity, not just whether a session exists.
            var restored = client.auth.currentUser?.id.uuidString.lowercased() == outgoingUID.lowercased()
            if !restored, let outgoing {
                if let session = try? await client.auth.setSession(accessToken: outgoing.accessToken, refreshToken: outgoing.refreshToken),
                   session.user.id.uuidString.caseInsensitiveCompare(outgoing.userID) == .orderedSame {
                    restored = await AuthenticationService.shared.adoptSession(session)
                }
            }
            let safeToReturn = restored && AccountStorage.currentUserID.caseInsensitiveCompare(outgoingUID) == .orderedSame
            if !safeToReturn { AuthenticationService.shared.parkSessionForAccountSwitch(); isAddingAccount = true }
            let requiresPassword = WhisperAuthFailurePolicy.requiresSignIn(error)
            if requiresPassword {
                lastError = "Sign in to @\(account.username) again with your password."
                needsSignIn = account
            } else {
                lastError = "Couldn't switch accounts right now. Your saved login is still here. Please try again."
            }
            transition.fail(lastError ?? "Couldn't switch accounts.", recoveryTitle: requiresPassword ? "Enter password" : (safeToReturn ? "Back to your account" : "Go to sign in")) {
                transition.close()
                if requiresPassword { Task { await self.beginAddAccount(reauth: account) } }
            }
            return false
        }
    }

    /// Forgets an account on this device (tokens deleted). Never signs the
    /// active account out — use the settings sign-out for that.
    func remove(_ account: WhisperSwitchableAccount) {
        guard ensureVaultLoaded() else { return }
        WhisperJasperCredentials.forget(owner: account.userID)
        accounts.removeAll { $0.userID.lowercased() == account.userID.lowercased() }
        WhisperAccountKeychain.save(accounts)
    }

    /// "Add Whisper account": remembers the current session, steps this
    /// device back to the sign-in screen WITHOUT telling the server anything
    /// (the parked refresh token stays valid), and flags the auth sheet as
    /// an add-account flow. Pass an account to prefill its email when the
    /// user is signing back into a login that expired.
    func beginAddAccount(reauth account: WhisperSwitchableAccount? = nil) async {
        guard !isSwitching, !AuthenticationService.shared.isLoading, !WhisperAccountTransition.shared.isActive else { return }
        isSwitching = true
        defer { isSwitching = false }
        await rememberCurrent()
        isAddingAccount = true
        needsSignIn = nil
        lastError = nil
        AuthenticationService.shared.parkSessionForAccountSwitch()
        reauthAccount = account
    }

    /// Identity-only intent; the password is always entered afresh.
    var reauthAccount: WhisperSwitchableAccount? = nil

    /// Cancel out of "Add account" by hopping back into the most recent
    /// parked account. Returns false when there's nothing to return to.
    @discardableResult
    func returnToLastAccount() async -> Bool {
        guard let last = accounts.sorted(by: { $0.lastActiveAt > $1.lastActiveAt }).first else {
            isAddingAccount = false
            return false
        }
        let succeeded = await switchTo(last)
        if succeeded { isAddingAccount = false }
        return succeeded
    }

    /// Retain the account identity, but never reuse credentials after explicit logout.
    /// Selecting this row opens password entry instead of attempting a dead session.
    func forgetCurrentOnSignOut() {
        guard ensureVaultLoaded() else { return }
        let uid = AccountStorage.currentUserID.lowercased()
        guard let index = accounts.firstIndex(where: { $0.userID.lowercased() == uid }) else { return }
        accounts[index].accessToken = ""
        accounts[index].refreshToken = ""
        WhisperAccountKeychain.save(accounts)
    }
}

// MARK: - Keychain

/// Device-only generic-password storage for the saved-accounts list.
private nonisolated enum WhisperAccountKeychain {
    private static let service = "app.jasper.whisper.accounts"
    private static let item = "saved-accounts.v1"

    static func load() -> [WhisperSwitchableAccount]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode([WhisperSwitchableAccount].self, from: data)
    }

    static func save(_ accounts: [WhisperSwitchableAccount]) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item,
        ]
        if accounts.isEmpty { SecItemDelete(deleteQuery as CFDictionary); return }
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        let update = SecItemUpdate(deleteQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else {
            print("[AccountSwitcher] Keychain update unavailable (\(update))")
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[AccountSwitcher] Keychain write failed (\(status))")
        }
    }
}

// MARK: - Sheet

/// The account switcher — opened from the profile header's username chevron.
/// Instagram's grammar: the current account checked on top, every other
/// saved account beneath (tap to switch, swipe to forget), then "Add
/// Whisper account".
struct WhisperAccountSwitcherSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var switcher = WhisperAccountSwitcher.shared
    @State private var users = WhisperUserService.shared
    @State private var auth = AuthenticationService.shared
    @State private var confirmRemove: WhisperSwitchableAccount?

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }

    private var currentUsername: String {
        users.me?.username ?? auth.currentUser.username ?? switcher.current?.username ?? "you"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                List {
                    Section {
                        currentRow
                        ForEach(switcher.others) { account in
                            accountRow(account)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        confirmRemove = account
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    } footer: {
                        if !switcher.others.isEmpty {
                            Text("Swipe an account to remove it from this phone. Its login stays valid everywhere else.")
                        }
                    }

                    Section {
                        Button {
                            Haptics.tap()
                            Task {
                                await switcher.beginAddAccount()
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(ink)
                                    .frame(width: 44, height: 44)
                                    .background(WhisperTheme.card(colorScheme), in: Circle())
                                    .overlay { Circle().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                                Text("Add Whisper account")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ink)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(switcher.accounts.count >= WhisperAccountSwitcher.maxAccounts)
                    } footer: {
                        Text(switcher.accounts.count >= WhisperAccountSwitcher.maxAccounts
                             ? "You can keep up to \(WhisperAccountSwitcher.maxAccounts) accounts on one phone."
                             : "Switch between accounts without signing out. Whisper remembers each login securely on this phone.")
                    }

                    if let err = switcher.lastError {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(Color(red: 0.90, green: 0.35, blue: 0.35))
                                if let stale = switcher.needsSignIn {
                                    Button {
                                        Haptics.tap()
                                        Task {
                                            await switcher.beginAddAccount(reauth: stale)
                                            dismiss()
                                        }
                                    } label: {
                                        Text("Sign in to @\(stale.username)")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(WhisperTheme.surface(colorScheme))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 11)
                                            .background(ink, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .disabled(switcher.isSwitching)

                if switcher.isSwitching && !WhisperAccountTransition.shared.isActive {
                    ProgressView("Preparing sign in…")
                        .padding(24)
                        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 18))
                }
            }
            .navigationTitle("Switch account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(ink)
                        .disabled(switcher.isSwitching)
                }
            }
            .task { await switcher.rememberCurrent() }
            .confirmationDialog(
                "Remove @\(confirmRemove?.username ?? "") from this phone?",
                isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let a = confirmRemove { switcher.remove(a) }
                    confirmRemove = nil
                }
                Button("Cancel", role: .cancel) { confirmRemove = nil }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled(switcher.isSwitching)
    }

    private var currentRow: some View {
        HStack(spacing: 12) {
            WhisperAvatar(username: currentUsername, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(currentUsername)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
                Text(users.me?.display_name ?? auth.currentUser.displayName ?? "Signed in")
                    .font(.caption)
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(WhisperBrandGradient.accent)
        }
        .padding(.vertical, 2)
    }

    private func accountRow(_ account: WhisperSwitchableAccount) -> some View {
        Button {
            Haptics.tap()
            Task {
                let ok = await switcher.switchTo(account)
                if ok { dismiss() }
            }
        } label: {
            HStack(spacing: 12) {
                WhisperAvatar(username: account.username, size: 44, imageURL: account.avatarURL.flatMap(URL.init(string:)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.username)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(account.displayName ?? account.email ?? "Tap to switch")
                        .font(.caption)
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
                Spacer()
                Circle()
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1.5)
                    .frame(width: 20, height: 20)
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(switcher.isSwitching)
    }
}
