import SwiftUI

/// Notes editor for a recruiter prospect. Recruiters can keep private notes
/// (only they see) and shared notes (visible to the recruiting group) for
/// every client they interview.
struct WhisperRecruiterProspectNotesSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let prospect: WhisperRecruiterService.ProspectRow
    @State private var recruiter = WhisperRecruiterService.shared
    @State private var notes: String
    @State private var sharedNotes: String
    @State private var saving: Bool = false

    init(prospect: WhisperRecruiterService.ProspectRow) {
        self.prospect = prospect
        _notes = State(initialValue: prospect.notes ?? "")
        _sharedNotes = State(initialValue: prospect.shared_notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        privateNotesSection
                        sharedNotesSection
                        saveButton
                    }
                    .padding(16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            WhisperAvatar(
                username: prospect.prospect_username ?? prospect.prospect_display_name ?? "?",
                size: 50,
                imageURL: prospect.prospect_image_url.flatMap(URL.init(string:)),
                ring: false
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(prospect.prospect_display_name ?? prospect.prospect_username ?? "Prospect")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                if let username = prospect.prospect_username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            Spacer()
        }
    }

    private var privateNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Private notes")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Only you can see these", text: $notes, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(4...8)
                .padding(12)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
        }
    }

    private var sharedNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Shared notes")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    Text("Visible to your group")
                        .font(.caption2)
                }
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Interview takeaways, client feedback, meeting notes...", text: $sharedNotes, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(4...8)
                .padding(12)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
        }
    }

    private var saveButton: some View {
        Button {
            Haptics.success()
            saving = true
            Task {
                await recruiter.updateProspectNotes(
                    prospect,
                    notes: notes.isEmpty ? nil : notes,
                    sharedNotes: sharedNotes.isEmpty ? nil : sharedNotes
                )
                await MainActor.run {
                    saving = false
                    dismiss()
                }
            }
        } label: {
            HStack {
                if saving {
                    ProgressView().tint(.white)
                } else {
                    Text("Save notes")
                }
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(WhisperTheme.ink(colorScheme), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(saving)
    }
}
