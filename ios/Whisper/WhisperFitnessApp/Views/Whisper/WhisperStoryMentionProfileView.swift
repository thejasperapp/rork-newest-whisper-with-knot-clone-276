import SwiftUI

struct WhisperStoryMentionProfileView: View {
    let handle: String
    @Environment(\.dismiss) private var dismiss
    @State private var profile: WhisperUserRow?
    @State private var isLoading: Bool = true
    @State private var attempt: Int = 0

    var body: some View {
        NavigationStack {
            Group {
                if let profile { WhisperUserProfileView(user: profile) }
                else if isLoading { ProgressView("Loading profile…") }
                else {
                    ContentUnavailableView {
                        Label("Profile unavailable", systemImage: "person.crop.circle.badge.questionmark")
                    } description: { Text("This person may have changed their username, or the profile couldn't be loaded.") }
                    actions: { Button("Try again") { attempt += 1 } }
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task(id: attempt) {
                let epoch = AccountStorage.generation
                isLoading = true
                let result = await WhisperUserService.shared.fetchByUsername(handle)
                guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                profile = result; isLoading = false
            }
        }
    }
}
