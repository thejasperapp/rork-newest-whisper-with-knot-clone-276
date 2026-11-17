import SwiftUI

/// One foreground delivery reader, independent of the selected tab. This does
/// not execute responsibilities: durable server alarms own approved checks.
struct WhisperKnotSyncAgent: View {
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Color.clear.frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
            .task(id: "\(scenePhase):\(AccountStorage.generation):\(AuthenticationService.shared.isSignedIn)") {
                guard scenePhase == .active, AuthenticationService.shared.isSignedIn,
                      AccountStorage.currentUserID != "guest" else { return }
                let generation = AccountStorage.generation
                // Let the selected page's essential launch work run first.
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                while !Task.isCancelled, scenePhase == .active,
                      generation == AccountStorage.generation, AuthenticationService.shared.isSignedIn {
                    await WhisperKnotOwnedTurnService.flushStops()
                    await WhisperEmberHistoryStore.shared.sync()
                    await WhisperKnotBackgroundService.shared.syncMessages()
                    await WhisperKnotContactService.shared.refresh()
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                }
            }
    }
}
