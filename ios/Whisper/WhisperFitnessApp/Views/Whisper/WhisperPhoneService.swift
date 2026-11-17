import Foundation
import Supabase

// MARK: - Supabase schema (added by user)
//
// alter table public.profiles
//   add column phone text,
//   add column discoverable_by_phone boolean not null default true;
// create unique index profiles_phone_key on public.profiles (phone) where phone is not null;

/// Stores and reads the user's phone number on `public.profiles.phone` plus a
/// `discoverable_by_phone` privacy flag. Also publishes the phone hash into
/// `whisper_contact_identities` so other users' Find-Friends scans can match
/// against it (and tears that row down when the user opts out).
@MainActor
@Observable
final class WhisperPhoneService {
    static let shared = WhisperPhoneService()

    private let client = SupabaseService.shared.client

    /// Current stored phone in E.164 form (e.g. `+15551234567`). `nil` if unset.
    var phone: String?
    /// Whether other users can find this account by phone hash. Defaults to true.
    var discoverable: Bool = false
    var isSaving: Bool = false
    var lastError: String?
    private var hasHydrated: Bool = false
    private var revision: Int = 0

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private init() {}

    func resetForCurrentAccount() {
        revision += 1
        phone = nil
        discoverable = false
        hasHydrated = false
        isSaving = false
        lastError = nil
    }

    private func isCurrent(_ owner: String, _ generation: UUID) -> Bool {
        !Task.isCancelled && generation == AccountStorage.generation && owner == currentUID
            && client.auth.currentUser?.id.uuidString.lowercased() == owner.lowercased()
    }

    // MARK: - Hydrate

    /// One-shot hydrate from Supabase. Safe to call repeatedly — only the
    /// first remote call actually fetches.
    @discardableResult
    func hydrate(force: Bool = false) async -> Bool {
        guard isRemote else { return false }
        if hasHydrated && (!force || isSaving) { return true }
        let requestRevision = revision
        let owner = currentUID
        let generation = AccountStorage.generation
        nonisolated struct Row: Decodable, Sendable {
            let phone: String?
            let discoverable_by_phone: Bool?
        }
        do {
            let row: Row = try await client
                .from("profiles")
                .select("phone,discoverable_by_phone")
                .eq("id", value: currentUID)
                .single()
                .execute()
                .value
            guard isCurrent(owner, generation), requestRevision == revision else { return false }
            phone = row.phone
            discoverable = row.discoverable_by_phone ?? false
            hasHydrated = true
            lastError = nil
            return true
        } catch {
            guard isCurrent(owner, generation), requestRevision == revision else { return false }
            lastError = "Phone settings couldn’t be loaded. Try again."
            return false
        }
    }

    // MARK: - Save

    /// Validates + normalizes, writes to `profiles`, mirrors to local cache,
    /// and re-publishes/tears down the contact-identity hash row. Returns nil
    /// on success or an error string for the UI.
    @discardableResult
    func save(rawPhone: String) async -> String? {
        guard isRemote else { return "Sign in to add a phone number." }
        guard let e164 = Self.normalizeE164(rawPhone) else {
            return "Enter a valid number, including country code."
        }
        guard !isSaving else { return "An update is already in progress." }
        revision += 1
        isSaving = true
        let owner = currentUID
        let generation = AccountStorage.generation
        lastError = nil
        defer { if generation == AccountStorage.generation { isSaving = false } }
        guard await hydrate(), isCurrent(owner, generation) else { return "Phone settings couldn’t be loaded. Try again." }
        do {
            nonisolated struct Update: Encodable, Sendable { let phone: String }
            _ = try await client
                .from("profiles")
                .update(Update(phone: e164))
                .eq("id", value: currentUID)
                .execute()
            guard isCurrent(owner, generation) else { return "Account changed. Please try again." }
            phone = e164
            let synced = await WhisperContactsService.shared.publishMyIdentities(force: true)
            guard isCurrent(owner, generation) else { return "Account changed. Please try again." }
            guard synced else {
                lastError = "Your number was saved, but contact discovery needs to sync. Try saving again."
                return lastError
            }
            guard isCurrent(owner, generation) else { return "Account changed. Please try again." }
            Analytics.record("whisper_phone_saved")
            return nil
        } catch {
            guard isCurrent(owner, generation) else { return "Account changed. Please try again." }
            lastError = "Phone settings couldn’t be saved. Please try again."
            // Most likely cause: unique-index conflict (another account
            // claimed this number). Surface a friendlier message.
            let desc = error.localizedDescription.lowercased()
            if desc.contains("duplicate") || desc.contains("unique") {
                return "That number is already linked to another account."
            }
            return error.localizedDescription
        }
    }

