import SwiftUI
import Supabase

nonisolated struct WhisperContactPermission: Codable, Identifiable, Sendable {
    let recipient_id: String
    let sender_id: String
    let allowed: Bool
    var id: String { sender_id }
}
nonisolated struct WhisperContactCandidate: Codable, Identifiable, Sendable {
    let user_id: String
    let username: String
    var id: String { user_id }
}

struct WhisperContactPermissionsView: View {
    @State private var username = ""
    @State private var candidate: WhisperContactCandidate?
    @State private var permissions: [WhisperContactPermission] = []
    @State private var names: [String: String] = [:]
    @State private var working = false
    @State private var message: String?
    var body: some View {
        Form {
            Section("Explicit permission") {
                Text("Adult-to-teen first-contact messages require the teen’s explicit permission. Unknown age does not bypass contact checks. Age is self-declared, not verified.").font(.subheadline)
                Text("A prior message alone is not permission. Allowing a contact never overrides a block or active messaging restriction.").font(.caption).foregroundStyle(.secondary)
                TextField("Exact username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().onChange(of: username) { _, _ in candidate = nil }
                Button("Find contact") { Task { await find() } }.disabled(working || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let candidate { Button("Explicitly allow @\(candidate.username) to message me") { Task { await save(candidate.user_id, allowed: true) } }.disabled(working) }
                if let message { Text(message).font(.subheadline).accessibilityAddTraits(.updatesFrequently) }
            }
            Section("Permitted contacts") {
                ForEach(permissions.filter(\.allowed)) { permission in
                    HStack { Text(names[permission.sender_id.lowercased()].map { "@" + $0 } ?? "Permitted contact"); Spacer(); Button("Revoke", role: .destructive) { Task { await save(permission.sender_id, allowed: false) } }.disabled(working) }
                }
                Text("Revoking explicit permission restores the default age-based contact rules; use Block to stop all new direct messages.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Permitted contacts").task(id: AccountStorage.generation) { await load() }.refreshable { await load() }
    }
    @MainActor private func find() async {
        let session = WhisperReviewSession(); working = true; message = nil; candidate = nil
        do {
            try session.check()
            let rows: [WhisperContactCandidate] = try await SupabaseService.shared.client.from("whisper_profiles").select("user_id,username").eq("username", value: username.trimmingCharacters(in: CharacterSet(charactersIn: "@ ").union(.whitespacesAndNewlines)).lowercased()).limit(1).execute().value
            try session.check(); candidate = rows.first { $0.user_id.lowercased() != session.owner.lowercased() }; working = false
            if candidate == nil { message = "No matching contact found." }
        } catch is CancellationError { } catch { guard session.generation == AccountStorage.generation else { return }; working = false; message = "Contact lookup failed. Please retry." }
    }
    @MainActor private func load() async {
        let session = WhisperReviewSession(); let client = SupabaseService.shared.client
        do {
            try session.check()
            let rows: [WhisperContactPermission] = try await client.from("whisper_contact_permissions").select().eq("recipient_id", value: session.owner).execute().value
            try session.check()
            var lookup: [String: String] = [:]
            if !rows.isEmpty {
                let profiles: [WhisperContactCandidate] = try await client.from("whisper_profiles").select("user_id,username").in("user_id", values: rows.map(\.sender_id)).execute().value
                try session.check(); for profile in profiles { lookup[profile.user_id.lowercased()] = profile.username }
            }
            permissions = rows; names = lookup
        } catch is CancellationError { } catch { guard session.generation == AccountStorage.generation else { return }; message = "Contact permissions could not be loaded. Pull to refresh." }
    }
    @MainActor private func save(_ peer: String, allowed: Bool) async {
        let session = WhisperReviewSession(); working = true; message = nil
        do {
            try session.check()
            let persisted: WhisperContactPermission = try await SupabaseService.shared.client.from("whisper_contact_permissions").upsert(WhisperContactPermission(recipient_id: session.owner, sender_id: peer, allowed: allowed), onConflict: "recipient_id,sender_id").select().single().execute().value
            try session.check()
            guard persisted.allowed == allowed, persisted.sender_id.lowercased() == peer.lowercased() else { throw CancellationError() }
            message = allowed ? "Explicit permission saved." : "Explicit permission revoked."; candidate = nil; working = false; await load()
        } catch is CancellationError { } catch { guard session.generation == AccountStorage.generation else { return }; working = false; message = "Permission not confirmed. Refresh before trying again." }
    }
}

struct WhisperProfessionalRolesText: View {
    let username: String
    @State private var roles: [String] = []
    var body: some View {
        Group { if !roles.isEmpty { Text(roles.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary) } }
            .task(id: "\(username)-\(AccountStorage.generation)") {
                let session = WhisperReviewSession()
                nonisolated struct Roles: Decodable, Sendable { let is_coach: Bool?; let is_director: Bool?; let is_recruiter: Bool?; let is_blogger: Bool?; let account_type: String? }
                do {
                    try session.check()
                    let rows: [Roles] = try await SupabaseService.shared.client.from("whisper_profiles").select("is_coach,is_director,is_recruiter,is_blogger,account_type").eq("username", value: username).limit(1).execute().value
                    try session.check()
                    guard let row = rows.first else { roles = []; return }
                    roles = [(row.is_coach == true ? "Coach" : nil), (row.is_recruiter == true ? "Recruiter" : nil), (row.is_director == true ? "Director" : nil), (row.is_blogger == true ? "Writer" : nil), (row.account_type == "creator" ? "Creator" : nil)].compactMap { $0 }
                } catch { if session.generation == AccountStorage.generation { roles = [] } }
            }
    }
}
