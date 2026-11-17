import Foundation

/// Tiny persistence for the trackable goals and schedule the shared Jasper
/// brain hands back in ```goalplan / ```schedule blocks. Whisper keeps its
/// own light store (per-account, in `AccountStorage`) so saved goals survive
/// relaunches without standing up a new table — the brain stays server-side,
/// this is purely the local "saved" copy the user opted into.
@MainActor
@Observable
final class WhisperEmberGoalStore {
    static let shared = WhisperEmberGoalStore()

    private(set) var goals: [WhisperEmberBlocks.GoalPlan] = []
    private(set) var schedule: WhisperEmberBlocks.Schedule?

    private let goalsKey = "whisper.ember.goals"
    private let scheduleKey = "whisper.ember.schedule"

    private init() {
        if let data = AccountStorage.data(forKey: goalsKey),
           let decoded = try? JSONDecoder().decode([WhisperEmberBlocks.GoalPlan].self, from: data) {
            goals = decoded
        }
        if let data = AccountStorage.data(forKey: scheduleKey),
           let decoded = try? JSONDecoder().decode(WhisperEmberBlocks.Schedule.self, from: data) {
            schedule = decoded
        }
    }

    /// Saves (or replaces, by id) a goal plan and persists.
    func save(_ plan: WhisperEmberBlocks.GoalPlan) {
        goals.removeAll { $0.id == plan.id }
        goals.insert(plan, at: 0)
        if goals.count > 30 { goals = Array(goals.prefix(30)) }
        persistGoals()
    }

    func removeGoal(_ plan: WhisperEmberBlocks.GoalPlan) {
        goals.removeAll { $0.id == plan.id }
        persistGoals()
    }

    func saveSchedule(_ schedule: WhisperEmberBlocks.Schedule) {
        self.schedule = schedule
        if let data = try? JSONEncoder().encode(schedule) {
            AccountStorage.set(data, forKey: scheduleKey)
        }
    }

    private func persistGoals() {
        if let data = try? JSONEncoder().encode(goals) {
            AccountStorage.set(data, forKey: goalsKey)
        }
    }
}
