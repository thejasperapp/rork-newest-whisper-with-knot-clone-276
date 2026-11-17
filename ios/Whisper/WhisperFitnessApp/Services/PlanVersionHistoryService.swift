import Foundation

/// A single immutable snapshot of a saved plan. Mirrors Google Docs–style
/// version history so the user can compare or revert to any prior edit
/// without losing data.
nonisolated struct PlanVersionSnapshot: Codable, Sendable, Identifiable {
    let id: UUID
    /// ID of the underlying plan (e.g. WeeklyDietPlan.id) so versions group
    /// across the lifetime of a plan even as edits replace its contents.
    let planID: String
    /// Human-readable kind: "diet", "workout", "supplement", etc.
    let kind: String
    /// Display title at the time the snapshot was taken.
    let title: String
    /// Auto-incrementing label like "v1", "v2"…
    let label: String
    let createdAt: Date
    /// Optional one-liner summarizing what changed in this version.
    let changeNote: String?
    /// Encoded JSON payload of the plan at the time of snapshot. Decoded
    /// lazily by callers so this service stays plan-shape agnostic.
    let payload: Data

    init(
        id: UUID = UUID(),
        planID: String,
        kind: String,
        title: String,
        label: String,
        createdAt: Date = .now,
        changeNote: String? = nil,
        payload: Data
    ) {
        self.id = id
        self.planID = planID
        self.kind = kind
        self.title = title
        self.label = label
        self.createdAt = createdAt
        self.changeNote = changeNote
        self.payload = payload
    }
}

/// Persistent version-history store for any Codable plan. Keeps the most
/// recent snapshots per plan ID so the user can revisit and revert past
/// iterations the way Notion / Google Docs / Linear do.
@Observable
final class PlanVersionHistoryService {
    static let shared = PlanVersionHistoryService()

    private static let storeKey = "ember_plan_version_history_v1"
    /// Cap so persistence never balloons. 12 versions per plan covers
    /// roughly a season of weekly edits — plenty for reverts and diffs.
    private static let maxPerPlan = 12

    private(set) var snapshots: [PlanVersionSnapshot] = []

    static let didChangeNotification = Notification.Name("PlanVersionHistoryServiceDidChange")

    init() { load() }

    // MARK: - Public API

    /// Snapshot any Codable plan. Auto-numbers `vN` and trims oldest
    /// versions past the per-plan cap. Returns the newly stored snapshot.
    @discardableResult
    func snapshot<Plan: Codable>(
        plan: Plan,
        planID: String,
        kind: String,
        title: String,
        changeNote: String? = nil
    ) -> PlanVersionSnapshot? {
        guard let payload = try? JSONEncoder().encode(plan) else { return nil }
        let existing = snapshots.filter { $0.planID == planID }
        // Skip if payload identical to the latest snapshot — no point
        // recording a version that didn't actually change anything.
        if let latest = existing.sorted(by: { $0.createdAt > $1.createdAt }).first,
           latest.payload == payload {
            return latest
        }
        let nextNumber = existing.count + 1
        let snap = PlanVersionSnapshot(
            planID: planID,
            kind: kind,
            title: title,
            label: "v\(nextNumber)",
            changeNote: changeNote,
            payload: payload
        )
        snapshots.append(snap)
        trim(planID: planID)
        save()
        return snap
    }

    /// All snapshots for a plan, newest first.
    func versions(for planID: String) -> [PlanVersionSnapshot] {
        snapshots
            .filter { $0.planID == planID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// All snapshots regardless of plan, newest first — used by the Life
    /// Timeline so the user can scroll through everything they've edited.
    var allNewestFirst: [PlanVersionSnapshot] {
        snapshots.sorted { $0.createdAt > $1.createdAt }
    }

    /// Decode a snapshot back into its concrete plan type.
    func decode<Plan: Decodable>(_ snapshot: PlanVersionSnapshot, as type: Plan.Type) -> Plan? {
        try? JSONDecoder().decode(type, from: snapshot.payload)
    }

    func remove(id: UUID) {
        snapshots.removeAll { $0.id == id }
        save()
    }

    func clear(planID: String) {
        snapshots.removeAll { $0.planID == planID }
        save()
    }

    func clearAll() {
        snapshots.removeAll()
        save()
    }

    // MARK: - Persistence

    private func trim(planID: String) {
        let mine = snapshots
            .enumerated()
            .filter { $0.element.planID == planID }
            .sorted { $0.element.createdAt > $1.element.createdAt }
        if mine.count > Self.maxPerPlan {
            let toRemove = Set(mine.suffix(mine.count - Self.maxPerPlan).map { $0.element.id })
            snapshots.removeAll { toRemove.contains($0.id) }
        }
    }

    private func load() {
        guard let data = AccountStorage.data(forKey: Self.storeKey),
              let decoded = try? JSONDecoder().decode([PlanVersionSnapshot].self, from: data) else {
            snapshots = []
            return
        }
        snapshots = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshots) {
            AccountStorage.set(data, forKey: Self.storeKey)
            UserDefaults.standard.set(Date(), forKey: AccountStorage.key("\(Self.storeKey)_lastModified"))
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
