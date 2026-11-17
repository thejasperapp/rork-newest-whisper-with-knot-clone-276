import Foundation
import Supabase

// MARK: - Supabase schema (run once)
//
// create table if not exists public.whisper_coach_programs (
//   id uuid primary key,
//   coach_user_id uuid not null references auth.users(id) on delete cascade,
//   coach_username text not null,
//   title text not null,
//   focus text not null default 'general',
//   weeks int not null default 4,
//   sessions_per_week int not null default 3,
//   summary text not null default '',
//   payload jsonb not null,
//   is_public boolean not null default false,
//   created_at timestamptz not null default now()
// );
// create index if not exists whisper_coach_programs_coach_idx
//   on public.whisper_coach_programs (coach_user_id, created_at desc);
// alter table public.whisper_coach_programs enable row level security;
// create policy "wcp read public or own" on public.whisper_coach_programs
//   for select using (is_public or auth.uid() = coach_user_id);
// create policy "wcp insert own" on public.whisper_coach_programs
//   for insert with check (auth.uid() = coach_user_id);
// create policy "wcp update own" on public.whisper_coach_programs
//   for update using (auth.uid() = coach_user_id);
// create policy "wcp delete own" on public.whisper_coach_programs
//   for delete using (auth.uid() = coach_user_id);

// MARK: - Models

nonisolated struct WhisperProgramExercise: Codable, Sendable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var sets: Int
    var reps: String
    var restSeconds: Int
    var note: String?
}

nonisolated struct WhisperProgramDay: Codable, Sendable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var focus: String
    var exercises: [WhisperProgramExercise]
}

nonisolated struct WhisperCoachProgram: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var coachUserID: String
    var coachUsername: String
    var title: String
    var focus: String
    var weeks: Int
    var sessionsPerWeek: Int
    var summary: String
    var days: [WhisperProgramDay]
    /// One-time price in cents (0 = free). Lives inside the row's JSON
    /// payload so no schema change is needed — the payment backend reads
    /// the same field when creating checkout sessions.
    var priceCents: Int = 0
    var createdAt: Date

    var totalExercises: Int { days.reduce(0) { $0 + $1.exercises.count } }
    var isPaid: Bool { priceCents > 0 }
}

nonisolated struct WhisperCoachProgramRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let coach_user_id: String
    let coach_username: String
    let title: String
    let focus: String
    let weeks: Int
    let sessions_per_week: Int
    let summary: String
    let payload: WhisperProgramPayloadBlob
    let is_public: Bool?
    let created_at: String?
}

nonisolated struct WhisperProgramPayloadBlob: Codable, Sendable, Hashable {
    let days: [WhisperProgramDay]
    /// Optional so rows saved before program pricing still decode.
    let priceCents: Int?
}

nonisolated struct WhisperCoachProgramInsert: Codable, Sendable {
    let id: String
    let coach_user_id: String
    let coach_username: String
    let title: String
    let focus: String
    let weeks: Int
    let sessions_per_week: Int
    let summary: String
    let payload: WhisperProgramPayloadBlob
    let is_public: Bool
}

/// CRUD service for coach-built workout programs. Coach-only writes (gated
/// by `WhisperCoachService.isMeCoach`), readable by anyone the program is
/// shared with via DM (the embed itself carries the full payload, so even
/// non-public programs work over DM without extra RLS work).
@MainActor
@Observable
final class WhisperCoachProgramService {
    static let shared = WhisperCoachProgramService()

    private let client = SupabaseService.shared.client

