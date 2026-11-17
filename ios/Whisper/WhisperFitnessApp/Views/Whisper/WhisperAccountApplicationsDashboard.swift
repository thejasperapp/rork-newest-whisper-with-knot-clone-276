import SwiftUI
import Supabase

// MARK: - Supabase policy notes
//
// Admins/mods/owner need UPDATE rights on:
//   - whisper_coach_applications, whisper_athlete_applications (status)
//   - profiles + whisper_profiles (is_coach / is_athlete flags)
//
// drop policy if exists "wca update mod" on public.whisper_coach_applications;
// create policy "wca update mod" on public.whisper_coach_applications
//   for update using (
//     exists (select 1 from public.profiles p
//             where p.id = auth.uid()
//               and (p.is_moderator = true or p.is_admin = true or p.is_owner = true))
//   );
// drop policy if exists "wca read mod" on public.whisper_coach_applications;
// create policy "wca read mod" on public.whisper_coach_applications
//   for select using (
//     auth.uid() = user_id
//     or exists (select 1 from public.profiles p
//                where p.id = auth.uid()
//                  and (p.is_moderator = true or p.is_admin = true or p.is_owner = true))
//   );
// -- Same two policies for public.whisper_athlete_applications (waa update mod / waa read mod).

// MARK: - Full row models

nonisolated struct WhisperCoachApplicationFullRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let username: String
    let email: String?
    let full_name: String
    let credentials: String?
    let specialties: [String]?
    let experience_years: Int?
    let bio: String?
    let website: String?
    let social: String?
    let status: String
    let created_at: String?
}

nonisolated struct WhisperAthleteApplicationFullRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let username: String
    let email: String?
    let full_name: String
    let sport: String?
    let level: String?
    let team: String?
    let prs: String?
    let bio: String?
    let social: String?
    let status: String
    let created_at: String?
}

nonisolated struct WhisperCoachFlagUpdate: Codable, Sendable {
    let is_coach: Bool
}

nonisolated struct WhisperAthleteFlagUpdate: Codable, Sendable {
    let is_athlete: Bool
}

nonisolated struct WhisperApplicationStatusUpdate: Codable, Sendable {
    let status: String
}

// MARK: - Service

/// Admin/mod/owner dashboard for reviewing Coach and Athlete applications.
/// Approving here flips the `is_coach` / `is_athlete` flags on both
/// `profiles` and `whisper_profiles` AND marks the application row as
/// `approved` in one tap. Denying just stamps the row as `denied`.
@MainActor
@Observable
final class WhisperAccountApplicationsService {
    static let shared = WhisperAccountApplicationsService()

    private let client = SupabaseService.shared.client

    var pendingCoaches: [WhisperCoachApplicationFullRow] = []
    var recentCoaches: [WhisperCoachApplicationFullRow] = []
    var pendingAthletes: [WhisperAthleteApplicationFullRow] = []
    var recentAthletes: [WhisperAthleteApplicationFullRow] = []
    var isLoading: Bool = false
    var lastError: String?

    private init() {}

    var pendingCount: Int { pendingCoaches.count + pendingAthletes.count }

