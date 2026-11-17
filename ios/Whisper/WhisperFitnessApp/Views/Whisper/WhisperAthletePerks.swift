import SwiftUI
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// -- Personal record stat sheet (athlete-only). Each row is one lift / event.
// create table if not exists public.whisper_athlete_prs (
//   id uuid primary key default gen_random_uuid(),
//   user_id uuid not null references auth.users(id) on delete cascade,
//   lift text not null,                 -- "Back squat", "400m", "Bench"
//   value text not null,                -- "600 lb", "47.8 s", "315 lb x 5"
//   units text not null default '',     -- optional, used for sorting later
//   performed_on date,                  -- nullable
//   sort_order int not null default 0,
//   created_at timestamptz not null default now()
// );
// alter table public.whisper_athlete_prs enable row level security;
// create policy "wap read all"   on public.whisper_athlete_prs for select using (true);
// create policy "wap write own"  on public.whisper_athlete_prs for all   using (auth.uid() = user_id) with check (auth.uid() = user_id);
//
// -- Upcoming meet / event. We only ever show the next one, so this is
// -- effectively a 1-row-per-athlete table, but we keep history for later.
// create table if not exists public.whisper_athlete_meets (
//   id uuid primary key default gen_random_uuid(),
//   user_id uuid not null references auth.users(id) on delete cascade,
//   title text not null,
//   location text not null default '',
//   starts_at timestamptz not null,
//   created_at timestamptz not null default now()
// );
// alter table public.whisper_athlete_meets enable row level security;
// create policy "wam read all"  on public.whisper_athlete_meets for select using (true);
// create policy "wam write own" on public.whisper_athlete_meets for all   using (auth.uid() = user_id) with check (auth.uid() = user_id);
//
// -- Scouting filter columns on whisper_profiles. Owner copies these from
// -- the athlete application on approval so coaches can browse by sport.
// alter table public.whisper_profiles
//   add column if not exists athlete_sport text,
//   add column if not exists athlete_level text;

// MARK: - Models

nonisolated struct WhisperAthletePR: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let lift: String
    let value: String
    let units: String?
    let performed_on: String?
    let sort_order: Int?
    let created_at: String?
}

nonisolated struct WhisperAthletePRInsert: Codable, Sendable {
    let id: String
    let user_id: String
    let lift: String
    let value: String
    let units: String
    let performed_on: String?
    let sort_order: Int
}

nonisolated struct WhisperAthleteMeet: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let title: String
    let location: String?
    let starts_at: String
    let created_at: String?

    nonisolated var startsAtDate: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: starts_at) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: starts_at)
    }
}

nonisolated struct WhisperAthleteMeetInsert: Codable, Sendable {
    let id: String
    let user_id: String
    let title: String
    let location: String
    let starts_at: String
}

/// Roster row backing the scouting / recruiting filter. Decoded from a
/// `whisper_profiles` query with `is_athlete = true`.
nonisolated struct WhisperAthleteRosterRow: Codable, Sendable, Identifiable, Hashable {
    let user_id: String
    let username: String
    let display_name: String?
    let profile_image_url: String?
    let bio: String?
    let athlete_sport: String?
    let athlete_level: String?
    nonisolated var id: String { user_id }

    nonisolated var asUserRow: WhisperUserRow {
        WhisperUserRow(
            user_id: user_id,
            username: username,
            display_name: display_name,
            bio: bio,
            interests: nil,
            profile_image_url: profile_image_url,
            onboarded_at: nil,
            is_private: nil
        )
    }
}

// MARK: - Service

/// Backs the live athlete surfaces — PR stat sheet, upcoming-meet
/// countdown, and the scouting roster filter. Keeps everything separate
/// from `WhisperAthleteService` (which only tracks the `is_athlete` flag)
/// so the role plumbing stays light.
@MainActor
@Observable
final class WhisperAthletePerksService {
    static let shared = WhisperAthletePerksService()

    private let client = SupabaseService.shared.client
    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    var myPRs: [WhisperAthletePR] = []
    var myMeet: WhisperAthleteMeet?
    var prsByUserID: [String: [WhisperAthletePR]] = [:]
    var meetByUserID: [String: WhisperAthleteMeet?] = [:]
    var lastError: String?

    /// Cached roster results keyed by lowercased "sport|level".
    var rosterByKey: [String: [WhisperAthleteRosterRow]] = [:]

    private init() {}

    // MARK: PRs