    var myPrograms: [WhisperCoachProgram] = []
    var isLoading: Bool = false
    var lastError: String?

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }
    private var username: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    private var readTask: Task<Void, Never>?
    private var readOperation = UUID()
    private var mutations: Set<UUID> = []

    private init() {
        NotificationCenter.default.addObserver(forName: Notification.Name("WhisperMeetingAccountWillChange"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                self.invalidateReads(); self.myPrograms = []; self.lastError = nil; self.mutations = []
            }
        }
    }

    private func invalidateReads() {
        readOperation = UUID(); readTask?.cancel(); readTask = nil; isLoading = false
    }

    func fetchMyPrograms() async {
        guard isRemote else { invalidateReads(); myPrograms = []; return }
        if let readTask { await readTask.value; return }
        let owner = currentUID, generation = AccountStorage.generation, operation = UUID()
        readOperation = operation; isLoading = true
        let task = Task { await self.fetchOwnedPrograms(owner: owner, generation: generation, operation: operation) }
        readTask = task
        await task.value
        if readOperation == operation { readTask = nil; isLoading = false }
    }

    private func fetchOwnedPrograms(owner: String, generation: UUID, operation: UUID) async {
        do {
            let rows: [WhisperCoachProgramRow] = try await client
                .from("whisper_coach_programs")
                .select()
                .eq("coach_user_id", value: owner)
                .order("created_at", ascending: false)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID, readOperation == operation else { return }
            let fmt = ISO8601DateFormatter()
            myPrograms = rows.compactMap { r in
                guard let uuid = UUID(uuidString: r.id) else { return nil }
                let date = r.created_at.flatMap { fmt.date(from: $0) } ?? Date()
                return WhisperCoachProgram(
                    id: uuid,
                    coachUserID: r.coach_user_id,
                    coachUsername: r.coach_username,
                    title: r.title,
                    focus: r.focus,
                    weeks: r.weeks,
                    sessionsPerWeek: r.sessions_per_week,
                    summary: r.summary,
                    days: r.payload.days,
                    priceCents: max(0, r.payload.priceCents ?? 0),
                    createdAt: date
                )
            }
            lastError = nil
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID, readOperation == operation else { return }
            lastError = "Your programs couldn’t load. Please try again."
        }
    }

    @discardableResult
    func saveProgram(_ program: WhisperCoachProgram) async -> Bool {
        guard isRemote, program.coachUserID.lowercased() == currentUID.lowercased(), mutations.insert(program.id).inserted else { return false }
        let owner = currentUID, generation = AccountStorage.generation
        invalidateReads()
        defer { if generation == AccountStorage.generation { mutations.remove(program.id) } }
        let insert = WhisperCoachProgramInsert(
            id: program.id.uuidString,
            coach_user_id: owner,
            coach_username: username,
            title: program.title,
            focus: program.focus,
            weeks: program.weeks,
            sessions_per_week: program.sessionsPerWeek,
            summary: program.summary,
            payload: WhisperProgramPayloadBlob(
                days: program.days,
                priceCents: program.priceCents > 0 ? program.priceCents : nil
            ),
            is_public: false
        )
        do {
            try await client.from("whisper_coach_programs").upsert(insert).execute()
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID else { return false }
            invalidateReads()
            // Replace local cache entry.
            if let idx = myPrograms.firstIndex(where: { $0.id == program.id }) {
                myPrograms[idx] = program
            } else {
                myPrograms.insert(program, at: 0)
            }
            lastError = nil
            return true
        } catch {
            guard generation == AccountStorage.generation, owner == currentUID, !Task.isCancelled else { return false }
            lastError = "Your program couldn’t be saved. Please try again."
            return false
        }
    }

    func deleteProgram(_ id: UUID) async {
        guard isRemote, mutations.insert(id).inserted else { return }
        let owner = currentUID, generation = AccountStorage.generation
        invalidateReads()
        defer { if generation == AccountStorage.generation { mutations.remove(id) } }
        do {
            try await client.from("whisper_coach_programs")
                .delete()
                .eq("id", value: id.uuidString)
                .eq("coach_user_id", value: owner)
                .execute()
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID else { return }
            invalidateReads(); myPrograms.removeAll { $0.id == id }; lastError = nil
        } catch {
            guard generation == AccountStorage.generation, owner == currentUID, !Task.isCancelled else { return }
            lastError = "Your program couldn’t be deleted. Please try again."
        }
    }

    /// Loads the coach's saved Whisper programs (the same `GeneratedProgram`
    /// blobs the rest of Whisper uses under `savedWorkoutPrograms`). This is
    /// the bridge that lets a coach forward any program they've already built
    /// in Whisper straight into a client's DM — no rebuilding required.
    func loadSavedWhisperPrograms() -> [GeneratedProgram] {
        guard let data = AccountStorage.data(forKey: "savedWorkoutPrograms"),
              let arr = try? JSONDecoder().decode([GeneratedProgram].self, from: data)
        else { return [] }
        return arr
    }

    /// Converts a Whisper `GeneratedProgram` into the Whisper DM payload format
    /// so it can be forwarded to a client with the existing program embed.
    func bridge(_ g: GeneratedProgram) -> WhisperCoachProgram {
        let days: [WhisperProgramDay] = g.workoutDays.map { d in
            WhisperProgramDay(
                id: d.id,
                name: d.dayName,
                focus: d.focus,
                exercises: d.exercises.map { ex in
                    WhisperProgramExercise(
                        id: ex.id,
                        name: ex.name,
                        sets: ex.sets,
                        reps: ex.reps,
                        restSeconds: ex.restSeconds,
                        note: ex.notes.isEmpty ? nil : ex.notes
                    )
                }
            )
        }
        return WhisperCoachProgram(
            id: g.id,
            coachUserID: currentUID,
            coachUsername: username,
            title: g.title,
            focus: g.goal.rawValue,
            weeks: g.weeks,
            sessionsPerWeek: g.daysPerWeek,
            summary: g.overview,
            days: days,
            createdAt: g.createdAt
        )
    }

    /// Builds a brand-new empty program owned by the current coach.
    func makeBlankProgram(title: String = "New program") -> WhisperCoachProgram {
        WhisperCoachProgram(
            id: UUID(),
            coachUserID: currentUID,
            coachUsername: username,
            title: title,
            focus: "Strength",
            weeks: 4,
            sessionsPerWeek: 3,
            summary: "",
            days: [
                WhisperProgramDay(
                    name: "Day 1",
                    focus: "Upper",
                    exercises: [
                        WhisperProgramExercise(name: "Bench press", sets: 4, reps: "6-8", restSeconds: 120, note: nil)
                    ]
                )
            ],
            createdAt: Date()
        )
    }
}

