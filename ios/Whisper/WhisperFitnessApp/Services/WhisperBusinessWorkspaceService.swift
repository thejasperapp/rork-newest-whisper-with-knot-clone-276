import Foundation
import Observation
import Supabase

/// Authenticated CRUD over the existing Business+ tables. Subscription state is read-only.
@MainActor @Observable
final class WhisperBusinessWorkspaceService {
    static let shared = WhisperBusinessWorkspaceService()
    private let client = SupabaseService.shared.client
    private var accountID: String = ""
    private var generation: UUID = UUID()
    private(set) var contextVersion: UUID = UUID()
    private var loadRequest: UUID = UUID()
    private var dataRequest: UUID = UUID()
    private var accessTask: Task<Void, Never>?
    private var availablePlans: [WhisperBusinessModels.Plan] = []
    private var selectedID: String?
    private var storedMembers: [WhisperBusinessModels.Member] = []
    private var storedEvents: [WhisperBusinessModels.Event] = []
    private(set) var isLoading: Bool = false
    private(set) var accessError: String?
    private(set) var teamError: String?
    private(set) var agendaError: String?

    private var isCurrentAccount: Bool {
        accountID == AccountStorage.currentUserID
            && client.auth.currentUser?.id.uuidString.lowercased() == accountID.lowercased()
    }
    var plans: [WhisperBusinessModels.Plan] { isCurrentAccount ? availablePlans : [] }
    var members: [WhisperBusinessModels.Member] { context == nil ? [] : storedMembers }
    var events: [WhisperBusinessModels.Event] { context == nil ? [] : storedEvents }
    var context: WhisperBusinessModels.Plan? {
        plans.first { $0.user_id == selectedID } ?? plans.first
    }
    var isOwner: Bool { context?.user_id.lowercased() == AccountStorage.currentUserID.lowercased() }

    /// Invalidates success, failure and cleanup callbacks from the outgoing account.
    func resetForCurrentAccount() {
        accessTask?.cancel()
        accessTask = nil
        generation = UUID()
        accountID = AccountStorage.currentUserID
        availablePlans = []
        selectedID = nil
        clearSelectedData()
        loadRequest = UUID()
        isLoading = false
        accessError = nil
    }

    private func clearSelectedData() {
        contextVersion = UUID()
        dataRequest = UUID()
        storedMembers = []
        storedEvents = []
        teamError = nil; agendaError = nil
    }

    func refreshAccess() async {
        if accountID != AccountStorage.currentUserID { resetForCurrentAccount() }
        guard isCurrentAccount, UUID(uuidString: accountID) != nil, !Task.isCancelled else { return }
        if let accessTask { await accessTask.value; return }
        let requestGeneration = generation
        let task = Task { await fetchAccess(generation: requestGeneration) }
        accessTask = task
        await task.value
        if generation == requestGeneration { accessTask = nil }
    }

    private func fetchAccess(generation requestGeneration: UUID) async {
        let uid = accountID
        do {
            // RLS returns only owned plans and plans reached through a team seat.
            let rows: [WhisperBusinessModels.Plan] = try await client.from("whisper_business_plus")
                .select("id,user_id,plan,status,company_name").eq("status", value: "active")
                .order("updated_at", ascending: false).execute().value
            guard isCurrentAccount, generation == requestGeneration, !Task.isCancelled else { return }
            let oldBusiness = context?.user_id
            availablePlans = rows.sorted {
                ($0.user_id.lowercased() == uid.lowercased() ? 0 : 1)
                    < ($1.user_id.lowercased() == uid.lowercased() ? 0 : 1)
            }
            if !rows.contains(where: { $0.user_id == selectedID }) { selectedID = availablePlans.first?.user_id }
            if oldBusiness != context?.user_id { clearSelectedData() }
            accessError = nil
        } catch {
            guard isCurrentAccount, generation == requestGeneration, !Task.isCancelled else { return }
            availablePlans = []
            selectedID = nil
            clearSelectedData()
            accessError = "Business+ isn't available right now. Check your connection, or ask your administrator to finish Business+ setup."
        }
    }

