import Foundation
import Contacts
import CryptoKit
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_contact_identities (
//   user_id uuid not null references auth.users(id) on delete cascade,
//   hash text not null,                         -- SHA-256(lowercased email or E.164 phone)
//   kind text not null default 'phone',         -- 'phone' | 'email'
//   created_at timestamptz not null default now(),
//   primary key (user_id, hash)
// );
// create index if not exists whisper_contact_identities_hash_idx
//   on public.whisper_contact_identities (hash);
// alter table public.whisper_contact_identities enable row level security;
// -- A signed-in user can write only their own identities.
// create policy "wci insert own" on public.whisper_contact_identities
//   for insert with check (auth.uid() = user_id);
// create policy "wci delete own" on public.whisper_contact_identities
//   for delete using (auth.uid() = user_id);
// -- Any signed-in user can match against the table (only hashes are exposed).
// create policy "wci read all" on public.whisper_contact_identities
//   for select using (auth.role() = 'authenticated');

nonisolated struct WhisperContactIdentityInsert: Codable, Sendable {
    let user_id: String
    let hash: String
    let kind: String
}

nonisolated struct WhisperContactIdentityRow: Codable, Sendable, Hashable {
    let user_id: String
    let hash: String
    let kind: String?
}

/// Result of a contacts match: the resolved Whisper profile + which of the
/// user's contacts it matched (so we can render "John Smith — @johns").
struct WhisperContactMatch: Identifiable, Hashable {
    let profile: WhisperUserRow
    let contactName: String?
    var id: String { profile.user_id }
}

/// Find-Friends-from-Contacts pipeline. We never upload raw phone numbers or
/// emails — only SHA-256 hashes — so this is privacy-preserving. The user's
/// own identities (their email + Apple/Google phone if available) are written
/// to `whisper_contact_identities` so other users' devices can match against
/// them when they hash their own address book.
@MainActor
@Observable
final class WhisperContactsService {
    static let shared = WhisperContactsService()

    private let client = SupabaseService.shared.client
    private let store = CNContactStore()
    private let publishedKey = "whisper.contacts.publishedIdentities.v2"
    @ObservationIgnored private var publicationTask: Task<Bool, Never>?

    var isLoading: Bool = false
    var lastError: String?
    var permission: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    /// Latest match list (sorted by contact name).
    var matches: [WhisperContactMatch] = []
    /// Local snapshot of the user's full contact list (name + best identifier)
    /// used to render the "Invite" rail for people who aren't on Whisper yet.
    var inviteCandidates: [WhisperInviteContact] = []

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private init() {}

    // MARK: - Permission

    func refreshPermission() {
        permission = CNContactStore.authorizationStatus(for: .contacts)
    }

    /// Requests Contacts access. Returns true if granted.
    @discardableResult
    func requestAccess() async -> Bool {
        if permission == .authorized || permission == .limited { return true }
        do {
            let granted = try await store.requestAccess(for: .contacts)
            refreshPermission()
            return granted
        } catch {
            lastError = error.localizedDescription
            refreshPermission()
            return false
        }
    }

    // MARK: - Publish my identities

    /// Hashes the local user's email + phone (if any) and writes them so
    /// other users searching their contacts can find this account. Safe to
    /// re-run — uses upsert. Persists a flag so we don't re-publish on every
    /// app launch unless the underlying identifiers change.
    ///
    /// Honors `WhisperPhoneService.discoverable`: when the user has opted
    /// out of phone discovery we wipe every existing identity row for them
    /// so nobody can match them by phone (or email).
    @discardableResult
    func publishMyIdentities(force: Bool = false) async -> Bool {
        let owner = currentUID
        let generation = AccountStorage.generation
        let previous = publicationTask
        let task = Task { @MainActor in
            if let previous { _ = await previous.value }
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == self.currentUID else { return false }
            return await self.reconcileIdentities(owner: owner, generation: generation, force: force)
        }
        publicationTask = task
        let result = await task.value
        if publicationTask == task { publicationTask = nil }
        return result
    }

    func resetForCurrentAccount() {
        publicationTask?.cancel()
        publicationTask = nil
        matches = []
        inviteCandidates = []
        lastError = nil
        isLoading = false
    }

    private func reconcileIdentities(owner: String, generation: UUID, force: Bool) async -> Bool {
        func checkOwner() throws {
            try Task.checkCancellation()
            guard generation == AccountStorage.generation, owner == currentUID,
                  client.auth.currentUser?.id.uuidString.lowercased() == owner.lowercased() else { throw CancellationError() }
        }
        let phoneService = WhisperPhoneService.shared
        guard await phoneService.hydrate() else { return false }
        do {
            try checkOwner()
            var rows: [WhisperContactIdentityInsert] = []
            if phoneService.discoverable {
                if let email = AuthenticationService.shared.currentUser.email, !email.isEmpty {
                    rows.append(.init(user_id: owner, hash: Self.hashEmail(email), kind: "email"))
                }
                if let phone = phoneService.phone {
                    rows += Self.phoneHashVariants(phone).map { .init(user_id: owner, hash: $0, kind: "phone") }
                }
            }
            let signature = rows.map(\.hash).sorted().joined(separator: ",")
            if !force, AccountStorage.string(forKey: publishedKey) == signature { return true }
            let existing: [WhisperContactIdentityRow] = try await client.from("whisper_contact_identities")
                .select("user_id,hash,kind").eq("user_id", value: owner).execute().value
            try checkOwner()
            let desired = Set(rows.map(\.hash))
            let obsolete = existing.map(\.hash).filter { !desired.contains($0) }
            if !obsolete.isEmpty {
                try await client.from("whisper_contact_identities").delete()
                    .eq("user_id", value: owner).in("hash", values: obsolete).execute()
            }
            try checkOwner()
            if !rows.isEmpty {
                try await client.from("whisper_contact_identities").upsert(rows, onConflict: "user_id,hash").execute()
            }
            try checkOwner()
            AccountStorage.set(signature, forKey: publishedKey)
            return true
        } catch {
            guard generation == AccountStorage.generation else { return false }
            lastError = "Contact discovery couldn’t be synced. Please try again."
            return false
        }
    }

    // MARK: - Match

    /// Fetches contacts from the address book, hashes them, queries Supabase
    /// for matches, and resolves to full `WhisperUserRow` profiles. Updates
    /// `matches` and `inviteCandidates` on the main actor.
    func findFriends() async {
        guard isRemote else {
            lastError = "Sign in to find friends from your contacts."
            return
        }
        refreshPermission()
        if permission != .authorized && permission != .limited {
            let ok = await requestAccess()
            guard ok else { return }
        }
        isLoading = true
        defer { isLoading = false }
        let (hashToName, invites) = await Self.scanContacts(store: store)
        inviteCandidates = invites
        guard !hashToName.isEmpty else {
            matches = []
            return
        }
        do {
            // PostgREST `in` filter expects a Postgres array literal. Chunk
            // to avoid hitting URL length limits on large address books.
            var matchedUserIDs: [String: String] = [:] // user_id -> first matched contact name
            let chunks = Array(hashToName.keys).chunked(into: 250)
            for chunk in chunks {
                let rows: [WhisperContactIdentityRow] = try await client
                    .from("whisper_contact_identities")
                    .select("user_id,hash,kind")
                    .in("hash", values: chunk)
                    .neq("user_id", value: currentUID)
                    .execute()
                    .value
                for row in rows where matchedUserIDs[row.user_id] == nil {
                    matchedUserIDs[row.user_id] = hashToName[row.hash]
                }
            }
            guard !matchedUserIDs.isEmpty else {
                matches = []
                return
            }
            let profiles: [WhisperUserRow] = try await client
                .from("whisper_profiles")
                .select()
                .in("user_id", values: Array(matchedUserIDs.keys))
                .execute()
                .value
            let resolved: [WhisperContactMatch] = profiles.map { p in
                WhisperContactMatch(profile: p, contactName: matchedUserIDs[p.user_id])
            }
            matches = resolved.sorted { ($0.contactName ?? $0.profile.username).localizedCaseInsensitiveCompare($1.contactName ?? $1.profile.username) == .orderedAscending }
            Analytics.record("contacts_matched", ["count": String(resolved.count)])
        } catch {
            lastError = error.localizedDescription
            print("[Whisper] findFriends error: \(error)")
        }
    }

    // MARK: - Scanning

    /// Walks the address book and returns:
    ///  - a map of `hash -> displayName` for every email + phone variant
    ///  - an array of `WhisperInviteContact` for the invite rail
    private static func scanContacts(store: CNContactStore) async -> ([String: String], [WhisperInviteContact]) {
        await Task.detached(priority: .userInitiated) { () -> ([String: String], [WhisperInviteContact]) in
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .givenName
            var hashToName: [String: String] = [:]
            var invites: [WhisperInviteContact] = []
            do {
                try store.enumerateContacts(with: request) { contact, _ in
                    let name = [contact.givenName, contact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    var addedAny = false
                    for phone in contact.phoneNumbers {
                        let raw = phone.value.stringValue
                        for h in phoneHashVariants(raw) {
                            if hashToName[h] == nil { hashToName[h] = name.isEmpty ? raw : name }
                            addedAny = true
                        }
                    }
                    for email in contact.emailAddresses {
                        let raw = email.value as String
                        let h = hashEmail(raw)
                        if hashToName[h] == nil { hashToName[h] = name.isEmpty ? raw : name }
                        addedAny = true
                    }
                    // Build invite candidate even if we matched on a hash —
                    // we'll filter the rail later so it doesn't duplicate.
                    if addedAny {
                        let phone = contact.phoneNumbers.first?.value.stringValue
                        let email = contact.emailAddresses.first?.value as String?
                        invites.append(.init(
                            id: contact.identifier,
                            name: name.isEmpty ? (phone ?? email ?? "Unknown") : name,
                            phone: phone,
                            email: email
                        ))
                    }
                }
            } catch {
                print("[Whisper] enumerateContacts error: \(error)")
            }
            return (hashToName, invites)
        }.value
    }

    // MARK: - Hashing

    /// Lowercases & trims, then SHA-256. Stable across devices.
    nonisolated static func hashEmail(_ email: String) -> String {
        let normalized = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return sha256Hex(normalized)
    }

    /// Returns up to two phone hashes:
    ///  - the digits-only string (matches international users without +)
    ///  - the same string with a leading + (matches strict E.164)
    /// This gives us a good chance of catching matches without a phone
    /// number library — at the cost of a couple extra rows per contact.
    nonisolated static func phoneHashVariants(_ phone: String) -> [String] {
        let digits = phone.filter { $0.isNumber }
        guard digits.count >= 7 else { return [] }
        // Trim leading zeros so "0044" and "+44" hash the same.
        let trimmed = digits.drop(while: { $0 == "0" })
        var variants: Set<String> = []
        variants.insert(sha256Hex(String(trimmed)))
        variants.insert(sha256Hex("+" + String(trimmed)))
        // Heuristic for North-American 10-digit numbers — also try with
        // a leading "1" so it lines up with users who saved with country code.
        if trimmed.count == 10 {
            variants.insert(sha256Hex("1" + String(trimmed)))
            variants.insert(sha256Hex("+1" + String(trimmed)))
        }
        return Array(variants)
    }

    nonisolated private static func sha256Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// A contact who isn't on Whisper yet — shown in the Invite rail with a
/// system share sheet on tap.
struct WhisperInviteContact: Identifiable, Hashable {
    let id: String
    let name: String
    let phone: String?
    let email: String?
}

// MARK: - Array chunking helper

fileprivate extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