    func loadDashboard() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadCoaches() }
            group.addTask { await self.loadAthletes() }
        }
    }

    private func loadCoaches() async {
        do {
            let pending: [WhisperCoachApplicationFullRow] = try await client
                .from("whisper_coach_applications")
                .select()
                .eq("status", value: "pending")
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            pendingCoaches = pending
            let recent: [WhisperCoachApplicationFullRow] = try await client
                .from("whisper_coach_applications")
                .select()
                .in("status", values: ["approved", "denied"])
                .order("created_at", ascending: false)
                .limit(40)
                .execute()
                .value
            recentCoaches = recent
        } catch {
            lastError = "Coach applications: \(error.localizedDescription)"
        }
    }

    private func loadAthletes() async {
        do {
            let pending: [WhisperAthleteApplicationFullRow] = try await client
                .from("whisper_athlete_applications")
                .select()
                .eq("status", value: "pending")
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            pendingAthletes = pending
            let recent: [WhisperAthleteApplicationFullRow] = try await client
                .from("whisper_athlete_applications")
                .select()
                .in("status", values: ["approved", "denied"])
                .order("created_at", ascending: false)
                .limit(40)
                .execute()
                .value
            recentAthletes = recent
        } catch {
            lastError = "Athlete applications: \(error.localizedDescription)"
        }
    }

    // MARK: - Coach decisions

    /// Approval no longer flips `is_coach` directly — the badge is paid
    /// (annual). Setting status to "approved" fires the Supabase trigger that
    /// emails the applicant an activation link; the Stripe webhook flips the
    /// flag once they pay.
    @discardableResult
    func approveCoach(_ row: WhisperCoachApplicationFullRow) async -> Bool {
        do {
            try await client.from("whisper_coach_applications")
                .update(WhisperApplicationStatusUpdate(status: "approved"))
                .eq("id", value: row.id)
                .execute()
            await loadDashboard()
            return true
        } catch {
            lastError = "Approve coach failed: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func denyCoach(_ row: WhisperCoachApplicationFullRow) async -> Bool {
        do {
            try await client.from("whisper_coach_applications")
                .update(WhisperApplicationStatusUpdate(status: "denied"))
                .eq("id", value: row.id)
                .execute()
            // Make sure the flag isn't lingering on either table.
            try? await client.from("profiles")
                .update(WhisperCoachFlagUpdate(is_coach: false))
                .eq("id", value: row.user_id)
                .execute()
            try? await client.from("whisper_profiles")
                .update(WhisperCoachFlagUpdate(is_coach: false))
                .eq("user_id", value: row.user_id)
                .execute()
            WhisperCoachService.shared.coachByUserID[row.user_id.lowercased()] = false
            WhisperCoachService.shared.coachByUsername[row.username.lowercased()] = false
            await loadDashboard()
            return true
        } catch {
            lastError = "Deny coach failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Athlete decisions

    /// Same paid-badge flow as coaches: approval only sets the status; the
    /// `is_athlete` flag flips when the annual badge payment completes.
    @discardableResult
    func approveAthlete(_ row: WhisperAthleteApplicationFullRow) async -> Bool {
        do {
            try await client.from("whisper_athlete_applications")
                .update(WhisperApplicationStatusUpdate(status: "approved"))
                .eq("id", value: row.id)
                .execute()
            await loadDashboard()
            return true
        } catch {
            lastError = "Approve athlete failed: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func denyAthlete(_ row: WhisperAthleteApplicationFullRow) async -> Bool {
        do {
            try await client.from("whisper_athlete_applications")
                .update(WhisperApplicationStatusUpdate(status: "denied"))
                .eq("id", value: row.id)
                .execute()
            try? await client.from("profiles")
                .update(WhisperAthleteFlagUpdate(is_athlete: false))
                .eq("id", value: row.user_id)
                .execute()
            try? await client.from("whisper_profiles")
                .update(WhisperAthleteFlagUpdate(is_athlete: false))
                .eq("user_id", value: row.user_id)
                .execute()
            WhisperAthleteService.shared.athleteByUserID[row.user_id.lowercased()] = false
            WhisperAthleteService.shared.athleteByUsername[row.username.lowercased()] = false
            await loadDashboard()
            return true
        } catch {
            lastError = "Deny athlete failed: \(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - View

/// Admin/mod/owner-only dashboard for Coach + Athlete special-account
/// applications. A segmented control switches between the two queues;
/// each row gets Approve / Decline buttons that flip the live role flags
/// in one tap (no more digging into the user's profile).
struct WhisperAccountApplicationsDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var service = WhisperAccountApplicationsService.shared
    @State private var verification = WhisperVerificationService.shared
    @State private var tab: Tab = .coach
    @State private var coachDetail: WhisperCoachApplicationFullRow?
    @State private var athleteDetail: WhisperAthleteApplicationFullRow?
    @State private var verifyDetail: WhisperVerificationRequestRow?
    @State private var verifyNote: String = ""

    private enum Tab: String, CaseIterable, Identifiable {
        case coach = "Coaches"
        case athlete = "Athletes"
        case verification = "Verified"
        var id: String { rawValue }
    }

    private var coachAccent: Color { Color(red: 0.97, green: 0.45, blue: 0.30) }
    private var athleteAccent: Color { WhisperAthleteApplicationView.athleteAccent }
    private var verifyAccent: Color { Color(red: 0.13, green: 0.55, blue: 0.96) }
    private var accent: Color {
        switch tab {
        case .coach: return coachAccent
        case .athlete: return athleteAccent
        case .verification: return verifyAccent
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        picker
                        if service.isLoading && currentPendingIsEmpty {
                            ProgressView()
                                .tint(WhisperTheme.ink(colorScheme))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if currentPendingIsEmpty {
                            if service.lastError == nil { emptyState }
                        } else {
                            pendingList
                        }
                        recentSection
                        if let err = service.lastError {
                            Button("Try again") { Task { await service.loadDashboard() } }.frame(minHeight: 44)
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 18)
                        }
                        Color.clear.frame(height: 32)
                    }
                    .padding(.top, 6)
                }
                .whisperRefreshable { await service.loadDashboard() }
            }
            .navigationTitle("Account reviews")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .sheet(item: $coachDetail) { row in coachDetailSheet(row) }
            .sheet(item: $athleteDetail) { row in athleteDetailSheet(row) }
            .sheet(item: $verifyDetail) { row in verifyDetailSheet(row) }
            .task {
                await service.loadDashboard()
                await verification.loadDashboard()
            }
        }
    }

    private var currentPendingIsEmpty: Bool {
        switch tab {
        case .coach: return service.pendingCoaches.isEmpty
        case .athlete: return service.pendingAthletes.isEmpty
        case .verification: return verification.pending.isEmpty
        }
    }

    private func tabAccent(_ t: Tab) -> Color {
        switch t {
        case .coach: return coachAccent
        case .athlete: return athleteAccent
        case .verification: return verifyAccent
        }
    }

    private func pendingCount(for t: Tab) -> Int {
        switch t {
        case .coach: return service.pendingCoaches.count
        case .athlete: return service.pendingAthletes.count
        case .verification: return verification.pending.count
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Account reviews")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Approve or decline Coach, Athlete, and Verification applications. Approving flips the role flag on the user's profile instantly.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.horizontal, 18)
    }

    private var picker: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { t in
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3)) { tab = t }
                } label: {
                    HStack(spacing: 6) {
                        Text(t.rawValue)
                            .font(.subheadline.weight(.bold))
                        let count = pendingCount(for: t)
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(tab == t ? tabAccent(t) : .white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(
                                    (tab == t ? Color.white : tabAccent(t)),
                                    in: Capsule()
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        tab == t ? tabAccent(t) : WhisperTheme.card(colorScheme),
                        in: Capsule()
                    )
                    .foregroundStyle(tab == t ? .white : WhisperTheme.ink(colorScheme))
                    .overlay {
                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: tab == t ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
    }

    private var emptyState: some View {
        let iconName: String = {
            switch tab {
            case .coach: return "figure.run.circle"
            case .athlete: return "trophy"
            case .verification: return "checkmark.seal"
            }
        }()
        let label: String = {
            switch tab {
            case .coach: return "coach"
            case .athlete: return "athlete"
            case .verification: return "verification"
            }
        }()
        return VStack(spacing: 8) {
            WhisperMeetDoodle(symbol: iconName, height: 144)
            Text("No pending \(label) applications")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("New submissions will appear here.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.top, 30)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Pending

    @ViewBuilder
    private var pendingList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pending review")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(.horizontal, 18)
            VStack(spacing: 10) {
                switch tab {
                case .coach:
                    ForEach(service.pendingCoaches) { row in
                        coachRow(row, showActions: true)
                    }
                case .athlete:
                    ForEach(service.pendingAthletes) { row in
                        athleteRow(row, showActions: true)
                    }
                case .verification:
                    ForEach(verification.pending) { row in
                        verifyRow(row, showActions: true)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        switch tab {
        case .coach:
            if !service.recentCoaches.isEmpty {
                recentHeader
                VStack(spacing: 10) {
                    ForEach(service.recentCoaches) { row in
                        coachRow(row, showActions: false)
                    }
                }
                .padding(.horizontal, 16)
            }
        case .athlete:
            if !service.recentAthletes.isEmpty {
                recentHeader
                VStack(spacing: 10) {
                    ForEach(service.recentAthletes) { row in
                        athleteRow(row, showActions: false)
                    }
                }
                .padding(.horizontal, 16)
            }
        case .verification:
            if !verification.recentDecisions.isEmpty {
                recentHeader
                VStack(spacing: 10) {
                    ForEach(verification.recentDecisions) { row in
                        verifyRow(row, showActions: false)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var recentHeader: some View {
        Text("Recent decisions")
            .font(.headline.weight(.bold))
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            .padding(.horizontal, 18)
    }

    // MARK: - Coach row

    private func coachRow(_ row: WhisperCoachApplicationFullRow, showActions: Bool) -> some View {
        Button {
            Haptics.tap()
            coachDetail = row
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    WhisperAvatar(username: row.username, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(row.full_name)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            statusPill(row.status, accent: coachAccent)
                        }
                        Text("@\(row.username)")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        if let specs = row.specialties, !specs.isEmpty {
                            Text(specs.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                if let bio = row.bio, !bio.isEmpty {
                    Text(bio).font(.footnote)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(3)
                }
                if showActions {
                    actionButtons(
                        approve: { Task { _ = await service.approveCoach(row) } },
                        deny: { Task { _ = await service.denyCoach(row) } },
                        accent: coachAccent
                    )
                }
            }
            .padding(14)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Athlete row

    private func athleteRow(_ row: WhisperAthleteApplicationFullRow, showActions: Bool) -> some View {
        Button {
            Haptics.tap()
            athleteDetail = row
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    WhisperAvatar(username: row.username, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(row.full_name)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            statusPill(row.status, accent: athleteAccent)
                        }
                        Text("@\(row.username)")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        let sport = row.sport ?? ""
                        let level = row.level ?? ""
                        let sub = [sport, level].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !sub.isEmpty {
                            Text(sub)
                                .font(.caption2)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                if let bio = row.bio, !bio.isEmpty {
                    Text(bio).font(.footnote)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(3)
                }
                if showActions {
                    actionButtons(
                        approve: { Task { _ = await service.approveAthlete(row) } },
                        deny: { Task { _ = await service.denyAthlete(row) } },
                        accent: athleteAccent
                    )
                }
            }
            .padding(14)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Verification row

    private func verifyRow(_ row: WhisperVerificationRequestRow, showActions: Bool) -> some View {
        Button {
            Haptics.tap()
            verifyNote = ""
            verifyDetail = row
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    WhisperAvatar(username: row.username, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(row.full_name)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            statusPill(row.status, accent: verifyAccent)
                        }
                        Text("@\(row.username) · \(row.category.replacingOccurrences(of: "_", with: " "))")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        if (row.followers ?? 0) > 0 {
                            Text("\(row.followers ?? 0) followers")
                                .font(.caption2)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                    }
                    Spacer()
                }
                if !row.reason.isEmpty {
                    Text(row.reason)
                        .font(.footnote)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(3)
                }
                if showActions {
                    actionButtons(
                        approve: { Task { _ = await verification.approve(row) } },
                        deny: { Task { _ = await verification.deny(row) } },
                        accent: verifyAccent
                    )
                }
            }
            .padding(14)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared bits

    private func actionButtons(approve: @escaping () -> Void, deny: @escaping () -> Void, accent: Color) -> some View {
        HStack(spacing: 10) {
            Button {
                Haptics.success()
                approve()
            } label: {
                Text("Approve")
                    .font(.footnote.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Button {
                Haptics.warning()
                deny()
            } label: {
                Text("Decline")
                    .font(.footnote.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(WhisperTheme.surface(colorScheme), in: Capsule())
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .overlay {
                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private func statusPill(_ status: String, accent: Color) -> some View {
        let (color, label): (Color, String) = {
            switch status {
            case "approved": return (accent, "Approved")
            case "denied":   return (Color.red, "Denied")
            default:         return (Color.orange, "Pending")
            }
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Detail sheets

    private func coachDetailSheet(_ row: WhisperCoachApplicationFullRow) -> some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        applicantHeader(username: row.username, fullName: row.full_name)
                        if let e = row.email, !e.isEmpty { detailRow("Email", e) }
                        if let yrs = row.experience_years, yrs > 0 { detailRow("Experience", "\(yrs) yrs") }
                        if let specs = row.specialties, !specs.isEmpty {
                            detailRow("Specialties", specs.joined(separator: ", "))
                        }
                        if let c = row.credentials, !c.isEmpty { detailRow("Credentials", c) }
                        if let b = row.bio, !b.isEmpty { detailRow("Bio", b) }
                        if let w = row.website, !w.isEmpty { detailRow("Website", w) }
                        if let s = row.social, !s.isEmpty { detailRow("Social", s) }
                        if row.status == "pending" {
                            actionButtons(
                                approve: {
                                    Task {
                                        _ = await service.approveCoach(row)
                                        coachDetail = nil
                                    }
                                },
                                deny: {
                                    Task {
                                        _ = await service.denyCoach(row)
                                        coachDetail = nil
                                    }
                                },
                                accent: coachAccent
                            )
                            .padding(.top, 8)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Coach application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { coachDetail = nil }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private func verifyDetailSheet(_ row: WhisperVerificationRequestRow) -> some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        applicantHeader(username: row.username, fullName: row.full_name)
                        detailRow("Category", row.category.replacingOccurrences(of: "_", with: " "))
                        if let e = row.email, !e.isEmpty { detailRow("Email", e) }
                        if (row.followers ?? 0) > 0 { detailRow("Followers", "\(row.followers ?? 0)") }
                        if !row.reason.isEmpty { detailRow("Reason", row.reason) }
                        if let links = row.links, !links.isEmpty { detailRow("Links", links) }
                        if let note = row.review_note, !note.isEmpty { detailRow("Review note", note) }
                        if row.status == "pending" {
                            TextField("Optional note for the applicant", text: $verifyNote, axis: .vertical)
                                .lineLimit(1...4)
                                .padding(10)
                                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }
                            actionButtons(
                                approve: {
                                    Task {
                                        _ = await verification.approve(row, note: verifyNote.isEmpty ? nil : verifyNote)
                                        verifyDetail = nil
                                        verifyNote = ""
                                    }
                                },
                                deny: {
                                    Task {
                                        _ = await verification.deny(row, note: verifyNote.isEmpty ? nil : verifyNote)
                                        verifyDetail = nil
                                        verifyNote = ""
                                    }
                                },
                                accent: verifyAccent
                            )
                            .padding(.top, 8)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Verification application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { verifyDetail = nil }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private func athleteDetailSheet(_ row: WhisperAthleteApplicationFullRow) -> some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        applicantHeader(username: row.username, fullName: row.full_name)
                        if let e = row.email, !e.isEmpty { detailRow("Email", e) }
                        if let sp = row.sport, !sp.isEmpty { detailRow("Sport", sp) }
                        if let lv = row.level, !lv.isEmpty { detailRow("Level", lv) }
                        if let t = row.team, !t.isEmpty { detailRow("Team", t) }
                        if let prs = row.prs, !prs.isEmpty { detailRow("Personal records", prs) }
                        if let b = row.bio, !b.isEmpty { detailRow("Bio", b) }
                        if let s = row.social, !s.isEmpty { detailRow("Social", s) }
                        if row.status == "pending" {
                            actionButtons(
                                approve: {
                                    Task {
                                        _ = await service.approveAthlete(row)
                                        athleteDetail = nil
                                    }
                                },
                                deny: {
                                    Task {
                                        _ = await service.denyAthlete(row)
                                        athleteDetail = nil
                                    }
                                },
                                accent: athleteAccent
                            )
                            .padding(.top, 8)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Athlete application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { athleteDetail = nil }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private func applicantHeader(username: String, fullName: String) -> some View {
        HStack(spacing: 10) {
            WhisperAvatar(username: username, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(fullName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("@\(username)")
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.heavy))
                .tracking(1)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Text(value)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
