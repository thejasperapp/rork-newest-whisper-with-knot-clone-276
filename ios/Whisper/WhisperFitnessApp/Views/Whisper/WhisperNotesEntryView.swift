import SwiftUI

/// Hands off to Notes without granting access or sending anything to the conversation.
struct WhisperNotesEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var opening: Bool = false
    @State private var error: String?
    @State private var work: Task<Void, Never>?
    @State private var generation: UUID = AccountStorage.generation

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image("WhisperNotesApp").renderingMode(.original).resizable().scaledToFit()
                            .frame(width: 52, height: 52).clipShape(.rect(cornerRadius: 13))
                            .accessibilityHidden(true)
                        Text("Whisper Notes").font(.title2.bold())
                    }
                    Text("Your documents. The right people.").font(.title3.weight(.semibold))
                    Text("Open Notes to review shared documents and manage individual invitations. Opening Notes doesn't send anything or give this chat access to a document.")
                        .font(.body).foregroundStyle(.secondary)
                    Button(opening ? "Opening…" : "Open Whisper Notes", systemImage: "arrow.up.right") { open() }
                        .buttonStyle(.borderedProminent).frame(minHeight: 44).disabled(opening)
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Divider()
                    Label("Document & signature cards", systemImage: "lock").font(.headline)
                    Text("Reviewed cards will be available when Notes finishes its verified delivery connection. Existing restricted document links still work. Signing always requires review and email verification in Notes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }
            .navigationTitle("Notes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large]).presentationContentInteraction(.scrolls)
        .onDisappear { work?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in work?.cancel(); dismiss() }
    }

    private func open() {
        guard !opening, phase == .active, generation == AccountStorage.generation else { return }
        opening = true; error = nil
        work = Task {
            let success = await WhisperNotesHandoff.open(.shared(nil))
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            opening = false
            if !success { error = "Couldn't open Notes. Please try again." }
        }
    }
}
