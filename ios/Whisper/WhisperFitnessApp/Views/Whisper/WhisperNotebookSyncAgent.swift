import SwiftUI
import Supabase

/// Foreground account queue survives Notebook dismissal, but not app termination.
struct WhisperNotebookSyncAgent: View {
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Color.clear.frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
            .task(id: "\(scenePhase):\(AccountStorage.generation):\(AuthenticationService.shared.isSignedIn)") {
                guard scenePhase == .active, AuthenticationService.shared.isSignedIn else { return }
                let owner = AccountStorage.currentUserID.lowercased(), generation = AccountStorage.generation
                // Preserve the durable outbox, but do not scan all notebook files
                // and start full reconciliation during the initial Home burst.
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                while !Task.isCancelled && generation == AccountStorage.generation {
                    await WhisperTranscriptOutbox.shared.flush()
                    do {
                        _ = try await WhisperNotebookSyncService.sync(owner: owner) {
                            guard !Task.isCancelled, AuthenticationService.shared.isSignedIn, AccountStorage.generation == generation,
                                  AccountStorage.currentUserID.lowercased() == owner else { throw WhisperNotebookError.accountChanged }
                        }
                    } catch { /* Durable local documents remain pending; Notebook exposes retry status. */ }
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                }
            }
    }
}
