import SwiftUI
import AuthenticationServices
import CryptoKit
import Supabase

@Observable
class AuthenticationService {
    static let shared = AuthenticationService()

    var currentUser: UserProfile = .guest
    private(set) var profileLoadedGeneration: UUID?
    var isSignedIn: Bool = false
    private(set) var isRestoringSession: Bool = true
    private(set) var restorationError: String?
    private(set) var restorationIsTakingLonger = false
    @ObservationIgnored private var restorationTask: Task<Void, Never>?
    @ObservationIgnored private var signOutTask: Task<Void, Never>?
    private var restorationGeneration: UUID = UUID()
    var isLoading: Bool = false
    var errorMessage: String?

    private let userDefaultsKey = "savedUserProfile"
    private let cloudKit = CloudKitService.shared
    private let supabase = SupabaseService.shared.client
    private let supaSync = SupabaseSyncService.shared

    /// Raw nonce held between SignInWithAppleButton request creation and completion.
    /// SHA-256 of this value is sent to Apple as `request.nonce`; the raw value is passed
    /// to Supabase so it can verify the ID token's `nonce` claim.
    private var pendingAppleNonce: String?

    init() {
        loadSavedUser()
        retrySessionRestoration()
        Task { await observeAuthState() }
    }

    /// Long-running listener for Supabase auth state changes. If the user's
    /// session expires while the app is running (or is invalidated server-
    /// side), this flips `isSignedIn` off so the gate shows the auth sheet
    /// instead of leaving the app stuck with broken RLS calls.
    private func observeAuthState() async {
        for await (event, session) in supabase.auth.authStateChanges {
            let hasSession = session != nil
            await MainActor.run {
                switch event {
                case .signedOut, .userDeleted:
                    guard supabase.auth.currentSession == nil else { return }
                    if (isSignedIn || isRestoringSession), !WhisperAccountSwitcher.shared.isSwitching,
                       AccountStorage.currentUserID != "guest" {
                        resetApp(preservingSavedData: true)
                    }
                    // Clear the widget's mirrored session so it stops
                    // trying to hit Supabase with stale tokens.
                    WhisperWidgetSync.writeSession(accessToken: nil, refreshToken: nil, expiresAt: nil, userID: nil)
                case .tokenRefreshed, .signedIn, .initialSession, .userUpdated:
                    if hasSession, !isRestoringSession, restorationError == nil, !isSignedIn,
                       session?.user.id.uuidString.lowercased() == currentUser.userID.lowercased(),
                       currentUser.userID != "guest" {
                        isSignedIn = true
                    }
                    if let s = session {
                        WhisperWidgetSync.writeSession(
                            accessToken: s.accessToken,
                            refreshToken: s.refreshToken,
                            expiresAt: Date(timeIntervalSince1970: TimeInterval(s.expiresAt)),
                            userID: s.user.id.uuidString
                        )
                    }
                    // Refresh tokens rotate — keep the switcher's parked copy
                    // of THIS account current so a later switch-back can't
                    // present a token the server has already retired.
                    if event == .tokenRefreshed, let session {
                        WhisperAccountSwitcher.shared.rememberRotatedSession(session)
                    }
                default:
                    break
                }
            }
        }
    }

    private func activateAccount(_ userID: String) {
        AccountStorage.currentUserID = userID
        let generation = AccountStorage.generation
        Task {
            guard let session = try? await supabase.auth.session,
                  generation == AccountStorage.generation,
                  session.user.id.uuidString.lowercased() == AccountStorage.currentUserID.lowercased() else { return }
            WhisperWidgetSync.writeSession(accessToken: session.accessToken, refreshToken: session.refreshToken, expiresAt: Date(timeIntervalSince1970: session.expiresAt), userID: userID)
        }
        // Remember every real sign-in for the account switcher (guest and
        // local-only profiles have no server session to park).
        if userID != "guest", !userID.hasPrefix("local_") {
            Task { @MainActor in
                await WhisperAccountSwitcher.shared.rememberCurrent()
            }
        }
    }