    /// Removes the phone from the profile row + identity table.
    @discardableResult
    func remove() async -> String? {
        guard isRemote else { return nil }
        guard !isSaving else { return "An update is already in progress." }
        revision += 1
        isSaving = true
        let owner = currentUID
        let generation = AccountStorage.generation
        lastError = nil
        defer { if generation == AccountStorage.generation { isSaving = false } }
        guard await hydrate(), isCurrent(owner, generation) else { return "Phone settings couldn’t be loaded. Try again." }
        do {
            nonisolated struct ClearPhone: Encodable, Sendable {
                enum CodingKeys: String, CodingKey { case phone }
                func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    try container.encodeNil(forKey: .phone)
                }
            }
            _ = try await client
                .from("profiles")
                .update(ClearPhone())
                .eq("id", value: currentUID)
                .execute()
            guard isCurrent(owner, generation) else { return "Account changed. Please try again." }
            phone = nil
            let synced = await WhisperContactsService.shared.publishMyIdentities(force: true)
            guard isCurrent(owner, generation) else { return "Account changed. Please try again." }
            guard synced else {
                lastError = "Your number was removed, but old contact matches couldn’t be cleared. Retry removal."
                return lastError
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Updates the discoverable flag on the profile and re-syncs identity rows.
    func setDiscoverable(_ value: Bool) async {
        guard isRemote, !isSaving else { return }
        let owner = currentUID
        let generation = AccountStorage.generation
        revision += 1
        isSaving = true
        lastError = nil
        defer { if generation == AccountStorage.generation { isSaving = false } }
        nonisolated struct Update: Encodable, Sendable { let discoverable_by_phone: Bool }
        do {
            _ = try await client.from("profiles").update(Update(discoverable_by_phone: value))
                .eq("id", value: owner).execute()
            guard isCurrent(owner, generation) else { return }
            discoverable = value
            hasHydrated = false
            guard await hydrate(force: true), isCurrent(owner, generation) else { return }
            let synced = await WhisperContactsService.shared.publishMyIdentities(force: true)
            guard isCurrent(owner, generation) else { return }
            if !synced { lastError = "Your preference was saved, but contact matching hasn’t synced. Retry to finish applying it." }
        } catch {
            guard isCurrent(owner, generation) else { return }
            lastError = "Discovery wasn’t updated. Check your connection and try again."
        }
    }

    // MARK: - E.164 normalization

    /// Best-effort E.164 normalization. We don't ship a phone-number library
    /// in the sandbox, so we apply pragmatic rules:
    ///   - keep only digits + a leading `+`
    ///   - require at least 8 digits, max 15 (E.164 spec)
    ///   - if no `+` provided and length is 10, assume NANP (`+1`)
    ///   - if no `+` provided and length > 10, prepend `+`
    nonisolated static func normalizeE164(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hasPlus = trimmed.hasPrefix("+")
        let digits = trimmed.filter { $0.isNumber }
        guard digits.count >= 8, digits.count <= 15 else { return nil }
        if hasPlus { return "+" + digits }
        if digits.count == 10 { return "+1" + digits }
        return "+" + digits
    }

    /// Human-readable rendering of an E.164 number for the UI. Falls back to
    /// the raw value if we can't infer a country group.
    nonisolated static func displayFormatted(_ e164: String) -> String {
        guard e164.hasPrefix("+") else { return e164 }
        let digits = e164.dropFirst()
        // US/Canada: +1 NPA-NXX-XXXX
        if digits.count == 11, digits.hasPrefix("1") {
            let area = digits.index(digits.startIndex, offsetBy: 1)
            let mid  = digits.index(digits.startIndex, offsetBy: 4)
            let end  = digits.index(digits.startIndex, offsetBy: 7)
            return "+1 (\(digits[area..<mid])) \(digits[mid..<end])-\(digits[end...])"
        }
        return e164
    }
}
