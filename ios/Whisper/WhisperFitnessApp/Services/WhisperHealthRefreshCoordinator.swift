import Foundation

/// Coalesces launch/foreground widget reads instead of constructing competing HealthKit graphs.
@MainActor
final class WhisperHealthRefreshCoordinator {
    static let shared = WhisperHealthRefreshCoordinator()
    private let health = HealthKitService()
    private var refreshTask: Task<Void, Never>?
    private var lastRefresh: Date?
    private var didInstallObservers: Bool = false

    func refresh(deferForLaunch: Bool = false) async {
        if let refreshTask { await refreshTask.value; return }
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        let task = Task {
            if deferForLaunch {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
            if !didInstallObservers {
                didInstallObservers = true
                health.enableBackgroundDelivery()
            }
            await health.fetchAllData()
            lastRefresh = Date()
        }
        refreshTask = task
        await task.value
        if refreshTask == task { refreshTask = nil }
    }
}