    /// ACCOUNT SWITCHER: adopt an already-valid Supabase session for another
    /// account this phone remembers. Mirrors the email sign-in path exactly
    /// (wipe the outgoing account's caches, seed, hydrate, flip the gate) so
    /// the rest of the app can't tell a switch from a fresh sign-in.
    @discardableResult
    func adoptSession(_ session: Session) async -> Bool {
        let userID = session.user.id.uuidString
        let email = session.user.email
        let metadataName = (session.user.userMetadata["full_name"]?.stringValue) ?? ""

        wipeIfSwitchingAccounts(newUserID: userID, preservingSavedData: true)

        let existing = currentUser
        let seed = UserProfile(
            userID: userID,
            email: email ?? existing.email,
            displayName: metadataName.isEmpty ? existing.displayName : metadataName,
            givenName: metadataName.isEmpty ? existing.givenName : metadataName,
            familyName: existing.familyName,
            authProvider: existing.authProvider == .none ? .email : existing.authProvider,
            isProUser: existing.isProUser,
            joinDate: existing.userID == "guest" ? Date() : existing.joinDate,
            gender: existing.gender,
            weightLbs: existing.weightLbs,
            heightInches: existing.heightInches,
            dateOfBirth: existing.dateOfBirth,
            fitnessGoal: existing.fitnessGoal,
            activityLevel: existing.activityLevel,
            profileImageURL: existing.profileImageURL,
            hasCompletedProfileSetup: existing.hasCompletedProfileSetup
        )
        activateAccount(userID)
        currentUser = seed
        // Stay signed in THROUGH the hydration round-trip. Dropping the flag
        // here (as a fresh sign-in does) showed the sign-in screen for the
        // length of the network call — the "switching makes me log in again"
        // report. The wipe above toggles it false; flipping it back before
        // any await means SwiftUI never observes the dip.
        isSignedIn = true

        let generation = AccountStorage.generation
        await hydrateProfileFromSupabase(userID: userID)
        guard !Task.isCancelled, generation == AccountStorage.generation,
              supabase.auth.currentUser?.id.uuidString.caseInsensitiveCompare(userID) == .orderedSame else { return false }

        isSignedIn = true
        if currentUser.hasCompletedProfileSetup {
            AccountStorage.setOnboardingCompleted(true)
        }
        saveUser(currentUser)

        // Adoption is a read-only profile operation; never upsert a fallback seed.
        Task {
            guard generation == AccountStorage.generation else { return }
            await cloudKit.restoreAllUserData(userID: userID)
            guard generation == AccountStorage.generation else { return }
            await supaSync.pullAll(userID: userID)
        }
        return true
    }

    /// "Add account": step this DEVICE back to the sign-in screen WITHOUT a
    /// server sign-out. Even Supabase's `.local` scope ends the session and
    /// revokes its refresh token — the parked login could never come back.
    /// The outgoing Supabase session simply stays in the client until the
    /// next sign-in replaces it (or "Back to @you" re-adopts it).
    func parkSessionForAccountSwitch() {
        resetApp(preservingSavedData: true)
    }

    /// Detects when a DIFFERENT user is about to sign in on this device (e.g.
    /// the user logged out of account A and is now signing up / signing in as
    /// account B). When that happens we wipe every UserDefaults key that
    /// could carry data from the previous account so the new account starts
    /// with a clean slate — no leftover Whisper onboarding flag, no stale
    /// cached profile, no inherited feed / inbox state.
    ///
    /// Safe to call on every auth entry point: a no-op when the UID matches
    /// the currently-active account.
    private func wipeIfSwitchingAccounts(newUserID: String, preservingSavedData: Bool = false) {
        let previous = AccountStorage.currentUserID
        guard newUserID != previous else { return }
        // Supabase reports UUIDs lowercased while CloudKit/local storage may
        // hold the uppercase form. A case-only difference is the SAME account
        // — wiping here destroyed the profile/avatar caches on every launch
        // (the "random profiles show @user / no photo" bug).
        if newUserID.caseInsensitiveCompare(previous) == .orderedSame {
            AccountStorage.currentUserID = newUserID
            return
        }
        guard previous != "guest", !previous.isEmpty else {
            // First sign-in after a clean state — nothing user-scoped to wipe,
            // but still clear the small set of global keys so a guest-only
            // walkthrough flag (if any) doesn't skip Whisper onboarding.
            AccountStorage.wipeAllAccountData(forUserID: nil)
            return
        }
        print("[Auth] Switching accounts (\(previous) -> \(newUserID)) — wiping local cache.")
        AccountStorage.wipeAllAccountData(forUserID: previous, preservingSavedData: preservingSavedData)
        // In-memory caches that won't reload themselves on a UID change.
        currentUser = .guest
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        // Reset Whisper-specific onboarding so the new user is forced
        // through bio + interests + follow even if account A had completed it.
        WhisperUserService.shared.resetOnboardingLocally()
        // The thought-bubble cache lives in `UserDefaults` with un-namespaced
        // keys; the wipe above clears them on disk, but the in-memory
        // singleton still holds account A's text/style until we explicitly
        // re-read. Then kick off a server fetch so account B's own bubble
        // (if any) materializes once auth settles.
        WhisperThoughtService.shared.reloadFromDefaults()
        Task { await WhisperThoughtService.shared.refreshFromServer() }
    }

