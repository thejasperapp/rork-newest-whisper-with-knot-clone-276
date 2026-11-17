import SwiftUI

struct WhisperBadgeInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let highlight: WhisperBadgeKind?
    var body: some View {
        NavigationStack {
            List {
                Section("One identity indicator") {
                    Text("The indicator beside a name identifies a verified identity or a Whisper staff role: Moderator, Admin, or Owner.")
                    Text("It is not a guarantee of safety, expertise, or accuracy.")
                }
                Section("Profile details") {
                    Text("Professional roles appear as plain text. Age, membership, account age, and report counts are not public badges. Paid access and tools are unchanged.")
                }
                Section("Corrections") {
                    Text("A reviewed correction belongs to a particular post, not a person’s name. Optional AI analysis is not a moderation decision.")
                    Text("You can revisit decisions and appeal from Settings → Decisions & appeals.")
                }
            }
            .navigationTitle("Identity indicators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