    func load() async {
        if accountID != AccountStorage.currentUserID { resetForCurrentAccount() }
        guard !isLoading, !Task.isCancelled else { return }
        let request = UUID()
        let requestGeneration = generation
        loadRequest = request
        isLoading = true
        defer { if loadRequest == request { isLoading = false } }
        await refreshAccess()
        guard generation == requestGeneration, isCurrentAccount, !Task.isCancelled else { return }
        await loadSelected()
    }

    func select(_ businessID: String) async {
        guard !isLoading, !Task.isCancelled, plans.contains(where: { $0.user_id == businessID }) else { return }
        selectedID = businessID
        clearSelectedData()
        let request = UUID()
        loadRequest = request
        isLoading = true
        defer { if loadRequest == request { isLoading = false } }
        await loadSelected()
    }

    private func loadSelected() async {
        guard let business = context else { return }
        let version = contextVersion
        let request = UUID()
        dataRequest = request
        async let team: Void = loadTeam(businessID: business.user_id, version: version, request: request)
        async let agenda: Void = loadAgenda(businessID: business.user_id, version: version, request: request)
        _ = await (team, agenda)
    }

    private func loadTeam(businessID: String, version: UUID, request: UUID) async {
        do {
            let rows: [WhisperBusinessModels.Member] = try await client.from("whisper_business_team")
                .select().eq("business_id", value: businessID).order("added_at", ascending: true).execute().value
            guard isCurrentAccount, contextVersion == version, dataRequest == request, !Task.isCancelled else { return }
            storedMembers = rows; teamError = nil
        } catch {
            guard isCurrentAccount, contextVersion == version, dataRequest == request, !Task.isCancelled else { return }
            teamError = "Your team couldn’t refresh. Please try again."
        }
    }

    private func loadAgenda(businessID: String, version: UUID, request: UUID) async {
        do {
            let rows: [WhisperBusinessModels.Event] = try await client.from("whisper_calendar_events")
                .select().eq("business_id", value: businessID)
                .gte("start_time", value: Date().addingTimeInterval(-14 * 86400).ISO8601Format())
                .order("start_time", ascending: true).limit(100).execute().value
            guard isCurrentAccount, contextVersion == version, dataRequest == request, !Task.isCancelled else { return }
            storedEvents = rows; agendaError = nil
        } catch {
            guard isCurrentAccount, contextVersion == version, dataRequest == request, !Task.isCancelled else { return }
            agendaError = "Your agenda couldn’t refresh. Please try again."
        }
    }

    private func requireContext(_ version: UUID) throws {
        try Task.checkCancellation()
        guard isCurrentAccount, context != nil, contextVersion == version else {
            throw WhisperBusinessModels.Failure.contextChanged
        }
    }

    func renameCompany(_ name: String) async throws {
        guard let business = context, isOwner else { throw WhisperBusinessModels.Failure.owner }
        let version = contextVersion
        try requireContext(version)
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 100 else { throw WhisperBusinessModels.Failure.save }
        let rows: [WhisperBusinessModels.Plan] = try await client.from("whisper_business_plus")
            .update(["company_name": clean]).eq("id", value: business.id).eq("user_id", value: business.user_id)
            .select("id,user_id,plan,status,company_name").execute().value
        try requireContext(version)
        guard let saved = rows.first else { throw WhisperBusinessModels.Failure.save }
        if let index = availablePlans.firstIndex(where: { $0.id == saved.id }) { availablePlans[index] = saved }
    }