    func setupLocalProfile(
        name: String,
        gender: UserProfile.Gender,
        weight: Double?,
        heightInches: Double?,
        dateOfBirth: Date?,
        goal: UserProfile.FitnessGoal?,
        activityLevel: UserProfile.ActivityLevel?
    ) {
        let userID = currentUser.userID != "guest" ? currentUser.userID : "local_\(UUID().uuidString)"

        let profile = UserProfile(
            userID: userID,
            email: currentUser.email,
            displayName: name,
            givenName: name,
            familyName: currentUser.familyName,
            authProvider: currentUser.authProvider == .none ? .none : currentUser.authProvider,
            isProUser: true,
            joinDate: currentUser.joinDate == Date.distantPast ? Date() : (currentUser.userID == "guest" ? Date() : currentUser.joinDate),
            gender: gender,
            weightLbs: weight,
            heightInches: heightInches,
            dateOfBirth: dateOfBirth,
            fitnessGoal: goal,
            activityLevel: activityLevel,
            profileImageURL: currentUser.profileImageURL,
            hasCompletedProfileSetup: true
        )

        activateAccount(userID)

        Task {
            currentUser = profile
            saveUser(profile)
            await cloudKit.saveUserProfile(profile)
            await cloudKit.saveAllUserData(userID: userID)
            await syncProfileToSupabase(profile)
            await supaSync.pushAll(userID: userID)
        }

        currentUser = profile
        isSignedIn = true
        saveUser(profile)
        AccountStorage.setOnboardingCompleted(true)
    }

    func updateSubscriptionStatus(_ isPro: Bool) {}

    // MARK: - Apple Sign In

    /// Generate a fresh raw nonce and return its SHA-256 hash for the Apple request.
    /// Call from the `SignInWithAppleButton` request closure.
    func prepareAppleNonce() -> String {
        let raw = Self.randomNonceString()
        pendingAppleNonce = raw
        return Self.sha256(raw)
    }

    /// Exchange an Apple ID credential with Supabase, then persist the local profile.
    func applyAppleCredential(_ credential: ASAuthorizationAppleIDCredential) async throws {
        await waitForPendingSignOut()
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            print("[Auth] Apple credential missing identity token")
            throw AuthError.missingAppleIdentityToken
        }

        let nonce = pendingAppleNonce
        pendingAppleNonce = nil

        let session: Session
        do {
            session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
        } catch {
            print("[Auth] Supabase signInWithIdToken failed: \(error) | localized: \(error.localizedDescription)")
            throw AuthError.appleSupabaseFailed(error.localizedDescription)
        }

        let given = credential.fullName?.givenName
        let family = credential.fullName?.familyName
        let display: String? = {
            if let g = given, !g.isEmpty {
                if let f = family, !f.isEmpty { return "\(g) \(f)" }
                return g
            }
            return nil
        }()

        // Apple only delivers name/email on the first authorization — persist them to Supabase metadata.
        if display != nil || credential.email != nil {
            var attrs: [String: AnyJSON] = [:]
            if let d = display { attrs["full_name"] = .string(d) }
            if let g = given { attrs["given_name"] = .string(g) }
            if let f = family { attrs["family_name"] = .string(f) }
            if !attrs.isEmpty {
                _ = try? await supabase.auth.update(user: UserAttributes(data: attrs))
            }
        }

        let userID = session.user.id.uuidString
        let email = session.user.email ?? credential.email

        wipeIfSwitchingAccounts(newUserID: userID)

        let existing = currentUser
        let profile = UserProfile(
            userID: userID,
            email: email ?? existing.email,
            displayName: display ?? existing.displayName,
            givenName: given ?? existing.givenName,
            familyName: family ?? existing.familyName,
            authProvider: .apple,
            isProUser: existing.isProUser,
            joinDate: existing.userID == "guest" ? Date() : existing.joinDate,
            gender: existing.gender,
            weightLbs: existing.weightLbs,
            heightInches: existing.heightInches,
            dateOfBirth: existing.dateOfBirth,
            fitnessGoal: existing.fitnessGoal,
            activityLevel: existing.activityLevel,
            profileImageURL: existing.profileImageURL,
            hasCompletedProfileSetup: existing.hasCompletedProfileSetup
        )

        activateAccount(userID)
        currentUser = profile
        isSignedIn = true
        saveUser(profile)
        UserDefaults.standard.set(credential.user, forKey: "appleUserIdentifier")