// MARK: - Program embed (chat payload)

/// Encodes a coach program inside a DM message body. Mirrors the workout
/// embed pattern so the recipient can render it inline and download it.
enum WhisperProgramEmbed {
    static let prefix = "::whisper-program-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable {
        let id: String
        let coachUsername: String
        let title: String
        let focus: String
        let weeks: Int
        let sessionsPerWeek: Int
        let summary: String
        let days: [WhisperProgramDay]
        /// One-time price in cents — optional so old embeds still decode.
        /// Recipients must buy before the full plan opens when set.
        var priceCents: Int? = nil

        nonisolated var isPaid: Bool { (priceCents ?? 0) > 0 }
    }

    static func encode(_ p: WhisperCoachProgram) -> String {
        let payload = Payload(
            id: p.id.uuidString,
            coachUsername: p.coachUsername,
            title: p.title,
            focus: p.focus,
            weeks: p.weeks,
            sessionsPerWeek: p.sessionsPerWeek,
            summary: p.summary,
            days: p.days,
            priceCents: p.priceCents > 0 ? p.priceCents : nil
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    static func decode(_ body: String) -> Payload? {
        guard body.hasPrefix(prefix) else { return nil }
        let json = String(body.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }
}

/// Imports a coach program into Whisper as a downloadable set of workout
/// templates. Each program day is rendered as a `WorkoutSessionRecord`
/// template (zeroed-out sets) in the user's `workoutSessionHistory` blob —
/// so users can re-run it from their Whisper workouts UI.
enum WhisperProgramImport {
    @MainActor
    static func saveToWhisper(_ payload: WhisperProgramEmbed.Payload) {
        let programID = UUID(uuidString: payload.id) ?? UUID()
        var history: [WorkoutSessionRecord] = []
        if let data = AccountStorage.data(forKey: "workoutSessionHistory"),
           let decoded = try? JSONDecoder().decode([WorkoutSessionRecord].self, from: data) {
            history = decoded
        }
        let now = Date()
        for (idx, day) in payload.days.enumerated() {
            let exercises: [ExerciseLog] = day.exercises.map { ex in
                let sets = (0..<max(ex.sets, 1)).map { _ in
                    SetLog(id: UUID(), weight: 0, reps: 0, isComplete: false)
                }
                return ExerciseLog(
                    id: UUID(),
                    exerciseName: ex.name,
                    sets: sets,
                    targetSets: ex.sets,
                    targetReps: ex.reps,
                    restSeconds: ex.restSeconds,
                    userNotes: ex.note ?? "From coach @\(payload.coachUsername)"
                )
            }
            let dayDate = now.addingTimeInterval(TimeInterval(idx) * 3600)
            let record = WorkoutSessionRecord(
                id: UUID(),
                programId: programID,
                dayName: day.name,
                focus: day.focus,
                date: dayDate,
                duration: 0,
                exercises: exercises,
                averageHeartRate: 0,
                peakHeartRate: 0,
                heartRateTimeline: [],
                caloriesBurned: 0,
                avgOxygenSaturation: 0,
                customName: "\(payload.title) · \(day.name)"
            )
            if !history.contains(where: { $0.customName == record.customName }) {
                history.insert(record, at: 0)
            }
        }
        if let encoded = try? JSONEncoder().encode(history) {
            AccountStorage.set(encoded, forKey: "workoutSessionHistory")
        }
        // Also persist the raw program JSON under a dedicated key so the
        // Whisper-side companion app can pick up coach-authored programs
        // without re-deriving them from the workout history blob.
        if let raw = try? JSONEncoder().encode(payload) {
            var saved: [Data] = []
            if let existing = AccountStorage.data(forKey: "jasperCoachPrograms"),
               let arr = try? JSONDecoder().decode([Data].self, from: existing) {
                saved = arr
            }
            // Dedupe by program id.
            saved.removeAll { (try? JSONDecoder().decode(WhisperProgramEmbed.Payload.self, from: $0))?.id == payload.id }
            saved.insert(raw, at: 0)
            if let encoded = try? JSONEncoder().encode(saved) {
                AccountStorage.set(encoded, forKey: "jasperCoachPrograms")
            }
        }
        Haptics.success()
    }
}