    func refreshMine() async {
        guard isRemote else { return }
        async let prs: [WhisperAthletePR] = fetchPRs(forUserID: currentUID)
        async let meet: WhisperAthleteMeet? = fetchUpcomingMeet(forUserID: currentUID)
        let p = await prs
        let m = await meet
        myPRs = p
        myMeet = m
        prsByUserID[currentUID.lowercased()] = p
        meetByUserID[currentUID.lowercased()] = m
    }

    @discardableResult
    func fetchPRs(forUserID userID: String) async -> [WhisperAthletePR] {
        let key = userID.lowercased()
        do {
            let rows: [WhisperAthletePR] = try await client
                .from("whisper_athlete_prs")
                .select("id,user_id,lift,value,units,performed_on,sort_order,created_at")
                .eq("user_id", value: userID)
                .order("sort_order", ascending: true)
                .order("created_at", ascending: true)
                .execute()
                .value
            prsByUserID[key] = rows
            return rows
        } catch {
            handle(error, label: "fetch PRs")
            prsByUserID[key] = prsByUserID[key] ?? []
            return prsByUserID[key] ?? []
        }
    }

    @discardableResult
    func upsertPR(lift: String, value: String, units: String = "", performedOn: Date? = nil, existingID: String? = nil) async -> Bool {
        guard isRemote else { lastError = "Sign in to edit your stat sheet."; return false }
        let id = existingID ?? UUID().uuidString.lowercased()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let nextOrder = (myPRs.map { $0.sort_order ?? 0 }.max() ?? 0) + 1
        let payload = WhisperAthletePRInsert(
            id: id,
            user_id: currentUID,
            lift: lift,
            value: value,
            units: units,
            performed_on: performedOn.map { fmt.string(from: $0) },
            sort_order: nextOrder
        )
        do {
            try await client
                .from("whisper_athlete_prs")
                .upsert(payload, onConflict: "id")
                .execute()
            await refreshMine()
            return true
        } catch {
            handle(error, label: "save PR")
            return false
        }
    }

    @discardableResult
    func deletePR(id: String) async -> Bool {
        guard isRemote else { return false }
        do {
            try await client.from("whisper_athlete_prs").delete().eq("id", value: id).execute()
            myPRs.removeAll { $0.id == id }
            prsByUserID[currentUID.lowercased()] = myPRs
            return true
        } catch {
            handle(error, label: "delete PR")
            return false
        }
    }

    // MARK: Meet

    func fetchUpcomingMeet(forUserID userID: String) async -> WhisperAthleteMeet? {
        let key = userID.lowercased()
        let nowISO: String = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.string(from: Date())
        }()
        do {
            let rows: [WhisperAthleteMeet] = try await client
                .from("whisper_athlete_meets")
                .select("id,user_id,title,location,starts_at,created_at")
                .eq("user_id", value: userID)
                .gte("starts_at", value: nowISO)
                .order("starts_at", ascending: true)
                .limit(1)
                .execute()
                .value
            let first = rows.first
            meetByUserID[key] = first
            return first
        } catch {
            handle(error, label: "fetch meet")
            meetByUserID[key] = nil
            return nil
        }
    }

    @discardableResult
    func saveMeet(title: String, location: String, startsAt: Date, existingID: String? = nil) async -> Bool {
        guard isRemote else { lastError = "Sign in to save a meet."; return false }
        let id = existingID ?? UUID().uuidString.lowercased()
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let payload = WhisperAthleteMeetInsert(
            id: id,
            user_id: currentUID,
            title: title,
            location: location,
            starts_at: f.string(from: startsAt)
        )
        do {
            try await client
                .from("whisper_athlete_meets")
                .upsert(payload, onConflict: "id")
                .execute()
            await refreshMine()
            return true
        } catch {
            handle(error, label: "save meet")
            return false
        }
    }

    @discardableResult
    func clearMeet(id: String) async -> Bool {
        guard isRemote else { return false }
        do {
            try await client.from("whisper_athlete_meets").delete().eq("id", value: id).execute()
            if myMeet?.id == id { myMeet = nil }
            meetByUserID[currentUID.lowercased()] = nil
            return true
        } catch {
            handle(error, label: "clear meet")
            return false
        }
    }

    // MARK: Roster

    @discardableResult
    func fetchRoster(sport: String?, level: String?) async -> [WhisperAthleteRosterRow] {
        let key = "\((sport ?? "").lowercased())|\((level ?? "").lowercased())"
        do {
            var q = client
                .from("whisper_profiles")
                .select("user_id,username,display_name,profile_image_url,bio,athlete_sport,athlete_level")
                .eq("is_athlete", value: true)
            if let s = sport, !s.isEmpty {
                q = q.ilike("athlete_sport", pattern: "%\(s)%")
            }
            if let l = level, !l.isEmpty {
                q = q.ilike("athlete_level", pattern: l)
            }
            let rows: [WhisperAthleteRosterRow] = try await q
                .order("username", ascending: true)
                .limit(120)
                .execute()
                .value
            rosterByKey[key] = rows
            return rows
        } catch {
            handle(error, label: "fetch roster")
            rosterByKey[key] = rosterByKey[key] ?? []
            return rosterByKey[key] ?? []
        }
    }

    // MARK: Helpers

    private func handle(_ error: Error, label: String) {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("relation") && msg.contains("does not exist") {
            lastError = "Athlete tables missing. Owner: run the WhisperAthletePerks SQL block."
        } else if msg.contains("column") && msg.contains("does not exist") {
            lastError = "Athlete columns missing on whisper_profiles. Run the SQL block."
        } else {
            lastError = "Couldn't \(label): \(error.localizedDescription)"
        }
        print("[Whisper] athlete-perks \(label) error: \(error)")
    }
}