        Task {
            await hydrateProfileFromSupabase(userID: userID)
            await cloudKit.saveUserProfile(profile)
            await cloudKit.restoreAllUserData(userID: userID)
            await supaSync.pullAll(userID: userID)
            await syncProfileToSupabase(currentUser)
            await supaSync.pushAll(userID: userID)
        }
    }

    // MARK: - Email / password

    /// Create a new Supabase user with email + password and persist the local profile.
    func signUpWithEmail(name: String, email: String, password: String) async throws {
        await waitForPendingSignOut()
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        let response = try await supabase.auth.signUp(
            email: trimmedEmail,
            password: password,
            data: trimmedName.isEmpty ? nil : ["full_name": .string(trimmedName)]
        )

        // When email confirmations are ON and the email is already registered,
        // Supabase returns a user with an empty `identities` array (and no session) instead of an error.
        // Detect this and surface a clear message so the user knows to sign in.
        if response.session == nil, (response.user.identities?.isEmpty ?? true) {
            throw AuthError.emailAlreadyRegistered
        }

        // If there's no session yet, the user must confirm their email before we can write to RLS-protected tables.
        // The DB trigger (handle_new_user) will have created the profile row; we just need to inform the user.
        if response.session == nil {
            throw AuthError.emailConfirmationRequired
        }

        let userID = response.user.id.uuidString
        wipeIfSwitchingAccounts(newUserID: userID)
        applyEmailProfile(userID: userID, email: trimmedEmail, name: trimmedName)

        // Remember the fresh account for one-tap sign-in.
        WhisperQuickLoginStore.shared.rememberLogin(
            userID: userID,
            email: trimmedEmail,
            password: password,
            displayName: currentUser.displayName ?? trimmedEmail,
            username: currentUser.username,
            avatarURL: currentUser.profileImageURL
        )
    }

    /// Sign in an existing Supabase user with email + password.
    /// Awaits profile hydration from Supabase so callers can immediately read
    /// `currentUser.hasCompletedProfileSetup` to decide whether to show onboarding.
    func signInWithEmail(email: String, password: String) async throws {
        try await signIn(identifier: email, password: password)
    }

    func signIn(identifier: String, password: String, expectedUserID: String? = nil) async throws {
        guard !isLoading else { throw WhisperLoginError.unavailable }
        isLoading = true
        defer { isLoading = false }
        await waitForPendingSignOut()
        let entryGeneration = AccountStorage.generation
        let value = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens: WhisperLoginService.Tokens
        if value.contains("@"), !value.hasPrefix("@") {
            tokens = try await WhisperLoginService.passwordSession(email: value.lowercased(), password: password)
        } else if value.hasPrefix("+") {
            let phone = value.filter { !" ()-".contains($0) }
            guard phone.range(of: "^\\+[1-9][0-9]{7,14}$", options: .regularExpression) != nil else { throw WhisperLoginError.invalidPhone }
            tokens = try await WhisperLoginService.passwordSession(phone: phone, password: password)
        } else {
            tokens = try await WhisperLoginService.usernameSession(identifier: value, password: password)
        }
        guard entryGeneration == AccountStorage.generation, !Task.isCancelled else { throw CancellationError() }
        if let expectedUserID, expectedUserID.caseInsensitiveCompare(tokens.user_id) != .orderedSame { throw WhisperLoginError.wrongAccount }
        let session = try await supabase.auth.setSession(accessToken: tokens.access_token, refreshToken: tokens.refresh_token)
        guard entryGeneration == AccountStorage.generation, !Task.isCancelled,
              session.user.id.uuidString.caseInsensitiveCompare(tokens.user_id) == .orderedSame else { throw CancellationError() }
        restorationError = nil
        restorationIsTakingLonger = false
        let trimmedEmail = session.user.email ?? ""
        let userID = session.user.id.uuidString
        let metadataName = (session.user.userMetadata["full_name"]?.stringValue) ?? ""

        wipeIfSwitchingAccounts(newUserID: userID, preservingSavedData: true)

        // Seed local state with what we know from the session, then hydrate from DB.
        let existing = currentUser
        let seed = UserProfile(
            userID: userID,
            email: trimmedEmail,
            displayName: metadataName.isEmpty ? existing.displayName : metadataName,
            givenName: metadataName.isEmpty ? existing.givenName : metadataName,
            familyName: existing.familyName,
            authProvider: .email,
            isProUser: existing.isProUser,
            joinDate: existing.userID == "guest" ? Date() : existing.joinDate,
            gender: existing.gender,
            weightLbs: existing.weightLbs,
            heightInches: existing.heightInches,
            dateOfBirth: existing.dateOfBirth,
            fitnessGoal: existing.fitnessGoal,
            activityLevel: existing.activityLevel,
            profileImageURL: existing.profileImageURL,
            hasCompletedProfileSetup: existing.hasCompletedProfileSetup
        )
        activateAccount(userID)
        currentUser = seed

        let generation = AccountStorage.generation
        await hydrateProfileFromSupabase(userID: userID)
        guard !Task.isCancelled, generation == AccountStorage.generation,
              supabase.auth.currentUser?.id.uuidString.caseInsensitiveCompare(userID) == .orderedSame else { throw CancellationError() }

        isSignedIn = true
        if currentUser.hasCompletedProfileSetup {
            AccountStorage.setOnboardingCompleted(true)
        }
        saveUser(currentUser)

        // Remember this login for one-tap sign-in (Keychain-backed).
        if !trimmedEmail.isEmpty {
            WhisperQuickLoginStore.shared.rememberLogin(
                userID: userID,
                email: trimmedEmail,
                password: password,
                displayName: currentUser.displayName ?? trimmedEmail,
                username: currentUser.username,
                avatarURL: currentUser.profileImageURL
            )
        }

        WhisperAccountSwitcher.shared.reauthAccount = nil
        await WhisperAccountSwitcher.shared.rememberCurrent()
        Task {
            guard generation == AccountStorage.generation else { return }
            await cloudKit.restoreAllUserData(userID: userID)
            guard generation == AccountStorage.generation else { return }
            await supaSync.pullAll(userID: userID)
        }
    }

    private func applyEmailProfile(userID: String, email: String, name: String) {
        let existing = currentUser
        let profile = UserProfile(
            userID: userID,
            email: email,
            displayName: name.isEmpty ? existing.displayName : name,
            givenName: name.isEmpty ? existing.givenName : name,
            familyName: existing.familyName,
            authProvider: .email,
            isProUser: existing.isProUser,
            joinDate: existing.userID == "guest" ? Date() : existing.joinDate,
            gender: existing.gender,
            weightLbs: existing.weightLbs,
            heightInches: existing.heightInches,
            dateOfBirth: existing.dateOfBirth,
            fitnessGoal: existing.fitnessGoal,
            activityLevel: existing.activityLevel,
            profileImageURL: existing.profileImageURL,
            hasCompletedProfileSetup: existing.hasCompletedProfileSetup
        )

        activateAccount(userID)
        currentUser = profile
        isSignedIn = true
        saveUser(profile)

        Task {
            await hydrateProfileFromSupabase(userID: userID)
            await cloudKit.saveUserProfile(profile)
            await cloudKit.restoreAllUserData(userID: userID)
            await supaSync.pullAll(userID: userID)
            await syncProfileToSupabase(currentUser)
            await supaSync.pushAll(userID: userID)
        }
    }

    // MARK: - Password reset

    /// Send a password-reset email. Goes through the Whisper backend first so
    /// the user receives the BRANDED reset email (same shell as every other
    /// Whisper transactional email); falls back to Supabase's built-in
    /// template only if the backend is unreachable or unconfigured.
    func sendPasswordReset(email: String) async throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if await sendBrandedPasswordReset(email: trimmed) { return }
        // No Supabase fallback: its built-in template routes through the
        // project's default Site URL (localhost) because custom redirects
        // aren't allowlisted — users got dead "localhost refused to connect"
        // links. Better to surface a retry than send a broken email.
        throw AuthError.custom("Couldn't send the reset email — check your connection and try again.")
    }

    /// Calls the Cloudflare backend's branded reset endpoint. Returns true
    /// when the branded email was accepted, false to trigger the fallback.
    private func sendBrandedPasswordReset(email: String) async -> Bool {
        // THE DEAD-LINK ROOT CAUSE: this rode the PERMANENT alias host, which
        // the platform pins to an old deploy whose handler still mailed
        // Supabase's action_link — a link that bounces through Supabase's
        // verify endpoint and lands on the project's default Site URL
        // (localhost). The newest deploy mints a token_hash link straight to
        // mydailywhisper.com/reset-password. Resolve the freshest live host
        // exactly like every money call does.
        let base = await WhisperBillingBackend.moneyURL()
        guard let url = URL(string: "\(base)/auth/password-reset") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            print("[Auth] Branded password reset unavailable, falling back: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Profile image

    /// Upload raw image data to the `avatars` Supabase Storage bucket and update the current profile.
    /// Returns the public URL of the uploaded avatar.
    @discardableResult
    func uploadProfileImage(_ data: Data) async throws -> String {
        let userID = currentUser.userID
        guard userID != "guest" else { throw AuthError.notSignedIn }

        let generation = AccountStorage.generation
        try WhisperChatMediaService.checkAccount(userID, generation: generation)
        let path = "\(userID)/avatar.jpg"
        _ = try await supabase.storage
            .from("avatars")
            .upload(
                path: path,
                file: data,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )

        try WhisperChatMediaService.checkAccount(userID, generation: generation)
        let publicURL = try supabase.storage.from("avatars").getPublicURL(path: path)
        // Append a cache-buster so AsyncImage reloads after re-upload.
        let urlString = "\(publicURL.absoluteString)?v=\(Int(Date().timeIntervalSince1970))"

        currentUser.profileImageURL = urlString
        saveUser(currentUser)
        let profile = currentUser
        Task {
            await cloudKit.saveUserProfile(profile)
            await syncProfileToSupabase(profile)
        }
        return urlString
    }

    // MARK: - Session lifecycle

    /// Public, awaitable profile refresh for cold-start critical paths.
    /// Pulls the latest profile row (username, avatar URL, verification
    /// flags…) from Supabase and merges it into `currentUser` immediately,
    /// so the feed / composer / avatars never render a nulled username or
    /// missing profile picture while `restoreSupabaseSession()` is still
    /// in flight. Safe to call repeatedly; no-ops for guests.
    func refreshProfileNow() async {
        var userID = await MainActor.run { currentUser.userID }
        if userID == "guest" || userID.hasPrefix("local_") {
            // Local cache may not be activated yet on a fresh install —
            // fall back to the persisted Supabase session's user id.
            guard let session = try? await supabase.auth.session else { return }
            userID = session.user.id.uuidString
        }
        await hydrateProfileFromSupabase(userID: userID)
    }

    /// Restore a persisted Supabase session on launch (if any).
    ///
    /// Robustness:
    ///  - `supabase.auth.session` automatically refreshes an expired access
    ///    token using the stored refresh token, so this covers the common
    ///    "sometimes I'm not authenticated" case caused by a stale token.
    ///  - If restoration fails BUT we have a locally-cached signed-in
    ///    profile, we now drop `isSignedIn` so the UI bounces the user to
    ///    the auth sheet instead of leaving them stuck behind 401s.
    func retrySessionRestoration() {
        restorationTask?.cancel()
        let generation = UUID()
        restorationGeneration = generation
        restorationError = nil
        restorationIsTakingLonger = false
        isRestoringSession = true
        restorationTask = Task { await restoreSupabaseSession(generation: generation) }
        Task {
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard restorationGeneration == generation, isRestoringSession else { return }
            // A slow connection is not evidence that the session is invalid.
            // Keep the real restore running; offer an explicit retry without
            // publishing cached identity as authenticated or signing them out.
            restorationIsTakingLonger = true
        }
    }

    private func restoreSupabaseSession(generation: UUID) async {
        defer {
            if restorationGeneration == generation {
                isRestoringSession = false
                restorationIsTakingLonger = false
            }
        }
        print("[AuthStartup] restoring saved session")
        do {
            let session = try await supabase.auth.session
            guard restorationGeneration == generation, !Task.isCancelled else { return }
            let userID = session.user.id.uuidString
            if currentUser.userID != userID {
                await MainActor.run { wipeIfSwitchingAccounts(newUserID: userID) }
            }
            activateAccount(userID)
            currentUser.userID = userID
            await MainActor.run {
                WhisperWidgetSync.writeSession(
                    accessToken: session.accessToken,
                    refreshToken: session.refreshToken,
                    expiresAt: Date(timeIntervalSince1970: TimeInterval(session.expiresAt)),
                    userID: userID
                )
            }
            // Start read-only Home loading once SDK ownership is established,
            // while the authoritative profile is still being restored.
            let accountGeneration = AccountStorage.generation
            let prefetch = Task {
                guard accountGeneration == AccountStorage.generation, !Task.isCancelled else { return }
                // Both profile tables are read under the validated SDK owner.
                // Start social identity alongside the authoritative account profile,
                // rather than waiting for the signed-in shell to request it again.
                async let identity: Void = WhisperUserService.shared.refreshMeIfStale()
                async let follows: Void = WhisperFollowService.shared.refreshIfStale()
                async let posts: Void = WhisperBackendService.shared.fetchPostsIfStale()
                _ = await (identity, follows, posts)
            }
            defer { prefetch.cancel() }
            await hydrateProfileFromSupabase(userID: userID)
            guard restorationGeneration == generation, !Task.isCancelled,
                  supabase.auth.currentUser?.id.uuidString.lowercased() == userID.lowercased(),
                  AccountStorage.currentUserID.lowercased() == userID.lowercased() else { return }
            isSignedIn = true
            isRestoringSession = false
            Task { await WhisperAccountSwitcher.shared.rememberCurrent() }
            print("[AuthStartup] session ready; mounting signed-in shell")
            // Restoration reads the authoritative profile; never write cached or guest defaults back.
            await prefetch.value
            guard accountGeneration == AccountStorage.generation, !Task.isCancelled else { return }
            await supaSync.pullAll(userID: userID)
            guard accountGeneration == AccountStorage.generation, !Task.isCancelled else { return }
            await supaSync.pushAll(userID: userID)
        } catch {
            guard restorationGeneration == generation, !Task.isCancelled else { return }
            if !WhisperAuthFailurePolicy.requiresSignIn(error) {
                restorationError = "Couldn't connect to restore your session. Check your connection and try again."
            } else {
                WhisperAccountSwitcher.shared.reauthAccount = WhisperAccountSwitcher.shared.current
            }
            print("[AuthStartup] Session restoration unavailable")
            await MainActor.run {
                if currentUser.userID != "guest" {
                    // Local state says signed in but Supabase has no usable
                    // session — force the auth sheet so the user can sign in
                    // again rather than being stuck with broken backend
                    // calls.
                    print("[Auth] No valid session — surfacing auth sheet.")
                    isSignedIn = false
                }
            }
        }
    }

    /// Fetch the saved profile row from Supabase and merge it into `currentUser`.
    /// This is what lets returning users skip the onboarding flow on a fresh install / sign-in.
    private func hydrateProfileFromSupabase(userID: String) async {
        let generation = AccountStorage.generation
        nonisolated struct ProfileRow: Decodable {
            let id: String
            let email: String?
            let display_name: String?
            let given_name: String?
            let family_name: String?
            let auth_provider: String?
            let is_pro_user: Bool?
            let gender: String?
            let weight_lbs: Double?
            let height_inches: Double?
            let date_of_birth: String?
            let fitness_goal: String?
            let activity_level: String?
            let profile_image_url: String?
            let has_completed_profile_setup: Bool?
            let join_date: String?
            let username: String?
            let is_verified: Bool?
            let is_moderator: Bool?
            let is_owner: Bool?
            let active_subscription_product_id: String?
            let subscription_expires_at: String?
        }
        do {
            let row: ProfileRow = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value

            let iso = ISO8601DateFormatter()
            await MainActor.run {
                guard !Task.isCancelled, generation == AccountStorage.generation, AccountStorage.currentUserID.lowercased() == userID.lowercased(),
                      supabase.auth.currentUser?.id.uuidString.lowercased() == userID.lowercased() else { return }
                var profile = currentUser
                profile.userID = row.id
                if let v = row.email { profile.email = v }
                if let v = row.display_name, !v.isEmpty { profile.displayName = v }
                if let v = row.given_name, !v.isEmpty { profile.givenName = v }
                if let v = row.family_name, !v.isEmpty { profile.familyName = v }
                if let v = row.auth_provider, let p = UserProfile.AuthProvider(rawValue: v) { profile.authProvider = p }
                if let v = row.is_pro_user { profile.isProUser = v }
                if let v = row.gender, let g = UserProfile.Gender(rawValue: v) { profile.gender = g }
                if let v = row.weight_lbs { profile.weightLbs = v }
                if let v = row.height_inches { profile.heightInches = v }
                if let v = row.date_of_birth, let d = iso.date(from: v) { profile.dateOfBirth = d }
                if let v = row.fitness_goal, let g = UserProfile.FitnessGoal(rawValue: v) { profile.fitnessGoal = g }
                if let v = row.activity_level, let a = UserProfile.ActivityLevel(rawValue: v) { profile.activityLevel = a }
                if let v = row.profile_image_url, !v.isEmpty { profile.profileImageURL = v }
                // Never downgrade `true` -> `false`: onboarding may have just completed locally
                // and the DB row (created by the handle_new_user trigger) may still be `false`.
                if let v = row.has_completed_profile_setup, v { profile.hasCompletedProfileSetup = true }
                if let v = row.join_date, let d = iso.date(from: v) { profile.joinDate = d }
                if let v = row.username, !v.isEmpty {
                    profile.username = v
                    // Cache locally so LeaderboardService.savedUsername returns it
                    // synchronously on the next render.
                    AccountStorage.set(v, forKey: "leaderboard_username")
                }
                if let v = row.is_verified  { profile.isVerified  = v }
                if let v = row.is_moderator { profile.isModerator = v }
                if let v = row.is_owner     { profile.isOwner     = v }
                if let v = row.active_subscription_product_id, !v.isEmpty {
                    profile.activeSubscriptionProductID = v
                }
                if let v = row.subscription_expires_at, let d = iso.date(from: v) {
                    profile.subscriptionExpiresAt = d
                }
                currentUser = profile
                profileLoadedGeneration = generation
                saveUser(profile)
                if profile.hasCompletedProfileSetup {
                    AccountStorage.setOnboardingCompleted(true)
                }
            }
            print("[Auth] Hydrated profile from Supabase for user \(userID)")
        } catch {
            // No row yet (brand new sign-up) or RLS issue — nothing to merge.
            print("[Auth] No existing Supabase profile to hydrate: \(error)")
        }
    }

    func checkExistingCredential() async {
        guard let appleID = UserDefaults.standard.string(forKey: "appleUserIdentifier") else { return }
        let provider = ASAuthorizationAppleIDProvider()
        let state: ASAuthorizationAppleIDProvider.CredentialState = await withCheckedContinuation { continuation in
            provider.getCredentialState(forUserID: appleID) { state, _ in
                continuation.resume(returning: state)
            }
        }
        if state == .revoked || state == .notFound {
            signOut()
        }
    }

    func resetApp(preservingSavedData: Bool = false) {
        let previousUID = AccountStorage.currentUserID
        // Nuke per-account namespaced keys AND the global Whisper/Whisper/Jasper
        // caches that aren't already namespaced (whisper.onboarded.v1,
        // whisper.thought.*, whisper.repost.localIDs, etc.). Without this the
        // next account inherits the previous user's local state and skips
        // the Whisper walkthrough.
        AccountStorage.wipeAllAccountData(forUserID: previousUID, preservingSavedData: preservingSavedData)
        if !preservingSavedData { AccountStorage.setOnboardingCompleted(false) }
        currentUser = .guest
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        AccountStorage.currentUserID = "guest"
        // Force Whisper onboarding to surface on the next sign-in regardless
        // of whatever the in-memory service was holding.
        WhisperUserService.shared.resetOnboardingLocally()
    }

    func saveCurrentUser() {
        saveUser(currentUser)
        let profile = currentUser
        Task {
            await cloudKit.saveUserProfile(profile)
            await syncProfileToSupabase(profile)
            await supaSync.pushAll(userID: profile.userID)
        }
    }

    func signOut() {
        // A real sign-out revokes the session — the switcher must forget it too.
        WhisperAccountSwitcher.shared.forgetCurrentOnSignOut()
        signOutTask = Task { try? await supabase.auth.signOut() }
        resetApp()
    }

    func waitForPendingSignOut() async {
        if let task = signOutTask {
            await task.value
            if signOutTask == task { signOutTask = nil }
        }
    }

    func deleteAccount() async {
        let deletingUserID = currentUser.userID
        let generation = AccountStorage.generation
        do { try await WhisperKnotDocumentService.eraseForAccountRemoval() }
        catch {
            guard generation == AccountStorage.generation else { return }
            errorMessage = "Delivered files couldn’t be removed from Whisper’s server. Nothing was cleared on this device. Please reconnect and try again."
            return
        }
        guard generation == AccountStorage.generation else { return }
        WhisperJasperCredentials.forget(owner: deletingUserID)
        AccountStorage.currentUserID = deletingUserID
        AccountStorage.clearAccountData()
        // Deleted accounts must never leave a one-tap login behind.
        WhisperQuickLoginStore.shared.wipeEverything()
        try? await supabase.auth.signOut()
        resetApp()
    }

    private func saveUser(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func loadSavedUser() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else { return }
        activateAccount(profile.userID)
        currentUser = profile
        // A cached profile is not a restored session. The shell mounts only after restoration.
    }

    /// Upsert the full local profile into the `profiles` table in Supabase.
    /// Requires a `profiles` table (see SQL setup) with RLS allowing the owner to upsert their row.
    private func syncProfileToSupabase(_ profile: UserProfile) async {
        guard profile.userID != "guest", !profile.userID.hasPrefix("local_") else { return }
        nonisolated struct ProfileRow: Encodable {
            let id: String
            let email: String?
            let display_name: String?
            let given_name: String?
            let family_name: String?
            let auth_provider: String
            let is_pro_user: Bool
            let gender: String?
            let weight_lbs: Double?
            let height_inches: Double?
            let date_of_birth: String?
            let fitness_goal: String?
            let activity_level: String?
            let profile_image_url: String?
            let has_completed_profile_setup: Bool
            let join_date: String
            let updated_at: String
            let username: String?
            let active_subscription_product_id: String?
            let subscription_expires_at: String?
        }
        let iso = ISO8601DateFormatter()
        let row = ProfileRow(
            id: profile.userID,
            email: profile.email,
            display_name: profile.displayName,
            given_name: profile.givenName,
            family_name: profile.familyName,
            auth_provider: profile.authProvider.rawValue,
            is_pro_user: profile.isProUser,
            gender: profile.gender?.rawValue,
            weight_lbs: profile.weightLbs,
            height_inches: profile.heightInches,
            date_of_birth: profile.dateOfBirth.map { iso.string(from: $0) },
            fitness_goal: profile.fitnessGoal?.rawValue,
            activity_level: profile.activityLevel?.rawValue,
            profile_image_url: profile.profileImageURL,
            has_completed_profile_setup: profile.hasCompletedProfileSetup,
            join_date: iso.string(from: profile.joinDate),
            updated_at: iso.string(from: Date()),
            username: profile.username,
            active_subscription_product_id: profile.activeSubscriptionProductID,
            subscription_expires_at: profile.subscriptionExpiresAt.map { iso.string(from: $0) }
        )
        do {
            _ = try await supabase.from("profiles").upsert(row, onConflict: "id").execute()
            print("[Auth] Synced profile to Supabase for user \(profile.userID)")
        } catch {
            print("[Auth] Failed to sync profile to Supabase: \(error)")
        }
        // Mirror the coarse age band so other clients can render the Teen /
        // 18+ chips without ever needing to read the raw DOB.
        await WhisperSafetyService.shared.syncOwnAgeBand(
            userID: profile.userID,
            dateOfBirth: profile.dateOfBirth
        )
    }

    // MARK: - Nonce helpers

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if status != errSecSuccess { continue }
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

nonisolated enum AuthError: LocalizedError {
    case missingAppleIdentityToken
    case notSignedIn
    case emailAlreadyRegistered
    case emailConfirmationRequired
    case appleSupabaseFailed(String)
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .missingAppleIdentityToken: return "Apple didn't return an identity token. Please try again."
        case .notSignedIn: return "You need to be signed in to do that."
        case .emailAlreadyRegistered: return "An account with that email already exists. Try signing in instead."
        case .emailConfirmationRequired: return "Check your inbox to confirm your email, then sign in."
        case .appleSupabaseFailed(let detail): return "Sign in with Apple failed: \(detail)"
        case .custom(let message): return message
        }
    }
}
