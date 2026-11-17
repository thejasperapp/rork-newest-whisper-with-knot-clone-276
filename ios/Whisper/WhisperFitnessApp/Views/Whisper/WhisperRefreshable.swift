import SwiftUI
import UIKit

/// Hides the native spinner; refresh admission remains accessible through SwiftUI.
enum WhisperRefreshAppearance {
    static func install() { UIRefreshControl.appearance().tintColor = .clear }
}

nonisolated struct WhisperRefreshStatus: Equatable {
    var isRefreshing: Bool = false
    var pullProgress: Double = 0
    var isPulling: Bool = false
}

extension View {
    /// A header binding animates the existing mark and suppresses the extra indicator.
    func whisperRefreshable(headerStatus: Binding<WhisperRefreshStatus>? = nil, action: @escaping () async -> Void) -> some View {
        modifier(WhisperRefreshableModifier(headerStatus: headerStatus, action: action))
    }
}

private struct WhisperRefreshableModifier: ViewModifier {
    let headerStatus: Binding<WhisperRefreshStatus>?
    let action: () async -> Void
    @State private var isRefreshing: Bool = false
    @State private var pullProgress: Double = 0
    @State private var isPulling: Bool = false
    @State private var operationID: UUID = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var status: WhisperRefreshStatus {
        WhisperRefreshStatus(isRefreshing: isRefreshing, pullProgress: pullProgress, isPulling: isPulling)
    }

    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.always, axes: .vertical)
            .refreshable {
                await runRefresh()
            }
            .accessibilityAction(named: Text("Refresh")) { Task { await runRefresh() } }
            .onScrollPhaseChange { _, new in
                isPulling = new == .tracking || new == .interacting
                if !isPulling {
                    pullProgress = 0
                    headerStatus?.wrappedValue = status
                }
            }
            .onScrollGeometryChange(for: Int.self) { geometry in
                let pull = -(geometry.contentOffset.y + geometry.contentInsets.top)
                return Int((max(0, min(1, pull / 84)) * 60).rounded())
            } action: { _, step in
                let progress = isPulling ? Double(step) / 60 : 0
                if !isRefreshing, pullProgress != progress { pullProgress = progress }
            }
            .onChange(of: status) { _, value in headerStatus?.wrappedValue = value }
            .overlay(alignment: .top) {
                if headerStatus == nil, isRefreshing || pullProgress > 0.02 {
                    WhisperTraceLogo(size: 38, manualProgress: isRefreshing ? nil : pullProgress)
                        .padding(.top, 22)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .onDisappear {
                // A loading branch can temporarily replace its scroll view.
                // Do not cancel the admitted data request during that swap.
                headerStatus?.wrappedValue = .init()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in reset() }
    }

    private func reset() {
        operationID = UUID()
        isRefreshing = false
        pullProgress = 0
        isPulling = false
        headerStatus?.wrappedValue = .init()
    }

    private func runRefresh() async {
        guard !Task.isCancelled else { return }
        if isRefreshing {
            while isRefreshing {
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            }
            return
        }
        let operation = UUID()
        operationID = operation
        let generation = AccountStorage.generation
        isRefreshing = true
        headerStatus?.wrappedValue = status
        await action()
        guard operationID == operation, generation == AccountStorage.generation else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            isRefreshing = false
            pullProgress = 0
            headerStatus?.wrappedValue = .init()
        }
        if !Task.isCancelled { WhisperFeedback.refreshed() }
    }
}