// MARK: - Stat Sheet Card

/// Pinned card on an athlete's profile that lists their PRs. Mirrors the
/// IG-style "stats" panel used by athlete-first apps. Read-only for
/// viewers; the owner gets an inline pencil that pops the editor.
struct WhisperAthleteStatSheetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let userID: String
    let username: String
    let isMine: Bool
    var onEdit: (() -> Void)? = nil

    @State private var perks = WhisperAthletePerksService.shared
    @State private var prs: [WhisperAthletePR] = []
    @State private var loaded: Bool = false

    private var accent: Color { WhisperAthleteApplicationView.athleteAccent }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !loaded {
                ProgressView().tint(accent).frame(maxWidth: .infinity).padding(.vertical, 10)
            } else if prs.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(prs.enumerated()), id: \.element.id) { idx, pr in
                        row(pr)
                        if idx < prs.count - 1 {
                            Rectangle()
                                .fill(WhisperTheme.hairline(colorScheme))
                                .frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(accent.opacity(0.25), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .task(id: userID) { await load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(accent)
            Text("Stat sheet")
                .font(.caption.weight(.heavy))
                .tracking(1.5)
                .foregroundStyle(accent)
            Spacer()
            if isMine, let onEdit {
                Button {
                    Haptics.tap()
                    onEdit()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ pr: WhisperAthletePR) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(pr.lift)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(pr.value)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(accent)
                if let on = pr.performed_on, !on.isEmpty {
                    Text(on)
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            WhisperMeetDoodle(symbol: "trophy", height: 96)
            Text(isMine ? "Add your first PR" : "No PRs yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text(isMine
                 ? "Tap the pencil to log lifts, times, or any personal best you want pinned to your profile."
                 : "@\(username) hasn't logged a PR yet.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func load() async {
        if isMine {
            await perks.refreshMine()
            prs = perks.myPRs
        } else {
            prs = await perks.fetchPRs(forUserID: userID)
        }
        loaded = true
    }
}

// MARK: - Meet Countdown Card

struct WhisperAthleteMeetCountdownCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let userID: String
    let username: String
    let isMine: Bool
    var onEdit: (() -> Void)? = nil

    @State private var perks = WhisperAthletePerksService.shared
    @State private var meet: WhisperAthleteMeet?
    @State private var loaded: Bool = false
    @State private var now: Date = Date()

    private var accent: Color { WhisperAthleteApplicationView.athleteAccent }

    var body: some View {
        Group {
            if let m = meet {
                card(m)
            } else if isMine && loaded {
                addCTA
            } else {
                EmptyView()
            }
        }
        .task(id: userID) { await load() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
    }

    private func card(_ m: WhisperAthleteMeet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(accent)
                Text("Next meet")
                    .font(.caption.weight(.heavy))
                    .tracking(1.5)
                    .foregroundStyle(accent)
                Spacer()
                if isMine, let onEdit {
                    Button {
                        Haptics.tap()
                        onEdit()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(m.title)
                .font(.title3.weight(.heavy))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            if let loc = m.location, !loc.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse").font(.caption2)
                    Text(loc).font(.caption)
                }
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            countdownStrip(target: m.startsAtDate ?? Date())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private var addCTA: some View {
        Button {
            Haptics.tap()
            onEdit?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(accent)
                Text("Add an upcoming meet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(accent.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private func countdownStrip(target: Date) -> some View {
        let delta = target.timeIntervalSince(now)
        let parts = Self.breakdown(delta)
        return HStack(spacing: 10) {
            ForEach(parts, id: \.0) { (label, value) in
                VStack(spacing: 2) {
                    Text(value)
                        .font(.title2.weight(.black).monospacedDigit())
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(label)
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(WhisperTheme.surface(colorScheme).opacity(0.6), in: .rect(cornerRadius: 10))
            }
        }
    }

    private static func breakdown(_ interval: TimeInterval) -> [(String, String)] {
        let total = max(0, Int(interval))
        let d = total / 86_400
        let h = (total % 86_400) / 3_600
        let m = (total % 3_600) / 60
        let s = total % 60
        return [("DAYS", "\(d)"), ("HRS", "\(h)"), ("MIN", "\(m)"), ("SEC", "\(s)")]
    }

    private func load() async {
        if isMine {
            await perks.refreshMine()
            meet = perks.myMeet
        } else {
            meet = await perks.fetchUpcomingMeet(forUserID: userID)
        }
        loaded = true
    }
}

// MARK: - Editor

/// Sheet the athlete pops from their own profile to manage PRs and the
/// upcoming meet. Coaches & viewers never see this — it's gated on
/// `isMeAthlete` at the call site.
struct WhisperAthleteEditView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var perks = WhisperAthletePerksService.shared

    @State private var newLift: String = ""
    @State private var newValue: String = ""

    @State private var meetTitle: String = ""
    @State private var meetLocation: String = ""
    @State private var meetDate: Date = Date().addingTimeInterval(60 * 60 * 24 * 7)
    @State private var hasMeet: Bool = false
    @State private var editingMeetID: String?

    private var accent: Color { WhisperAthleteApplicationView.athleteAccent }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        prSection
                        meetSection
                        if let err = perks.lastError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Athlete card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(accent)
                        .font(.subheadline.weight(.bold))
                }
            }
            .task {
                await perks.refreshMine()
                if let m = perks.myMeet, let d = m.startsAtDate {
                    meetTitle = m.title
                    meetLocation = m.location ?? ""
                    meetDate = d
                    hasMeet = true
                    editingMeetID = m.id
                }
            }
        }
    }

    private var prSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Personal records", system: "trophy.fill")
            VStack(spacing: 8) {
                ForEach(perks.myPRs) { pr in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.lift).font(.subheadline.weight(.semibold))
                            Text(pr.value).font(.caption).foregroundStyle(accent)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Haptics.tap()
                            Task { _ = await perks.deletePR(id: pr.id) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.footnote.weight(.bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                }

                VStack(spacing: 8) {
                    TextField("Lift or event (Back squat, 400m, …)", text: $newLift)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                    TextField("PR value (600 lb, 47.8 s, …)", text: $newValue)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                    Button {
                        Haptics.tap()
                        let lift = newLift.trimmingCharacters(in: .whitespaces)
                        let value = newValue.trimmingCharacters(in: .whitespaces)
                        guard !lift.isEmpty && !value.isEmpty else { return }
                        Task {
                            let ok = await perks.upsertPR(lift: lift, value: value)
                            if ok {
                                newLift = ""; newValue = ""
                                Haptics.success()
                            }
                        }
                    } label: {
                        Text("Add PR")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(newLift.trimmingCharacters(in: .whitespaces).isEmpty
                              || newValue.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var meetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Upcoming meet", system: "flag.checkered")
            VStack(spacing: 8) {
                TextField("Event name", text: $meetTitle)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                TextField("Location (optional)", text: $meetLocation)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                DatePicker("Starts", selection: $meetDate, in: Date()...)
                    .datePickerStyle(.compact)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))

                HStack(spacing: 8) {
                    Button {
                        Haptics.tap()
                        let title = meetTitle.trimmingCharacters(in: .whitespaces)
                        guard !title.isEmpty else { return }
                        Task {
                            let ok = await perks.saveMeet(
                                title: title,
                                location: meetLocation.trimmingCharacters(in: .whitespaces),
                                startsAt: meetDate,
                                existingID: editingMeetID
                            )
                            if ok {
                                hasMeet = true
                                Haptics.success()
                                if let mid = perks.myMeet?.id { editingMeetID = mid }
                            }
                        }
                    } label: {
                        Text(hasMeet ? "Update meet" : "Save meet")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(meetTitle.trimmingCharacters(in: .whitespaces).isEmpty)

                    if hasMeet, let mid = editingMeetID {
                        Button(role: .destructive) {
                            Haptics.warning()
                            Task {
                                _ = await perks.clearMeet(id: mid)
                                hasMeet = false
                                editingMeetID = nil
                                meetTitle = ""
                                meetLocation = ""
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(WhisperTheme.card(colorScheme), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, system: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: system).foregroundStyle(accent)
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
    }
}

// MARK: - Scouting Roster

/// Athlete-only scouting view. Coaches (and anyone really) can browse
/// every approved athlete, filtered by sport keyword and level. Tapping
/// a row pushes the normal `WhisperUserProfileView`.
struct WhisperAthleteRosterView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var perks = WhisperAthletePerksService.shared

    @State private var sportQuery: String = ""
    @State private var level: String = ""
    @State private var rows: [WhisperAthleteRosterRow] = []
    @State private var loading: Bool = false
    @State private var openUser: WhisperUserRow?

    private let levels: [String] = ["", "Amateur", "Collegiate", "Semi-pro", "Pro", "Masters"]
    private var accent: Color { WhisperAthleteApplicationView.athleteAccent }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                VStack(spacing: 12) {
                    filterBar
                    levelPicker
                    Group {
                        if loading {
                            ProgressView().tint(accent).padding(.top, 32)
                        } else if rows.isEmpty {
                            WhisperEmptyState(
                                icon: "trophy",
                                title: "No athletes found",
                                message: "Try a different sport or level. Athletes appear here once their application is approved."
                            )
                            .padding(.horizontal, 16)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(rows) { row in
                                        rowButton(row)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.top, 8)
            }
            .navigationTitle("Athlete scouting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .navigationDestination(item: $openUser) { user in
                WhisperUserProfileView(user: user)
            }
            .task { await reload() }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Sport (powerlifting, track, MMA…)", text: $sportQuery)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit { Task { await reload() } }
            if !sportQuery.isEmpty {
                Button {
                    sportQuery = ""
                    Task { await reload() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .padding(.horizontal, 16)
    }

    private var levelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(levels, id: \.self) { l in
                    let isOn = level == l
                    Button {
                        Haptics.tap()
                        level = l
                        Task { await reload() }
                    } label: {
                        Text(l.isEmpty ? "All levels" : l)
                            .font(.footnote.weight(.bold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(isOn ? accent : WhisperTheme.card(colorScheme), in: Capsule())
                            .foregroundStyle(isOn ? .white : WhisperTheme.ink(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func rowButton(_ row: WhisperAthleteRosterRow) -> some View {
        Button {
            Haptics.tap()
            openUser = row.asUserRow
        } label: {
            HStack(spacing: 12) {
                avatar(for: row)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.display_name?.isEmpty == false ? row.display_name! : row.username)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Image(systemName: "trophy.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(accent)
                    }
                    Text("@\(row.username)")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    if (row.athlete_sport ?? "").isEmpty == false || (row.athlete_level ?? "").isEmpty == false {
                        HStack(spacing: 4) {
                            if let s = row.athlete_sport, !s.isEmpty {
                                tag(s)
                            }
                            if let l = row.athlete_level, !l.isEmpty {
                                tag(l)
                            }
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(12)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func tag(_ s: String) -> some View {
        Text(s)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(accent.opacity(0.15), in: Capsule())
            .foregroundStyle(accent)
    }

    private func avatar(for row: WhisperAthleteRosterRow) -> some View {
        Group {
            if let s = row.profile_image_url, let url = URL(string: s) {
                WhisperCachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                    default: accent.opacity(0.2)
                    }
                }
            } else {
                accent.opacity(0.2)
                    .overlay {
                        Text(String(row.username.prefix(1)).uppercased())
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(accent)
                    }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(.circle)
    }

    private func reload() async {
        loading = true
        let s = sportQuery.trimmingCharacters(in: .whitespaces)
        rows = await perks.fetchRoster(sport: s.isEmpty ? nil : s, level: level.isEmpty ? nil : level)
        loading = false
    }
}