    func saveMember(username: String, role: String, existing: WhisperBusinessModels.Member? = nil) async throws {
        guard let business = context, isOwner else { throw WhisperBusinessModels.Failure.owner }
        let version = contextVersion
        try requireContext(version)
        let title = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count <= 80 else { throw WhisperBusinessModels.Failure.save }
        let person: WhisperBusinessModels.Member
        if let existing {
            guard existing.business_id == business.user_id else { throw WhisperBusinessModels.Failure.contextChanged }
            person = existing
        } else {
            let handle = username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
            guard !handle.isEmpty else { throw WhisperBusinessModels.Failure.notFound }
            let user = await WhisperUserService.shared.fetchByUsername(handle)
            try requireContext(version)
            guard let user, user.username.lowercased() == handle.lowercased(), user.user_id.lowercased() != business.user_id.lowercased() else { throw WhisperBusinessModels.Failure.notFound }
            person = .init(business_id: business.user_id, user_id: user.user_id, username: user.username,
                           role_title: title, accent: "#FF7340")
        }
        let row = WhisperBusinessModels.Member(business_id: business.user_id, user_id: person.user_id,
            username: person.username, role_title: title.isEmpty ? "Team member" : title, accent: person.accent)
        try requireContext(version)
        let saved: [WhisperBusinessModels.Member] = try await client.from("whisper_business_team")
            .upsert(row, onConflict: "business_id,user_id").select().execute().value
        try requireContext(version)
        guard let member = saved.first else { throw WhisperBusinessModels.Failure.save }
        dataRequest = UUID()
        storedMembers.removeAll { $0.id == member.id }
        storedMembers.append(member)
    }

    func removeMember(_ member: WhisperBusinessModels.Member) async throws {
        guard let business = context, isOwner, member.business_id == business.user_id else { throw WhisperBusinessModels.Failure.owner }
        let version = contextVersion
        try requireContext(version)
        let removed: [WhisperBusinessModels.Member] = try await client.from("whisper_business_team")
            .delete().eq("business_id", value: business.user_id).eq("user_id", value: member.user_id)
            .select().execute().value
        try requireContext(version)
        guard !removed.isEmpty else { throw WhisperBusinessModels.Failure.save }
        dataRequest = UUID()
        storedMembers.removeAll { $0.id == member.id }
    }

    func createEvent(id: String, title: String, details: String, start: Date, minutes: Int, meetingLink: String) async throws {
        guard let business = context else { throw WhisperBusinessModels.Failure.access }
        let version = contextVersion
        let uid = accountID
        try requireContext(version)
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 150, details.count <= 4000,
              UUID(uuidString: id) != nil, (1...1440).contains(minutes), start.timeIntervalSince1970.isFinite else {
            throw WhisperBusinessModels.Failure.save
        }
        let link = meetingLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard link.isEmpty || WhisperServedAd.webURL(link) != nil else { throw WhisperBusinessModels.Failure.save }
        let payload: [String: String] = [
            "id": id, "business_id": business.user_id, "created_by": uid,
            "created_by_username": LeaderboardService.shared.savedUsername ?? AuthenticationService.shared.currentUser.username ?? "member",
            "title": clean, "description": details, "event_type": "meet",
            "start_time": start.ISO8601Format(), "end_time": start.addingTimeInterval(Double(minutes) * 60).ISO8601Format(),
            "meeting_link": WhisperServedAd.webURL(link)?.absoluteString ?? ""
        ]
        let saved: [WhisperBusinessModels.Event] = try await client.from("whisper_calendar_events")
            .insert(payload).select().execute().value
        try requireContext(version)
        guard let event = saved.first else { throw WhisperBusinessModels.Failure.save }
        dataRequest = UUID()
        storedEvents.removeAll { $0.id == event.id }
        storedEvents.append(event)
        storedEvents.sort { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    func deleteEvent(_ event: WhisperBusinessModels.Event) async throws {
        guard let business = context, event.business_id == business.user_id else { throw WhisperBusinessModels.Failure.contextChanged }
        guard event.created_by.lowercased() == accountID.lowercased() else { throw WhisperBusinessModels.Failure.eventOwner }
        let version = contextVersion
        try requireContext(version)
        let removed: [WhisperBusinessModels.Event] = try await client.from("whisper_calendar_events")
            .delete().eq("id", value: event.id).eq("created_by", value: accountID)
            .eq("business_id", value: business.user_id).select().execute().value
        try requireContext(version)
        guard !removed.isEmpty else { throw WhisperBusinessModels.Failure.save }
        dataRequest = UUID()
        storedEvents.removeAll { $0.id == event.id }
    }
}
