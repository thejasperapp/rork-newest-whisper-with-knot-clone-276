import Foundation
import UIKit
import UserNotifications
import Supabase

// MARK: - Supabase payloads
//
// Canonical schema lives in `supabase/push-notifications-fix.sql` (device
// tokens table + `whisper_claim_device_token` SECURITY DEFINER function).

nonisolated struct WhisperDeviceTokenClaim: Codable, Sendable {
    let p_token: String
    let p_bundle_id: String?
    let p_sandbox: Bool
    let p_platform: String
}

nonisolated struct WhisperDeviceTokenUpsert: Codable, Sendable {
    let token: String
    let user_id: String
    let platform: String
    let bundle_id: String?
    let sandbox: Bool
    let active: Bool
}

/// Legacy table shape (environment text column, no sandbox/active) — kept
/// as a last-resort fallback so token registration never fully fails.
nonisolated struct WhisperDeviceTokenLegacyUpsert: Codable, Sendable {
    let token: String
    let user_id: String
    let platform: String
    let bundle_id: String?
    let environment: String
}

/// Uploads the device's APNs token to Supabase so the push-fanout edge
/// function can deliver notifications for new DMs / followers / activity.
///
/// Two hard-won rules live here:
///  1. The token is CLAIMED via a SECURITY DEFINER function, not upserted.
///     A push token belongs to the physical device — if a different account
///     signed in on this device earlier, RLS blocks a plain upsert from
///     reassigning the row, and the token keeps ringing the OLD account
///     (the "I message a friend and my own phone buzzes" bug).
///  2. The APNs environment (sandbox vs production) is detected from the
///     embedded provisioning profile, NOT `#if DEBUG` — Release-config
///     dev-signed builds get sandbox tokens, and mislabeling them got the
///     tokens marked dead on first push.
@MainActor
@Observable
final class WhisperPushService {
    static let shared = WhisperPushService()

    private let client = SupabaseService.shared.client
    private var lastUploadedToken: String?
    private var lastUploadedUID: String?
    var lastError: String?

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private init() {}

    /// True when this install's APNs tokens are issued by the sandbox
    /// environment (development-signed builds, simulator). TestFlight and
    /// App Store installs carry no development `aps-environment` in their
    /// provisioning profile and use production.
    nonisolated static func apnsEnvironmentIsSandbox() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .isoLatin1) else {
            return false // No embedded profile → App Store / TestFlight
        }
        guard let range = content.range(of: "<key>aps-environment</key>") else {
            return false
        }
        return content[range.upperBound...].prefix(120).contains("development")
        #endif
    }

    /// Requests notification permission for Whisper. Safe to call on every
    /// app launch — iOS only shows the prompt once.
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            // ignore — user can enable later in Settings
        }
    }

    /// Called from the AppDelegate `didRegisterForRemoteNotificationsWithDeviceToken`
    /// callback. Persists the hex token to UserDefaults and pushes it to
    /// Supabase if the user is signed in.
    func handleAPNsToken(_ tokenHex: String) {
        UserDefaults.standard.set(tokenHex, forKey: "whisper.apnsToken")
        Task { await self.upload(token: tokenHex) }
    }

    /// Re-uploads the cached APNs token (if any) for the currently signed-in
    /// user. Safe to call on every Whisper launch / sign-in — account
    /// switches re-claim the token for the new user.
    func registerIfNeeded() async {
        guard isRemote else { return }
        WhisperPushPreferenceSync.shared.refresh()
        guard let token = UserDefaults.standard.string(forKey: "whisper.apnsToken"),
              !token.isEmpty else { return }
        await upload(token: token)
    }

    /// Detaches the current device token from this user's account. Call on
    /// sign-out so a shared device doesn't keep delivering push to whoever
    /// signed in previously.
    func unregister() async {
        guard isRemote,
              let token = UserDefaults.standard.string(forKey: "whisper.apnsToken"),
              !token.isEmpty else { return }
        do {
            try await client.from("whisper_device_tokens")
                .delete()
                .eq("token", value: token)
                .eq("user_id", value: currentUID)
                .execute()
            lastUploadedToken = nil
            lastUploadedUID = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func upload(token: String) async {
        guard isRemote else { return }
        let uid = currentUID
        // Dedupe — skip only when the SAME account already uploaded this
        // exact token. A user switch must always re-claim.
        if lastUploadedToken == token && lastUploadedUID == uid { return }
        let bundleID = Bundle.main.bundleIdentifier
        let sandbox = Self.apnsEnvironmentIsSandbox()

        // 1) Preferred path: claim the token for the CURRENT account.
        do {
            try await client.rpc(
                "whisper_claim_device_token",
                params: WhisperDeviceTokenClaim(
                    p_token: token,
                    p_bundle_id: bundleID,
                    p_sandbox: sandbox,
                    p_platform: "ios"
                )
            ).execute()
            lastUploadedToken = token
            lastUploadedUID = uid
            lastError = nil
            return
        } catch {
            print("[Whisper] token claim rpc unavailable, falling back to upsert: \(error)")
        }

        // 2) Fallback: direct upsert (new schema).
        do {
            try await client.from("whisper_device_tokens")
                .upsert(WhisperDeviceTokenUpsert(
                    token: token,
                    user_id: uid,
                    platform: "ios",
                    bundle_id: bundleID,
                    sandbox: sandbox,
                    active: true
                ), onConflict: "token")
                .execute()
            lastUploadedToken = token
            lastUploadedUID = uid
            lastError = nil
            return
        } catch {
            print("[Whisper] push token upsert failed, trying legacy shape: \(error)")
        }

        // 3) Last resort: legacy schema (environment text column).
        do {
            try await client.from("whisper_device_tokens")
                .upsert(WhisperDeviceTokenLegacyUpsert(
                    token: token,
                    user_id: uid,
                    platform: "ios",
                    bundle_id: bundleID,
                    environment: sandbox ? "sandbox" : "production"
                ), onConflict: "token")
                .execute()
            lastUploadedToken = token
            lastUploadedUID = uid
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            print("[Whisper] push token upload failed: \(error)")
        }
    }
}
